import MoniMacCore
import SwiftUI

// Memory: filled in by ticket 05. Kept in its own file so tickets built in parallel
// don't edit shared views.

/// The popover's Memory tab.
struct MemoryPopoverTab: View {
    let monitor: Monitor

    var body: some View {
        ComingSoon(title: "Memory")
    }
}

/// The main window's Memory tab.
struct MemoryWindowTab: View {
    let monitor: Monitor

    /// The toolbar subtitle for this tab, e.g. hardware details.
    static func subtitle(_ monitor: Monitor) -> String? {
        nil
    }

    var body: some View {
        ComingSoon(title: "Memory")
    }
}
