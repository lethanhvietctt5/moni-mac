import Foundation

// Thermal: filled in by ticket 10. The scaffold keeps every hook in this file so tickets
// built in parallel don't edit shared code.

/// What SystemSampler reads for thermal on each tick.
public struct ThermalReading: Equatable, Sendable {
    public init() {}
}

extension Snapshot {
    /// Values MetricsHistory records for thermal.
    var thermalSeries: [SeriesSample] { [] }
}

/// The temperature menu bar item.
enum TemperatureMenuBar: MenuBarMetric {
    /// The widest text the item can show; the item is sized for it.
    static func widestText(preferences: Preferences) -> String {
        "100°C"
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
    /// The main window toolbar subtitle for the Temperature & Fans tab, e.g. hardware details.
    public var temperatureSubtitle: String? { nil }
}
