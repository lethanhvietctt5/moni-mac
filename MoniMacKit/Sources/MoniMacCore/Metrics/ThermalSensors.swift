import Foundation

/// Where in the Mac a temperature sensor sits, as far as its name tells.
public enum SensorGroup: CaseIterable, Sendable {
    case performanceCores, efficiencyCores, socDie, gpu, memory, ssd, battery, palmRest, wireless, ambient

    public var title: String {
        switch self {
        case .performanceCores: "CPU Performance Cores"
        case .efficiencyCores: "CPU Efficiency Cores"
        case .socDie: "SoC Die"
        case .gpu: "GPU Cluster"
        case .memory: "Memory"
        case .ssd: "SSD"
        case .battery: "Battery"
        case .palmRest: "Palm Rest"
        case .wireless: "Wireless Module"
        case .ambient: "Ambient"
        }
    }

    /// Readings outside this band are placeholders the hardware reports for idle or absent sensors
    /// (0, 6.2, −9201 °C), not temperatures.
    static let plausible: ClosedRange<Double> = 1...125

    /// The group a sensor belongs to, or nil when its name doesn't say where it sits.
    ///
    /// SMC key names follow the convention other Apple silicon monitors (Stats, macmon) use;
    /// Apple doesn't document them. Keys not listed here stay unnamed rather than guessed.
    public static func of(sensorNamed name: String) -> SensorGroup? {
        // IOHID products (the fallback source).
        if name.hasPrefix("NAND ") { return .ssd }
        if name.hasPrefix("gas gauge battery") { return .battery }
        if name.hasPrefix("PMU"), name.contains(" tdie") { return .socDie }

        // SMC keys: four characters starting with T.
        let key = Array(name)
        guard key.count == 4, key[0] == "T" else { return nil }
        switch (key[1], key[2], key[3]) {
        case ("p", _, _): return .performanceCores
        case ("e", _, _): return .efficiencyCores
        case ("g", _, _): return .gpu
        case ("m", _, "P"), ("m", _, "p"): return .memory
        case ("H", "0", _): return .ssd
        case ("B", _, "T"): return .battery
        case ("s", "0", "P"), ("s", "1", "P"): return .palmRest
        case ("W", "0", "P"): return .wireless
        case ("A", "0", "P"), ("A", "1", "P"): return .ambient
        default: return nil
        }
    }
}

/// Sensors averaged per group.
public struct ThermalGroups: Equatable, Sendable {
    /// Average °C per group, for groups with at least one plausible reading.
    public private(set) var averages: [SensorGroup: Double] = [:]
    /// The CPU: every performance and efficiency core sensor averaged. Falls back to the SoC die
    /// when the cores aren't reported separately.
    public private(set) var cpu: Double?
    /// Plausible readings whose name doesn't say where they sit.
    public private(set) var unnamedCount = 0

    public init(_ sensors: [ThermalSensor]) {
        var named: [SensorGroup: [Double]] = [:]
        for sensor in sensors where SensorGroup.plausible.contains(sensor.celsius) {
            if let group = SensorGroup.of(sensorNamed: sensor.name) {
                named[group, default: []].append(sensor.celsius)
            } else {
                unnamedCount += 1
            }
        }
        func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        averages = named.compactMapValues(mean)
        cpu = mean((named[.performanceCores] ?? []) + (named[.efficiencyCores] ?? [])) ?? averages[.socDie]
    }

    /// The group's average °C, or nil when the Mac doesn't report it.
    public func average(_ group: SensorGroup) -> Double? { averages[group] }

    /// The hottest group average.
    public var hottest: Double? { averages.values.max() }
}
