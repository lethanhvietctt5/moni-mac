import AppKit
import MoniMacCore
import MoniMacSystem
import os

private let log = Logger(subsystem: "io.github.lethanhvietctt5.MoniMac", category: "App")

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = Monitor(
        sampler: HostSampler(), history: makeHistory(), preferences: Preferences(), actions: WorkspaceActions()
    )
    private var statusBar: StatusBarController?
    private lazy var mainWindow = MainWindowController(monitor: monitor)
    private var refresh: Task<Void, Never>?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        statusBar = StatusBarController(monitor: monitor) { [weak self] in self?.mainWindow.show() }
        refresh = Task { [monitor] in
            await monitor.run(every: .seconds(2))
        }
        // Development aid: `--show-popover` opens the popover on launch, so it can be screenshotted.
        // `--show-window` opens the main window on launch, for the same reason; add `--tab=<tab>`
        // (a `WindowTab` raw value, e.g. `--tab=temperature`) to open it on that tab.
        if CommandLine.arguments.contains("--show-window") {
            let tab = CommandLine.arguments.lazy.filter { $0.hasPrefix("--tab=") }
                .compactMap { WindowTab(rawValue: String($0.dropFirst("--tab=".count))) }.first
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.mainWindow.show(tab: tab)
            }
        }
        if CommandLine.arguments.contains("--show-popover") {
            Task { @MainActor [statusBar] in
                try? await Task.sleep(for: .seconds(3))
                statusBar?.showPopover()
            }
        }
    }

    /// MoniMac shows no menu bar of its own, but key equivalents like ⌘W and ⌘Q still route through it.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit MoniMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)
        let windowItem = NSMenuItem()
        windowItem.submenu = NSMenu(title: "Window")
        windowItem.submenu?.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu?.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(windowItem)
        return main
    }

    func applicationWillTerminate(_ notification: Notification) {
        refresh?.cancel()
    }

    /// History lives in Application Support. If it can't be opened, MoniMac keeps working in memory.
    private static func makeHistory() -> MetricsHistory {
        let url = URL.applicationSupportDirectory.appending(path: "MoniMac/History.sqlite")
        do {
            return try MetricsHistory(.file(url))
        } catch {
            log.error("History unavailable at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            // An in-memory SQLite database only fails to open when out of memory.
            return try! MetricsHistory(.inMemory)
        }
    }
}
