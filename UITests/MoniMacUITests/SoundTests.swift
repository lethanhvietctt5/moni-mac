import AudioToolbox
import CoreAudio
import XCTest

/// Ticket 17: the Sound tab's system volume slider and output device menu change the real Mac.
/// Each test records the original value first and restores it in teardown, even when it fails.
final class SoundTests: MoniMacUITestCase {
    /// Setting the system volume with the slider changes the default output's volume.
    @MainActor
    func testVolumeSliderChangesSystemVolume() throws {
        let device = try XCTUnwrap(SystemAudio.defaultOutput, "No default output device")
        let original = try XCTUnwrap(SystemAudio.volume(of: device), "The default output has no volume control")
        addTeardownBlock { @MainActor in
            // MoniMac sets the volume on a background queue; let it finish, then put the user's back.
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            SystemAudio.setVolume(original, of: device)
        }
        // Lower, so a test never plays louder than the user had it (unless it was nearly silent).
        let target = original >= 0.2 ? original - 0.15 : original + 0.1

        let app = launchMoniMac(["--show-window", "--tab", "sound"])
        let window = mainWindow(of: app)
        let slider = window.sliders["sound.systemVolume"]
        XCTAssertTrue(slider.waitForExistence(timeout: 15), "No volume slider on the Sound tab")
        slider.adjust(toNormalizedSliderPosition: CGFloat(target))
        XCTAssertTrue(waitUntil(timeout: 5) {
            SystemAudio.volume(of: device).map { abs($0 - target) < 0.06 } ?? false
        }, "The volume is \(SystemAudio.volume(of: device) ?? -1), not about \(target)")
        attachScreenshot(of: window, named: "Sound tab after setting the volume")
    }

    /// Picking another device in the output menu makes it the default output.
    @MainActor
    func testOutputMenuSwitchesDefaultDevice() throws {
        let original = try XCTUnwrap(SystemAudio.defaultOutput, "No default output device")
        let originalSystem = SystemAudio.systemOutput
        // A real device, not a virtual one (e.g. a call app's driver), so a call isn't disturbed.
        let others = SystemAudio.outputDevices.filter { $0 != original && !SystemAudio.isVirtual($0) }
        guard let target = others.first, let name = SystemAudio.name(of: target) else {
            throw XCTSkip("Only one real output device, so there's nothing to switch to")
        }
        addTeardownBlock { @MainActor in
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            SystemAudio.setDefaultOutput(original)
            if let originalSystem, SystemAudio.systemOutput != originalSystem {
                SystemAudio.setSystemOutput(originalSystem)
            }
        }

        let app = launchMoniMac(["--show-window", "--tab", "sound"])
        let window = mainWindow(of: app)
        let menu = window.descendants(matching: .any)["sound.outputDevice"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "No output device menu on the Sound tab")
        menu.click()
        let item = app.menuItems[name]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\(name) isn't in the output menu")
        item.click()
        XCTAssertTrue(waitUntil(timeout: 5) { SystemAudio.defaultOutput == target },
                      "The default output is still \(SystemAudio.defaultOutput.flatMap(SystemAudio.name) ?? "?")")
        XCTAssertTrue(waitUntil(timeout: 10) { window.staticTexts[name].exists }, "The Sound tab doesn't show \(name)")
        attachScreenshot(of: window, named: "Sound tab after switching output")
    }
}

/// Core Audio reads and writes for checking and restoring the Mac's output, from the test runner.
enum SystemAudio {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ initial: T) -> T? {
        var address = address(selector, scope)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    @discardableResult
    private static func write<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: T,
                               _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
        var address = address(selector, scope)
        var value = value
        return AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value) == noErr
    }

    static var defaultOutput: AudioObjectID? {
        read(system, kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, AudioObjectID(0))
            .flatMap { $0 == 0 ? nil : $0 }
    }

    static var systemOutput: AudioObjectID? {
        read(system, kAudioHardwarePropertyDefaultSystemOutputDevice, kAudioObjectPropertyScopeGlobal, AudioObjectID(0))
            .flatMap { $0 == 0 ? nil : $0 }
    }

    static func setDefaultOutput(_ device: AudioObjectID) {
        write(system, kAudioHardwarePropertyDefaultOutputDevice, device)
    }

    static func setSystemOutput(_ device: AudioObjectID) {
        write(system, kAudioHardwarePropertyDefaultSystemOutputDevice, device)
    }

    static func volume(of device: AudioObjectID) -> Double? {
        read(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyScopeOutput, Float32(0))
            .map(Double.init)
    }

    static func setVolume(_ volume: Double, of device: AudioObjectID) {
        write(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(volume), kAudioObjectPropertyScopeOutput)
    }

    /// Devices with at least one output stream.
    static var outputDevices: [AudioObjectID] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.filter { device in
            var streams = Self.address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
            var streamSize: UInt32 = 0
            return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr && streamSize > 0
        }
    }

    static func isVirtual(_ device: AudioObjectID) -> Bool {
        let transport = read(device, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal, UInt32(0))
        return transport == kAudioDeviceTransportTypeVirtual || transport == kAudioDeviceTransportTypeAggregate
            || transport == kAudioDeviceTransportTypeAutoAggregate
    }

    static func name(of device: AudioObjectID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }
}
