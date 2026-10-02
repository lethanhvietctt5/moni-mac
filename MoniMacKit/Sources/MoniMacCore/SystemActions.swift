import Foundation

/// Seam 2: the only way MoniMac changes anything outside itself.
///
/// The real implementation lives in MoniMacSystem; tests use a recording fake.
@MainActor
public protocol SystemActions: AnyObject {
    /// Asks an app to quit normally, so it can save work or refuse. Never forces.
    /// `reopenWindows` asks the app to restore its windows next launch, as Quit and Keep Windows (⌥⌘Q) does.
    func quitApp(pid: Int32, reopenWindows: Bool)
    /// Ends an app at once, without letting it save. Only after the user chose Force Quit.
    func forceQuitApp(pid: Int32)
    func openActivityMonitor()
    /// Asks one of the user's processes to stop (SIGTERM), only if it's still the process that
    /// started at `startedAt` (pids are reused). Never escalates.
    func stopProcess(pid: Int32, startedAt: Date)
    /// Stops a Docker container through the Docker API.
    func stopContainer(id: String)
    func openURL(_ url: URL)
    /// Shows the folder selected in Finder.
    func revealInFinder(path: String)
    /// Whether MoniMac is registered to open at login. Reading it changes nothing; it sits here,
    /// beside the only action that changes it, rather than in every snapshot.
    var launchAtLogin: LaunchAtLogin { get }
    /// Adds MoniMac to, or removes it from, the user's login items.
    func setLaunchAtLogin(_ enabled: Bool)
    /// Asks for permission to post notifications. macOS prompts only the first time; Monitor calls this
    /// only on first use (an alert firing or a rule being turned on), never at launch.
    func requestNotificationAuthorization()
    /// Posts an alert as a system notification, with "Quit <App>" (when offered) and "Show" actions.
    func deliver(_ alert: Alert)
}
