import AppKit
import Darwin
import MoniMacCore
import os

private let log = Logger(subsystem: "io.github.lethanhvietctt5.MoniMac", category: "Actions")

/// The real SystemActions, through NSWorkspace, signals, and the Docker API.
@MainActor
public final class WorkspaceActions: SystemActions {
    public init() {}

    public func quitApp(pid: Int32, reopenWindows: Bool) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        // terminate() sends a normal quit request, so the app can save work or refuse. It can't say
        // whether to keep windows, so that one case sends the quit event itself.
        guard reopenWindows else {
            app.terminate()
            return
        }
        do {
            try sendQuitKeepingWindows(to: pid)
        } catch {
            // e.g. -1743 if macOS withholds Apple events from MoniMac. Still quit, as asked; the app
            // then follows its own window setting.
            log.error("Quit and Keep Windows failed for pid \(pid): \(String(describing: error), privacy: .public)")
            app.terminate()
        }
    }

    /// Sends the quit Apple event that Quit and Keep Windows (⌥⌘Q) and logout's "Reopen windows when
    /// logging back in" use: `kAEQuitApplication` with `kAEQuitPreserveState` = `kAEYes`. AppKit apps
    /// then save their windows for restoration on next launch, whatever the system's "Close windows
    /// when quitting an application" setting says. Apps that don't use macOS window restoration ignore it.
    private func sendQuitKeepingWindows(to pid: Int32) throws {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEQuitApplication),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(kAEYes)), forKeyword: AEKeyword(kAEQuitPreserveState))
        // No reply: the app may show a save dialog and take as long as the user needs.
        _ = try event.sendEvent(options: [.noReply], timeout: 5)
    }

    public func forceQuitApp(pid: Int32) {
        NSRunningApplication(processIdentifier: pid)?.forceTerminate()
    }

    public func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    public func stopProcess(pid: Int32, startedAt: Date) {
        // The pid comes from a reading up to ~15 s old. Signal it only if it's still the same
        // process and the user's own; a reused pid could be anything.
        guard let info = DevProcessInfo.bsdInfo(pid), info.pbi_uid == getuid(),
              abs(DevProcessInfo.startTime(info).timeIntervalSince(startedAt)) < 1
        else {
            log.notice("Not stopping pid \(pid): it's no longer the same process")
            return
        }
        if kill(pid, SIGTERM) != 0 {
            log.error("SIGTERM to pid \(pid) failed: \(String(cString: strerror(errno)), privacy: .public)")
        }
    }

    public func stopContainer(id: String) {
        // Container ids are hex; anything else isn't one of ours to put in a URL path.
        guard !id.isEmpty, id.allSatisfy(\.isHexDigit), let socket = DockerClient.locate()?.socketPath else { return }
        // Docker waits up to 10 s for the container to exit before killing it.
        let client = DockerClient(socketPath: socket, timeout: 15)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let response = try client.request("POST", "/containers/\(id)/stop")
                if !(200..<300).contains(response.status), response.status != 304 {
                    log.error("Stopping container failed with HTTP \(response.status)")
                }
            } catch {
                log.error("Stopping container failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    public func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    public func revealInFinder(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
