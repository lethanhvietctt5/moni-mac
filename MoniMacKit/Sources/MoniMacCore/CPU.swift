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
    var cpuSeries: [(SeriesKey, Double)] {
        guard let cpu = cpu.value else { return [] }
        return [(.cpuTotal, cpu.total), (.cpuUser, cpu.user), (.cpuSystem, cpu.system)]
    }
}
