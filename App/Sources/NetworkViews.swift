import MoniMacCore
import SwiftUI

// Network: filled in by ticket 07. Kept in its own file so tickets built in parallel
// don't edit shared views.

/// The popover's Network tab.
struct NetworkPopoverTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the popover so it survives switching tabs.
    @Binding var range: TimeRange

    var body: some View {
        ComingSoon(title: "Network")
    }
}

/// The main window's Network tab.
struct NetworkWindowTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the window so it survives switching tabs.
    @Binding var range: TimeRange

    var body: some View {
        ComingSoon(title: "Network")
    }
}
