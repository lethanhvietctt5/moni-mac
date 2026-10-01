import Foundation

/// Everything the main window's CPU tab shows.
public struct CPUDetail: Equatable, Sendable {
    /// The ranges the window chart offers.
    public static let ranges: [TimeRange] = [.twelveHours, .twentyFourHours, .sevenDays, .thirtyDays]
    public static let historyBarCount = 36
    public static let topAppCount = 5

    public struct Stat: Equatable, Sendable {
        public var label: String
        public var value: String
        public var detail: String
    }

    public struct Core: Equatable, Sendable {
        /// "P1", "E3", …
        public var label: String
        public var kind: CoreKind
        public var usage: Double
        /// e.g. "72%".
        public var value: String
    }

    public struct AppRow: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var bundlePath: String?
        /// e.g. "12.4%".
        public var value: String
        /// Bar length: share of the whole CPU, 0...1.
        public var share: Double
    }

    /// Toolbar subtitle, e.g. "Apple M3 Pro · 12 cores (6P + 6E)".
    public var subtitle: String
    public var total: String
    /// Current shares of the whole CPU, for the usage bar.
    public var split: CPUUsage?
    /// User, System, Idle, Load Average, Threads.
    public var stats: [Stat]
    public var range: TimeRange
    /// e.g. "Peak 87% at 14:12", or nil with no history in the range.
    public var peak: String?
    /// `historyBarCount` bars over `range`, oldest first; nil where there's no data.
    public var history: [CPUPanel.StackedBar?]
    /// Top, middle, and bottom of the chart's scale, e.g. ["100%", "50%", "0%"].
    public var yAxis: [String]
    /// Evenly spaced from the start of the range; the last is "Now".
    public var xAxis: [String]
    /// e.g. "6 performance · 6 efficiency".
    public var coreSummary: String
    /// Performance cores first, then efficiency cores.
    public var cores: [Core]
    public var topApps: [AppRow]
}

extension CPUDetail {
    @MainActor
    static func make(
        snapshot: Snapshot?, apps: [AppUsage], history: MetricsHistory, range: TimeRange, mode: CPUMode,
        timeZone: TimeZone = .current
    ) -> CPUDetail {
        let system = snapshot?.system ?? .unknown
        let cores = system.logicalCores
        let cpu = snapshot?.cpu.value
        let format = { (share: Double) in Format.cpu(share, mode: mode, logicalCores: cores) }
        let dash = Format.placeholder
        let load = snapshot?.loadAverage.value
        let tasks = snapshot?.taskCounts.value
        let now = snapshot?.timestamp
        let peak = now.flatMap { try? history.summary(.cpuTotal, over: range, endingAt: $0).peak }

        return CPUDetail(
            subtitle: "\(system.chipName) · \(cores) cores (\(system.performanceCores)P + \(system.efficiencyCores)E)",
            total: cpu.map { format($0.total) } ?? dash,
            split: cpu,
            stats: [
                Stat(label: "User", value: cpu.map { format($0.user) } ?? dash, detail: "Apps & services"),
                Stat(label: "System", value: cpu.map { format($0.system) } ?? dash, detail: "macOS kernel"),
                Stat(label: "Idle", value: cpu.map { format($0.idle) } ?? dash,
                     detail: cpu.map { String(format: "%.1f of %d cores", $0.idle * Double(cores), cores) } ?? dash),
                Stat(label: "Load Average", value: load.map { Format.load($0.one) } ?? dash,
                     detail: load.map { "5m \(Format.load($0.five)) · 15m \(Format.load($0.fifteen))" } ?? dash),
                Stat(label: "Threads", value: tasks.map { Format.count($0.threads) } ?? dash,
                     detail: tasks.map { "\(Format.count($0.processes)) processes" } ?? dash),
            ],
            range: range,
            peak: peak.map { "Peak \(format($0.value)) at \(Format.time($0.time, within: range, timeZone: timeZone))" },
            history: CPUPanel.historyBars(history, range: range, endingAt: now, count: historyBarCount),
            yAxis: [format(1), format(0.5), format(0)],
            xAxis: xAxis(range: range, endingAt: now, timeZone: timeZone),
            coreSummary: "\(system.performanceCores) performance · \(system.efficiencyCores) efficiency",
            cores: CPUPanel.coreBars(snapshot?.cores.value ?? []).map {
                Core(label: $0.label, kind: $0.kind, usage: $0.usage, value: Format.percent($0.usage))
            },
            topApps: apps.prefix(topAppCount).map { app in
                let share = app.cpu / Double(max(cores, 1))
                return AppRow(id: app.id, name: app.name, bundlePath: app.bundlePath,
                              value: Format.cpu(share, mode: mode, logicalCores: cores, decimals: 1),
                              share: min(share, 1))
            }
        )
    }

    /// Four labels at 0, ¼, ½, ¾ of the range, then "Now". Within a day they snap to the hour.
    private static func xAxis(range: TimeRange, endingAt now: Date?, timeZone: TimeZone) -> [String] {
        guard let now else { return [] }
        let start = now.addingTimeInterval(-range.duration)
        return (0..<4).map { index in
            var date = start.addingTimeInterval(range.duration * Double(index) / 4)
            if range.duration <= TimeRange.twentyFourHours.duration {
                date = Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 3600).rounded(.down) * 3600)
            }
            let label = Format.time(date, within: range, timeZone: timeZone)
            // For a week, the weekday alone reads better on an axis.
            return range == .sevenDays ? String(label.prefix(3)) : label
        } + ["Now"]
    }
}
