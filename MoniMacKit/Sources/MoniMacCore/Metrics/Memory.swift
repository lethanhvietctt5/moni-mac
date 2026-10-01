import Foundation

// Memory: filled in by ticket 05. The scaffold keeps every hook in this file so tickets
// built in parallel don't edit shared code.

/// What SystemSampler reads for memory on each tick.
public struct MemoryReading: Equatable, Sendable {
    public init() {}
}

extension Snapshot {
    /// Values MetricsHistory records for memory.
    var memorySeries: [(SeriesKey, Double)] { [] }
}

/// The memory menu bar item.
enum MemoryMenuBar {
    /// The widest text the item can show; the item is sized for it.
    static let widestText = "11.2 GB"

    static func text(_ snapshot: Snapshot?, preferences: Preferences) -> String {
        Format.placeholder
    }

    /// Sparkline bars over the last minute, 0...1, `Sparkline.barCount` long.
    @MainActor
    static func bars(history: MetricsHistory, endingAt now: Date?) -> [Double?] {
        Sparkline.empty
    }
}
