import Foundation
import Observation

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
///
/// Metric-specific settings (e.g. units) can live in that metric's file as an extension;
/// prefix their keys with the metric, e.g. "network.units". Settings write through `set(_:forKey:)`,
/// so every surface that read a setting re-renders as soon as it changes. Internal bookkeeping
/// that no surface renders (e.g. project activity) may write `defaults` directly.
@Observable
public final class Preferences {
    @ObservationIgnored private let store: UserDefaults
    /// Bumped on every settings write. Reads go through `defaults`, which reads this, so Observation
    /// tracks every setting a view or menu bar item used.
    private var revision = 0

    public init(defaults: UserDefaults = .standard) {
        store = defaults
    }

    var defaults: UserDefaults {
        _ = revision
        return store
    }

    /// Writes a setting and tells observers.
    func set(_ value: Any?, forKey key: String) {
        store.set(value, forKey: key)
        revision &+= 1
    }

    public func menuBarStyle(for metric: Metric) -> MenuBarStyle {
        defaults.string(forKey: Self.styleKey(metric)).flatMap(MenuBarStyle.init(rawValue:)) ?? .value
    }

    public func setMenuBarStyle(_ style: MenuBarStyle, for metric: Metric) {
        set(style.rawValue, forKey: Self.styleKey(metric))
    }

    /// Whether a metric has a menu bar item. Only CPU is shown until the user adds others.
    public func isMenuBarItemEnabled(_ metric: Metric) -> Bool {
        defaults.object(forKey: Self.enabledKey(metric)) as? Bool ?? (metric == .cpu)
    }

    public func setMenuBarItemEnabled(_ enabled: Bool, for metric: Metric) {
        set(enabled, forKey: Self.enabledKey(metric))
    }

    public var cpuMode: CPUMode {
        get { defaults.string(forKey: "cpu.mode").flatMap(CPUMode.init(rawValue:)) ?? .system }
        set { set(newValue.rawValue, forKey: "cpu.mode") }
    }

    // MARK: General

    public var refreshInterval: RefreshInterval {
        get { RefreshInterval(rawValue: defaults.integer(forKey: "general.refreshInterval")) ?? .twoSeconds }
        set { set(newValue.rawValue, forKey: "general.refreshInterval") }
    }

    /// Off by default: MoniMac is a menu bar app.
    public var showsDockIcon: Bool {
        get { defaults.bool(forKey: "general.showsDockIcon") }
        set { set(newValue, forKey: "general.showsDockIcon") }
    }

    public var keepHistory: HistoryRetention {
        get { HistoryRetention(rawValue: defaults.integer(forKey: "history.keepDays")) ?? .thirtyDays }
        set { set(newValue.rawValue, forKey: "history.keepDays") }
    }

    // MARK: Layout

    /// Window tabs in the user's sidebar order, as raw values. Empty until the user reorders.
    var tabOrder: [String] {
        get { defaults.stringArray(forKey: "layout.tabs.order") ?? [] }
        set { set(newValue, forKey: "layout.tabs.order") }
    }

    /// Window tabs the user hid, as raw values.
    var hiddenTabs: Set<String> {
        get { Set(defaults.stringArray(forKey: "layout.tabs.hidden") ?? []) }
        set { set(newValue.sorted(), forKey: "layout.tabs.hidden") }
    }

    /// A window tab's sections in the user's order, as ids. Empty until the user reorders.
    func sectionOrder(in tab: WindowTab) -> [String] {
        defaults.stringArray(forKey: Self.sectionsKey(tab)) ?? []
    }

    func setSectionOrder(_ order: [String], in tab: WindowTab) {
        set(order, forKey: Self.sectionsKey(tab))
    }

    private static func sectionsKey(_ tab: WindowTab) -> String {
        "layout.sections.\(tab.rawValue)"
    }

    private static func enabledKey(_ metric: Metric) -> String {
        "menuBar.\(metric.rawValue).enabled"
    }

    private static func styleKey(_ metric: Metric) -> String {
        "menuBar.\(metric.rawValue).style"
    }
}
