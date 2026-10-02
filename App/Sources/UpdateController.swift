import AppKit
import MoniMacCore
import Observation
import Sparkle
import os

private let log = Logger(subsystem: "io.github.lethanhvietctt5.MoniMac", category: "Updates")

/// The in-app updater (Sparkle), for release builds only.
///
/// Release builds set `MoniMacUpdatesEnabled` (scripts/release/build.sh) and carry the project's EdDSA key.
/// Development builds never start Sparkle: they don't contact the feed, don't ask about automatic checks,
/// and "Check for Updates…" is disabled. Sparkle's own prompt (on the second launch) decides automatic checks.
@MainActor
@Observable
final class UpdateController: NSObject {
    static let shared = UpdateController()

    private(set) var status: UpdateStatus = .off
    /// False in development builds and while Sparkle is already checking.
    private(set) var canCheck = false
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    /// Starts Sparkle if this is a release build. Errors are logged, never shown: a misconfigured build just has no updates.
    func start() {
        guard controller == nil, Self.updatesEnabled else { return }
        // Started by hand rather than by the controller, which would show an alert if the configuration is invalid.
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        do {
            try controller.updater.start()
        } catch {
            log.error("Updates unavailable: \(error.localizedDescription, privacy: .public)")
            return
        }
        self.controller = controller
        status = .idle
        // Sparkle changes this on the main thread.
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let canCheck = change.newValue ?? false
            MainActor.assumeIsolated { self?.canCheck = canCheck }
        }
    }

    /// Sparkle's own window shows progress, the release notes, and the result.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    private static var updatesEnabled: Bool {
        // A build setting substituted into Info.plist, so it arrives as the string "YES" or "NO".
        Bundle.main.object(forInfoDictionaryKey: "MoniMacUpdatesEnabled") as? String == "YES"
    }
}

extension UpdateController: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated { status = .available(version) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { status = .upToDate }
    }
}
