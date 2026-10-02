import AppKit
import MoniMacCore
import SwiftUI

/// Asks to quit an app group, which opens the quit sheet. Surfaces never quit directly.
struct RequestQuitAction {
    let handler: @MainActor (AppUsage.ID) -> Void

    @MainActor
    func callAsFunction(_ id: AppUsage.ID) {
        handler(id)
    }
}

extension EnvironmentValues {
    @Entry var requestQuit = RequestQuitAction { _ in }
}

/// Shows the quit confirmation for an app: as a sheet on the main window when there is one, or as a
/// small floating panel of its own (from the popover, or later a notification's "Quit <App>" action).
///
/// MoniMac is an accessory app, so the panel activates the app first; otherwise it would open behind
/// the app the user is in. Only one quit sheet is shown at a time.
@MainActor
final class QuitSheetPresenter: NSObject, NSWindowDelegate {
    private let monitor: Monitor
    private var panel: NSPanel?
    /// The window the sheet is attached to, or nil for a standalone panel.
    private weak var parent: NSWindow?
    /// The "Reopen windows" checkbox, remembered while MoniMac runs. Off by default: it takes effect
    /// only where macOS lets MoniMac send the app Apple events (see `WorkspaceActions.quitApp`).
    private var reopenWindows = false

    init(monitor: Monitor) {
        self.monitor = monitor
    }

    /// Opens the sheet for an app group. Groups that can't be quit open nothing.
    func present(appID: AppUsage.ID, over window: NSWindow? = nil) {
        guard monitor.quitSheet(for: appID) != nil else { return }
        dismiss()
        let panel = makePanel(appID: appID)
        self.panel = panel
        if let window, window.isVisible {
            parent = window
            window.beginSheet(panel)
        } else {
            NSApp.activate()
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func makePanel(appID: AppUsage.ID) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
                            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        // Panels hide when their app isn't active, and macOS may decline MoniMac's activation request.
        panel.hidesOnDeactivate = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self
        let content = NSHostingController(rootView: QuitSheetView(
            monitor: monitor, appID: appID,
            reopenWindows: Binding { [weak self] in self?.reopenWindows ?? false } set: { [weak self] in
                self?.reopenWindows = $0
            },
            finish: { [weak self] choice in self?.finish(appID: appID, choice: choice) }
        ))
        content.sizingOptions = [.preferredContentSize]
        panel.contentViewController = content
        return panel
    }

    private func finish(appID: AppUsage.ID, choice: QuitChoice) {
        // Close first: a quit can take a while (the app may show its own save dialog).
        dismiss()
        monitor.resolveQuit(appID: appID, choice: choice)
    }

    private func dismiss() {
        guard let panel else { return }
        self.panel = nil
        if let parent {
            parent.endSheet(panel)
        }
        parent = nil
        panel.delegate = nil
        panel.close()
        panel.contentViewController = nil
    }

    /// The panel's close button counts as Cancel.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSPanel, window === panel else { return }
        panel = nil
        parent = nil
        window.contentViewController = nil
    }
}

/// The quit confirmation. Renders `QuitSheet`; holds no logic.
private struct QuitSheetView: View {
    let monitor: Monitor
    let appID: AppUsage.ID
    @Binding var reopenWindows: Bool
    let finish: (QuitChoice) -> Void

    var body: some View {
        // Live: figures follow the monitor while the sheet is open.
        if let sheet = monitor.quitSheet(for: appID) {
            QuitSheetContent(sheet: sheet, reopenWindows: $reopenWindows, finish: finish)
        } else {
            // The app quit on its own while the sheet was open.
            Color.clear.frame(width: 440, height: 1).onAppear {
                // After this update: closing the panel tears down the view being updated.
                Task { @MainActor in finish(.cancel) }
            }
        }
    }
}

private struct QuitSheetContent: View {
    let sheet: QuitSheet
    @Binding var reopenWindows: Bool
    let finish: (QuitChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: AppIcons.icon(for: sheet.bundlePath)).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(sheet.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.textPrimary)
                        .accessibilityIdentifier("quitSheet.title")
                    Text(sheet.message).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            processTable
            Toggle(isOn: $reopenWindows) {
                Text(sheet.reopenLabel).font(.system(size: 12)).foregroundStyle(Palette.textPrimary)
            }
            .toggleStyle(.checkbox)
            .help("Like Quit and Keep Windows (⌥⌘Q): the app reopens its windows next launch. "
                + "Needs macOS to allow MoniMac to control the app; otherwise it quits normally.")
            HStack {
                Button { finish(.forceQuit) } label: {
                    Text("Force Quit").foregroundStyle(.red)
                }
                .help("Ends the app at once. Unsaved work is lost.")
                Spacer()
                Button("Cancel") { finish(.cancel) }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("quitSheet.cancel")
                Button("Quit") { finish(.quit(reopenWindows: reopenWindows)) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("quitSheet.quit")
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(20)
        .padding(.top, 8)
        .frame(width: 440)
        .background(Palette.windowBackground)
    }

    private var processTable: some View {
        VStack(spacing: 0) {
            row("Process", "PID", "CPU", "Memory", header: true)
            ForEach(sheet.processes) { process in
                row(process.name, process.pid, process.cpu, process.memory, header: false)
            }
            if let total = sheet.total {
                HStack {
                    Text(sheet.more ?? "").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text(total).font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Palette.surfaceRaised)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ name: String, _ pid: String, _ cpu: String, _ memory: String, header: Bool) -> some View {
        HStack(spacing: 8) {
            Text(name).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(header ? Palette.textSecondary : Palette.textPrimary)
            Text(pid).frame(width: 52, alignment: .trailing).foregroundStyle(Palette.textSecondary)
            Text(cpu).frame(width: 48, alignment: .trailing)
                .foregroundStyle(header ? Palette.textSecondary : Palette.textPrimary)
            Text(memory).frame(width: 64, alignment: .trailing)
                .foregroundStyle(header ? Palette.textSecondary : Palette.textPrimary)
        }
        .font(.system(size: header ? 11 : 12, weight: header ? .semibold : .regular).monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
