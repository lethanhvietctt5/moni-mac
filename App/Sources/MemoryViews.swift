import MoniMacCore
import SwiftUI

// Memory: filled in by ticket 05. Kept in its own file so tickets built in parallel
// don't edit shared views.

/// The popover's Memory tab.
struct MemoryPopoverTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the popover so it survives switching tabs.
    @Binding var range: TimeRange

    var body: some View {
        ComingSoon(title: "Memory")
    }
}

/// The main window's Memory tab.
struct MemoryWindowTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the window so it survives switching tabs.
    @Binding var range: TimeRange

    var body: some View {
        ComingSoon(title: "Memory")
    }
}
