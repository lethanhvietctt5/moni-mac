import Foundation

/// Share of total CPU time over one interval, each in 0...1. `user + system + idle == 1`.
public struct CPUUsage: Equatable, Sendable {
    public var user: Double
    public var system: Double
    public var idle: Double

    public init(user: Double, system: Double, idle: Double) {
        self.user = user
        self.system = system
        self.idle = idle
    }

    /// Fraction of the whole CPU in use (user + system), 0...1.
    public var total: Double { user + system }
}

/// Cumulative per-state CPU ticks as the kernel reports them. The counters are 32-bit and wrap.
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt32
    public var system: UInt32
    public var idle: UInt32
    public var nice: UInt32

    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

extension CPUUsage {
    /// Usage between two tick readings. Nice time counts as user time.
    /// Returns nil when no time elapsed between the readings.
    public init?(from previous: CPUTicks, to current: CPUTicks) {
        let user = Double(current.user &- previous.user) + Double(current.nice &- previous.nice)
        let system = Double(current.system &- previous.system)
        let idle = Double(current.idle &- previous.idle)
        let total = user + system + idle
        guard total > 0 else { return nil }
        self.init(user: user / total, system: system / total, idle: idle / total)
    }
}

extension Snapshot {
    /// Values MetricsHistory records for CPU.
    var cpuSeries: [SeriesSample] {
        guard let cpu = cpu.value else { return [] }
        let busiest = AppGrouping.busiestApp(in: processes.value ?? [], by: \.cpu)
        return [
            SeriesSample(.cpuTotal, cpu.total, contributor: busiest),
            SeriesSample(.cpuUser, cpu.user),
            SeriesSample(.cpuSystem, cpu.system),
        ]
    }
}

/// The CPU menu bar item.
enum CPUMenuBar: MenuBarMetric {
    /// Per-core reaches four digits, e.g. "1200%" on 12 cores.
    static func widestText(preferences: Preferences) -> String {
        preferences.cpuMode == .system ? "100%" : "1000%"
    }

    static func text(_ snapshot: Snapshot?, preferences: Preferences) -> String {
        guard let snapshot, let cpu = snapshot.cpu.value else { return Format.placeholder }
        return Format.cpu(cpu.total, mode: preferences.cpuMode, logicalCores: snapshot.system.logicalCores)
    }

    @MainActor
    static func bars(history: MetricsHistory, endingAt now: Date?) -> [Double?] {
        guard let now else { return Sparkline.empty }
        let points = (try? history.summary(.cpuTotal, over: .oneMinute, endingAt: now).points) ?? []
        return Sparkline.bars(points, endingAt: now)
    }
}

extension Monitor {
    /// The main window toolbar subtitle for the CPU tab.
    public var cpuSubtitle: String? {
        latest.map { CPUDetail.subtitle(for: $0.system) }
    }
}
