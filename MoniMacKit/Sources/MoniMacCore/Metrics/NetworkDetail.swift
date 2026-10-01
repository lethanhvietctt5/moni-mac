import Foundation

/// The headline figures both Network tabs show: the connection, live rates, and session totals.
public struct NetworkSummary: Equatable, Sendable {
    /// e.g. "Wi-Fi 6E · Studio-5G · 1.2 Gb/s link".
    public var interfaceLine: String
    public var download: NetworkFormat.Rate
    public var upload: NetworkFormat.Rate
    /// Totals since MoniMac started, e.g. "3.8 GB".
    public var downloaded: String
    public var uploaded: String
    /// When the session totals started, e.g. "since 08:42".
    public var sessionStart: String
}

extension NetworkSummary {
    @MainActor
    static func make(
        snapshot: Snapshot?, history: MetricsHistory, units: NetworkUnits, sessionStart: Date, calendar: Calendar
    ) -> NetworkSummary {
        let now = snapshot?.timestamp
        let network = snapshot?.network.value
        let dash = NetworkFormat.Rate(value: Format.placeholder, unit: "")
        func total(_ series: SeriesKey) -> String {
            guard let now, let bytes = (try? history.sum(series, from: sessionStart, to: now)) ?? nil else {
                return Format.placeholder
            }
            return NetworkFormat.bytes(bytes)
        }
        return NetworkSummary(
            interfaceLine: snapshot.map { NetworkFormat.interfaceLine($0.network) } ?? Format.placeholder,
            download: network.map { NetworkFormat.rate($0.downloadPerSecond, units: units) } ?? dash,
            upload: network.map { NetworkFormat.rate($0.uploadPerSecond, units: units) } ?? dash,
            downloaded: total(.networkDownBytes),
            uploaded: total(.networkUpBytes),
            sessionStart: NetworkFigures.sessionStart(sessionStart, now: now, calendar: calendar)
        )
    }
}

/// Everything the main window's Network tab shows.
public struct NetworkDetail: Equatable, Sendable {
    /// The live chart covers the last minute, one bar per 2-second sample.
    public static let liveBarCount = 30
    public static let topAppCount = 6

    public var summary: NetworkSummary
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
        func daily(_ days: Int) -> DailyUsageChart {
            NetworkFigures.daily(history: history, days: days, endingAt: now ?? sessionStart, calendar: calendar)
        }
        return NetworkDetail(
            summary: .make(snapshot: snapshot, history: history, units: units, sessionStart: sessionStart,
                           calendar: calendar),
            live: now.map {
                NetworkFigures.throughputBars(history: history, over: .oneMinute, endingAt: $0, count: liveBarCount)
            } ?? Array(repeating: nil, count: liveBarCount),
            lastWeek: daily(7),
            lastMonth: daily(30),
            topApps: NetworkFigures.topApps(apps, count: topAppCount, units: units)
        )
    }
}
