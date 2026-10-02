import Foundation

/// The notification rules a user can turn on and tune in Settings › Notifications. Each watches one app
/// at a time; the system-wide CPU rule behind the menu bar warning badge isn't one of them (see `AlertEngine`).
///
/// Thresholds are stored in one unit per rule, independent of display settings:
/// - `appCPU`: **cores** (1.0 = one core fully busy), the unit of `AppUsage.cpu`. The CPU mode only changes
///   how it reads: 0.8 is "80%" in Per-core and "6.7%" in System on 12 cores. Flipping the mode never changes
///   when the rule fires.
/// - `memoryGrowth`: bytes (binary, like every memory figure).
/// - `diskWrites`: bytes written per hour (decimal, like every disk figure).
/// - `network`: bytes per second, in and out together (decimal).
public enum AlertRule: String, CaseIterable, Sendable {
    case appCPU, memoryGrowth, diskWrites, network

    var enabledByDefault: Bool { self != .network }

    /// Disk and network turn on and off with a switch, as the design draws them; CPU and memory have
    /// an "Off" entry in their threshold menu instead.
    var hasSwitch: Bool { self == .diskWrites || self == .network }

    var defaultThreshold: Double {
        switch self {
        case .appCPU: 0.8
        case .memoryGrowth: 1_073_741_824
        case .diskWrites: 10_000_000_000
        case .network: 10_000_000
        }
    }

    /// The thresholds Settings offers.
    var thresholdOptions: [Double] {
        switch self {
        case .appCPU: [0.5, 0.8, 1, 2, 4]
        case .memoryGrowth: [536_870_912, 1_073_741_824, 2_147_483_648, 4_294_967_296]
        case .diskWrites: [5_000_000_000, 10_000_000_000, 20_000_000_000, 50_000_000_000]
        case .network: [1_000_000, 5_000_000, 10_000_000, 25_000_000, 50_000_000]
        }
    }

    /// How long a sustained rule's condition must hold, or the window a growth or volume rule looks back over.
    var duration: TimeInterval {
        switch self {
        case .appCPU: 120
        case .memoryGrowth: 600
        case .diskWrites: 3600
        case .network: 240
        }
    }

    /// Where "Show" lands: the Overview List sorted by this column, with the app expanded.
    var column: OverviewListColumn {
        switch self {
        case .appCPU: .cpu
        case .memoryGrowth: .memory
        case .diskWrites: .disk
        case .network: .network
        }
    }
}

/// One rule's settings.
public struct AlertRuleSettings: Equatable, Sendable {
    public var isEnabled: Bool
    public var threshold: Double

    public init(isEnabled: Bool, threshold: Double) {
        self.isEnabled = isEnabled
        self.threshold = threshold
    }
}

extension Preferences {
    /// A rule's settings, keyed `alerts.<rule>.enabled` and `alerts.<rule>.threshold`. CPU, memory, and disk
    /// rules are on by default; network is off.
    public func alertSettings(_ rule: AlertRule) -> AlertRuleSettings {
        let threshold = defaults.object(forKey: Self.alertThresholdKey(rule)) as? Double
        return AlertRuleSettings(
            isEnabled: defaults.object(forKey: Self.alertEnabledKey(rule)) as? Bool ?? rule.enabledByDefault,
            // A hand-edited zero or negative threshold would alert on everything.
            threshold: threshold.flatMap { $0 > 0 ? $0 : nil } ?? rule.defaultThreshold
        )
    }

    func setAlertEnabled(_ enabled: Bool, for rule: AlertRule) {
        set(enabled, forKey: Self.alertEnabledKey(rule))
    }

    func setAlertThreshold(_ threshold: Double, for rule: AlertRule) {
        set(threshold, forKey: Self.alertThresholdKey(rule))
    }

    private static func alertEnabledKey(_ rule: AlertRule) -> String { "alerts.\(rule.rawValue).enabled" }
    private static func alertThresholdKey(_ rule: AlertRule) -> String { "alerts.\(rule.rawValue).threshold" }
}

/// How alert figures read: thresholds in Settings and the figures in notifications follow the user's units.
struct AlertFormat {
    var cpuMode: CPUMode
    var logicalCores: Int
    var networkUnits: NetworkUnits

    /// CPU given in cores, e.g. "412%" in Per-core or "34%" in System on 12 cores; one decimal below 10%.
    /// Before the core count is known, per-core figures are the only honest reading.
    func cpu(cores: Double) -> String {
        guard logicalCores > 0 else { return Format.cpu(cores, mode: .perCore, logicalCores: 1) }
        let share = cores / Double(logicalCores)
        let shown = cpuMode == .system ? share : cores
        return Format.cpu(share, mode: cpuMode, logicalCores: logicalCores, decimals: shown < 0.095 ? 1 : 0)
    }

    /// e.g. "10 MB/s" or "80 Mbps"; a threshold drops a trailing ".0".
    func networkRate(_ bytesPerSecond: Double, trimmed: Bool = false) -> String {
        var rate = NetworkFormat.rate(bytesPerSecond, units: networkUnits)
        if trimmed, rate.value.hasSuffix(".0") { rate.value.removeLast(2) }
        return rate.text
    }

    /// A rule's threshold as Settings shows it, e.g. "80%", "1 GB", "10 GB", "10 MB/s".
    func threshold(_ value: Double, for rule: AlertRule) -> String {
        switch rule {
        case .appCPU: cpu(cores: value).replacingOccurrences(of: ".0%", with: "%")
        case .memoryGrowth: Format.memorySize(UInt64(max(value, 0)))
        case .diskWrites: DiskFormat.bytes(value)
        case .network: networkRate(value, trimmed: true)
        }
    }
}
