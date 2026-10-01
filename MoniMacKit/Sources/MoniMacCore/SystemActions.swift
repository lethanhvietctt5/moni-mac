/// Seam 2: the only way MoniMac changes anything outside itself.
///
/// The real implementation lives in MoniMacSystem; tests use a recording fake.
@MainActor
public protocol SystemActions: AnyObject {
    /// Asks an app to quit normally, so it can save work. Never forces.
    func quitApp(pid: Int32)
    func openActivityMonitor()
}
