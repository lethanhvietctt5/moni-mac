import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import MoniMacCore
import os

private let log = Logger(subsystem: "io.github.lethanhvietctt5.MoniMac", category: "Sound")

/// The app an audio process belongs to.
struct AudioAppIdentity: Equatable, Sendable {
    /// The bundle id.
    var id: String
    var name: String
    var path: String
}

/// One Core Audio process object: an audio client.
struct AudioClient: Equatable, Sendable {
    var object: AudioObjectID
    var pid: pid_t
    /// The app it belongs to, or nil for macOS's background services and other processes without an app,
    /// which are never listed or tapped (except by pid, for `--sound-selftest`).
    var app: AudioAppIdentity?
    var isRunningOutput: Bool
    var isRunningInput: Bool
}

/// The default output device, as the taps need it.
struct AudioOutputInfo: Equatable, Sendable {
    var id: AudioDeviceID
    var uid: String
    var transport: UInt32
    /// Input streams on the output device itself, e.g. a headset's microphone. They join every aggregate
    /// built on it, so the taps must skip them (`AudioTapPipeline`'s microphone guard).
    var inputStreams: Int
    var sampleRate: Double?
}

/// Keeps a cache of audio clients and output devices current with Core Audio listeners, so reading it
/// costs nothing. Listeners exist only while someone needs the cache: the Sound reading (`SoundDemand`)
/// or a tap. Otherwise MoniMac makes no Core Audio calls at all.
///
/// Everything runs on `queue`, which the mixer shares; the published copy is read under a lock.
final class AudioWatcher: @unchecked Sendable {
    enum User: Hashable { case reading, mixer }

    /// `output`: the default output device, its sample rate, or its streams changed, so taps need rebuilding.
    /// `volume`: only its volume did.
    enum Change { case clients, output, devices, volume }

    struct Published: Sendable {
        var clients: [AudioClient] = []
        var output: SoundDevice?
        var devices: [SoundDevice] = []
        /// The first read after starting has finished.
        var isReady = false
    }

    let queue: DispatchQueue
    /// Called on `queue` after the cache changed.
    var onChange: ((Change) -> Void)?

    private let published = OSAllocatedUnfairLock(initialState: Published())
    private let ownPID = getpid()

    // Confined to `queue`.
    private var users: Set<User> = []
    private(set) var clients: [AudioObjectID: AudioClient] = [:]
    private(set) var output: AudioOutputInfo?
    private var outputDevice: SoundDevice?
    private var devices: [SoundDevice] = []
    private var systemListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var clientListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var outputListener: (AudioDeviceID, AudioObjectPropertyListenerBlock)?

    private static let clientProperties = [kAudioProcessPropertyIsRunningOutput, kAudioProcessPropertyIsRunningInput]
    private static let outputProperties: [(AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
        (kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput),
        (kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal),
        // A headset switching to hands-free adds its microphone's input stream.
        (kAudioDevicePropertyStreams, kAudioObjectPropertyScopeGlobal),
    ]

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    /// The latest cache, from any thread.
    func latest() -> Published {
        published.withLock { $0 }
    }

    /// Starts listening when the first user needs it and stops when the last one doesn't. Call on `queue`.
    func setNeeded(_ needed: Bool, by user: User) {
        dispatchPrecondition(condition: .onQueue(queue))
        let wasRunning = !users.isEmpty
        if needed { users.insert(user) } else { users.remove(user) }
        switch (wasRunning, !users.isEmpty) {
        case (false, true): start()
        case (true, false): stop()
        default: break
        }
    }

    var isRunning: Bool { !users.isEmpty }

    // MARK: Lifecycle

    private func start() {
        log.notice("Watching audio")
        let watched: [(AudioObjectPropertySelector, Change)] = [
            (kAudioHardwarePropertyProcessObjectList, .clients),
            (kAudioHardwarePropertyDefaultOutputDevice, .output),
            (kAudioHardwarePropertyDevices, .devices),
        ]
        for (selector, change) in watched {
            var address = AudioHAL.address(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh(change) }
            if AudioObjectAddPropertyListenerBlock(AudioHAL.system, &address, queue, block) == noErr {
                systemListeners.append((address, block))
            }
        }
        refreshClients()
        refreshOutput()
        refreshDevices()
        published.withLock { $0.isReady = true }
    }

    private func stop() {
        log.notice("Stopped watching audio")
        for (address, block) in systemListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(AudioHAL.system, &address, queue, block)
        }
        systemListeners = []
        for object in Array(clientListeners.keys) { unwatch(client: object) }
        unwatchOutput()
        clients = [:]
        output = nil
        outputDevice = nil
        devices = []
        published.withLock { $0 = Published() }
    }

    private func refresh(_ change: Change) {
        guard isRunning else { return }
        switch change {
        case .clients: refreshClients()
        case .output: refreshOutput()
        case .devices: refreshDevices()
        case .volume: readOutputDevice()
        }
        onChange?(change)
    }

    // MARK: Clients

    private func refreshClients() {
        let current = Set(AudioHAL.objects(AudioHAL.system, kAudioHardwarePropertyProcessObjectList))
        for object in clients.keys where !current.contains(object) {
            unwatch(client: object)
            clients[object] = nil
        }
        for object in current where clients[object] == nil {
            guard let pid = AudioHAL.pid(ofProcess: object), pid > 0, pid != ownPID else { continue }
            let app = Self.identity(of: pid, ownPID: ownPID)
            clients[object] = AudioClient(
                object: object, pid: pid, app: app,
                isRunningOutput: AudioHAL.isRunning(object, kAudioProcessPropertyIsRunningOutput),
                isRunningInput: AudioHAL.isRunning(object, kAudioProcessPropertyIsRunningInput)
            )
            watch(client: object)
        }
        publishClients()
    }

    private func watch(client object: AudioObjectID) {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, isRunning, var client = clients[object] else { return }
            client.isRunningOutput = AudioHAL.isRunning(object, kAudioProcessPropertyIsRunningOutput)
            client.isRunningInput = AudioHAL.isRunning(object, kAudioProcessPropertyIsRunningInput)
            guard client != clients[object] else { return }
            clients[object] = client
            publishClients()
            onChange?(.clients)
        }
        for selector in Self.clientProperties {
            var address = AudioHAL.address(selector)
            AudioObjectAddPropertyListenerBlock(object, &address, queue, block)
        }
        clientListeners[object] = block
    }

    private func unwatch(client object: AudioObjectID) {
        guard let block = clientListeners.removeValue(forKey: object) else { return }
        // The object may already be gone with its process; removing then fails harmlessly.
        for selector in Self.clientProperties {
            var address = AudioHAL.address(selector)
            AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
        }
    }

    private func publishClients() {
        let list = clients.values.sorted { $0.object < $1.object }
        published.withLock { $0.clients = list }
    }

    /// The app responsible for `pid` (a browser for its audio helper), from LaunchServices: the bundle id
    /// and name are the app's, even for apps that run from a relocated copy (Chrome's code-sign clone).
    /// Nil for macOS's background services (under /System/Library) and processes without an app.
    static func identity(of pid: pid_t, ownPID: pid_t) -> AudioAppIdentity? {
        let responsible = Responsibility.pid(for: pid) ?? pid
        guard responsible != ownPID else { return nil }
        for candidate in [responsible, pid] {
            guard let app = NSRunningApplication(processIdentifier: candidate), let id = app.bundleIdentifier,
                  let url = app.bundleURL, url.pathExtension == "app" else { continue }
            let path = url.path
            if path.hasPrefix("/System/Library/") { return nil }
            return AudioAppIdentity(id: id, name: app.localizedName ?? url.deletingPathExtension().lastPathComponent,
                                    path: path)
        }
        return nil
    }

    // MARK: Devices

    private func refreshOutput() {
        unwatchOutput()
        guard let id = AudioHAL.defaultOutputDevice, let uid = AudioHAL.string(id, kAudioDevicePropertyDeviceUID) else {
            output = nil
            outputDevice = nil
            published.withLock { $0.output = nil }
            return
        }
        let transport = AudioHAL.transport(id)
        output = AudioOutputInfo(
            id: id, uid: uid, transport: transport,
            inputStreams: AudioHAL.streamCount(id, kAudioObjectPropertyScopeInput),
            sampleRate: AudioHAL.float64(id, kAudioDevicePropertyNominalSampleRate)
        )
        readOutputDevice()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, isRunning, output?.id == id else { return }
            let rate = AudioHAL.float64(id, kAudioDevicePropertyNominalSampleRate)
            let inputs = AudioHAL.streamCount(id, kAudioObjectPropertyScopeInput)
            let reshaped = rate != output?.sampleRate || inputs != output?.inputStreams
            output?.sampleRate = rate
            output?.inputStreams = inputs
            readOutputDevice()
            onChange?(reshaped ? .output : .volume)
        }
        for (selector, scope) in Self.outputProperties {
            var address = AudioHAL.address(selector, scope)
            AudioObjectAddPropertyListenerBlock(id, &address, queue, block)
        }
        outputListener = (id, block)
    }

    private func readOutputDevice() {
        guard let output else { return }
        let device = SoundDevice(
            uid: output.uid, name: AudioHAL.string(output.id, kAudioObjectPropertyName) ?? "Output",
            kind: AudioHAL.kind(transport: output.transport), sampleRate: output.sampleRate,
            volume: AudioHAL.volume(output.id)
        )
        outputDevice = device
        published.withLock { $0.output = device }
    }

    private func unwatchOutput() {
        guard let (id, block) = outputListener else { return }
        for (selector, scope) in Self.outputProperties {
            var address = AudioHAL.address(selector, scope)
            AudioObjectRemovePropertyListenerBlock(id, &address, queue, block)
        }
        outputListener = nil
    }

    /// Devices that can play sound, without hidden ones and MoniMac's own aggregates.
    private func refreshDevices() {
        devices = AudioHAL.objects(AudioHAL.system, kAudioHardwarePropertyDevices).compactMap { id in
            guard AudioHAL.streamCount(id, kAudioObjectPropertyScopeOutput) > 0,
                  AudioHAL.uint32(id, kAudioDevicePropertyIsHidden) != 1,
                  let uid = AudioHAL.string(id, kAudioDevicePropertyDeviceUID),
                  !uid.hasPrefix(AudioTapPipeline.uidPrefix) else { return nil }
            return SoundDevice(uid: uid, name: AudioHAL.string(id, kAudioObjectPropertyName) ?? uid,
                               kind: AudioHAL.kind(transport: AudioHAL.transport(id)))
        }
        let list = devices
        published.withLock { $0.devices = list }
    }
}
