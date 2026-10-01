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

    /// Tabs with content so far; Overview is a placeholder until ticket 11.
    var isAvailable: Bool { self != .overview }
}

/// The popover shown when a menu bar item is clicked.
struct PopoverView: View {
    let monitor: Monitor
    let openWindow: () -> Void
    let quit: () -> Void
    @State private var tab: PopoverTab = .cpu

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 12) {
                SegmentedPicker(options: PopoverTab.allCases, selection: $tab, label: \.rawValue,
                                isEnabled: \.isAvailable)
                switch tab {
                case .overview: ComingSoon(title: "Overview")
                case .cpu: CPUTab(monitor: monitor)
                case .memory: MemoryPopoverTab(monitor: monitor)
                case .gpu: GPUPopoverTab(monitor: monitor)
                case .network: NetworkPopoverTab(monitor: monitor)
                case .disk: DiskPopoverTab(monitor: monitor)
                case .battery: BatteryPopoverTab(monitor: monitor)
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
                headerButton("macwindow", help: "Open MoniMac", action: openWindow)
                // Wired up by Settings (ticket 13).
                headerButton("gearshape", help: "Settings (coming soon)", action: nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func headerButton(_ symbol: String, help: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Image(systemName: symbol).font(.system(size: 13))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.textSecondary)
        .disabled(action == nil)
        .help(help)
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
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.textSecondary)
        .padding(.top, 2)
    }
}
