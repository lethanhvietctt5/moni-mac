import MoniMacCore
import SwiftUI

// Temperature & Fans: filled in by ticket 10. Kept in its own file so tickets built in parallel
// don't edit shared views.

/// The main window's Temperature & Fans tab.
struct TemperatureWindowTab: View {
    let monitor: Monitor

    /// The toolbar subtitle for this tab, e.g. hardware details.
    static func subtitle(_ monitor: Monitor) -> String? {
        nil
    }

    var body: some View {
        ComingSoon(title: "Temperature & Fans")
    }
}
