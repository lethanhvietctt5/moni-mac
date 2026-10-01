import Foundation

/// The main window's tabs, in default sidebar order.
public enum WindowTab: String, CaseIterable, Identifiable, Sendable {
    case overview, cpu, memory, gpu, network, disk
    case battery, bluetooth, sound, temperature
    case projects
    case settings

    public var id: Self { self }

    public var title: String {
        switch self {
        case .overview: "Overview"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .gpu: "GPU"
        case .network: "Network"
        case .disk: "Disk"
        case .battery: "Battery"
        case .bluetooth: "Bluetooth"
        case .sound: "Sound"
        case .temperature: "Temperature & Fans"
        case .projects: "Projects"
        case .settings: "Settings"
        }
    }

    /// The Settings chip's label, where space is tight.
    public var shortTitle: String {
        self == .temperature ? "Temps & Fans" : title
    }

    /// Overview and Settings are always in the sidebar: one is home, the other is how to bring tabs back.
    public var canHide: Bool {
        self != .overview && self != .settings
    }

    /// Sidebar groups in default order; Settings sits alone at the bottom.
    public static let groups: [(title: String, tabs: [WindowTab])] = [
        ("Monitor", [.overview, .cpu, .memory, .gpu, .network, .disk]),
        ("Devices", [.battery, .bluetooth, .sound, .temperature]),
        ("Developer", [.projects]),
    ]
}

/// One group of the sidebar, in the user's order with hidden tabs left out.
public struct SidebarGroup: Equatable, Sendable {
    public var title: String
    public var tabs: [WindowTab]
}

/// A Settings › Window Tabs chip: ✓ when the tab is shown, + when hidden.
public struct WindowTabChip: Equatable, Sendable, Identifiable {
    public var tab: WindowTab
    public var title: String
    public var isShown: Bool
    /// False for tabs that are always shown.
    public var canToggle: Bool

    public var id: WindowTab { tab }
}

/// User-arranged order over a fixed set of items, such as sidebar tabs or a tab's sections.
public enum LayoutOrder {
    /// The items in `saved` order. Saved ids that no longer exist are dropped, and items missing
    /// from `saved` (e.g. added in an update) keep their default place after their default predecessor.
    public static func arranged<ID: Equatable>(_ defaults: [ID], saved: [ID]) -> [ID] {
        var order = saved.reduce(into: [ID]()) { order, id in
            if defaults.contains(id), !order.contains(id) { order.append(id) }
        }
        for (index, id) in defaults.enumerated() where !order.contains(id) {
            let predecessor = defaults[..<index].last { order.contains($0) }
            let position = predecessor.flatMap { order.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            order.insert(id, at: position)
        }
        return order
    }

    /// Drops `item` onto `target`: it takes the target's place, and the target moves toward
    /// where the item came from. Unknown ids leave the order unchanged.
    public static func moving<ID: Equatable>(_ item: ID, onto target: ID, in order: [ID]) -> [ID] {
        guard item != target, let from = order.firstIndex(of: item), let to = order.firstIndex(of: target) else {
            return order
        }
        var order = order
        order.remove(at: from)
        order.insert(item, at: to)
        return order
    }
}

/// How wide a window-tab section is. Consecutive half-width sections share a row.
public enum SectionWidth: Sendable {
    case full, half
}

public enum SectionLayout {
    /// Groups sections into rows: each full-width section alone, half-width sections in pairs
    /// as they come. A half-width section with no partner gets the row to itself.
    public static func rows<ID>(_ order: [ID], width: (ID) -> SectionWidth) -> [[ID]] {
        var rows: [[ID]] = []
        var pending: ID?
        for id in order {
            switch width(id) {
            case .full:
                if let half = pending { rows.append([half]) }
                pending = nil
                rows.append([id])
            case .half:
                if let half = pending {
                    rows.append([half, id])
                    pending = nil
                } else {
                    pending = id
                }
            }
        }
        if let half = pending { rows.append([half]) }
        return rows
    }
}

extension Monitor {
    /// The sidebar: the user's tab order, without hidden tabs, tabs for hardware this Mac lacks, or
    /// groups left empty. Settings isn't in a group; it always sits at the bottom.
    public var sidebarGroups: [SidebarGroup] {
        let order = tabOrder
        let hidden = preferences.hiddenTabs
        return WindowTab.groups.compactMap { group in
            let tabs = order.filter { group.tabs.contains($0) && isAvailable($0) && !isHidden($0, in: hidden) }
            return tabs.isEmpty ? nil : SidebarGroup(title: group.title, tabs: tabs)
        }
    }

    /// Settings › Window Tabs, in default order. Tabs this Mac can't show have no chip.
    public var windowTabChips: [WindowTabChip] {
        let hidden = preferences.hiddenTabs
        return WindowTab.allCases.filter { $0 != .settings && isAvailable($0) }.map { tab in
            WindowTabChip(tab: tab, title: tab.shortTitle, isShown: !isHidden(tab, in: hidden), canToggle: tab.canHide)
        }
    }

    /// Shows or hides a sidebar tab. Overview and Settings can't be hidden.
    public func setTabShown(_ shown: Bool, _ tab: WindowTab) {
        guard tab.canHide else { return }
        var hidden = preferences.hiddenTabs
        if shown { hidden.remove(tab.rawValue) } else { hidden.insert(tab.rawValue) }
        preferences.hiddenTabs = hidden
    }

    /// Drops a sidebar tab onto another in the same group. Tabs don't move between groups.
    public func moveTab(_ tab: WindowTab, onto target: WindowTab) {
        guard WindowTab.groups.contains(where: { $0.tabs.contains(tab) && $0.tabs.contains(target) }) else { return }
        preferences.tabOrder = LayoutOrder.moving(tab, onto: target, in: tabOrder).map(\.rawValue)
    }

    /// A tab's section ids in the user's order. `defaults` is the tab's own section list, in default order.
    public func sectionOrder(in tab: WindowTab, defaults: [String]) -> [String] {
        LayoutOrder.arranged(defaults, saved: preferences.sectionOrder(in: tab))
    }

    /// Drops one of a tab's sections onto another.
    public func moveSection(_ section: String, onto target: String, in tab: WindowTab, defaults: [String]) {
        let order = sectionOrder(in: tab, defaults: defaults)
        let moved = LayoutOrder.moving(section, onto: target, in: order)
        if moved != order { preferences.setSectionOrder(moved, in: tab) }
    }

    private var tabOrder: [WindowTab] {
        LayoutOrder.arranged(WindowTab.allCases, saved: preferences.tabOrder.compactMap(WindowTab.init(rawValue:)))
    }

    /// Tabs that can't be hidden never are, even if settings were edited by hand.
    private func isHidden(_ tab: WindowTab, in hidden: Set<String>) -> Bool {
        tab.canHide && hidden.contains(tab.rawValue)
    }

    private func isAvailable(_ tab: WindowTab) -> Bool {
        tab == .battery ? hasBattery : true
    }
}
