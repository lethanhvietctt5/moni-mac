import Foundation

/// How often MoniMac samples. Faster is fresher; slower saves energy.
public enum RefreshInterval: Int, CaseIterable, Sendable {
    case oneSecond = 1
    case twoSeconds = 2
    case fiveSeconds = 5

    public var duration: Duration { .seconds(rawValue) }
    /// e.g. "2s".
    public var title: String { "\(rawValue)s" }
}

/// How long history is kept ("Keep history").
public enum HistoryRetention: Int, CaseIterable, Sendable {
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90

    public var duration: TimeInterval { TimeInterval(rawValue) * 86_400 }
    /// e.g. "30 days".
    public var title: String { "\(rawValue) days" }
}

extension CPUMode {
    /// "System" or "Per-core".
    public var title: String { self == .system ? "System" : "Per-core" }
}

extension NetworkUnits {
    /// "MB/s" or "Mbps".
    public var title: String { self == .bytes ? "MB/s" : "Mbps" }
}

extension MenuBarStyle {
    /// "Value", "Graph", or "Both".
    public var title: String {
        switch self {
        case .value: "Value"
        case .graph: "Graph"
        case .both: "Both"
        }
    }
}

/// The Settings tab's feature state.
public struct SettingsPanel: Equatable, Sendable {
    /// One row of Settings › Menu Bar Items.
    public struct MenuBarRow: Equatable, Sendable, Identifiable {
        public var metric: Metric
        public var isEnabled: Bool
        /// False for the last enabled item: MoniMac always keeps one menu bar item.
        public var canToggle: Bool
        public var style: MenuBarStyle

        public var id: Metric { metric }
    }

    public var launchesAtLogin: Bool
    public var refreshInterval: RefreshInterval
    public var showsDockIcon: Bool
    public var temperatureUnit: TemperatureUnit
    public var networkUnits: NetworkUnits
    public var cpuMode: CPUMode
    /// e.g. "Per-core shows up to 1200% on 12 cores".
    public var cpuModeNote: String
    public var menuBarRows: [MenuBarRow]
    public var windowTabs: [WindowTabChip]
    public var keepHistory: HistoryRetention
    /// e.g. "MoniMac 1.4.2".
    public var about: String
}

extension Monitor {
    /// Settings, with `version` the app's marketing version, e.g. "1.4.2".
    public func settingsPanel(version: String) -> SettingsPanel {
        let cores = latest?.system.logicalCores ?? 0
        let enabled = menuBarItems.map(\.metric)
        return SettingsPanel(
            launchesAtLogin: launchesAtLogin,
            refreshInterval: preferences.refreshInterval,
            showsDockIcon: preferences.showsDockIcon,
            temperatureUnit: preferences.temperatureUnit,
            networkUnits: preferences.networkUnits,
            cpuMode: preferences.cpuMode,
            cpuModeNote: cores > 0
                ? "Per-core shows up to \(cores * 100)% on \(cores) cores"
                : "Per-core counts each core as 100%",
            menuBarRows: Metric.allCases.map { metric in
                SettingsPanel.MenuBarRow(
                    metric: metric,
                    isEnabled: enabled.contains(metric),
                    canToggle: enabled != [metric],
                    style: preferences.menuBarStyle(for: metric)
                )
            },
            windowTabs: windowTabChips,
            keepHistory: preferences.keepHistory,
            about: "MoniMac \(version)"
        )
    }

    /// How often the refresh loop samples. The app restarts its loop when this changes.
    public var refreshInterval: RefreshInterval { preferences.refreshInterval }

    /// Whether MoniMac shows a Dock icon; the app applies it as its activation policy.
    public var showsDockIcon: Bool { preferences.showsDockIcon }

    // MARK: Intents

    public func setRefreshInterval(_ interval: RefreshInterval) {
        preferences.refreshInterval = interval
    }

    public func setShowsDockIcon(_ shows: Bool) {
        preferences.showsDockIcon = shows
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        actions.setLaunchAtLogin(enabled)
        // Registration can fail or need approval; show what the system actually did.
        launchesAtLogin = actions.launchesAtLogin
    }

    public func setTemperatureUnit(_ unit: TemperatureUnit) {
        preferences.temperatureUnit = unit
        rebuildMenuBarItems()
    }

    public func setNetworkUnits(_ units: NetworkUnits) {
        preferences.networkUnits = units
        rebuildMenuBarItems()
    }

    /// One setting for every surface: menu bar, popover, window, and lists.
    public func setCPUMode(_ mode: CPUMode) {
        preferences.cpuMode = mode
        rebuildMenuBarItems()
    }

    /// Changing it prunes history beyond the new limit at once.
    public func setKeepHistory(_ retention: HistoryRetention) {
        preferences.keepHistory = retention
        history.retention = retention.duration
    }
}
