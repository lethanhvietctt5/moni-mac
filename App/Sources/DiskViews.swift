import MoniMacCore
import SwiftUI

// Disk: filled in by ticket 08. Kept in its own file so tickets built in parallel
// don't edit shared views.

/// The popover's Disk tab.
struct DiskPopoverTab: View {
    let monitor: Monitor

    var body: some View {
        ComingSoon(title: "Disk")
    }
}

/// The main window's Disk tab.
struct DiskWindowTab: View {
    let monitor: Monitor

    /// The toolbar subtitle for this tab, e.g. hardware details.
    static func subtitle(_ monitor: Monitor) -> String? {
        nil
    }

    var body: some View {
        ComingSoon(title: "Disk")
    }
}
