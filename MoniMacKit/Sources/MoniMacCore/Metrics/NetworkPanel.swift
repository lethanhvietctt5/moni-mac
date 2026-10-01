import Foundation

/// Everything the popover's Network tab shows: a compact version of the window tab.
public struct NetworkPanel: Equatable, Sendable {
    /// The ranges the popover chart offers.
    public static let ranges: [TimeRange] = CPUPanel.ranges
    public static let historyBarCount = 30
    public static let topAppCount = 4

    /// e.g. "Wi-Fi 6E · Studio-5G · 1.2 Gb/s link".
    public var interfaceLine: String
    public var download: NetworkFormat.Rate
    public var upload: NetworkFormat.Rate
    public var range: TimeRange
    /// `historyBarCount` bars over `range`, oldest first; nil where there's no data.
    public var history: [ThroughputBar?]
    /// Totals since MoniMac started.
    public var downloaded: String
    public var uploaded: String
    /// e.g. "since 08:42".
    public var sessionStart: String
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
        let rates = NetworkCharts.rates(snapshot, units: units)
        let totals = NetworkCharts.sessionTotals(history: history, since: sessionStart, now: now)
        return NetworkPanel(
            interfaceLine: snapshot.map { NetworkFormat.interfaceLine($0.network) } ?? Format.placeholder,
            download: rates.down,
            upload: rates.up,
            range: range,
            history: now.map {
                NetworkCharts.throughputBars(history: history, over: range, endingAt: $0, count: historyBarCount)
            } ?? Array(repeating: nil, count: historyBarCount),
            downloaded: totals.down,
            uploaded: totals.up,
            sessionStart: NetworkCharts.sessionStart(sessionStart, now: now, calendar: calendar),
            lastWeek: NetworkCharts.daily(history: history, days: 7, endingAt: now ?? sessionStart, calendar: calendar),
            topApps: NetworkCharts.topApps(apps, count: topAppCount, units: units)
        )
    }
}
