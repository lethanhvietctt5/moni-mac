import MoniMacCore
import SwiftUI

enum PopoverTab: String, CaseIterable {
    case overview = "Overview"
    case cpu = "CPU"
    case memory = "Memory"
    case gpu = "GPU"
    case network = "Network"
    case disk = "Disk"
    case battery = "Battery"

    /// Tabs for hardware this Mac lacks are hidden.
    @MainActor
    func isShown(on monitor: Monitor) -> Bool {
        self == .battery ? monitor.hasBattery : true
    }
}

/// The popover shown when a menu bar item is clicked.
struct PopoverView: View {
    let monitor: Monitor
    let openWindow: () -> Void
    let quit: () -> Void
    let openSettings: () -> Void
    @State private var tab = PopoverTab.allCases.first { $0.rawValue.lowercased() == AppDelegate.launchTab } ?? .overview
    /// Each tab's chart range, so it survives switching tabs while the popover is open.
    @State private var ranges: [PopoverTab: TimeRange] = [:]

    private func range(for tab: PopoverTab) -> Binding<TimeRange> {
        Binding { ranges[tab] ?? .fiveMinutes } set: { ranges[tab] = $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 12) {
                SegmentedPicker(options: PopoverTab.allCases.filter { $0.isShown(on: monitor) }, selection: $tab,
                                label: \.rawValue)
                let range = range(for: tab)
                switch tab {
                case .overview: OverviewPopoverTab(monitor: monitor, openWindow: openWindow)
                case .cpu: CPUTab(monitor: monitor, range: range)
                case .memory: MemoryPopoverTab(monitor: monitor, range: range)
                case .gpu: GPUPopoverTab(monitor: monitor, range: range)
                case .network: NetworkPopoverTab(monitor: monitor, range: range)
                case .disk: DiskPopoverTab(monitor: monitor, range: range)
                case .battery: BatteryPopoverTab(monitor: monitor, range: range)
                }
                footer(status: monitor.statusLine)
            }
            .padding(14)
        }
        .frame(width: 380)
        .background(Palette.windowBackground)
    }

    private var header: some View {
        HStack {
            Text("MoniMac")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            HStack(spacing: 12) {
                headerButton("macwindow", help: "Open MoniMac", id: "popover.openWindow", action: openWindow)
                headerButton("gearshape", help: "Settings", id: "popover.settings", action: openSettings)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func headerButton(_ symbol: String, help: String, id: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Image(systemName: symbol).font(.system(size: 13))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.textSecondary)
        .disabled(action == nil)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(id)
    }

    private func footer(status: String) -> some View {
        HStack {
            HStack(spacing: 6) {
                Circle().fill(Palette.success).frame(width: 6, height: 6)
                Text(status)
            }
            Spacer()
            Button("Quit MoniMac", action: quit)
                .buttonStyle(.plain)
                .fontWeight(.medium)
                .accessibilityIdentifier("popover.quit")
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.textSecondary)
        .padding(.top, 2)
    }
}
