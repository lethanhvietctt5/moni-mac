import AppKit
import MoniMacCore
import Observation

/// Owns the menu bar items and re-renders them whenever the monitor's feature state changes.
@MainActor
final class StatusBarController: NSObject {
    private let monitor: Monitor
    private var items: [Metric: NSStatusItem] = [:]
    /// The style each item was last sized for; the item is resized only when this changes.
    private var sizedStyles: [Metric: MenuBarStyle] = [:]

    init(monitor: Monitor) {
        self.monitor = monitor
        super.init()
        observe()
    }

    private func observe() {
        withObservationTracking {
            render(monitor.menuBarItems)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func render(_ menuBarItems: [MenuBarItem]) {
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
            updateStyleChecks(in: statusItem.menu, selected: item.style)
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
        statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        statusItem.menu = makeMenu(for: metric)
        return statusItem
    }

    // Temporary until the popover (ticket 03) and Settings (ticket 13): style picker and Quit.
    private func makeMenu(for metric: Metric) -> NSMenu {
        let menu = NSMenu()
        for style in MenuBarStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(selectStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = StyleChoice(metric: metric, style: style)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MoniMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func updateStyleChecks(in menu: NSMenu?, selected: MenuBarStyle) {
        for item in menu?.items ?? [] {
            guard let choice = item.representedObject as? StyleChoice else { continue }
            item.state = choice.style == selected ? .on : .off
        }
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? StyleChoice else { return }
        monitor.setMenuBarStyle(choice.style, for: choice.metric)
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
