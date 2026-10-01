import AppKit
import MoniMacCore
import MoniMacSystem

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = Monitor(sampler: HostSampler())
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
}
