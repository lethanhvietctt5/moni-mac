import AppKit
import MoniMacCore
import Observation
import SwiftUI

/// The main window's tabs, in sidebar order.
enum WindowTab: String, CaseIterable, Identifiable {
    case overview, cpu, memory, gpu, network, disk
    case battery, bluetooth, sound, temperature
    case projects
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .gpu: "GPU"
        case .network: "Network"
        case .disk: "Disk"
        case .battery: "Battery"
        case .bluetooth: "Bluetooth"
        case .sound: "Sound"
        case .temperature: "Temperature & Fans"
        case .projects: "Projects"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .gpu: "rectangle.3.group"
        case .network: "arrow.up.arrow.down"
        case .disk: "internaldrive"
        case .battery: "battery.75percent"
        case .bluetooth: "dot.radiowaves.left.and.right"
        case .sound: "speaker.wave.2"
        case .temperature: "thermometer.medium"
        case .projects: "folder"
        case .settings: "gearshape"
        }
    }

    /// Sidebar groups; Settings sits alone at the bottom.
    static let groups: [(title: String, tabs: [WindowTab])] = [
        ("Monitor", [.overview, .cpu, .memory, .gpu, .network, .disk]),
        ("Devices", [.battery, .bluetooth, .sound, .temperature]),
        ("Developer", [.projects]),
    ]
}

@MainActor
@Observable
final class WindowState {
    var tab: WindowTab = .cpu
}

/// Owns the main window. The window (and its SwiftUI views) exist only while it's open.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let monitor: Monitor
    private let state = WindowState()
    private var window: NSWindow?

    init(monitor: Monitor) {
        self.monitor = monitor
    }

    func show(tab: WindowTab? = nil) {
        if let tab { state.tab = tab }
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "MoniMac"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1000, height: 680)
        window.contentView = NSHostingView(rootView: MainWindowView(monitor: monitor, state: state))
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("MoniMac.MainWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
    }
}

struct MainWindowView: View {
    let monitor: Monitor
    @Bindable var state: WindowState
    @State private var range: TimeRange = .twentyFourHours

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $state.tab)
                .frame(width: 232)
            VStack(spacing: 0) {
                toolbar
                Rectangle().fill(Palette.separator).frame(height: 1)
                ScrollView {
                    content.padding(24)
                }
            }
            .background(Palette.windowBackground)
        }
        .ignoresSafeArea()
    }

    private var subtitle: String? {
        switch state.tab {
        case .cpu: monitor.cpuDetail(range: range).subtitle
        default: nil
        }
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(state.tab.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            // Wired up by the share card (ticket 19).
            Button {} label: {
                Image(systemName: "square.and.arrow.up").font(.system(size: 14))
                    .frame(width: 30, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textSecondary)
            .disabled(true)
            .help("Share (coming soon)")
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
    }

    @ViewBuilder
    private var content: some View {
        switch state.tab {
        case .cpu:
            CPUWindowTab(detail: monitor.cpuDetail(range: range), range: $range)
        default:
            Text("\(state.tab.title) is coming soon.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 400)
        }
    }
}

private struct Sidebar: View {
    @Binding var selection: WindowTab

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Room for the window's traffic lights.
            Spacer().frame(height: 36)
            ForEach(WindowTab.groups, id: \.title) { group in
                Text(group.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                ForEach(group.tabs) { item($0) }
            }
            Spacer()
            item(.settings)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Palette.separator).frame(width: 1)
        }
    }

    private func item(_ tab: WindowTab) -> some View {
        let selected = tab == selection
        return Button {
            selection = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 13))
                    .frame(width: 16)
                    .foregroundStyle(selected ? .white : Palette.accent)
                Text(tab.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? .white : Palette.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Palette.accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
