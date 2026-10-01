import Foundation

// Network: filled in by ticket 07. The scaffold keeps every hook in this file so tickets
// built in parallel don't edit shared code.

/// What SystemSampler reads for network on each tick.
public struct NetworkReading: Equatable, Sendable {
    public init() {}
}

extension Snapshot {
    /// Values MetricsHistory records for network.
    var networkSeries: [(SeriesKey, Double)] { [] }
}

/// The network menu bar item.
enum NetworkMenuBar {
    /// The widest text the item can show; the item is sized for it.
    static let widestText = "999 KB/s"

    static func text(_ snapshot: Snapshot?, preferences: Preferences) -> String {
        Format.placeholder
    }

    /// Sparkline bars over the last minute, 0...1, `Sparkline.barCount` long.
    @MainActor
    static func bars(history: MetricsHistory, endingAt now: Date?) -> [Double?] {
        Sparkline.empty
    }
}
