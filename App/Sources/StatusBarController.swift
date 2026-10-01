import AppKit
import MoniMacCore
import Observation
import SwiftUI

/// Owns the menu bar items and re-renders them whenever the monitor's feature state changes.
@MainActor
final class StatusBarController: NSObject {
    private let monitor: Monitor
    private var items: [Metric: NSStatusItem] = [:]
    /// The style each item was last sized for; the item is resized only when this changes.
    private var sizedStyles: [Metric: MenuBarStyle] = [:]
    private var menus: [Metric: NSMenu] = [:]
    private let popover = NSPopover()
    private let openWindow: () -> Void

    init(monitor: Monitor, openWindow: @escaping () -> Void) {
        self.monitor = monitor
        self.openWindow = openWindow
        super.init()
        popover.behavior = .transient
        popover.delegate = self
        observe()
    }

    /// Opens the popover under the first menu bar item.
    func showPopover() {
        guard let metric = monitor.menuBarItems.first?.metric, let button = items[metric]?.button else { return }
        show(from: button)
    }

    /// The SwiftUI content exists only while the popover is open, so a closed popover costs nothing.
    private func show(from button: NSStatusBarButton) {
        guard !popover.isShown else { return }
        let content = NSHostingController(rootView: PopoverView(
            monitor: monitor,
            openWindow: { [weak self] in
                self?.popover.performClose(nil)
                self?.openWindow()
            },
            quit: { NSApp.terminate(nil) }
        ))
        content.sizingOptions = [.preferredContentSize]
        popover.contentViewController = content
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func observe() {
        withObservationTracking {
            render(monitor.menuBarItems)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func render(_ menuBarItems: [MenuBarItem]) {
        let shown = Set(menuBarItems.map(\.metric))
        for (metric, statusItem) in items where !shown.contains(metric) {
            NSStatusBar.system.removeStatusItem(statusItem)
            items[metric] = nil
            sizedStyles[metric] = nil
            menus[metric] = nil
        }
        for item in menuBarItems {
            let statusItem = items[item.metric] ?? makeStatusItem(for: item.metric)
            items[item.metric] = statusItem
            guard let button = statusItem.button else { continue }

            if sizedStyles[item.metric] != item.style {
                // Size for the widest possible value so the item never changes width as values change.
                apply(item, text: item.widestText, to: button)
                statusItem.length = button.fittingSize.width
                sizedStyles[item.metric] = item.style
            }
            apply(item, text: item.text, to: button)
            refreshMenuStates(in: menus[item.metric], style: item.style)
        }
    }

    private func apply(_ item: MenuBarItem, text: String, to button: NSStatusBarButton) {
        switch item.style {
        case .value:
            button.image = MenuBarGraphics.icon(for: item.metric)
            button.title = text
        case .graph:
            button.image = MenuBarGraphics.iconAndSparkline(for: item.metric, bars: item.bars)
            button.title = ""
        case .both:
            button.image = MenuBarGraphics.sparkline(item.bars)
            button.title = text
        }
        button.imagePosition = button.title.isEmpty ? .imageOnly : .imageLeading
    }

    private func makeStatusItem(for metric: Metric) -> NSStatusItem {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "MoniMac.\(metric.rawValue)"
        if let button = statusItem.button {
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.identifier = NSUserInterfaceItemIdentifier(metric.rawValue)
        }
        menus[metric] = makeMenu(for: metric)
        return statusItem
    }

    /// Left click toggles the popover; right click shows the item's menu.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let metric = sender.identifier.flatMap({ Metric(rawValue: $0.rawValue) }),
              let statusItem = items[metric] else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            statusItem.menu = menus[metric]
            sender.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            show(from: sender)
        }
    }

    // Right-click menu, temporary until Settings (ticket 13): style picker and Quit.
    private func makeMenu(for metric: Metric) -> NSMenu {
        let menu = NSMenu()
        for style in MenuBarStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(selectStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = StyleChoice(metric: metric, style: style)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let itemsMenu = NSMenu()
        for other in Metric.allCases {
            let item = NSMenuItem(title: other.title, action: #selector(toggleItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = MetricChoice(metric: other)
            itemsMenu.addItem(item)
        }
        let itemsEntry = NSMenuItem(title: "Menu Bar Items", action: nil, keyEquivalent: "")
        itemsEntry.submenu = itemsMenu
        menu.addItem(itemsEntry)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MoniMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    /// Checks the item's current style and every metric currently shown in the menu bar.
    private func refreshMenuStates(in menu: NSMenu?, style: MenuBarStyle) {
        for item in menu?.items ?? [] {
            if let choice = item.representedObject as? StyleChoice {
                item.state = choice.style == style ? .on : .off
            }
            for subitem in item.submenu?.items ?? [] {
                guard let choice = subitem.representedObject as? MetricChoice else { continue }
                subitem.state = monitor.isMenuBarItemEnabled(choice.metric) ? .on : .off
            }
        }
    }

    @objc private func toggleItem(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? MetricChoice else { return }
        monitor.setMenuBarItemEnabled(!monitor.isMenuBarItemEnabled(choice.metric), for: choice.metric)
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? StyleChoice else { return }
        monitor.setMenuBarStyle(choice.style, for: choice.metric)
    }
}

extension StatusBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }
}

private final class MetricChoice: NSObject {
    let metric: Metric

    init(metric: Metric) {
        self.metric = metric
    }
}

private final class StyleChoice: NSObject {
    let metric: Metric
    let style: MenuBarStyle

    init(metric: Metric, style: MenuBarStyle) {
        self.metric = metric
        self.style = style
    }
}

private extension MenuBarStyle {
    var title: String {
        switch self {
        case .value: "Show Value"
        case .graph: "Show Graph"
        case .both: "Show Value + Graph"
        }
    }
}
