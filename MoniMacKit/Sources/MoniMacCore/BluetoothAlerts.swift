import Foundation

/// The "Bluetooth device below 20%" rule: one notification per device per low episode.
///
/// A connected device is low when its lowest level in use (`BluetoothBattery.lowest`: the main battery or
/// either earbud, not the case) is under `threshold`. The episode lasts until the device reads at least
/// `rearmLevel`, i.e. it was charged: levels jitter by a point, so recovering to just 20% doesn't count.
/// A device that disconnects while low (it may have died) stays in its episode, so reconnecting it still
/// low doesn't notify again. The state lives in memory; after a relaunch a device that's still low
/// notifies once more.
struct BluetoothLowBatteryRule {
    static let threshold = 20
    static let rearmLevel = 25

    private var low: Set<String> = []

    /// Returns the connected devices whose low episode just started.
    mutating func observe(_ devices: [BluetoothDevice]) -> [BluetoothDevice] {
        var started: [BluetoothDevice] = []
        for device in devices where device.isConnected {
            guard let level = device.battery.lowest else { continue }
            if level < Self.threshold {
                if low.insert(device.address).inserted { started.append(device) }
            } else if level >= Self.rearmLevel {
                low.remove(device.address)
            }
        }
        return started.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Turning the rule off ends every episode.
    mutating func reset() {
        low = []
    }
}

extension Alert {
    /// e.g. "Magic Trackpad battery is low" with the chip "14%". The id is per device, and posting it
    /// replaces the device's earlier banner. "Show" opens the Bluetooth tab; there is nothing to quit.
    static func bluetoothLowBattery(_ device: BluetoothDevice) -> Alert {
        let battery = device.battery
        let level = battery.lowest ?? 0
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
        let started = alerts.bluetooth.observe(reading.devices)
        guard !started.isEmpty else { return }
        requestNotificationPermission()
        for device in started {
            actions.deliver(.bluetoothLowBattery(device))
        }
    }
}
