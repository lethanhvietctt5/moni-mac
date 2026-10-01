import MoniMacCore
import SwiftUI

// Network: filled in by ticket 07. Kept in its own file so tickets built in parallel
// don't edit shared views.

/// The popover's Network tab.
struct NetworkPopoverTab: View {
    let monitor: Monitor

    var body: some View {
        ComingSoon(title: "Network")
    }
}

/// The main window's Network tab.
struct NetworkWindowTab: View {
    let monitor: Monitor

    /// The toolbar subtitle for this tab, e.g. hardware details.
    static func subtitle(_ monitor: Monitor) -> String? {
        nil
    }

    var body: some View {
        ComingSoon(title: "Network")
    }
}
