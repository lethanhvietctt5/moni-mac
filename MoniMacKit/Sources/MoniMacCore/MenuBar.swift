/// The metrics that can appear as menu bar items.
public enum Metric: String, CaseIterable, Sendable {
    case cpu, memory, network, gpu, temperature
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

    public init(metric: Metric, style: MenuBarStyle, text: String, bars: [Double?]) {
        self.metric = metric
        self.style = style
        self.text = text
        self.bars = bars
    }

    /// The widest text this metric can show. Surfaces size the item for it so it never changes width.
    public var widestText: String {
        switch metric {
        case .cpu: "100%"
        case .memory: MemoryMenuBar.widestText
        case .network: NetworkMenuBar.widestText
        case .gpu: GPUMenuBar.widestText
        case .temperature: ThermalMenuBar.widestText
        }
    }
}
