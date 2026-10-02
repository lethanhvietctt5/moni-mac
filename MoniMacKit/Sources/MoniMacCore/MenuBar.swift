import Foundation

/// The metrics that can appear as menu bar items.
public enum Metric: String, CaseIterable, Sendable {
    case cpu, memory, network, gpu, temperature
}

/// What a metric's menu bar item shows. Each metric's file implements one.
protocol MenuBarMetric {
    /// The widest text the item can show in the current units; the item is sized for it.
    static func widestText(preferences: Preferences) -> String
    static func text(_ snapshot: Snapshot?, preferences: Preferences) -> String
    /// Sparkline bars over the last minute, 0...1, `Sparkline.barCount` long.
    @MainActor static func bars(history: MetricsHistory, endingAt now: Date?) -> [Double?]
}

extension Metric {
    /// The one place a metric is mapped to its menu bar implementation.
    var menuBar: any MenuBarMetric.Type {
        switch self {
        case .cpu: CPUMenuBar.self
        case .memory: MemoryMenuBar.self
        case .network: NetworkMenuBar.self
        case .gpu: GPUMenuBar.self
        case .temperature: TemperatureMenuBar.self
        }
    }
}

/// What one menu bar item displays.
public struct MenuBarItem: Equatable, Sendable {
    public var metric: Metric
    public var style: MenuBarStyle
    /// The current value, e.g. `32%`, or a placeholder when unavailable.
    public var text: String
    /// Sparkline bars (0...1, oldest first, nil = no data), always `Sparkline.barCount` long.
    /// Empty for the `.value` style.
    public var bars: [Double?]
    /// The widest text this item can show. Surfaces size the item for it so it never changes width.
    public var widestText: String
    /// Set while the system is under strain: the item shows this warning badge instead.
    public var warning: MenuBarWarning?

    public init(
        metric: Metric, style: MenuBarStyle, text: String, bars: [Double?], widestText: String,
        warning: MenuBarWarning? = nil
    ) {
        self.metric = metric
        self.style = style
        self.text = text
        self.bars = bars
        self.widestText = widestText
        self.warning = warning
    }
}
