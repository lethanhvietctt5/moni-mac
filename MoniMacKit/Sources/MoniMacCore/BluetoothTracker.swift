import Foundation

/// What MoniMac remembers about one device between readings and across relaunches.
public struct BluetoothDeviceRecord: Equatable, Sendable, Codable {
    public var name: String
    /// The last reading that found it connected.
    public var lastSeen: Date?
    /// Its levels at that reading.
    public var battery: BluetoothBattery
    /// The last reading that found it charging, or a level risen since the reading before.
    public var chargedAt: Date?
    /// Where the drain is measured from: the levels after the last charge (or when first seen).
    public var drain: Drain?

    /// Levels at a moment, to measure the drain since.
    public struct Drain: Equatable, Sendable, Codable {
        public var from: BluetoothBattery
        public var since: Date

        public init(from: BluetoothBattery, since: Date) {
            self.from = from
            self.since = since
        }
    }

    public init(name: String, lastSeen: Date? = nil, battery: BluetoothBattery = BluetoothBattery(),
                chargedAt: Date? = nil, drain: Drain? = nil) {
        self.name = name
        self.lastSeen = lastSeen
        self.battery = battery
        self.chargedAt = chargedAt
        self.drain = drain
    }

    /// How long `battery` lasts at the rate it has drained since the last charge: the first of its parts in
    /// use (main, left, right) to run out. Each part is measured against its own earlier level, so an earbud
    /// that stops reporting doesn't skew the other. Nil until a part has dropped at least
    /// `BluetoothTracker.minimumDrop` points over at least `minimumTime`.
    public func timeLeft(_ battery: BluetoothBattery, now: Date, minimumTime: TimeInterval) -> TimeInterval? {
        guard let drain else { return nil }
        let elapsed = now.timeIntervalSince(drain.since)
        guard elapsed >= minimumTime else { return nil }
        return BluetoothBattery.inUse.compactMap { part -> TimeInterval? in
            guard let level = battery[keyPath: part], let from = drain.from[keyPath: part],
                  from - level >= BluetoothTracker.minimumDrop else { return nil }
            return Double(level) / (Double(from - level) / elapsed)
        }.min()
    }
}

/// Remembers each paired device across readings and relaunches: when it was last seen connected, its
/// last levels, when it was last charged, and how fast it has drained since.
///
/// Records change only when the reader runs, so "last seen" is the last time MoniMac looked and found it
/// connected: while the Bluetooth tab is open or low-battery notifications are on.
///
/// Only connected devices update a record: a disconnected device's levels (macOS keeps AirPods' last ones)
/// are old news. A charge is a reading that says the device is charging, or a part (main, left, right)
/// at least `chargeRise` points above its level the reading before (levels jitter by a point). Parts are
/// compared one by one, so an earbud dropping out of a reading isn't mistaken for a charge. Records are
/// saved in Preferences only when a new reading changed them. Devices that are no longer paired are forgotten.
@MainActor
final class BluetoothTracker {
    /// A part this many points above its last level means the device was charged in between.
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
        let battery = device.battery
        if battery.lowest != nil {
            let rose = BluetoothBattery.inUse.contains { part in
                guard let level = battery[keyPath: part], let before = record.battery[keyPath: part] else { return false }
                return level >= before + chargeRise
            }
            let measurable = record.drain.map { drain in
                BluetoothBattery.inUse.contains { drain.from[keyPath: $0] != nil && battery[keyPath: $0] != nil }
            } ?? false
            if device.isCharging == true || rose {
                record.chargedAt = now
                record.drain = .init(from: battery, since: now)
            } else if !measurable {
                // First sight, or no part in common with where the drain started: start it here.
                record.drain = .init(from: battery, since: now)
            }
        }
        if !battery.isEmpty { record.battery = battery }
    }
}

extension BluetoothBattery {
    /// The parts that run out in use: everything but the case.
    static var inUse: [KeyPath<BluetoothBattery, Int?>] { [\.main, \.left, \.right] }
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
