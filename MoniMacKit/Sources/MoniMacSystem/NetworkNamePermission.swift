import CoreLocation

/// macOS shows the Wi-Fi network name only to apps with Location access.
///
/// The Network tab asks once, the first time it's shown (never at launch). macOS prompts only while
/// the decision is undetermined, so after the user answers this does nothing. If access is denied,
/// the sampler reads no network name and the tab shows the interface without it.
@MainActor
public enum NetworkNamePermission {
    private static var manager: CLLocationManager?

    public static func requestIfNeeded() {
        guard manager == nil else { return }
        let manager = CLLocationManager()
        // Kept alive: the prompt is dismissed if its manager is released.
        self.manager = manager
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }
}
