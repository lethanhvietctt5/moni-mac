import Foundation

/// How a menu bar item presents its metric.
public enum MenuBarStyle: String, CaseIterable, Sendable {
    /// Icon and number, e.g. `32%`.
    case value
    /// Icon and a sparkline of the last 60 seconds.
    case graph
    /// Sparkline and number.
    case both
}

/// Every user setting, persisted in UserDefaults.
public final class Preferences {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func menuBarStyle(for metric: Metric) -> MenuBarStyle {
        defaults.string(forKey: Self.styleKey(metric)).flatMap(MenuBarStyle.init(rawValue:)) ?? .value
    }

    public func setMenuBarStyle(_ style: MenuBarStyle, for metric: Metric) {
        defaults.set(style.rawValue, forKey: Self.styleKey(metric))
    }

    public var cpuMode: CPUMode {
        get { defaults.string(forKey: "cpu.mode").flatMap(CPUMode.init(rawValue:)) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "cpu.mode") }
    }

    private static func styleKey(_ metric: Metric) -> String {
        "menuBar.\(metric.rawValue).style"
    }
}
