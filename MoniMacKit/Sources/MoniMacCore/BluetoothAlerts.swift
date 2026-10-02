import Foundation

/// The "Bluetooth device below 20%" rule: one notification per device per low episode.
///
/// A connected device is low when a part in use (the main battery or either earbud, not the case) is under
/// `threshold`. The episode lasts until every part that was low reads at least `rearmLevel`, i.e. it was
/// charged: levels jitter by a point, so recovering to just 20% doesn't count. A part that stops reporting
/// (an earbud put away) or a device that disconnects while low (it may have died) stays in its episode, so
/// coming back still low doesn't notify again. Episodes live in memory; after a relaunch a device that's
/// still low notifies once more.
struct BluetoothLowBatteryRule {
    static let threshold = 20
    static let rearmLevel = 25

    /// Each device in an episode, with its parts that went low and haven't recovered.
    private var low: [String: Set<KeyPath<BluetoothBattery, Int?>>] = [:]

    /// Returns the connected devices whose low episode just started, with the level that started it.
    mutating func observe(_ reading: BluetoothReading) -> [(device: BluetoothDevice, level: Int)] {
        var started: [(device: BluetoothDevice, level: Int)] = []
        for device in reading.devices where device.isConnected {
            var parts = low[device.address] ?? []
            let wasLow = !parts.isEmpty
            for part in BluetoothBattery.inUse {
                guard let level = device.battery[keyPath: part] else { continue }
                if level < Self.threshold { parts.insert(part) } else if level >= Self.rearmLevel { parts.remove(part) }
            }
            low[device.address] = parts.isEmpty ? nil : parts
            if !wasLow, !parts.isEmpty, let level = device.battery.lowest { started.append((device, level)) }
        }
        // Unpaired devices take their episodes with them.
        if reading.isPoweredOn {
            let paired = Set(reading.devices.map(\.address))
            low = low.filter { paired.contains($0.key) }
        }
        return started.sorted { $0.device.name.localizedStandardCompare($1.device.name) == .orderedAscending }
    }

    /// Turning the rule off ends every episode.
    mutating func reset() {
        low = [:]
    }
}

extension Alert {
    /// e.g. "Magic Trackpad battery is low" with the chip "14%". The id is per device, and posting it
    /// replaces the device's earlier banner. "Show" opens the Bluetooth tab; there is nothing to quit.
    static func bluetoothLowBattery(_ device: BluetoothDevice, level: Int) -> Alert {
        let battery = device.battery
        let parts: String
        if battery.hasEarbuds {
            parts = [("Left", battery.left), ("Right", battery.right)]
                .compactMap { label, value in value.map { "\(label) \($0)%" } }
                .joined(separator: ", ") + ". "
        } else {
            parts = ""
        }
        return Alert(
            id: "bluetoothBattery:\(device.address)", threadID: "bluetoothBattery",
            title: "\(device.name) battery is low",
            body: "\(parts)Charge it soon, before it turns off.",
            chip: "\(level)%", target: .tab(.bluetooth)
        )
    }
}

extension Monitor {
    /// Runs the low-battery rule over a new reading and delivers the episodes that just started.
    func evaluateBluetoothAlerts(_ reading: BluetoothReading) {
        guard preferences.bluetoothLowBatteryAlerts else { return }
        let started = alerts.bluetooth.observe(reading)
        guard !started.isEmpty else { return }
        requestNotificationPermission()
        for (device, level) in started {
            actions.deliver(.bluetoothLowBattery(device, level: level))
        }
    }
}
