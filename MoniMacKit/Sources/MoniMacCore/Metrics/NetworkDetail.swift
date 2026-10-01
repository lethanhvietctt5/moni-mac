import Foundation

/// Everything the main window's Network tab shows.
public struct NetworkDetail: Equatable, Sendable {
    /// The live chart covers the last minute, one bar per 2-second sample.
    public static let liveBarCount = 30
    public static let topAppCount = 6

    /// e.g. "Wi-Fi 6E · Studio-5G · 1.2 Gb/s link".
    public var interfaceLine: String
    public var download: NetworkFormat.Rate
    public var upload: NetworkFormat.Rate
    /// Totals since MoniMac started, e.g. "3.8 GB".
    public var downloaded: String
    public var uploaded: String
    /// When the session totals started, e.g. "since 08:42".
    public var sessionStart: String
    /// The last 60 seconds, oldest first; nil where there's no data.
    public var live: [ThroughputBar?]
    public var lastWeek: DailyUsageChart
    public var lastMonth: DailyUsageChart
    public var topApps: [NetworkAppRow]
}

extension NetworkDetail {
    @MainActor
    static func make(
        snapshot: Snapshot?, apps: [AppUsage], history: MetricsHistory, units: NetworkUnits, sessionStart: Date,
        calendar: Calendar = .current
    ) -> NetworkDetail {
        let now = snapshot?.timestamp
        let rates = NetworkCharts.rates(snapshot, units: units)
        let totals = NetworkCharts.sessionTotals(history: history, since: sessionStart, now: now)
        func daily(_ days: Int) -> DailyUsageChart {
            NetworkCharts.daily(history: history, days: days, endingAt: now ?? sessionStart, calendar: calendar)
        }
        return NetworkDetail(
            interfaceLine: snapshot.map { NetworkFormat.interfaceLine($0.network) } ?? Format.placeholder,
            download: rates.down,
            upload: rates.up,
            downloaded: totals.down,
            uploaded: totals.up,
            sessionStart: NetworkCharts.sessionStart(sessionStart, now: now, calendar: calendar),
            live: now.map {
                NetworkCharts.throughputBars(history: history, over: .oneMinute, endingAt: $0, count: liveBarCount)
            } ?? Array(repeating: nil, count: liveBarCount),
            lastWeek: daily(7),
            lastMonth: daily(30),
            topApps: NetworkCharts.topApps(apps, count: topAppCount, units: units)
        )
    }
}
