import AppKit
import Darwin
import MoniMacCore
import os
import ServiceManagement

private let log = Logger(subsystem: "io.github.lethanhvietctt5.MoniMac", category: "Actions")

/// The real SystemActions, through NSWorkspace, signals, and the Docker API.
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

    public var launchAtLogin: LaunchAtLogin {
        switch SMAppService.mainApp.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        default: .off
        }
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Launch at login \(enabled ? "on" : "off", privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }
}
