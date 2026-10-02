import AppKit
import MoniMacCore
@preconcurrency import UserNotifications

/// Handles the buttons on MoniMac's notifications. "Quit <App>" opens the quit sheet as a standalone panel
/// (it never quits by itself); "Show", or clicking the banner, opens the window on Overview › List sorted by
/// the alert's figure, with the app expanded, or on the alert's tab (Bluetooth for a low battery).
@MainActor
final class AlertNotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    private let quitSheet: QuitSheetPresenter
    private let show: (AlertTarget) -> Void

    init(quitSheet: QuitSheetPresenter, show: @escaping (AlertTarget) -> Void) {
        self.quitSheet = quitSheet
        self.show = show
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let target = AlertNotification.target(from: response.notification.request.content.userInfo) else { return }
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case AlertNotification.quitAction:
                if case .app(let app, _) = target { quitSheet.present(appID: app, over: nil) }
            case AlertNotification.showAction, UNNotificationDefaultActionIdentifier:
                show(target)
            default:
                break
            }
        }
    }

    /// MoniMac is usually in the background, but if it's frontmost (e.g. the window is open), still show the banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
