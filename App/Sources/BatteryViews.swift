import MoniMacCore
import SwiftUI

// Battery: filled in by ticket 09. Kept in its own file so tickets built in parallel
// don't edit shared views.

/// The popover's Battery tab.
struct BatteryPopoverTab: View {
    let monitor: Monitor

    var body: some View {
        ComingSoon(title: "Battery")
    }
}

/// The main window's Battery tab.
struct BatteryWindowTab: View {
    let monitor: Monitor

    /// The toolbar subtitle for this tab, e.g. hardware details.
    static func subtitle(_ monitor: Monitor) -> String? {
        nil
    }

    var body: some View {
        ComingSoon(title: "Battery")
    }
}
