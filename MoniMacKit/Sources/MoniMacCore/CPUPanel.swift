import Foundation

/// Everything the popover's CPU tab shows.
public struct CPUPanel: Equatable, Sendable {
    /// The ranges the popover chart offers.
    public static let ranges: [TimeRange] = [.oneMinute, .fiveMinutes, .oneHour, .twentyFourHours]
    public static let historyBarCount = 30
    public static let topAppCount = 4

    public struct StackedBar: Equatable, Sendable {
        /// Shares of the whole CPU, 0...1.
        public var user: Double
        public var system: Double
    }

    public struct Core: Equatable, Sendable {
        /// "P1", "E3", …
        public var label: String
        public var kind: CoreKind
        public var usage: Double
    }

    public struct AppRow: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var bundlePath: String?
        /// e.g. "23 processes".
        public var detail: String
        public var value: String
        /// Bar length: share of the whole CPU, 0...1.
        public var share: Double
        public var canQuit: Bool
    }

    /// e.g. "Apple M3 Pro · 12 cores".
    public var chipLine: String
    public var total: String
    public var range: TimeRange
    /// `historyBarCount` bars over `range`, oldest first; nil where there's no data.
    public var history: [StackedBar?]
    /// Current shares of the whole CPU, for the split bar.
    public var split: CPUUsage?
    public var user: String
    public var system: String
    public var idle: String
    /// 1, 5, and 15 minutes.
    public var loadAverages: [String]
    /// e.g. "6 Performance · 6 Efficiency".
    public var coreSummary: String
    /// Performance cores first, then efficiency cores.
    public var cores: [Core]
    public var topApps: [AppRow]
}

extension CPUPanel {
    @MainActor
    static func make(
        snapshot: Snapshot?, apps: [AppUsage], history: MetricsHistory, range: TimeRange, mode: CPUMode
    ) -> CPUPanel {
        let system = snapshot?.system ?? .unknown
        let cores = system.logicalCores
        let cpu = snapshot?.cpu.value
        let format = { (share: Double) in Format.cpu(share, mode: mode, logicalCores: cores) }

        return CPUPanel(
            chipLine: "\(system.chipName) · \(cores) cores",
            total: cpu.map { format($0.total) } ?? Format.placeholder,
            range: range,
            history: historyBars(history, range: range, endingAt: snapshot?.timestamp, count: historyBarCount),
            split: cpu,
            user: cpu.map { format($0.user) } ?? Format.placeholder,
            system: cpu.map { format($0.system) } ?? Format.placeholder,
            idle: cpu.map { format($0.idle) } ?? Format.placeholder,
            loadAverages: snapshot?.loadAverage.value.map {
                [$0.one, $0.five, $0.fifteen].map(Format.load)
            } ?? Array(repeating: Format.placeholder, count: 3),
            coreSummary: "\(system.performanceCores) Performance · \(system.efficiencyCores) Efficiency",
            cores: coreBars(snapshot?.cores.value ?? []),
            topApps: apps.prefix(topAppCount).map { app in
                let share = app.cpu / Double(max(cores, 1))
                return AppRow(
                    id: app.id, name: app.name, bundlePath: app.bundlePath,
                    detail: app.processCount == 1 ? "1 process" : "\(app.processCount) processes",
                    value: format(share), share: min(share, 1), canQuit: app.canQuit
                )
            }
        )
    }

    /// User and system history as `count` stacked bars over the range.
    @MainActor
    static func historyBars(_ history: MetricsHistory, range: TimeRange, endingAt now: Date?, count: Int) -> [StackedBar?] {
        guard let now else { return Array(repeating: nil, count: count) }
        func bars(_ series: SeriesKey) -> [Double?] {
            let points = (try? history.summary(series, over: range, endingAt: now).points) ?? []
            return Resample.bars(points, endingAt: now, window: range.duration, count: count)
        }
        return zip(bars(.cpuUser), bars(.cpuSystem)).map { user, system in
            guard let user, let system else { return nil }
            return StackedBar(user: user, system: system)
        }
    }

    /// Labels P1… then E1…, performance cores first, keeping kernel order within each kind.
    static func coreBars(_ cores: [CoreUsage]) -> [Core] {
        func bars(_ kind: CoreKind, prefix: String) -> [Core] {
            cores.filter { $0.kind == kind }.enumerated().map {
                Core(label: "\(prefix)\($0.offset + 1)", kind: kind, usage: $0.element.usage)
            }
        }
        return bars(.performance, prefix: "P") + bars(.efficiency, prefix: "E")
    }
}
