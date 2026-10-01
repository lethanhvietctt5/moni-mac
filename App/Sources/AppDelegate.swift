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
    /// The quit confirmation, shared by the popover, the window, and (later) notifications.
    private lazy var quitSheet = QuitSheetPresenter(monitor: monitor)
    private lazy var mainWindow = MainWindowController(monitor: monitor, quitSheet: quitSheet)
    private var refresh: Task<Void, Never>?
    /// Development aid: `--tab <name>` or `--tab=<name>` (e.g. `--tab battery`) picks the tab the window
    /// or popover opens on. Names are the tabs' raw values, case-insensitive.
    static let launchTab: String? = {
        let arguments = CommandLine.arguments
        if let inline = arguments.first(where: { $0.hasPrefix("--tab=") }) {
            return String(inline.dropFirst("--tab=".count)).lowercased()
        }
        return value(after: "--tab")?.lowercased()
    }()

    /// The argument after `flag`, e.g. `--show-quit-sheet Safari` → "Safari".
    static func value(after flag: String) -> String? {
        let arguments = CommandLine.arguments
        return arguments.firstIndex(of: flag).flatMap {
            arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
        }
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        statusBar = StatusBarController(monitor: monitor, quitSheet: quitSheet) { [weak self] in self?.mainWindow.show() }
        refresh = Task { [monitor] in
            await monitor.run(every: .seconds(2))
        }
        // Development aid: `--show-popover` opens the popover on launch, so it can be screenshotted.
        // `--show-window` opens the main window on launch, for the same reason; `--tab` picks its tab,
        // `--overview-list` shows Overview as a List, and `--expand <app name>` opens that app's group.
        if CommandLine.arguments.contains("--show-window") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                let expanded = await self.appIDs(named: Self.value(after: "--expand").map { [$0] } ?? [])
                self.mainWindow.show(tab: Self.launchTab.flatMap(WindowTab.init(rawValue:)),
                                     layout: CommandLine.arguments.contains("--overview-list") ? .list : nil,
                                     expanding: Set(expanded))
            }
        }
        // Development aid: `--show-quit-sheet <app name>` opens the quit sheet for that app on launch,
        // standalone as from the popover, so it can be screenshotted. It never presses a button.
        if let name = Self.value(after: "--show-quit-sheet") {
            Task { @MainActor [weak self] in
                guard let self, let id = await self.appIDs(named: [name]).first else { return }
                self.quitSheet.present(appID: id)
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

    /// For the development flags: the ids of the app groups with these names (case-insensitive).
    /// The process list takes a few seconds to arrive, so this waits up to 15 s for it.
    private func appIDs(named names: [String]) async -> [AppUsage.ID] {
        guard !names.isEmpty else { return [] }
        let wanted = Set(names.map { $0.lowercased() })
        for _ in 0..<30 {
            let ids = monitor.apps.filter { wanted.contains($0.name.lowercased()) }.map(\.id)
            if !ids.isEmpty { return ids }
            try? await Task.sleep(for: .milliseconds(500))
        }
        log.notice("No running app named \(names.joined(separator: ", "), privacy: .public)")
        return []
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
