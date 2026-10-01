import Foundation

/// The share card's content: the last 7 days of history, summarized (ticket 19).
///
/// Everything is computed locally from `MetricsHistory` and the latest snapshot. When history covers less
/// than the window, figures cover what there is and `period` says so.
public struct WeeklySummary: Equatable, Sendable {
    public static let window = TimeRange.sevenDays
    public static let sparklineBarCount = 16
    public static let projectURL = "github.com/lethanhvietctt5/moni-mac"

    public enum TileKind: CaseIterable, Sendable {
        case cpu, memory, gpu, network, battery
    }

    public struct Tile: Equatable, Sendable, Identifiable {
        public var kind: TileKind
        /// e.g. "CPU".
        public var title: String
        /// e.g. "32%" (the average), "11.2 GB", "48 GB" (downloaded), "94%" (battery health).
        public var value: String
        /// e.g. "avg · peak 94%", "of 36 GB · pressure low", "down · 6.2 GB up", "health · 212 cycles".
        public var caption: String
        /// `sparklineBarCount` bars over the covered range, 0...1, oldest first; nil where there's no data.
        public var bars: [Double?]

        public var id: TileKind { kind }
    }

    /// The figures behind the card, which the headline and summary are chosen from.
    public struct Figures: Equatable, Sendable {
        /// How much of the window history covers, in seconds. 0 means no history.
        public var covered: TimeInterval = 0
        /// Hours the Mac was awake with MoniMac recording: 15-minute history buckets with samples.
        public var uptimeHours: Double = 0
        /// Separate spells of throttling (thermal state serious or critical), at 15-minute granularity.
        /// Nil when the thermal state was never recorded.
        public var throttlingEvents: Int?
        /// Shares of the whole CPU, 0...1.
        public var cpuAverage: Double?
        public var cpuPeak: Double?
        /// Share of installed memory, 0...1.
        public var memoryAverage: Double?
        /// The worst pressure level recorded.
        public var memoryPressure: MemoryPressureLevel?
        public var gpuAverage: Double?
        public var gpuPeak: Double?
        /// Bytes.
        public var downloaded: Double?
        public var uploaded: Double?
        /// The app most often behind the hourly CPU peak.
        public var busiestApp: String?
        /// Hours in which `busiestApp` was behind the CPU peak, out of `hoursWithCPU`.
        public var busiestHours = 0
        public var hoursWithCPU = 0

        public init() {}
    }

    /// e.g. "MacBook Pro · M3 Pro · 36 GB".
    public var device: String
    /// e.g. "LAST 7 DAYS · 24 SEP – 1 OCT 2026", or "LAST 2 DAYS 4 HOURS · 29 SEP – 1 OCT 2026".
    public var period: String
    /// False when history covers less than the whole window.
    public var coversWindow: Bool
    /// e.g. "Busy week, cool head.", from `WeeklySummaryHeadline`'s phrase table.
    public var headline: String
    /// e.g. "52 hours of uptime, zero thermal throttling, and Xcode doing most of the heavy lifting."
    public var summary: String
    /// CPU, Memory, GPU, Network, then Battery on Macs that have one.
    public var tiles: [Tile]
    /// e.g. "Busiest app: Xcode · top CPU user in 18 of 52 hours"; nil when no app stood out.
    public var busiestLine: String?
    public var figures: Figures
}

extension WeeklySummary {
    @MainActor
    public static func make(
        snapshot: Snapshot?, history: MetricsHistory, mode: CPUMode, hasBattery: Bool, now: Date,
        timeZone: TimeZone = .current
    ) -> WeeklySummary {
        let windowStart = now.addingTimeInterval(-window.duration)
        func summary(_ series: SeriesKey) -> SeriesSummary? { try? history.summary(series, over: window, endingAt: now) }
        func peak(_ series: SeriesKey) -> SeriesPoint? { try? history.peak(series, from: windowStart, to: now) }
        func sum(_ series: SeriesKey) -> Double? { try? history.sum(series, from: windowStart, to: now) }

        // Coverage: CPU is recorded on every tick, so its buckets say when MoniMac was recording.
        let cpu = summary(.cpuTotal)
        let olderHistory = (try? history.peak(.cpuTotal, from: .distantPast, to: windowStart)) ?? nil
        let start = olderHistory != nil ? windowStart : max(cpu?.points.first?.time ?? now, windowStart)

        var figures = Figures()
        figures.covered = now.timeIntervalSince(start)
        // Each bucket counts in full, so the one under way can't push uptime past the time covered.
        figures.uptimeHours = min(Double(cpu?.points.count ?? 0) / 4, figures.covered / 3600)
        figures.throttlingEvents = summary(.thermalThrottled).flatMap { throttlingEvents($0.points) }
        figures.cpuAverage = cpu?.average
        figures.cpuPeak = cpu?.peak?.value
        let memory = summary(.memoryUsed)
        figures.memoryAverage = memory?.average
        figures.memoryPressure = worstPressure(warning: peak(.memoryPressureWarning), critical: peak(.memoryPressureCritical))
        let gpu = summary(.gpuUtilization)
        figures.gpuAverage = gpu?.average
        figures.gpuPeak = gpu?.peak?.value
        figures.downloaded = sum(.networkDownBytes)
        figures.uploaded = sum(.networkUpBytes)
        let busiest = busiestApp(history: history, from: windowStart, to: now)
        (figures.busiestApp, figures.busiestHours, figures.hoursWithCPU) = (busiest.app, busiest.hours, busiest.of)

        let cores = snapshot?.system.logicalCores ?? 1
        let bars = SparklineSource(history: history, start: start, now: now)
        var tiles = [
            cpuTile(figures, mode: mode, cores: cores, bars: bars),
            memoryTile(figures, total: snapshot?.memory.value?.total, bars: bars),
            gpuTile(figures, bars: bars),
            networkTile(figures, bars: bars),
        ]
        if hasBattery { tiles.append(batteryTile(snapshot?.battery.value, bars: bars)) }

        return WeeklySummary(
            device: (snapshot?.system ?? .unknown).deviceLine(memory: snapshot?.memory.value?.total),
            period: period(start: start, end: now, full: olderHistory != nil, timeZone: timeZone),
            coversWindow: olderHistory != nil,
            headline: WeeklySummaryHeadline.pick(figures),
            summary: summaryLine(figures),
            tiles: tiles,
            busiestLine: figures.busiestApp.map {
                "Busiest app: \($0) · top CPU user in \(figures.busiestHours) of \(plural(figures.hoursWithCPU, "hour"))"
            },
            figures: figures
        )
    }

    // MARK: Figures

    /// Runs of 15-minute buckets that had a throttled sample. A gap in history (the Mac asleep) ends a run.
    static func throttlingEvents(_ points: [SeriesPoint]) -> Int? {
        guard !points.isEmpty else { return nil }
        var events = 0
        var previous: SeriesPoint?
        for point in points {
            let continues = previous.map { $0.value > 0 && point.time.timeIntervalSince($0.time) <= 15 * 60 } ?? false
            if point.value > 0, !continues { events += 1 }
            previous = point
        }
        return events
    }

    /// The worst level from the 0/1 indicator series: a peak above 0 means at least one such sample.
    static func worstPressure(warning: SeriesPoint?, critical: SeriesPoint?) -> MemoryPressureLevel? {
        if (critical?.value ?? 0) > 0 { return .critical }
        if (warning?.value ?? 0) > 0 { return .warning }
        return warning == nil ? nil : .normal
    }

    /// The app most often behind each hour's CPU peak. There's no per-app CPU series (recording one per tick
    /// would cost too much), so this tallies the contributor history keeps with each peak.
    @MainActor
    static func busiestApp(history: MetricsHistory, from start: Date, to end: Date) -> (app: String?, hours: Int, of: Int) {
        var tally: [String: (hours: Int, total: Double)] = [:]
        var hoursWithCPU = 0
        // Whole clock hours, so each 15-minute bucket falls in exactly one.
        var hour = Date(timeIntervalSinceReferenceDate: (start.timeIntervalSinceReferenceDate / 3600).rounded(.down) * 3600)
        while hour < end {
            let next = hour.addingTimeInterval(3600)
            // `peak` includes both ends; stop just short of the next hour's first bucket.
            let to = next < end ? next.addingTimeInterval(-0.001) : end
            if let peak = try? history.peak(.cpuTotal, from: max(hour, start), to: to) {
                hoursWithCPU += 1
                if let app = peak.contributor {
                    let entry = tally[app] ?? (0, 0)
                    tally[app] = (entry.hours + 1, entry.total + peak.value)
                }
            }
            hour = next
        }
        let best = tally.max { a, b in
            (a.value.hours, a.value.total, b.key) < (b.value.hours, b.value.total, a.key)
        }
        return (best?.key, best?.value.hours ?? 0, hoursWithCPU)
    }

    // MARK: Text

    /// e.g. "LAST 7 DAYS · 24 SEP – 1 OCT 2026"; a partial window states what it covers.
    static func period(start: Date, end: Date, full: Bool, timeZone: TimeZone) -> String {
        let covered = end.timeIntervalSince(start)
        guard full || covered > 0 else { return "NO HISTORY YET · \(dates(end, end, timeZone: timeZone))" }
        let span = full ? "7 DAYS" : duration(covered).uppercased()
        return "LAST \(span) · \(dates(start, end, timeZone: timeZone))"
    }

    /// "2 days 4 hours", "5 hours", "12 minutes".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(Int(seconds / 60), 1)
        let (days, hours) = (minutes / 1440, minutes / 60 % 24)
        if days > 0 { return hours > 0 ? "\(plural(days, "day")) \(plural(hours, "hour"))" : plural(days, "day") }
        if hours > 0 { return plural(hours, "hour") }
        return plural(minutes, "minute")
    }

    /// "24 SEP – 1 OCT 2026", "28 DEC 2026 – 3 JAN 2027", or one day, "1 OCT 2026".
    static func dates(_ start: Date, _ end: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func format(_ date: Date, _ pattern: String) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = pattern
            return formatter.string(from: date).uppercased()
        }
        let last = format(end, "d MMM yyyy")
        if calendar.isDate(start, inSameDayAs: end) { return last }
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: end)
        return "\(format(start, sameYear ? "d MMM" : "d MMM yyyy")) – \(last)"
    }

    /// e.g. "52 hours of uptime, zero thermal throttling, and Xcode doing most of the heavy lifting."
    static func summaryLine(_ figures: Figures) -> String {
        guard figures.covered > 0 else { return "MoniMac hasn't recorded any history yet. Check back in a few days." }
        let uptime = figures.uptimeHours >= 1
            ? "\(plural(Int(figures.uptimeHours.rounded()), "hour")) of uptime"
            : "\(plural(Int(figures.uptimeHours * 60), "minute")) of uptime"
        let throttling = figures.throttlingEvents.map { events in
            switch events {
            case 0: "zero thermal throttling"
            case 1: "one throttling event"
            default: "\(events) throttling events"
            }
        }
        let busiest = figures.busiestApp.map { "\($0) doing most of the heavy lifting" }
        let parts = [uptime, throttling, busiest].compactMap { $0 }
        let joined = parts.count < 3 ? parts.joined(separator: " and ")
            : parts.dropLast().joined(separator: ", ") + ", and " + parts.last!
        return joined + "."
    }

    /// e.g. "1 hour", "52 hours", "212 cycles".
    static func plural(_ count: Int, _ noun: String) -> String {
        "\(Format.count(count)) \(noun)\(count == 1 ? "" : "s")"
    }

    // MARK: Tiles
    //
    // Shares (CPU, memory, GPU, charge) are drawn as they are, like the Overview tiles; network has no
    // capacity, so its busiest bar is full height.

    /// A figure averaged over the window, with its peak in the caption.
    private static func averageAndPeak(_ average: Double?, _ peak: Double?, format: (Double) -> String)
        -> (value: String, caption: String) {
        (average.map(format) ?? Format.placeholder, "avg · peak \(peak.map(format) ?? Format.placeholder)")
    }

    @MainActor private static func cpuTile(_ figures: Figures, mode: CPUMode, cores: Int, bars: SparklineSource) -> Tile {
        let text = averageAndPeak(figures.cpuAverage, figures.cpuPeak) { Format.cpu($0, mode: mode, logicalCores: cores) }
        return Tile(kind: .cpu, title: "CPU", value: text.value, caption: text.caption, bars: bars.series(.cpuTotal))
    }

    @MainActor private static func memoryTile(_ figures: Figures, total: UInt64?, bars: SparklineSource) -> Tile {
        let value: String = switch (figures.memoryAverage, total) {
        case let (average?, total?): Format.memorySize(UInt64(average * Double(total)))
        case let (average?, nil): Format.percent(average)
        case (nil, _): Format.placeholder
        }
        let pressure: String? = switch figures.memoryPressure {
        case .normal: "pressure low"
        case .warning: "pressure warning"
        case .critical: "pressure critical"
        case nil: nil
        }
        let caption = ([total.map { "of \(Format.memorySize($0))" } ?? "avg"] + [pressure].compactMap { $0 })
            .joined(separator: " · ")
        return Tile(kind: .memory, title: "Memory", value: value, caption: caption, bars: bars.series(.memoryUsed))
    }

    @MainActor private static func gpuTile(_ figures: Figures, bars: SparklineSource) -> Tile {
        let text = averageAndPeak(figures.gpuAverage, figures.gpuPeak, format: Format.percent)
        return Tile(kind: .gpu, title: "GPU", value: text.value, caption: text.caption,
                    bars: bars.series(.gpuUtilization))
    }

    @MainActor private static func networkTile(_ figures: Figures, bars: SparklineSource) -> Tile {
        let throughput = zip(bars.series(.networkDown), bars.series(.networkUp)).map { down, up -> Double? in
            down == nil && up == nil ? nil : (down ?? 0) + (up ?? 0)
        }
        return Tile(kind: .network, title: "Network",
                    value: figures.downloaded.map(NetworkFormat.bytes) ?? Format.placeholder,
                    caption: "down · \(figures.uploaded.map(NetworkFormat.bytes) ?? Format.placeholder) up",
                    bars: bars.relative(throughput))
    }

    /// Health and cycles are the battery's current figures; the sparkline is the week's charge.
    @MainActor private static func batteryTile(_ battery: BatteryReading?, bars: SparklineSource) -> Tile {
        let cycles = battery?.cycleCount.map { plural($0, "cycle") }
        return Tile(kind: .battery, title: "Battery", value: battery?.health.map(Format.percent) ?? Format.placeholder,
                    caption: (["health"] + [cycles].compactMap { $0 }).joined(separator: " · "),
                    bars: bars.series(.batteryCharge))
    }
}

/// Sparkline bars over the covered range, read at the finest tier that holds it.
@MainActor
private struct SparklineSource {
    let history: MetricsHistory
    let start: Date
    let now: Date

    func series(_ key: SeriesKey) -> [Double?] {
        let window = now.timeIntervalSince(start)
        let count = WeeklySummary.sparklineBarCount
        guard window > 0 else { return Array(repeating: nil, count: count) }
        let range: TimeRange = switch window {
        case ...TimeRange.oneHour.duration: .oneHour
        case ...TimeRange.twentyFourHours.duration: .twentyFourHours
        default: .sevenDays
        }
        let points = (try? history.summary(key, over: range, endingAt: now).points) ?? []
        return Resample.bars(points, endingAt: now, window: window, count: count)
    }

    /// Bars scaled so the highest is full height, for figures without a capacity.
    func relative(_ bars: [Double?]) -> [Double?] {
        let highest = bars.compactMap { $0 }.max() ?? 0
        guard highest > 0 else { return bars }
        return bars.map { $0.map { $0 / highest } }
    }
}

extension Monitor {
    /// The share card's content for the last 7 days, ending at the latest sample.
    public func weeklySummary() -> WeeklySummary {
        WeeklySummary.make(snapshot: latest, history: history, mode: preferences.cpuMode, hasBattery: hasBattery,
                           now: latest?.timestamp ?? Date())
    }
}
