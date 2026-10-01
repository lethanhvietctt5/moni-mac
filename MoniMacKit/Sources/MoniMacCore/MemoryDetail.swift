import Foundation

/// Everything the Memory tab shows: the main window's tab, or the popover's compact version of it.
public struct MemoryDetail: Equatable, Sendable {
    /// Which surface the tab is built for; the popover shows less.
    public enum Layout: Sendable {
        case popover, window

        /// The ranges the chart offers.
        public var ranges: [TimeRange] {
            switch self {
            case .popover: CPUPanel.ranges
            case .window: CPUDetail.ranges
            }
        }

        var topAppCount: Int { self == .popover ? 4 : 8 }
    }

    public static let historyBarCount = 30
    /// The pressure chart's scale, top to bottom.
    public static let yAxis = ["High", "Med", "Low"]

    public struct Stat: Equatable, Sendable {
        public var label: String
        public var value: String
        public var detail: String
    }

    public enum SegmentKind: Equatable, Sendable {
        case app, wired, compressed, cached, free
    }

    public struct Segment: Equatable, Sendable {
        public var kind: SegmentKind
        /// e.g. "App Memory".
        public var label: String
        /// e.g. "6.8 GB".
        public var value: String
        /// Share of installed memory, 0...1. The five segments add up to 1.
        public var share: Double
        /// e.g. "Kernel, can't page out".
        public var detail: String
    }

    public struct PressureBar: Equatable, Sendable {
        /// Pressure, 0...1: the bar's height.
        public var value: Double
        /// The kernel's level over the bar's span (the nearest to its average), which colors the bar Low/Med/High.
        public var level: MemoryPressureLevel
    }

    public struct AppRow: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var bundlePath: String?
        /// e.g. "6 processes".
        public var detail: String
        /// e.g. "1.9 GB".
        public var value: String
        /// Bar length: share of installed memory, 0...1.
        public var share: Double
        public var canQuit: Bool
    }

    public var layout: Layout
    /// e.g. "18 GB unified memory". Memory type (e.g. LPDDR5) has no cheap public source, so it's left out.
    public var subtitle: String
    /// e.g. "11.4", with `usedUnit` "GB".
    public var used: String
    public var usedUnit: String
    /// e.g. "18 GB".
    public var total: String
    /// Used share of installed memory, 0...1, for the usage bar.
    public var usedShare: Double
    public var pressure: Stat
    /// Colors the card's dot. Nil when the pressure state is unknown.
    public var pressureLevel: MemoryPressureLevel?
    public var swap: Stat
    public var compression: Stat
    /// App Memory, Wired, Compressed, Cached Files, Free; empty before the first reading.
    public var breakdown: [Segment]
    public var range: TimeRange
    /// `historyBarCount` pressure bars over `range`, oldest first; nil where there's no data.
    public var history: [PressureBar?]
    /// Evenly spaced from the start of the range; the last is "Now".
    public var xAxis: [String]
    /// Apps holding the most memory, largest first.
    public var topApps: [AppRow]
}

extension MemoryDetail {
    @MainActor
    static func make(
        snapshot: Snapshot?, apps: [AppUsage], history: MetricsHistory, range: TimeRange, layout: Layout,
        timeZone: TimeZone = .current
    ) -> MemoryDetail {
        let memory = snapshot?.memory.value
        let dash = Format.placeholder
        let used = memory.map { Format.memorySizeParts($0.used) }
        let now = snapshot?.timestamp

        return MemoryDetail(
            layout: layout,
            subtitle: memory.map { subtitle(total: $0.total) } ?? "Memory",
            used: used?.number ?? dash,
            usedUnit: used?.unit ?? "",
            total: memory.map { Format.memorySize($0.total) } ?? dash,
            usedShare: memory?.usedFraction ?? 0,
            pressure: pressureStat(memory),
            pressureLevel: memory?.pressureLevel,
            swap: swapStat(memory?.swap),
            compression: compressionStat(memory),
            breakdown: memory.map { breakdown($0, apps: apps) } ?? [],
            range: range,
            history: pressureBars(history, range: range, endingAt: now),
            xAxis: CPUDetail.xAxis(range: range, endingAt: now, timeZone: timeZone),
            topApps: topApps(apps, total: memory?.total, count: layout.topAppCount)
        )
    }

    public static func subtitle(total: UInt64) -> String {
        "\(Format.memorySize(total)) unified memory"
    }

    private static func pressureStat(_ memory: MemoryReading?) -> Stat {
        let (value, state): (String, String?) = switch memory?.pressureLevel {
        case .normal: ("Normal", "no throttling")
        case .warning: ("Warning", "some throttling")
        case .critical: ("Critical", "heavy throttling")
        case nil: (Format.placeholder, nil)
        }
        let detail = [memory?.pressure.map(Format.percent), state].compactMap { $0 }.joined(separator: " · ")
        return Stat(label: "Memory Pressure", value: value, detail: detail.isEmpty ? Format.placeholder : detail)
    }

    private static func swapStat(_ swap: MemoryReading.Swap?) -> Stat {
        Stat(
            label: "Swap Used",
            value: swap.map { Format.memorySize($0.used) } ?? Format.placeholder,
            detail: swap.map { $0.total == 0 ? "No swap file" : "of \(Format.memorySize($0.total)) swap file" }
                ?? Format.placeholder
        )
    }

    /// e.g. "2.6×" with "5.9 GB → 2.3 GB".
    private static func compressionStat(_ memory: MemoryReading?) -> Stat {
        guard let memory else {
            return Stat(label: "Compression", value: Format.placeholder, detail: Format.placeholder)
        }
        let ratio = memory.compressed == 0 ? nil : Double(memory.compressedOriginal) / Double(memory.compressed)
        return Stat(
            label: "Compression",
            value: ratio.map { String(format: "%.1f×", $0) } ?? Format.placeholder,
            detail: "\(Format.memorySize(memory.compressedOriginal)) → \(Format.memorySize(memory.compressed))"
        )
    }

    private static func breakdown(_ memory: MemoryReading, apps: [AppUsage]) -> [Segment] {
        let total = Double(max(memory.total, 1))
        func segment(_ kind: SegmentKind, _ label: String, _ bytes: UInt64, _ detail: String) -> Segment {
            Segment(kind: kind, label: label, value: Format.memorySize(bytes), share: Double(bytes) / total, detail: detail)
        }
        let appCount = apps.filter { $0.bundlePath != nil && ($0.resources.memory ?? 0) > 0 }.count
        let saved = memory.compressedOriginal > memory.compressed ? memory.compressedOriginal - memory.compressed : 0
        return [
            segment(.app, "App Memory", memory.app, appCount == 1 ? "Used by 1 app" : "Used by \(appCount) apps"),
            segment(.wired, "Wired", memory.wired, "Kernel, can't page out"),
            segment(.compressed, "Compressed", memory.compressed, "Saved \(Format.memorySize(saved))"),
            segment(.cached, "Cached Files", memory.cached, "Reclaimable"),
            segment(.free, "Free", memory.free, "Available now"),
        ]
    }

    /// Pressure as `historyBarCount` bars over the range, each colored by the kernel's level. As in
    /// Activity Monitor, color comes from the level, not the height: a Mac can sit at 50% and be fine.
    @MainActor
    private static func pressureBars(_ history: MetricsHistory, range: TimeRange, endingAt now: Date?) -> [PressureBar?] {
        guard let now else { return Array(repeating: nil, count: historyBarCount) }
        func bars(_ series: SeriesKey) -> [Double?] {
            let points = (try? history.summary(series, over: range, endingAt: now).points) ?? []
            return Resample.bars(points, endingAt: now, window: range.duration, count: historyBarCount)
        }
        return zip(bars(.memoryPressure), bars(.memoryPressureLevel)).map { pressure, level in
            guard let pressure, let level else { return nil }
            return PressureBar(value: min(max(pressure, 0), 1), level: MemoryPressureLevel(seriesValue: level))
        }
    }

    private static func topApps(_ apps: [AppUsage], total: UInt64?, count: Int) -> [AppRow] {
        let total = Double(max(total ?? 0, 1))
        // Stable for equal memory: keeps the CPU order.
        return apps.enumerated()
            .filter { ($0.element.resources.memory ?? 0) > 0 }
            .sorted { lhs, rhs in
                let (a, b) = (lhs.element.resources.memory ?? 0, rhs.element.resources.memory ?? 0)
                return a != b ? a > b : lhs.offset < rhs.offset
            }
            .prefix(count)
            .map { _, app in
                let bytes = app.resources.memory ?? 0
                return AppRow(
                    id: app.id, name: app.name, bundlePath: app.bundlePath,
                    detail: app.processCount == 1 ? "1 process" : "\(app.processCount) processes",
                    value: Format.memorySize(bytes), share: min(Double(bytes) / total, 1), canQuit: app.canQuit
                )
            }
    }
}
