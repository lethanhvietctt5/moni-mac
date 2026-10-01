import Foundation

/// The kernel's memory pressure state, as Activity Monitor names it.
public enum MemoryPressureLevel: Equatable, Sendable {
    case normal
    case warning
    case critical

    /// How `SeriesKey.memoryPressureLevel` records it: 0, 1, 2.
    var seriesValue: Double {
        switch self {
        case .normal: 0
        case .warning: 1
        case .critical: 2
        }
    }

    /// The nearest level to a recorded (possibly averaged) series value.
    init(seriesValue: Double) {
        switch seriesValue {
        case ..<0.5: self = .normal
        case ..<1.5: self = .warning
        default: self = .critical
        }
    }
}

/// What SystemSampler reads for memory on each tick. Sizes are bytes.
///
/// The breakdown follows Activity Monitor; `MemoryReader` documents how each figure is derived.
public struct MemoryReading: Equatable, Sendable {
    public struct Swap: Equatable, Sendable {
        public var used: UInt64
        /// The swap files' current size.
        public var total: UInt64

        public init(used: UInt64, total: UInt64) {
            self.used = used
            self.total = total
        }
    }

    /// Installed memory.
    public var total: UInt64
    /// Anonymous memory apps hold, excluding purgeable.
    public var app: UInt64
    /// Pinned by the kernel; can't be compressed or paged out.
    public var wired: UInt64
    /// Physical memory the compressor occupies.
    public var compressed: UInt64
    /// What the compressed pages held before compression.
    public var compressedOriginal: UInt64
    /// File-backed and purgeable pages the system can reclaim.
    public var cached: UInt64
    /// Nil when the kernel's pressure state couldn't be read.
    public var pressureLevel: MemoryPressureLevel?
    /// Share of memory under pressure, 0...1 (100% minus the kernel's free percentage).
    public var pressure: Double?
    public var swap: Swap?

    public init(
        total: UInt64, app: UInt64, wired: UInt64, compressed: UInt64, compressedOriginal: UInt64, cached: UInt64,
        pressureLevel: MemoryPressureLevel?, pressure: Double?, swap: Swap?
    ) {
        self.total = total
        self.app = app
        self.wired = wired
        self.compressed = compressed
        self.compressedOriginal = compressedOriginal
        self.cached = cached
        self.pressureLevel = pressureLevel
        self.pressure = pressure
        self.swap = swap
    }

    /// Activity Monitor's "Memory Used": App + Wired + Compressed.
    public var used: UInt64 { app + wired + compressed }

    /// Whatever the other four figures don't cover, so the breakdown adds up to `total`.
    /// Mostly free pages, plus small kernel bookkeeping the VM counters don't classify.
    public var free: UInt64 {
        let accounted = used + cached
        return total > accounted ? total - accounted : 0
    }

    /// Used share of `total`, 0...1.
    public var usedFraction: Double {
        total == 0 ? 0 : min(Double(used) / Double(total), 1)
    }
}

extension SeriesKey {
    /// Memory used as a share of installed memory, 0...1. Its contributor is the app holding the most memory.
    public static let memoryUsed = SeriesKey(rawValue: "memory.used")
    /// Memory pressure, 0...1.
    public static let memoryPressure = SeriesKey(rawValue: "memory.pressure")
    /// The kernel's pressure level: 0 normal, 1 warning, 2 critical.
    public static let memoryPressureLevel = SeriesKey(rawValue: "memory.pressureLevel")
}

extension Snapshot {
    /// Values MetricsHistory records for memory.
    var memorySeries: [SeriesSample] {
        guard let memory = memory.value else { return [] }
        let biggest = AppGrouping.busiestApp(in: processes.value ?? []) { $0.resources.memory.map(Double.init) }
        var samples = [SeriesSample(.memoryUsed, memory.usedFraction, contributor: biggest)]
        if let pressure = memory.pressure {
            samples.append(SeriesSample(.memoryPressure, pressure, contributor: biggest))
        }
        if let level = memory.pressureLevel {
            samples.append(SeriesSample(.memoryPressureLevel, level.seriesValue))
        }
        return samples
    }
}

/// The memory menu bar item, e.g. `11.2 GB` used.
enum MemoryMenuBar: MenuBarMetric {
    /// Sizes of 100 GB and up drop the decimal (`128 GB`), so no Mac needs more room than this.
    static func widestText(preferences: Preferences) -> String {
        "88.8 GB"
    }

    static func text(_ snapshot: Snapshot?, preferences: Preferences) -> String {
        guard let memory = snapshot?.memory.value else { return Format.placeholder }
        return Format.memorySize(memory.used)
    }

    /// Used share of memory over the last minute.
    @MainActor
    static func bars(history: MetricsHistory, endingAt now: Date?) -> [Double?] {
        guard let now else { return Sparkline.empty }
        let points = (try? history.summary(.memoryUsed, over: .oneMinute, endingAt: now).points) ?? []
        return Sparkline.bars(points, endingAt: now)
    }
}

extension Monitor {
    /// The main window toolbar subtitle for the Memory tab, e.g. "18 GB unified memory".
    public var memorySubtitle: String? {
        latest?.memory.value.map { MemoryDetail.subtitle(total: $0.total) }
    }

    /// The popover's Memory tab for the given chart range.
    public func memoryPanel(range: TimeRange) -> MemoryDetail {
        MemoryDetail.make(snapshot: latest, apps: apps, history: history, range: range, layout: .popover)
    }

    /// The main window's Memory tab for the given chart range.
    public func memoryDetail(range: TimeRange) -> MemoryDetail {
        MemoryDetail.make(snapshot: latest, apps: apps, history: history, range: range, layout: .window)
    }
}

extension Format {
    /// Memory in binary units, as macOS shows it: `"18 GB"`, `"11.4 GB"`, `"128 GB"`, `"512 MB"`.
    /// One decimal below 100 GB, dropped when it's zero.
    public static func memorySize(_ bytes: UInt64) -> String {
        let (number, unit) = memorySizeParts(bytes)
        return "\(number) \(unit)"
    }

    /// `memorySize` split into number and unit, e.g. `("11.4", "GB")`.
    public static func memorySizeParts(_ bytes: UInt64) -> (number: String, unit: String) {
        let mib = Double(bytes) / 1_048_576
        if mib.rounded() < 1000 { return ("\(Int(mib.rounded()))", "MB") }
        let gib = mib / 1024
        if gib >= 99.95 { return ("\(Int(gib.rounded()))", "GB") }
        let tenths = (gib * 10).rounded()
        let number = tenths.truncatingRemainder(dividingBy: 10) == 0
            ? "\(Int(tenths / 10))" : String(format: "%.1f", tenths / 10)
        return (number, "GB")
    }
}
