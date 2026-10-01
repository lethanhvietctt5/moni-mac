import Foundation

/// Where in the Mac a temperature sensor sits, as far as its name tells.
public enum ThermalSensorGroup: CaseIterable, Sendable {
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
    /// `chip` is the brand string, e.g. "Apple M2 Pro": core and GPU keys differ per generation.
    /// SMC key names follow the per-chip tables other Apple silicon monitors use (Stats, macmon);
    /// Apple doesn't document them. Keys not covered stay unnamed rather than guessed.
    public static func of(sensorNamed name: String, chip: String) -> ThermalSensorGroup? {
        // IOHID products (the fallback source).
        if name.hasPrefix("NAND ") { return .ssd }
        if name.hasPrefix("gas gauge battery") { return .battery }
        if name.hasPrefix("PMU"), name.contains(" tdie") { return .socDie }

        // SMC keys: four characters starting with T.
        let key = Array(name)
        guard key.count == 4, key[0] == "T" else { return nil }
        if let group = coreOrGPU(key: name, generation: generation(of: chip)) { return group }
        switch (key[1], key[2], key[3]) {
        case ("m", _, "P"), ("m", _, "p"): return .memory
        case ("H", "0", _): return .ssd
        case ("B", _, "T"): return .battery
        case ("s", "0", "P"), ("s", "1", "P"): return .palmRest
        case ("W", "0", "P"): return .wireless
        case ("A", "0", "P"), ("A", "1", "P"): return .ambient
        default: return nil
        }
    }

    /// CPU core and GPU keys, which each Apple silicon generation lays out differently.
    private static func coreOrGPU(key: String, generation: Int?) -> ThermalSensorGroup? {
        let prefix = key.prefix(2)
        let third = key.dropFirst(2).first
        switch generation {
        case 1:
            // M1 reports its efficiency cores under Tp too.
            if ["Tp09", "Tp0T"].contains(key) { return .efficiencyCores }
        case 2:
            if ["Tp1h", "Tp1t", "Tp1p", "Tp1l"].contains(key) { return .efficiencyCores }
        case 3:
            // M3 moved performance cores (Tf0x, Tf4x) and the GPU (Tf1x, Tf2x) to Tf.
            if prefix == "Tf", let third {
                if third == "0" || third == "4" { return .performanceCores }
                if third == "1" || third == "2" { return .gpu }
            }
        default:
            break
        }
        switch prefix {
        case "Tp": return .performanceCores
        case "Te": return .efficiencyCores
        case "Tg": return .gpu
        default: return nil
        }
    }

    /// 1 for "Apple M1 Pro", 4 for "Apple M4"; nil for anything else.
    static func generation(of chip: String) -> Int? {
        guard let range = chip.range(of: #"Apple M(\d+)"#, options: .regularExpression) else { return nil }
        return Int(chip[range].dropFirst("Apple M".count))
    }
}

/// Sensors averaged per group.
public struct ThermalGroups: Equatable, Sendable {
    /// Average °C per group, for groups with at least one plausible reading.
    private var averages: [ThermalSensorGroup: Double] = [:]
    /// The CPU: every performance and efficiency core sensor averaged. Falls back to the SoC die
    /// when the cores aren't reported separately.
    public private(set) var cpu: Double?
    /// Plausible readings whose name doesn't say where they sit.
    public private(set) var unnamedCount = 0

    /// `chip` is the brand string, e.g. "Apple M4" (`SystemInfo.chipName`).
    public init(_ sensors: [ThermalSensor], chip: String) {
        var named: [ThermalSensorGroup: [Double]] = [:]
        for sensor in sensors where ThermalSensorGroup.plausible.contains(sensor.celsius) {
            if let group = ThermalSensorGroup.of(sensorNamed: sensor.name, chip: chip) {
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
    public func average(_ group: ThermalSensorGroup) -> Double? { averages[group] }

    /// The hottest group average.
    public var hottest: Double? { averages.values.max() }
}
