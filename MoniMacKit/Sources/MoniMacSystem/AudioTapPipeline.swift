import CoreAudio
import Foundation
import MoniMacCore
import os

private let log = Logger(subsystem: "io.github.lethanhvietctt5.MoniMac", category: "Sound")

/// What the real-time IO block shares with the mixer: plain memory, no locks. Aligned 32- and 64-bit
/// loads and stores are single instructions on Apple silicon, so each side sees whole values; a reading
/// one callback stale is fine. (`Synchronization.Atomic` needs macOS 15; MoniMac supports 14.2.)
final class AudioTapShared: @unchecked Sendable {
    /// The gain the mixer wants, 0...1.
    let target = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    /// The gain applied at the end of the last callback; the IO block ramps it toward `target`.
    let applied = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    /// IO callbacks so far.
    let callbacks = UnsafeMutablePointer<UInt64>.allocate(capacity: 1)
    /// Callbacks whose tap input had any non-zero sample.
    let audible = UnsafeMutablePointer<UInt64>.allocate(capacity: 1)
    /// Peak of the tap input, linear, decaying ~0.9 per callback (about −45 dB per second at 48 kHz/512).
    let peak = UnsafeMutablePointer<Float>.allocate(capacity: 1)

    init(gain: Float) {
        target.initialize(to: gain)
        applied.initialize(to: gain)
        callbacks.initialize(to: 0)
        audible.initialize(to: 0)
        peak.initialize(to: 0)
    }

    deinit {
        target.deallocate()
        applied.deallocate()
        callbacks.deallocate()
        audible.deallocate()
        peak.deallocate()
    }
}

/// One app's volume control: a private process tap on the app's audio processes that mutes them at the
/// device (`.mutedWhenTapped`), feeding a private aggregate device whose main sub-device is the current
/// output. Its IO block copies the tap's audio to the output times the gain. Built and destroyed on the
/// mixer's queue; the first build can block while macOS asks for the audio capture permission.
///
/// Private taps and aggregates disappear with MoniMac, so a crash never leaves an app muted.
final class AudioTapPipeline {
    /// Aggregate UIDs start with this, so the device list can leave them out.
    static let uidPrefix = "io.github.lethanhvietctt5.MoniMac.tap."
    /// A full 0 ↔ 1 change is spread over this long, so gain changes don't click.
    private static let rampSeconds: Float = 0.025

    enum Failure: Error, CustomStringConvertible {
        case coreAudio(String, OSStatus)
        /// The aggregate has input streams besides the tap (the output device has a microphone) that
        /// couldn't be told apart from it. Starting would risk reading the microphone, so it doesn't start.
        case unexpectedInputs(Int)

        var description: String {
            switch self {
            case .coreAudio(let call, let status): "\(call) failed: \(AudioHAL.describe(status))"
            case .unexpectedInputs(let count): "the aggregate has \(count) input streams; expected the tap plus the device's own"
            }
        }
    }

    let target: SoundTarget
    private(set) var objects: [AudioObjectID]
    let output: AudioOutputInfo
    let shared: AudioTapShared

    private let tapUUID = UUID()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let ioQueue: DispatchQueue

    /// Builds and starts the pipeline, or throws having cleaned up after itself.
    init(target: SoundTarget, objects: [AudioObjectID], gain: Double, output: AudioOutputInfo) throws {
        self.target = target
        self.objects = objects
        self.output = output
        shared = AudioTapShared(gain: Float(gain))
        ioQueue = DispatchQueue(label: "io.github.lethanhvietctt5.MoniMac.tap.io", qos: .userInteractive)
        do {
            try build()
        } catch {
            destroy()
            throw error
        }
    }

    deinit {
        destroy()
    }

    var gain: Double {
        get { Double(shared.target.pointee) }
        set { shared.target.pointee = Float(min(max(newValue, 0), 1)) }
    }

    private func description(for objects: [AudioObjectID]) -> CATapDescription {
        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        description.uuid = tapUUID
        description.name = "MoniMac volume"
        description.isPrivate = true
        // The app is silenced at the device only while MoniMac reads the tap: if MoniMac stops reading,
        // the app is heard again rather than going silent.
        description.muteBehavior = .mutedWhenTapped
        return description
    }

    private func build() throws {
        var status = AudioHardwareCreateProcessTap(description(for: objects), &tapID)
        guard status == noErr else { throw Failure.coreAudio("AudioHardwareCreateProcessTap", status) }

        // Drift compensation crackles on Bluetooth and virtual devices (FineTune's finding); elsewhere it
        // keeps the tap in step with the output clock.
        let drift = !AudioHAL.isBluetooth(transport: output.transport)
            && ![kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate].contains(output.transport)
        let settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MoniMac volume",
            kAudioAggregateDeviceUIDKey: Self.uidPrefix + tapUUID.uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output.uid,
            kAudioAggregateDeviceClockDeviceKey: output.uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output.uid]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUUID.uuidString,
                                               kAudioSubTapDriftCompensationKey: drift]],
        ]
        status = AudioHardwareCreateAggregateDevice(settings as CFDictionary, &aggregateID)
        guard status == noErr else { throw Failure.coreAudio("AudioHardwareCreateAggregateDevice", status) }

        // Microphone guard. Sub-devices' streams come before taps', so with M microphone streams on the
        // output device the tap is input stream M. Anything else is unexpected: don't start.
        let inputs = AudioHAL.streamCount(aggregateID, kAudioObjectPropertyScopeInput)
        guard inputs == output.inputStreams + 1 else { throw Failure.unexpectedInputs(inputs) }
        let tapIndex = output.inputStreams

        let shared = shared
        let rampPerFrame = 1 / (Self.rampSeconds * Float(output.sampleRate ?? 48000))
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, ioQueue) { _, input, _, output, _ in
            Self.process(input: input, output: output, tapIndex: tapIndex, rampPerFrame: rampPerFrame, shared: shared)
        }
        guard status == noErr, let procID else { throw Failure.coreAudio("AudioDeviceCreateIOProcIDWithBlock", status) }
        if output.inputStreams > 0 { try disableMicrophoneStreams(procID, total: inputs) }
        status = AudioDeviceStart(aggregateID, procID)
        guard status == noErr else { throw Failure.coreAudio("AudioDeviceStart", status) }
        log.notice("Tap started for \(String(describing: self.target), privacy: .public): \(self.objects.count) processes on \(self.output.uid, privacy: .public)")
    }

    /// Marks the output device's own input streams unused by MoniMac's IO block, so Core Audio passes no
    /// microphone data to it (their buffers arrive as NULL). Only the tap's stream stays on.
    private func disableMicrophoneStreams(_ procID: AudioDeviceIOProcID, total: Int) throws {
        // struct AudioHardwareIOProcStreamUsage { void *mIOProc; UInt32 mNumberStreams; UInt32 mStreamIsOn[]; }
        let headerSize = MemoryLayout<UnsafeRawPointer>.size + MemoryLayout<UInt32>.size
        let size = headerSize + total * MemoryLayout<UInt32>.size
        let usage = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<UnsafeRawPointer>.alignment)
        defer { usage.deallocate() }
        usage.storeBytes(of: unsafeBitCast(procID, to: UnsafeRawPointer.self), as: UnsafeRawPointer.self)
        usage.storeBytes(of: UInt32(total), toByteOffset: MemoryLayout<UnsafeRawPointer>.size, as: UInt32.self)
        for index in 0..<total {
            let isOn: UInt32 = index == output.inputStreams ? 1 : 0
            usage.storeBytes(of: isOn, toByteOffset: headerSize + index * MemoryLayout<UInt32>.size, as: UInt32.self)
        }
        var address = AudioHAL.address(kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput)
        let status = AudioObjectSetPropertyData(aggregateID, &address, 0, nil, UInt32(size), usage)
        guard status == noErr else { throw Failure.coreAudio("Setting IOProcStreamUsage", status) }
    }

    /// Points the tap at the app's current processes (after one quit or a new helper started) without
    /// rebuilding the aggregate. Returns false when Core Audio refused; the caller then rebuilds.
    func retarget(_ objects: [AudioObjectID]) -> Bool {
        guard AudioHAL.isSettable(tapID, kAudioTapPropertyDescription) else { return false }
        var address = AudioHAL.address(kAudioTapPropertyDescription)
        var reference: Unmanaged<CATapDescription>? = Unmanaged.passRetained(description(for: objects))
        defer { reference?.release() }
        let status = AudioObjectSetPropertyData(tapID, &address, 0, nil, UInt32(MemoryLayout<UnsafeRawPointer>.size), &reference)
        guard status == noErr else {
            log.error("Retargeting the tap failed: \(AudioHAL.describe(status), privacy: .public)")
            return false
        }
        self.objects = objects
        return true
    }

    /// Stops IO and destroys the aggregate and the tap. Safe to call twice.
    func destroy() {
        if let procID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            let status = AudioHardwareDestroyAggregateDevice(aggregateID)
            if status != noErr { log.error("Destroying the aggregate failed: \(AudioHAL.describe(status), privacy: .public)") }
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            let status = AudioHardwareDestroyProcessTap(tapID)
            if status != noErr { log.error("Destroying the tap failed: \(AudioHAL.describe(status), privacy: .public)") }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    // MARK: Real-time IO

    /// Copies the tap's stereo mixdown to the output times the gain: left and right to the first two
    /// output channels (both averaged on a mono output), silence on the rest. Runs once per IO cycle on the
    /// pipeline's own high-priority queue, inside Core Audio's IO deadline: no locks, no allocation, no Objective-C.
    private static func process(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>,
                                tapIndex: Int, rampPerFrame: Float, shared: AudioTapShared) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        shared.callbacks.pointee &+= 1

        var source: UnsafePointer<Float>?
        var sourceChannels = 0
        var sourceFrames = 0
        if tapIndex < inputs.count, let data = inputs[tapIndex].mData {
            sourceChannels = max(Int(inputs[tapIndex].mNumberChannels), 1)
            sourceFrames = Int(inputs[tapIndex].mDataByteSize) / MemoryLayout<Float>.size / sourceChannels
            source = UnsafePointer(data.assumingMemoryBound(to: Float.self))
        }

        var peak: Float = 0
        if let source {
            for index in 0..<(sourceFrames * sourceChannels) { peak = max(peak, abs(source[index])) }
        }
        if peak > 0 { shared.audible.pointee &+= 1 }
        shared.peak.pointee = max(peak, shared.peak.pointee * 0.9)

        var totalChannels = 0
        var frames = 0
        for buffer in outputs where buffer.mNumberChannels > 0 {
            totalChannels += Int(buffer.mNumberChannels)
            frames = max(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / Int(buffer.mNumberChannels))
        }
        let start = shared.applied.pointee
        let limit = rampPerFrame * Float(max(frames, 1))
        let end = start + min(max(shared.target.pointee - start, -limit), limit)

        var channelBase = 0
        for buffer in outputs {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else {
                channelBase += channels
                continue
            }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
            // Each buffer ramps from start to end over its own frames (non-interleaved outputs have one per channel).
            let step = (end - start) / Float(max(count, 1))
            var gain = start
            for frame in 0..<count {
                gain += step
                for channel in 0..<channels {
                    var sample: Float = 0
                    if let source, frame < sourceFrames {
                        let base = frame * sourceChannels
                        let left = source[base]
                        let right = sourceChannels > 1 ? source[base + 1] : left
                        let index = channelBase + channel
                        sample = totalChannels == 1 ? (left + right) * 0.5 : (index == 0 ? left : (index == 1 ? right : 0))
                    }
                    data[frame * channels + channel] = sample * gain
                }
            }
            channelBase += channels
        }
        shared.applied.pointee = end
    }

    // MARK: Readings for the mixer

    var callbacks: UInt64 { shared.callbacks.pointee }
    var audibleCallbacks: UInt64 { shared.audible.pointee }

    /// The app's recent peak level in dBFS, or nil before the tap has delivered any sound.
    var level: Double? {
        guard shared.audible.pointee > 0 else { return nil }
        let peak = Double(shared.peak.pointee)
        return peak > 0 ? 20 * log10(peak) : -160
    }
}
