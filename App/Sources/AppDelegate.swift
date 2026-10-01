import AppKit
import MoniMacCore
import MoniMacSystem
import os

private let log = Logger(subsystem: "io.github.lethanhvietctt5.MoniMac", category: "App")

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = Monitor(sampler: HostSampler(), history: makeHistory(), preferences: Preferences())
    private var statusBar: StatusBarController?
    private var refresh: Task<Void, Never>?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(monitor: monitor)
        refresh = Task { [monitor] in
            await monitor.run(every: .seconds(2))
        }
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
