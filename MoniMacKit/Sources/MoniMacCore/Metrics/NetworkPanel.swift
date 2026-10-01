import Foundation

/// Everything the popover's Network tab shows: a compact version of the window tab.
public struct NetworkPanel: Equatable, Sendable {
    /// The ranges the popover chart offers, the same as every popover tab.
    public static let ranges: [TimeRange] = CPUPanel.ranges
    public static let historyBarCount = 30
    public static let topAppCount = 4

    public var summary: NetworkSummary
    public var range: TimeRange
    /// `historyBarCount` bars over `range`, oldest first; nil where there's no data.
    public var history: [ThroughputBar?]
    public var lastWeek: DailyUsageChart
    public var topApps: [NetworkAppRow]
}

extension NetworkPanel {
    @MainActor
    static func make(
        snapshot: Snapshot?, apps: [AppUsage], history: MetricsHistory, range: TimeRange, units: NetworkUnits,
        sessionStart: Date, calendar: Calendar = .current
    ) -> NetworkPanel {
        let now = snapshot?.timestamp
        return NetworkPanel(
            summary: .make(snapshot: snapshot, history: history, units: units, sessionStart: sessionStart,
                           calendar: calendar),
            range: range,
            history: now.map {
                NetworkFigures.throughputBars(history: history, over: range, endingAt: $0, count: historyBarCount)
            } ?? Array(repeating: nil, count: historyBarCount),
            lastWeek: NetworkFigures.daily(history: history, days: 7, endingAt: now ?? sessionStart, calendar: calendar),
            topApps: NetworkFigures.topApps(apps, count: topAppCount, units: units)
        )
    }
}
