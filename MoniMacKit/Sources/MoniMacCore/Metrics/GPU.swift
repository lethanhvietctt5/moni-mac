import Foundation

// GPU: filled in by ticket 06. The scaffold keeps every hook in this file so tickets
// built in parallel don't edit shared code.

/// What SystemSampler reads for gpu on each tick.
public struct GPUReading: Equatable, Sendable {
    public init() {}
}

extension Snapshot {
    /// Values MetricsHistory records for gpu.
    var gpuSeries: [SeriesSample] { [] }
}

/// The gpu menu bar item.
enum GPUMenuBar: MenuBarMetric {
    /// The widest text the item can show; the item is sized for it.
    static func widestText(preferences: Preferences) -> String {
        "100%"
    }

    static func text(_ snapshot: Snapshot?, preferences: Preferences) -> String {
        Format.placeholder
    }

    /// Sparkline bars over the last minute, 0...1, `Sparkline.barCount` long.
    @MainActor
    static func bars(history: MetricsHistory, endingAt now: Date?) -> [Double?] {
        Sparkline.empty
    }
}

extension Monitor {
    /// The main window toolbar subtitle for the GPU tab, e.g. hardware details.
    public var gpuSubtitle: String? { nil }
}
