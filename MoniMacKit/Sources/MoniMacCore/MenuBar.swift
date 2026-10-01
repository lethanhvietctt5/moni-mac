/// The metrics that can appear as menu bar items.
public enum Metric: String, CaseIterable, Sendable {
    case cpu
}

/// What one menu bar item displays.
public struct MenuBarItem: Equatable, Sendable {
    public var metric: Metric
    public var text: String

    public init(metric: Metric, text: String) {
        self.metric = metric
        self.text = text
    }
}

extension MenuBarItem {
    static func cpu(_ snapshot: Snapshot?) -> MenuBarItem {
        let text = snapshot?.cpu.value.map { Format.percent($0.total) } ?? Format.placeholder
        return MenuBarItem(metric: .cpu, text: text)
    }
}
