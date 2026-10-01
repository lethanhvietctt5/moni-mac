import Foundation

/// One column of a network chart: download stacked under upload, each a share of the chart's height.
public struct ThroughputBar: Equatable, Sendable {
    public var down: Double
    public var up: Double
}

/// Per-day download and upload over the last N days.
public struct DailyUsageChart: Equatable, Sendable {
    /// e.g. "↓ 85.5 GB · ↑ 9.8 GB".
    public var totals: String
    /// One per day, oldest first, scaled to `yAxis`; nil for days with no history.
    public var bars: [ThroughputBar?]
    /// Top, middle, and bottom of the scale, e.g. ["25 GB", "12.5 GB", "0"]. Empty with no history.
    public var yAxis: [String]
    /// One per bar; nil where the bar has no label. The last is "Today".
    public var xAxis: [String?]
}

/// An app's live network rate.
public struct NetworkAppRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var bundlePath: String?
    /// e.g. "3.2 MB/s".
    public var value: String
    /// Bar length, relative to the busiest app: 0...1.
    public var share: Double
    public var canQuit: Bool
}

/// Chart and list building shared by the popover and window Network tabs.
enum NetworkCharts {
    /// Download and upload over `range` as `count` bars, scaled so the busiest bar is full height.
    @MainActor
    static func throughputBars(
        history: MetricsHistory, over range: TimeRange, endingAt now: Date, count: Int
    ) -> [ThroughputBar?] {
        func bars(_ series: SeriesKey) -> [Double?] {
            let points = (try? history.summary(series, over: range, endingAt: now).points) ?? []
            return Resample.bars(points, endingAt: now, window: range.duration, count: count)
        }
        let pairs: [(down: Double, up: Double)?] = zip(bars(.networkDown), bars(.networkUp)).map { down, up in
            guard let down, let up else { return nil }
            return (down, up)
        }
        let peak = pairs.compactMap { $0.map { $0.down + $0.up } }.max() ?? 0
        return pairs.map { pair in
            pair.map { peak > 0 ? ThroughputBar(down: $0.down / peak, up: $0.up / peak) : ThroughputBar(down: 0, up: 0) }
        }
    }

    /// Per-day totals for the last `days` days, ending today.
    @MainActor
    static func daily(
        history: MetricsHistory, days: Int, endingAt now: Date, calendar: Calendar
    ) -> DailyUsageChart {
        func totals(_ series: SeriesKey) -> [Double?] {
            (try? history.dailyTotals(series, days: days, endingAt: now, calendar: calendar).map(\.total))
                ?? Array(repeating: nil, count: days)
        }
        let down = totals(.networkDownBytes)
        let up = totals(.networkUpBytes)
        let dayStarts = (0..<days).reversed().map {
            calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: now))!
        }
        let xAxis = dayStarts.enumerated().map { index, day -> String? in
            if index == days - 1 { return "Today" }
            if days <= 7 { return format(day, "EEE", calendar) }
            // Weekly, leaving room before "Today".
            return index % 7 == 0 && index + 7 < days ? format(day, "MMM d", calendar) : nil
        }

        let recorded = zip(down, up).filter { $0 != nil || $1 != nil }
        guard !recorded.isEmpty else {
            return DailyUsageChart(totals: "No history yet", bars: Array(repeating: nil, count: days), yAxis: [],
                                   xAxis: xAxis)
        }
        let peak = recorded.map { ($0 ?? 0) + ($1 ?? 0) }.max() ?? 0
        let scale = niceCeiling(peak)
        let bars = zip(down, up).map { down, up -> ThroughputBar? in
            guard down != nil || up != nil else { return nil }
            return ThroughputBar(down: (down ?? 0) / scale, up: (up ?? 0) / scale)
        }
        let sum = { (values: [Double?]) in values.compactMap { $0 }.reduce(0, +) }
        return DailyUsageChart(
            totals: "↓ \(NetworkFormat.bytes(sum(down))) · ↑ \(NetworkFormat.bytes(sum(up)))",
            bars: bars,
            yAxis: [NetworkFormat.bytes(scale), NetworkFormat.bytes(scale / 2), "0"],
            xAxis: xAxis
        )
    }

    /// Apps moving data right now, busiest first.
    static func topApps(_ apps: [AppUsage], count: Int, units: NetworkUnits) -> [NetworkAppRow] {
        let active = apps.enumerated()
            .compactMap { index, app in (app.resources.network ?? 0) > 0 ? (index, app) : nil }
            .sorted { lhs, rhs in
                let (a, b) = (lhs.1.resources.network ?? 0, rhs.1.resources.network ?? 0)
                return a != b ? a > b : lhs.0 < rhs.0
            }
            .prefix(count)
            .map(\.1)
        let busiest = active.first?.resources.network ?? 0
        return active.map { app in
            let rate = app.resources.network ?? 0
            return NetworkAppRow(
                id: app.id, name: app.name, bundlePath: app.bundlePath,
                value: NetworkFormat.rate(rate, units: units).text,
                share: busiest > 0 ? rate / busiest : 0, canQuit: app.canQuit
            )
        }
    }

    /// Download and upload totals since `start`.
    @MainActor
    static func sessionTotals(history: MetricsHistory, since start: Date, now: Date?) -> (down: String, up: String) {
        guard let now else { return (Format.placeholder, Format.placeholder) }
        func total(_ series: SeriesKey) -> String {
            ((try? history.sum(series, from: start, to: now)) ?? nil).map(NetworkFormat.bytes) ?? Format.placeholder
        }
        return (total(.networkDownBytes), total(.networkUpBytes))
    }

    /// e.g. "since 08:42", or "since 29 Sep 08:42" for a session that started on an earlier day.
    static func sessionStart(_ start: Date, now: Date?, calendar: Calendar) -> String {
        let sameDay = now.map { calendar.isDate(start, inSameDayAs: $0) } ?? true
        return "since " + format(start, sameDay ? "HH:mm" : "d MMM HH:mm", calendar)
    }

    /// The download and upload rates, or placeholders.
    static func rates(_ snapshot: Snapshot?, units: NetworkUnits) -> (down: NetworkFormat.Rate, up: NetworkFormat.Rate) {
        guard let network = snapshot?.network.value else {
            let dash = NetworkFormat.Rate(value: Format.placeholder, unit: "")
            return (dash, dash)
        }
        return (NetworkFormat.rate(network.downloadPerSecond, units: units),
                NetworkFormat.rate(network.uploadPerSecond, units: units))
    }

    /// The smallest 1, 2, 2.5, or 5 × 10ⁿ at or above `value`.
    private static func niceCeiling(_ value: Double) -> Double {
        guard value > 0 else { return 1000 }
        let base = pow(10, (log10(value)).rounded(.down))
        return [1, 2, 2.5, 5, 10].map { $0 * base }.first { $0 >= value * 0.999_999 } ?? 10 * base
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
