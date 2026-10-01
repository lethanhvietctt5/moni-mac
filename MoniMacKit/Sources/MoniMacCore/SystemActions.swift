import Foundation

/// Seam 2: the only way MoniMac changes anything outside itself.
///
/// The real implementation lives in MoniMacSystem; tests use a recording fake.
@MainActor
public protocol SystemActions: AnyObject {
    /// Asks an app to quit normally, so it can save work. Never forces.
    func quitApp(pid: Int32)
    func openActivityMonitor()
    /// Asks one of the user's processes to stop (SIGTERM), only if it's still the process that
    /// started at `startedAt` (pids are reused). Never escalates.
    func stopProcess(pid: Int32, startedAt: Date)
    /// Stops a Docker container through the Docker API.
    func stopContainer(id: String)
    func openURL(_ url: URL)
    /// Shows the folder selected in Finder.
    func revealInFinder(path: String)
    /// Whether MoniMac is registered to open at login. Reading it changes nothing.
    var launchesAtLogin: Bool { get }
    /// Adds MoniMac to, or removes it from, the user's login items.
    func setLaunchAtLogin(_ enabled: Bool)
}
