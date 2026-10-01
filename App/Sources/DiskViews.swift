import MoniMacCore
import SwiftUI

// Disk: filled in by ticket 08. Kept in its own file so tickets built in parallel
// don't edit shared views.

/// The popover's Disk tab.
struct DiskPopoverTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the popover so it survives switching tabs.
    @Binding var range: TimeRange

    var body: some View {
        ComingSoon(title: "Disk")
    }
}

/// The main window's Disk tab.
struct DiskWindowTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the window so it survives switching tabs.
    @Binding var range: TimeRange

    var body: some View {
        ComingSoon(title: "Disk")
    }
}
