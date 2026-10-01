import AppKit
import MoniMacCore

/// The real SystemActions, through NSWorkspace and NSRunningApplication.
@MainActor
public final class WorkspaceActions: SystemActions {
    public init() {}

    public func quitApp(pid: Int32) {
        // terminate() sends a normal quit request, so the app can save work or refuse.
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    public func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
