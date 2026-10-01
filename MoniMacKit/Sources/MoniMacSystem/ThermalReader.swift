import Foundation
import MoniMacCore

/// Reads the thermal state, temperature sensors, and fans for each snapshot. Read-only: it never
/// writes to the SMC and never controls fans.
///
/// An SMC read takes ~0.1 ms (mostly waiting; ~0.01 ms of CPU), and an M4 has ~80 named
/// temperature keys, so reads are throttled: named sensors every `sensorInterval`; unnamed sensors,
/// fan limits, and the IOHID fallback every `slowInterval`; only fan speeds every tick. Between
/// reads the last values are reported.
@MainActor
final class ThermalReader {
    /// The SMC's temperature and fan keys, discovered once.
    private struct Catalog {
        /// Keys `ThermalSensorGroup` can name, read every `sensorInterval`.
        var named: [String] = []
        /// Other temperature keys, read every `slowInterval` (they're only counted).
        var unnamed: [String] = []
        /// One entry per fan, with its SMC name if any; nil when the fan count couldn't be read.
        var fanNames: [String?]?
    }

    private let smc = SMC()
    /// Key names differ per Apple silicon generation, e.g. "Apple M4".
    private let chip = SystemInfoReader.read().chipName
    private lazy var catalog: Catalog = discover()
    /// The IOHID fallback, created only if the SMC reports no named temperatures.
    private lazy var hid = ThermalHID()
    private let sensorInterval: UInt64
    private let slowInterval: UInt64
    private var readings: [String: Double] = [:]
    private var fanLimits: [(minimum: Double, maximum: Double)]?
    private var lastSensorRead: UInt64?
    private var lastSlowRead: UInt64?

    init(sensorInterval: TimeInterval = 5, slowInterval: TimeInterval = 30) {
        self.sensorInterval = UInt64(sensorInterval * 1_000_000_000)
        self.slowInterval = UInt64(slowInterval * 1_000_000_000)
    }

    func sample() -> Reading<ThermalReading> {
        let now = DispatchTime.now().uptimeNanoseconds
        let sensorsDue = lastSensorRead.map { now - $0 >= sensorInterval } ?? true
        let slowDue = lastSlowRead.map { now - $0 >= slowInterval } ?? true
        if sensorsDue { lastSensorRead = now }
        if slowDue { lastSlowRead = now }
        return .value(ThermalReading(
            state: Self.state(ProcessInfo.processInfo.thermalState),
            sensors: sensors(readNamed: sensorsDue, readSlow: slowDue),
            fans: fans(readLimits: slowDue)
        ))
    }

    private func sensors(readNamed: Bool, readSlow: Bool) -> Reading<[ThermalSensor]> {
        guard let smc, !catalog.named.isEmpty else {
            // IOHID costs ~40 ms a pass; read it at the slow cadence.
            guard let hid else { return .unavailable(.unsupported) }
            if readSlow { readings = Dictionary(hid.read().map { ($0.name, $0.celsius) }) { first, _ in first } }
            return .value(readings.sorted { $0.key < $1.key }.map { ThermalSensor(name: $0.key, celsius: $0.value) })
        }
        var keys = readNamed ? catalog.named : []
        if readSlow { keys += catalog.unnamed }
        for key in keys {
            readings[key] = smc.number(key)
        }
        let sensors = (catalog.named + catalog.unnamed).compactMap { key in
            readings[key].map { ThermalSensor(name: key, celsius: $0) }
        }
        return sensors.isEmpty ? .unavailable(.failed("the SMC returned no temperatures")) : .value(sensors)
    }

    /// Every fan, or none: a partial list would misnumber them.
    private func fans(readLimits: Bool) -> Reading<[Fan]> {
        guard let smc else { return .unavailable(.failed("AppleSMC couldn't be opened")) }
        guard let names = catalog.fanNames else { return .unavailable(.failed("the SMC didn't report a fan count")) }
        guard !names.isEmpty else { return .unavailable(.unsupported) }
        /// One value per fan, or nil if any fan's is missing.
        func perFan<T>(_ read: (Int) -> T?) -> [T]? {
            var values: [T] = []
            for index in names.indices {
                guard let value = read(index) else { return nil }
                values.append(value)
            }
            return values
        }
        if readLimits || fanLimits == nil {
            fanLimits = perFan { index in
                smc.number(Self.fanKey(index, "Mn")).flatMap { minimum in
                    smc.number(Self.fanKey(index, "Mx")).map { (minimum, $0) }
                }
            }
        }
        guard let limits = fanLimits, let speeds = perFan({ smc.number(Self.fanKey($0, "Ac")) })
        else { return .unavailable(.failed("the SMC didn't report fan speeds")) }
        return .value(names.indices.map { index in
            Fan(name: names[index], rpm: max(speeds[index], 0), minimumRPM: limits[index].minimum,
                maximumRPM: limits[index].maximum)
        })
    }

    /// Walks every SMC key once (~40 ms) to find the temperature keys and fans.
    private func discover() -> Catalog {
        var catalog = Catalog()
        guard let smc, let count = smc.keyCount() else { return catalog }
        for index in 0..<count {
            // Temperatures are `flt` on Apple silicon, `sp78` on older SMCs; other T keys are flags and counters.
            guard let key = smc.key(at: index), key.hasPrefix("T"),
                  let info = smc.info(key), ["flt ", "sp78"].contains(info.type)
            else { continue }
            if ThermalSensorGroup.of(sensorNamed: key, chip: chip) != nil {
                catalog.named.append(key)
            } else {
                catalog.unnamed.append(key)
            }
        }
        // A missing FNum means no fans; an FNum that exists but can't be read is a failure.
        if smc.info("FNum") == nil {
            catalog.fanNames = []
        } else if let fanCount = smc.number("FNum") {
            catalog.fanNames = (0..<Int(fanCount)).map { fanName(smc, index: $0) }
        }
        return catalog
    }

    /// The fan's name from its `F<n>ID` key (a 16-byte record with the name at bytes 4–15), if any.
    private func fanName(_ smc: SMC, index: Int) -> String? {
        guard let bytes = smc.read(Self.fanKey(index, "ID")), bytes.count >= 16 else { return nil }
        let name = String(decoding: bytes[4..<16].prefix { $0 != 0 }, as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Fan keys: `F0Ac` (current RPM), `F0Mn`/`F0Mx` (range), `F0ID` (name).
    private static func fanKey(_ index: Int, _ field: String) -> String {
        "F\(index)\(field)"
    }

    private static func state(_ state: ProcessInfo.ThermalState) -> ThermalState? {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: nil
        }
    }
}
