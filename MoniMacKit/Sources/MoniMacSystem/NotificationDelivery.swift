import AppKit
import MoniMacCore
import os
@preconcurrency import UserNotifications

private let log = Logger(subsystem: "io.github.lethanhvietctt5.MoniMac", category: "Notifications")

/// Posts alerts through the system notification center.
///
/// The notification center is touched only when asking for permission or posting, never at launch, so
/// nothing prompts until a rule is turned on or the first alert fires. With `isMuted` (the `--mute-notifications`
/// development flag) alerts are only logged and the notification center is never touched at all.
@MainActor
final class NotificationDelivery {
    private let isMuted: Bool
    /// Categories registered so far. An action's title is fixed per category, so every app that can be
    /// quit gets its own, carrying "Quit <App>".
    private var categories: [String: UNNotificationCategory] = [:]

    init(isMuted: Bool) {
        self.isMuted = isMuted
    }

    func requestAuthorization() {
        guard !isMuted else {
            log.notice("Notifications muted: not asking for permission")
            return
        }
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                log.notice("Notification permission \(granted ? "granted" : "not granted", privacy: .public)")
            } catch {
                log.error("Notification permission request failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func deliver(_ alert: Alert) {
        guard !isMuted else {
            log.notice("Alert (muted) \(alert.id, privacy: .public): \(alert.title, privacy: .public) · \(alert.chip, privacy: .public)")
            return
        }
        let center = UNUserNotificationCenter.current()
        let category = register(category(for: alert), in: center)
        let content = UNMutableNotificationContent()
        content.title = alert.title
        // The metric chip: macOS banners have no pill, so the figure leads as the subtitle.
        content.subtitle = alert.chip
        content.body = alert.body
        content.categoryIdentifier = category
        content.threadIdentifier = alert.rule.rawValue
        content.userInfo = AlertNotification.userInfo(for: alert)
        if let icon = alert.bundlePath.flatMap(Self.iconAttachment) { content.attachments = [icon] }
        // One notification per condition: a re-armed condition replaces its earlier banner.
        let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
        Task {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                break
            case .notDetermined:
                guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            default:
                log.notice("Notifications are off for MoniMac; not posting \(alert.id, privacy: .public)")
                return
            }
            do {
                try await center.add(request)
            } catch {
                log.error("Posting \(alert.id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func category(for alert: Alert) -> UNNotificationCategory {
        let show = UNNotificationAction(identifier: AlertNotification.showAction, title: "Show", options: [.foreground])
        guard let quitTitle = alert.quitTitle else {
            return UNNotificationCategory(identifier: "alert.show", actions: [show], intentIdentifiers: [])
        }
        let quit = UNNotificationAction(identifier: AlertNotification.quitAction, title: quitTitle, options: [.foreground])
        return UNNotificationCategory(identifier: "alert.quit.\(alert.appID)", actions: [quit, show], intentIdentifiers: [])
    }

    /// Registers a category the first time it's needed. Registration is asynchronous, so the very first
    /// notification of a new category can, rarely, show without its buttons.
    private func register(_ category: UNNotificationCategory, in center: UNUserNotificationCenter) -> String {
        if categories[category.identifier] == nil {
            categories[category.identifier] = category
            center.setNotificationCategories(Set(categories.values))
        }
        return category.identifier
    }

    /// The app's icon as an attachment, shown as the banner's thumbnail. The system moves the file into its
    /// own store, so each notification gets a fresh copy.
    private static func iconAttachment(bundlePath: String) -> UNNotificationAttachment? {
        let icon = NSWorkspace.shared.icon(forFile: bundlePath)
        icon.size = NSSize(width: 128, height: 128)
        guard let tiff = icon.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "MoniMac-alert-\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return try UNNotificationAttachment(identifier: "icon", url: url)
        } catch {
            log.error("App icon attachment failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
