import AppKit
import MoniMacCore
import Observation

/// Owns the menu bar items and re-renders them whenever the monitor's feature state changes.
@MainActor
final class StatusBarController {
    private let monitor: Monitor
    private var items: [Metric: NSStatusItem] = [:]

    init(monitor: Monitor) {
        self.monitor = monitor
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
            statusItem.button?.title = item.text
        }
    }

    private func makeStatusItem(for metric: Metric) -> NSStatusItem {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "MoniMac.\(metric.rawValue)"
        if let button = statusItem.button {
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.image = NSImage(systemSymbolName: metric.symbolName, accessibilityDescription: metric.title)
            button.imagePosition = .imageLeading
        }
        // Temporary until the popover lands (ticket 03): an accessory app has no other way to quit.
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit MoniMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        return statusItem
    }
}

private extension Metric {
    var title: String {
        switch self {
        case .cpu: "CPU"
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: "cpu"
        }
    }
}
