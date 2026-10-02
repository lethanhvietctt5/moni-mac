import Foundation

/// One notification: a per-app condition that just started, worded for the user at the moment it fired.
public struct Alert: Equatable, Sendable, Identifiable {
    /// The condition's stable identity, "<rule>:<app id>". It alerts once until the condition clears.
    public var id: String { "\(rule.rawValue):\(appID)" }
    public var rule: AlertRule
    public var appID: AppUsage.ID
    public var appName: String
    /// The app's bundle, for its icon.
    public var bundlePath: String?
    /// e.g. "Xcode is using a lot of CPU".
    public var title: String
    /// e.g. "412% for the last 2 minutes. Your Mac may feel slower and run warmer."
    public var body: String
    /// The figure, e.g. "412%", "+2.1 GB", "24 MB/s".
    public var chip: String
    /// "Quit Xcode", or nil when the app isn't a running regular app (only Show is offered then).
    public var quitTitle: String?
    /// Where "Show" lands: the Overview List sorted by this column, with the app expanded.
    public var showColumn: OverviewListColumn
}

/// The menu bar warning badge, shown while the whole CPU has been above 90% for 2 minutes.
public struct MenuBarWarning: Equatable, Sendable {
    /// e.g. "CPU 98%".
    public var text: String
    /// The widest text the badge can show in the current CPU mode; the item is sized for it.
    public var widestText: String
    /// e.g. "CPU above 90% for 2 min".
    public var title: String
    /// e.g. "Xcode is using 412% · click for details".
    public var detail: String
}

/// What a notification carries so its actions can find their way back, and the action identifiers.
public enum AlertNotification {
    public static let quitAction = "quit"
    public static let showAction = "show"

    /// The notification's payload.
    public static func userInfo(for alert: Alert) -> [String: String] {
        ["app": alert.appID, "column": alert.showColumn.rawValue]
    }

    /// The app and the List column a notification's actions act on, or nil for a payload MoniMac didn't write.
    public static func target(from userInfo: [AnyHashable: Any]) -> (appID: AppUsage.ID, column: OverviewListColumn)? {
        guard let app = userInfo["app"] as? String,
              let column = (userInfo["column"] as? String).flatMap(OverviewListColumn.init(rawValue:)) else { return nil }
        return (app, column)
    }
}

extension Alert {
    static func make(_ event: AlertEngine.Event, format: AlertFormat) -> Alert {
        let app = event.app
        let name = app.name
        let (title, body, chip): (String, String, String)
        switch event.rule {
        case .appCPU:
            chip = format.cpu(cores: event.value)
            title = "\(name) is using a lot of CPU"
            body = "\(chip) for the last \(minutes(event.rule.duration)). Your Mac may feel slower and run warmer."
        case .memoryGrowth:
            chip = "+" + Format.memorySize(UInt64(event.value))
            title = "\(name) memory is growing fast"
            let now = app.resources.memory.map { ", now \(Format.memorySize($0))" } ?? ""
            body = "\(chip) within \(minutes(event.rule.duration))\(now). A steady climb can mean a memory leak."
        case .diskWrites:
            let rate = app.resources.diskWritePerSecond ?? 0
            chip = rate > 0 ? DiskFormat.rate(rate) : DiskFormat.bytes(event.value)
            title = "Heavy disk writes from \(name)"
            body = "\(DiskFormat.bytes(event.value)) written in the last hour. Heavy writing wears out an SSD over time."
        case .network:
            chip = format.networkRate(event.value)
            title = "\(name) is using the network heavily"
            body = "Sustained \(chip) for \(minutes(event.rule.duration))."
        }
        return Alert(rule: event.rule, appID: app.id, appName: name, bundlePath: app.bundlePath, title: title,
                     body: body, chip: chip, quitTitle: app.canQuit ? "Quit \(name)" : nil,
                     showColumn: event.rule.column)
    }

    private static func minutes(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes == 1 ? "minute" : "\(minutes) minutes"
    }
}

/// One rule's row in Settings › Notifications.
public struct AlertRuleRow: Equatable, Sendable, Identifiable {
    public struct Option: Equatable, Sendable, Identifiable {
        public var value: Double
        /// e.g. "80%", "1 GB".
        public var title: String
        /// Checked in the menu: the current threshold, unless the menu's own "Off" is.
        public var isSelected: Bool
        public var id: Double { value }
    }

    public var rule: AlertRule
    public var label: String
    /// e.g. "Possible leak: +1 GB within 10 minutes".
    public var description: String
    public var isEnabled: Bool
    /// The current threshold, e.g. "80%".
    public var thresholdTitle: String
    /// What the threshold menu reads: the threshold, or "Off" for a rule turned off from that menu.
    public var menuTitle: String
    /// Whether the menu's "Off" entry is checked (rules without a switch only).
    public var isOffSelected: Bool
    /// A rule with a switch keeps its threshold menu dimmed while it's off.
    public var isMenuDisabled: Bool
    /// The thresholds offered, always including the current one.
    public var options: [Option]
    /// Turned on and off with a switch beside the threshold, as the design draws disk and network.
    /// Otherwise the threshold menu has an "Off" entry.
    public var hasSwitch: Bool

    public var id: AlertRule { rule }
}

/// The Monitor's alert bookkeeping. Stored on the Monitor; it never re-renders a surface by itself.
struct AlertState {
    var engine = AlertEngine()
    /// The busiest app at the last per-app evaluation, named by the warning badge's tooltip.
    var busiest: AppUsage?
    /// Whether this session has asked for notification permission yet.
    var hasRequestedPermission = false
}

extension Monitor {
    /// Runs the alert rules over a new snapshot and delivers the alerts that just started.
    /// The system rule runs every tick; per-app rules only at the process list's cadence, and only while
    /// a per-app rule is on or the warning badge needs its culprit.
    func evaluateAlerts(_ snapshot: Snapshot) {
        alerts.engine.observeSystemCPU(snapshot.cpu.value?.total, at: snapshot.timestamp)
        let settings = Dictionary(uniqueKeysWithValues: AlertRule.allCases.map { ($0, preferences.alertSettings($0)) })
        let needed = alerts.engine.isStrained || settings.values.contains(where: \.isEnabled)
        guard needed, alerts.engine.isAppEvaluationDue(at: snapshot.timestamp) else { return }
        let apps = apps
        alerts.busiest = apps.first
        let events = alerts.engine.observeApps(apps, at: snapshot.timestamp, settings: settings)
        guard !events.isEmpty else { return }
        let format = alertFormat
        requestNotificationPermission()
        for event in events {
            actions.deliver(Alert.make(event, format: format))
        }
    }

    /// The menu bar warning badge, or nil while the system isn't under strain.
    var menuBarWarning: MenuBarWarning? {
        guard alerts.engine.isStrained, let latest, let cpu = latest.cpu.value else { return nil }
        let format = alertFormat
        let cores = latest.system.logicalCores
        let mode = preferences.cpuMode
        let threshold = Format.cpu(AlertEngine.strainThreshold, mode: mode, logicalCores: cores)
        let minutes = Int(AlertEngine.strainDuration / 60)
        let culprit = alerts.busiest.map { "\($0.name) is using \(format.cpu(cores: $0.cpu)) · " } ?? ""
        return MenuBarWarning(
            text: "CPU " + Format.cpu(cpu.total, mode: mode, logicalCores: cores),
            widestText: "CPU " + CPUMenuBar.widestText(preferences: preferences),
            title: "CPU above \(threshold) for \(minutes) min",
            detail: culprit + "click for details"
        )
    }

    private var alertFormat: AlertFormat {
        AlertFormat(cpuMode: preferences.cpuMode, logicalCores: latest?.system.logicalCores ?? 0,
                    networkUnits: preferences.networkUnits)
    }

    /// Asks once per session, and only on first use: when an alert first fires or a rule is turned on.
    private func requestNotificationPermission() {
        guard !alerts.hasRequestedPermission else { return }
        alerts.hasRequestedPermission = true
        actions.requestNotificationAuthorization()
    }

    // MARK: Settings › Notifications

    var alertRuleRows: [AlertRuleRow] {
        let format = alertFormat
        return AlertRule.allCases.map { rule in
            let settings = preferences.alertSettings(rule)
            let title = format.threshold(settings.threshold, for: rule)
            let values = Set(rule.thresholdOptions + [settings.threshold]).sorted()
            let description = switch rule {
            case .appCPU: "Alert when one app stays above the limit for 2 min"
            case .memoryGrowth: "Possible leak: +\(title) within 10 minutes"
            case .diskWrites: "More than \(title) written in an hour"
            case .network: "One app above \(title) for 4 minutes"
            }
            let label = switch rule {
            case .appCPU: "App exceeds CPU threshold"
            case .memoryGrowth: "Rapid memory growth"
            case .diskWrites: "Heavy disk writes"
            case .network: "Heavy network activity"
            }
            let hasSwitch = rule.hasSwitch
            let offInMenu = !hasSwitch && !settings.isEnabled
            return AlertRuleRow(
                rule: rule,
                label: label,
                description: description,
                isEnabled: settings.isEnabled,
                thresholdTitle: title,
                menuTitle: offInMenu ? "Off" : title,
                isOffSelected: offInMenu,
                isMenuDisabled: hasSwitch && !settings.isEnabled,
                options: values.map {
                    AlertRuleRow.Option(value: $0, title: format.threshold($0, for: rule),
                                        isSelected: !offInMenu && $0 == settings.threshold)
                },
                hasSwitch: hasSwitch
            )
        }
    }

    // MARK: Intents

    /// Turning a rule on is the first use of notifications, so it asks for permission (once per session).
    public func setAlertEnabled(_ enabled: Bool, for rule: AlertRule) {
        preferences.setAlertEnabled(enabled, for: rule)
        if enabled { requestNotificationPermission() }
    }

    /// For a rule without a switch, picking a threshold from its menu also turns it back on.
    public func setAlertThreshold(_ threshold: Double, for rule: AlertRule) {
        guard threshold > 0 else { return }
        preferences.setAlertThreshold(threshold, for: rule)
        if !rule.hasSwitch, !preferences.alertSettings(rule).isEnabled { setAlertEnabled(true, for: rule) }
    }
}
