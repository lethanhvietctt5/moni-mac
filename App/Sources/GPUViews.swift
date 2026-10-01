import MoniMacCore
import SwiftUI

// GPU: filled in by ticket 06. Kept in its own file so tickets built in parallel
// don't edit shared views.

/// The popover's GPU tab.
struct GPUPopoverTab: View {
    let monitor: Monitor

    var body: some View {
        ComingSoon(title: "GPU")
    }
}

/// The main window's GPU tab.
struct GPUWindowTab: View {
    let monitor: Monitor

    /// The toolbar subtitle for this tab, e.g. hardware details.
    static func subtitle(_ monitor: Monitor) -> String? {
        nil
    }

    var body: some View {
        ComingSoon(title: "GPU")
    }
}
