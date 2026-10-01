import Foundation
import MoniMacCore

/// Reads the thermal state, temperature sensors, and fans for each snapshot. Read-only: it never
/// writes to the SMC and never controls fans.
///
/// SMC reads cost ~0.14 ms each, and an M4 has ~80 named temperature keys (~11 ms a pass), so they
/// are throttled: named sensors every `sensorInterval`, unnamed sensors and fan limits every
/// `slowInterval`, and only fan speeds every tick. Between reads the last values are reported.
@MainActor
final class ThermalReader {
    /// The SMC's temperature and fan keys, discovered once.
    private struct Catalog {
        /// Keys `SensorGroup` can name, read every `sensorInterval`.
        var named: [String] = []
        /// Other temperature keys, read every `slowInterval` (they're only counted).
        var unnamed: [String] = []
        var fanNames: [String?] = []
    }

    private let smc = SMC()
    private lazy var catalog: Catalog = discover()
    /// The IOHID fallback, created only if the SMC reports no named temperatures.
    private lazy var hid = ThermalHID()
    private let sensorInterval: UInt64
    private let slowInterval: UInt64
    private var readings: [String: Double] = [:]
    private var fanLimits: [(minimum: Double, maximum: Double)?] = []
    private var lastSensorRead: UInt64?
    private var lastSlowRead: UInt64?

    init(sensorInterval: TimeInterval = 5, slowInterval: TimeInterval = 60) {
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
        if smc == nil || catalog.named.isEmpty {
            // IOHID is costly; read it at the slow cadence.
            guard let hid else { return .unavailable(.unsupported) }
            if readSlow { readings = Dictionary(hid.read().map { ($0.name, $0.celsius) }) { first, _ in first } }
            return .value(readings.sorted { $0.key < $1.key }.map { ThermalSensor(name: $0.key, celsius: $0.value) })
        }
        guard let smc else { return .unavailable(.unsupported) }
        var keys = readNamed ? catalog.named : []
        if readSlow { keys += catalog.unnamed }
        for key in keys {
            readings[key] = smc.number(key)
        }
        let sensors = (catalog.named + catalog.unnamed).compactMap { key in
            readings[key].map { ThermalSensor(name: key, celsius: $0) }
        }
        return sensors.isEmpty ? .unavailable(.failed("The SMC returned no temperatures")) : .value(sensors)
    }

    private func fans(readLimits: Bool) -> Reading<[Fan]> {
        guard let smc else { return .unavailable(.failed("AppleSMC couldn't be opened")) }
        guard !catalog.fanNames.isEmpty else { return .unavailable(.unsupported) }
        if readLimits || fanLimits.count != catalog.fanNames.count {
            fanLimits = catalog.fanNames.indices.map { index in
                guard let minimum = smc.number("F\(index)Mn"), let maximum = smc.number("F\(index)Mx") else { return nil }
                return (minimum, maximum)
            }
        }
        let fans = catalog.fanNames.enumerated().compactMap { index, name -> Fan? in
            guard let limits = fanLimits[index], let rpm = smc.number("F\(index)Ac") else { return nil }
            return Fan(name: name, rpm: max(rpm, 0), minimumRPM: limits.minimum, maximumRPM: limits.maximum)
        }
        return fans.isEmpty ? .unavailable(.failed("The SMC returned no fan speeds")) : .value(fans)
    }

    /// Walks every SMC key once (~0.1 s) to find the temperature keys and fans.
    private func discover() -> Catalog {
        var catalog = Catalog()
        guard let smc, let count = smc.keyCount() else { return catalog }
        for index in 0..<count {
            // Temperatures are `flt` on Apple silicon, `sp78` on older SMCs; other T keys are flags and counters.
            guard let key = smc.key(at: index), key.hasPrefix("T"),
                  let info = smc.info(key), ["flt ", "sp78"].contains(info.type)
            else { continue }
            if SensorGroup.of(sensorNamed: key) != nil {
                catalog.named.append(key)
            } else {
                catalog.unnamed.append(key)
            }
        }
        let fanCount = Int(smc.number("FNum") ?? 0)
        catalog.fanNames = (0..<fanCount).map { fanName(smc, index: $0) }
        return catalog
    }

    /// The fan's name from its `F<n>ID` key (a 16-byte record with the name at bytes 4–15), if any.
    private func fanName(_ smc: SMC, index: Int) -> String? {
        guard let bytes = smc.read("F\(index)ID"), bytes.count >= 16 else { return nil }
        let name = String(decoding: bytes[4..<16].prefix { $0 != 0 }, as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private static func state(_ state: ProcessInfo.ThermalState) -> ThermalState {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .serious
        }
    }
}
