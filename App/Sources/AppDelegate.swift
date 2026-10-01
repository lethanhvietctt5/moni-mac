import AppKit
import MoniMacCore
import MoniMacSystem
import os

private let log = Logger(subsystem: "io.github.lethanhvietctt5.MoniMac", category: "App")

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = Monitor(
        sampler: HostSampler(storageScanCache: .standard), history: makeHistory(), preferences: Preferences(), actions: WorkspaceActions()
    )
    private var statusBar: StatusBarController?
    private lazy var mainWindow = MainWindowController(monitor: monitor)
    private var refresh: Task<Void, Never>?
    /// Development aid: `--tab <name>` or `--tab=<name>` (e.g. `--tab battery`) picks the tab the window
    /// or popover opens on. Names are the tabs' raw values, case-insensitive.
    static let launchTab: String? = {
        let arguments = CommandLine.arguments
        if let inline = arguments.first(where: { $0.hasPrefix("--tab=") }) {
            return String(inline.dropFirst("--tab=".count)).lowercased()
        }
        return arguments.firstIndex(of: "--tab").flatMap {
            arguments.indices.contains($0 + 1) ? arguments[$0 + 1].lowercased() : nil
        }
    }()

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
        // `--show-window` opens the main window on launch, for the same reason; `--tab` picks its tab.
        if CommandLine.arguments.contains("--show-window") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.mainWindow.show(tab: Self.launchTab.flatMap(WindowTab.init(rawValue:)))
            }
        }
        if CommandLine.arguments.contains("--show-popover") {
            Task { @MainActor [statusBar] in
                try? await Task.sleep(for: .seconds(3))
                statusBar?.showPopover()
            }
        }
        // `--show-share-card` opens the share card preview. `--export-share-card <path> [--dark]` renders the
        // card to a PNG and quits, so its size and look can be checked without clicking.
        if CommandLine.arguments.contains("--show-share-card") {
            Task { @MainActor [monitor] in
                try? await Task.sleep(for: .seconds(2))
                ShareCardWindowController.shared.show(monitor: monitor)
            }
        }
        if let path = Self.launchValue("--export-share-card") {
            Task { @MainActor [monitor] in
                // Wait for a few samples, so the card has the Mac's memory and battery and the process list
                // (for the busiest app's icon) has warmed up.
                try? await Task.sleep(for: .seconds(5))
                let dark = CommandLine.arguments.contains("--dark")
                if !ShareCardWindowController.export(monitor: monitor, to: path, dark: dark) {
                    log.error("Couldn't export the share card to \(path, privacy: .public)")
                }
                NSApp.terminate(nil)
            }
        }
    }

    /// The value after a development flag, e.g. the path in `--export-share-card <path>`.
    private static func launchValue(_ flag: String) -> String? {
        let arguments = CommandLine.arguments
        return arguments.firstIndex(of: flag).flatMap {
            arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
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
        let url = AppFiles.directory.appending(path: "History.sqlite")
        do {
            return try MetricsHistory(.file(url))
        } catch {
            log.error("History unavailable at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            // An in-memory SQLite database only fails to open when out of memory.
            return try! MetricsHistory(.inMemory)
        }
    }
}
