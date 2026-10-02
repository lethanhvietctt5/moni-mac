import Darwin
import Foundation
import IOKit
import MoniMacCore
import os

private let log = Logger(subsystem: "io.github.lethanhvietctt5.MoniMac", category: "Bluetooth")

/// Paired Bluetooth devices and their batteries, read on a utility-QoS background queue only when
/// something needs them (`BluetoothDemand`): every 30 s while the Bluetooth tab shows, every 5 min while
/// low-battery notifications are on, otherwise never. The refresh loop only picks up the latest result.
///
/// Two sources, neither needing a permission prompt or a usage description:
/// - `system_profiler SPBluetoothDataType -json`: every paired device, connected or not, with its type,
///   firmware, and the levels macOS has (AirPods' left, right, and case, and most third-party
///   devices' main battery). macOS gets these from bluetoothd through an entitlement system_profiler
///   holds, so MoniMac itself never touches Bluetooth and TCC never asks. A run costs ~20 ms of CPU
///   in the child, so it's never on the refresh loop. A run that hangs is stopped after `timeout`.
/// - IOKit's `AppleDeviceManagementHIDEventService` entries, for Apple's own HID peripherals (Magic
///   Keyboard, Mouse, Trackpad), whose battery system_profiler doesn't report: `BatteryPercent` and the
///   charging bit of `BatteryStatusFlags`, read key by key.
///
/// IOBluetooth was ruled out: listing devices through it raises the Bluetooth privacy prompt and needs
/// `NSBluetoothAlwaysUsageDescription`, and it has no battery levels for AirPods.
final class BluetoothReader: Sendable {
    private struct State {
        var latest: Reading<BluetoothReading> = .unavailable(.warmingUp)
        var running = false
        var lastRun: Date?
        var runs = 0
        var childCPU: Double = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let timeout: TimeInterval
    private let started: Date
    /// Background reads wait this long after launch, so launch stays light. A showing tab reads at once.
    private let backgroundDelay: TimeInterval

    init(timeout: TimeInterval = 15, backgroundDelay: TimeInterval = 10, now: Date = Date()) {
        self.timeout = timeout
        self.backgroundDelay = backgroundDelay
        started = now
    }

    func latest() -> Reading<BluetoothReading> {
        state.withLock { $0.latest }
    }

    /// Starts a background read if `demand` wants one, the last is older than its interval, and none is running.
    func refreshIfDue(demand: BluetoothDemand, now: Date = Date()) {
        guard let interval = demand.interval else { return }
        if demand == .background, now.timeIntervalSince(started) < backgroundDelay { return }
        let due = state.withLock { state in
            guard !state.running, state.lastRun.map({ now.timeIntervalSince($0) >= interval }) ?? true
            else { return false }
            (state.running, state.lastRun) = (true, now)
            return true
        }
        guard due else { return }
        DispatchQueue.global(qos: .utility).async { [self] in
            let childBefore = Self.childCPUSeconds()
            let reading = Self.read(timeout: timeout)
            let childCPU = Self.childCPUSeconds() - childBefore
            let (runs, total) = state.withLock { state in
                state.latest = reading
                state.running = false
                state.runs += 1
                state.childCPU += childCPU
                return (state.runs, state.childCPU)
            }
            // Its cost lands in the child, where `ps` on MoniMac can't see it, so it's logged now and then.
            if runs == 1 || runs % 12 == 0 {
                log.notice("""
                    Bluetooth read #\(runs): \(reading.value?.devices.count ?? -1) devices, child CPU \
                    \(childCPU * 1000, format: .fixed(precision: 0)) ms (avg \
                    \(total / Double(runs) * 1000, format: .fixed(precision: 0)) ms)
                    """)
            }
        }
    }

    /// Reads both sources now, on the caller's thread.
    static func read(timeout: TimeInterval) -> Reading<BluetoothReading> {
        let readAt = Date()
        guard let output = runProfiler(timeout: timeout) else {
            return .unavailable(.failed("system_profiler didn't answer"))
        }
        let parsed = parse(output, readAt: readAt)
        guard let reading = parsed.value else { return parsed }
        return .value(merge(reading, hid: readHIDBatteries()))
    }

    // MARK: system_profiler

    private static func runProfiler(timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            log.error("system_profiler couldn't run: \(String(describing: error), privacy: .public)")
            return nil
        }
        // A run that hangs is stopped, which ends its output, so the read below never waits forever.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            log.error("system_profiler failed or timed out (status \(process.terminationStatus))")
            return nil
        }
        return data
    }

    /// Parses `system_profiler SPBluetoothDataType -json`. Levels are percent strings ("85%"); numbers are
    /// accepted too. Unknown keys are ignored.
    static func parse(_ data: Data, readAt: Date) -> Reading<BluetoothReading> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return .unavailable(.failed("system_profiler's output wasn't readable")) }
        guard !sections.isEmpty else { return .unavailable(.unsupported) }
        var devices: [BluetoothDevice] = []
        var isPoweredOn = true
        for section in sections {
            if let controller = section["controller_properties"] as? [String: Any],
               let state = controller["controller_state"] as? String {
                isPoweredOn = state == "attrib_on"
            }
            for (key, isConnected) in [("device_connected", true), ("device_not_connected", false)] {
                for entry in section[key] as? [[String: Any]] ?? [] {
                    for (name, properties) in entry {
                        guard let properties = properties as? [String: Any],
                              let address = (properties["device_address"] as? String).flatMap(normalizedAddress)
                        else { continue }
                        devices.append(device(name: name, address: address, properties, isConnected: isConnected))
                    }
                }
            }
        }
        return .value(BluetoothReading(devices: devices, isPoweredOn: isPoweredOn, readAt: readAt))
    }

    private static func device(name: String, address: String, _ properties: [String: Any],
                               isConnected: Bool) -> BluetoothDevice {
        func level(_ key: String) -> Int? {
            let value: Int? = switch properties["device_batteryLevel\(key)"] {
            case let number as NSNumber: number.intValue
            case let text as String: Int(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: ""))
            default: nil
            }
            return value.flatMap { (0...100).contains($0) ? $0 : nil }
        }
        let firmware = (properties["device_firmwareVersion"] as? String)?.trimmingCharacters(in: .whitespaces)
        return BluetoothDevice(
            address: address, name: name, minorType: properties["device_minorType"] as? String,
            vendorID: (properties["device_vendorID"] as? String).flatMap(hexID),
            isConnected: isConnected,
            // Some devices report "0.0.0", which isn't a version.
            firmware: firmware.flatMap { $0.isEmpty || $0 == "0.0.0" ? nil : $0 },
            battery: BluetoothBattery(main: level("Main"), left: level("Left"), right: level("Right"), case: level("Case"))
        )
    }

    /// "AA:BB:CC:DD:EE:FF" from colon- or dash-separated octets in either case (IOKit writes
    /// "aa-bb-cc-dd-ee-ff"), or nil for anything else.
    static func normalizedAddress(_ raw: String) -> String? {
        let octets = raw.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == ":" || $0 == "-" })
        guard octets.count == 6, octets.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isHexDigit) }) else { return nil }
        return octets.joined(separator: ":").uppercased()
    }

    /// "0x004C" or "0x004C (Apple)" → 0x4C.
    private static func hexID(_ text: String) -> Int? {
        guard let token = text.split(separator: " ").first, token.hasPrefix("0x") else { return nil }
        return Int(token.dropFirst(2), radix: 16)
    }

    // MARK: IOKit HID

    struct HIDBattery: Equatable {
        var percent: Int
        var isCharging: Bool?
    }

    /// Apple HID peripherals' batteries by normalized address. Reads three keys per entry, never whole tables.
    static func readHIDBatteries() -> [String: HIDBattery] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }
        var batteries: [String: HIDBattery] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard let percent = (property("BatteryPercent") as? NSNumber)?.intValue, (0...100).contains(percent),
                  let address = (property("DeviceAddress") as? String).flatMap(normalizedAddress) else { continue }
            let flags = (property("BatteryStatusFlags") as? NSNumber)?.intValue
            // Bit 0x2 of the status flags means charging.
            batteries[address] = HIDBattery(percent: percent, isCharging: flags.map { $0 & 0x2 != 0 })
        }
        return batteries
    }

    /// Adds HID levels to the connected devices system_profiler gave no level for.
    static func merge(_ reading: BluetoothReading, hid: [String: HIDBattery]) -> BluetoothReading {
        var reading = reading
        for index in reading.devices.indices where reading.devices[index].isConnected {
            guard let battery = hid[reading.devices[index].address] else { continue }
            if reading.devices[index].battery.lowest == nil { reading.devices[index].battery.main = battery.percent }
            reading.devices[index].isCharging = battery.isCharging
        }
        return reading
    }

    /// CPU used by this process's finished children, in seconds.
    private static func childCPUSeconds() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_CHILDREN, &usage) == 0 else { return 0 }
        func seconds(_ time: timeval) -> Double { Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }
}
