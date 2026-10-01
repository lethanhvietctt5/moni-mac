import MoniMacCore
import SwiftUI

// Temperature & Fans: filled in by ticket 10. Kept in its own file so tickets built in parallel
// don't edit shared views.

/// The main window's Temperature & Fans tab.
struct TemperatureWindowTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the window so it survives switching tabs.
    @Binding var range: TimeRange

    var body: some View {
        ComingSoon(title: "Temperature & Fans")
    }
}
