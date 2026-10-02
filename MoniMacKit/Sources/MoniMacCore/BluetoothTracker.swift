import Foundation

/// What MoniMac remembers about one device between readings and across relaunches.
public struct BluetoothDeviceRecord: Equatable, Sendable, Codable {
    public var name: String
    /// The last reading that found it connected.
    public var lastSeen: Date?
    /// Its levels at that reading.
    public var battery: BluetoothBattery
    /// The last reading that found it charging, or its level risen since the reading before.
    public var chargedAt: Date?
    /// Where the drain is measured from: the level after the last charge (or when first seen) and when.
    public var drainFrom: Int?
    public var drainSince: Date?

    public init(name: String, lastSeen: Date? = nil, battery: BluetoothBattery = BluetoothBattery(),
                chargedAt: Date? = nil, drainFrom: Int? = nil, drainSince: Date? = nil) {
        self.name = name
        self.lastSeen = lastSeen
        self.battery = battery
        self.chargedAt = chargedAt
        self.drainFrom = drainFrom
        self.drainSince = drainSince
    }

    /// How long `level` lasts at the rate it has drained since the last charge, or nil until the drain says
    /// enough: at least `BluetoothTracker.minimumDrop` points over at least `minimumTime`.
    public func timeLeft(at level: Int, now: Date, minimumTime: TimeInterval) -> TimeInterval? {
        guard let drainFrom, let drainSince else { return nil }
        let drop = drainFrom - level
        let elapsed = now.timeIntervalSince(drainSince)
        guard drop >= BluetoothTracker.minimumDrop, elapsed >= minimumTime else { return nil }
        return Double(level) / (Double(drop) / elapsed)
    }
}

/// Remembers each paired device across readings and relaunches: when it was last seen connected, its
/// last levels, when it was last charged, and how fast it has drained since.
///
/// Only connected devices update a record: a disconnected device's levels (macOS keeps AirPods' last ones)
/// are old news. A charge is a reading that says the device is charging, or a level at least `chargeRise`
/// points above the one before (levels jitter by a point). Records are saved in Preferences only when a
/// new reading changed them, which is at most every 30 s while the tab shows and every 5 min otherwise.
/// Devices that are no longer paired are forgotten.
@MainActor
final class BluetoothTracker {
    /// A level this many points above the last one means the device was charged in between.
    nonisolated static let chargeRise = 3
    /// The drain must fall this many points before it's used for an estimate; levels move in steps.
    nonisolated static let minimumDrop = 5

    private let preferences: Preferences
    private(set) var records: [String: BluetoothDeviceRecord]
    private var lastReadAt: Date?

    init(preferences: Preferences) {
        self.preferences = preferences
        records = preferences.bluetoothDeviceRecords
    }

    /// Takes in a reading. Returns false for one already seen (the same reading repeats between reads).
    func observe(_ reading: BluetoothReading) -> Bool {
        guard reading.readAt != lastReadAt else { return false }
        lastReadAt = reading.readAt
        var next = records
        for device in reading.devices {
            var record = next[device.address] ?? BluetoothDeviceRecord(name: device.name)
            record.name = device.name
            if device.isConnected {
                Self.update(&record, with: device, at: reading.readAt)
            } else if record.battery.isEmpty, !device.battery.isEmpty {
                // Never seen connected, but macOS remembers its levels (AirPods): better than nothing.
                record.battery = device.battery
            }
            next[device.address] = record
        }
        // A device that's no longer paired is forgotten. With Bluetooth off macOS may list nothing,
        // which says nothing about pairing.
        if reading.isPoweredOn {
            let paired = Set(reading.devices.map(\.address))
            next = next.filter { paired.contains($0.key) }
        }
        guard next != records else { return true }
        records = next
        preferences.bluetoothDeviceRecords = next
        return true
    }

    private static func update(_ record: inout BluetoothDeviceRecord, with device: BluetoothDevice, at now: Date) {
        record.lastSeen = now
        if let level = device.battery.lowest {
            let previous = record.battery.lowest
            let charged = device.isCharging == true || previous.map { level >= $0 + chargeRise } ?? false
            if charged {
                record.chargedAt = now
                (record.drainFrom, record.drainSince) = (level, now)
            } else if record.drainFrom == nil || level > record.drainFrom! {
                // First sight, or a level that crept up without counting as a charge: start the drain here.
                (record.drainFrom, record.drainSince) = (level, now)
            }
        }
        if !device.battery.isEmpty { record.battery = device.battery }
    }
}

extension Preferences {
    /// Each paired device's record, keyed by address. Bookkeeping: written without re-rendering surfaces.
    var bluetoothDeviceRecords: [String: BluetoothDeviceRecord] {
        get {
            guard let data = defaults.data(forKey: "bluetooth.devices") else { return [:] }
            return (try? JSONDecoder().decode([String: BluetoothDeviceRecord].self, from: data)) ?? [:]
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "bluetooth.devices") }
    }
}
