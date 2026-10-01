import Foundation

/// Everything the main window's GPU tab shows.
public struct GPUDetail: Equatable, Sendable {
    /// The ranges the window chart offers.
    public static let ranges: [TimeRange] = [.twelveHours, .twentyFourHours, .sevenDays, .thirtyDays]
    public static let historyBarCount = 36
    public static let topAppCount = 6
    public static let tileBarCount = 16
    /// What the Utilization and GPU Memory tile sparklines cover.
    public static let liveTileWindow = TimeRange.fiveMinutes

    public struct Tile: Equatable, Sendable {
        public var label: String
        public var value: String
        public var caption: String
        /// `tileBarCount` sparkline bars, 0...1, oldest first; nil where there's no data.
        public var bars: [Double?]
    }

    public typealias AppRow = GPUPanel.AppRow

    /// Toolbar subtitle, e.g. "Apple M4 · 10-core GPU".
    public var subtitle: String?
    public var utilization: Tile
    public var memory: Tile
    /// Over the last 24 hours, compared with the 24 hours before.
    public var average: Tile
    /// The highest sample in the last 24 hours, the app that caused it, and when.
    public var peak: Tile
    public var range: TimeRange
    /// e.g. "Avg 14% · Peak 91% at 14:12" over `range`, or nil with no history in it.
    public var historySummary: String?
    /// `historyBarCount` utilization bars over `range` (0...1), oldest first; nil where there's no data.
    public var history: [Double?]
    public var yAxis: [String]
    /// Evenly spaced from the start of the range; the last is "Now".
    public var xAxis: [String]
    public var topApps: [AppRow]
    /// Shown instead of top apps when there are none, e.g. why per-app use can't be read.
    public var topAppsNote: String?
    /// Why there are no live GPU figures; nil while they're live.
    public var unavailable: String?
}

extension GPUDetail {
    @MainActor
    static func make(
        snapshot: Snapshot?, apps: [AppUsage], history: MetricsHistory, range: TimeRange, timeZone: TimeZone = .current
    ) -> GPUDetail {
        let gpu = snapshot?.gpu.value
        let now = snapshot?.timestamp
        let dash = Format.placeholder
        let day = now.flatMap { try? history.summary(.gpuUtilization, over: .twentyFourHours, endingAt: $0) }
        let shown = range == .twentyFourHours ? day : now.flatMap { try? history.summary(.gpuUtilization, over: range, endingAt: $0) }
        let (rows, note) = GPUFormat.appRows(apps, count: topAppCount)

        func bars(_ series: SeriesKey, over window: TimeRange, normalized: Bool = false) -> [Double?] {
            guard let now else { return Array(repeating: nil, count: tileBarCount) }
            let points = (try? history.summary(series, over: window, endingAt: now).points) ?? []
            let bars = Resample.bars(points, endingAt: now, window: window.duration, count: tileBarCount)
            guard normalized, let top = bars.compactMap({ $0 }).max(), top > 0 else { return bars }
            return bars.map { $0.map { $0 / top } }
        }
        let dayBars = now.map {
            Resample.bars(day?.points ?? [], endingAt: $0, window: TimeRange.twentyFourHours.duration, count: tileBarCount)
        } ?? Array(repeating: nil, count: tileBarCount)

        return GPUDetail(
            subtitle: gpu?.subtitle,
            utilization: Tile(
                label: "Utilization",
                value: gpu.map { Format.percent($0.utilization) } ?? dash,
                caption: gpu.map {
                    "Renderer \($0.renderer.map(Format.percent) ?? dash) · Tiler \($0.tiler.map(Format.percent) ?? dash)"
                } ?? GPUFormat.reason(snapshot?.gpu) ?? "",
                bars: bars(.gpuUtilization, over: liveTileWindow)
            ),
            memory: Tile(
                label: "GPU Memory",
                value: gpu?.memoryInUse.map { GPUFormat.gigabytes($0) } ?? dash,
                caption: gpu?.unifiedMemory.map { "Shared from \(GPUFormat.gigabytes($0, decimals: 0)) unified" } ?? "",
                // Memory moves within a narrow band, so the sparkline is scaled to its own peak.
                bars: bars(.gpuMemory, over: liveTileWindow, normalized: true)
            ),
            average: Tile(
                label: "Average · 24H",
                value: day?.average.map(Format.percent) ?? dash,
                caption: comparison(today: day?.average, yesterday: now.flatMap { yesterdayAverage(history, endingAt: $0) }),
                bars: dayBars
            ),
            peak: Tile(
                label: "Peak · 24H",
                value: day?.peak.map { Format.percent($0.value) } ?? dash,
                caption: day?.peak.map { peak in
                    let time = Format.time(peak.time, within: .twentyFourHours, timeZone: timeZone)
                    return peak.contributor.map { "\($0) · \(time)" } ?? "at \(time)"
                } ?? "",
                bars: dayBars
            ),
            range: range,
            historySummary: shown.flatMap { summary in
                guard let average = summary.average, let peak = summary.peak else { return nil }
                let time = Format.time(peak.time, within: range, timeZone: timeZone)
                return "Avg \(Format.percent(average)) · Peak \(Format.percent(peak.value)) at \(time)"
            },
            history: GPUPanel.utilizationBars(history, range: range, endingAt: now, count: historyBarCount),
            yAxis: ["100%", "50%", "0%"],
            xAxis: CPUDetail.xAxis(range: range, endingAt: now, timeZone: timeZone),
            topApps: rows,
            topAppsNote: note,
            unavailable: GPUFormat.reason(snapshot?.gpu)
        )
    }

    /// Average utilization over the 24 hours ending 24 hours before `now`.
    ///
    /// Read from the 7-day range's quarter-hour buckets: the one-minute tier that serves a 24H range
    /// is pruned after about 25 hours, so a 24H query ending yesterday would cover only its last hour.
    @MainActor
    static func yesterdayAverage(_ history: MetricsHistory, endingAt now: Date) -> Double? {
        let end = now.addingTimeInterval(-TimeRange.twentyFourHours.duration)
        let start = end.addingTimeInterval(-TimeRange.twentyFourHours.duration)
        let points = (try? history.summary(.gpuUtilization, over: .sevenDays, endingAt: now).points) ?? []
        let values = points.filter { $0.time >= start && $0.time < end }.map(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// e.g. "3 pts lower than yesterday", comparing the percentages as displayed.
    static func comparison(today: Double?, yesterday: Double?) -> String {
        guard let today else { return "No history yet" }
        guard let yesterday else { return "No history from yesterday" }
        let points = Int((today * 100).rounded()) - Int((yesterday * 100).rounded())
        if points == 0 { return "Same as yesterday" }
        let unit = abs(points) == 1 ? "pt" : "pts"
        return "\(abs(points)) \(unit) \(points < 0 ? "lower" : "higher") than yesterday"
    }
}
