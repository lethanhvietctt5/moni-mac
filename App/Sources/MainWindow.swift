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

    /// Tabs for hardware this Mac lacks are hidden.
    @MainActor
    func isShown(on monitor: Monitor) -> Bool {
        self == .battery ? monitor.hasBattery : true
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
    var tab: WindowTab = .overview
    /// Each tab's chart range, so it survives switching tabs.
    var ranges: [WindowTab: TimeRange] = [:]

    /// Overview's Tiles or List view, and the List's sort, search, and grouping.
    var overviewLayout = OverviewLayout.tiles
    var listQuery = OverviewListQuery()

    func range(for tab: WindowTab) -> Binding<TimeRange> {
        Binding { self.ranges[tab] ?? .twentyFourHours } set: { self.ranges[tab] = $0 }
    }

    /// Shows Overview → List with every app, sorted by `column`.
    func showList(sortedBy column: OverviewListColumn) {
        tab = .overview
        overviewLayout = .list
        listQuery.showAll(sortedBy: column)
    }
}

enum OverviewLayout {
    case tiles, list
}

/// Owns the main window. The window (and its SwiftUI views) exist only while it's open.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let monitor: Monitor
    private let quitSheet: QuitSheetPresenter
    private let state = WindowState()
    private var window: NSWindow?

    init(monitor: Monitor, quitSheet: QuitSheetPresenter) {
        self.monitor = monitor
        self.quitSheet = quitSheet
    }

    func show(tab: WindowTab? = nil, layout: OverviewLayout? = nil, expanding expanded: Set<AppUsage.ID> = []) {
        if let tab { state.tab = tab }
        if let layout { state.overviewLayout = layout }
        state.listQuery.expanded.formUnion(expanded)
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
        window.contentView = NSHostingView(rootView: MainWindowView(monitor: monitor, state: state)
            .environment(\.requestQuit, RequestQuitAction { [weak self, weak window] id in
                self?.quitSheet.present(appID: id, over: window)
            }))
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

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $state.tab, isShown: { $0.isShown(on: monitor) })
                .frame(width: 232)
            VStack(spacing: 0) {
                toolbar
                Rectangle().fill(Palette.separator).frame(height: 1)
                if state.tab == .overview && state.overviewLayout == .list {
                    // The table scrolls inside, so its header and footer stay put.
                    OverviewListTab(monitor: monitor, query: $state.listQuery).padding(24)
                } else {
                    ScrollView {
                        content.padding(24)
                    }
                }
            }
            .background(Palette.windowBackground)
        }
        .ignoresSafeArea()
        .environment(\.showInList, ShowInListAction { [state] in state.showList(sortedBy: $0) })
    }

    private var subtitle: String? {
        switch state.tab {
        case .cpu: monitor.cpuSubtitle
        case .memory: monitor.memorySubtitle
        case .gpu: monitor.gpuSubtitle
        case .network: monitor.networkSubtitle
        case .disk: monitor.diskSubtitle
        case .battery: monitor.batterySubtitle
        case .temperature: monitor.temperatureSubtitle
        case .overview: monitor.overviewSubtitle
        case .projects: monitor.projectsSubtitle
        case .bluetooth, .sound, .settings: nil
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
            if state.tab == .overview { OverviewLayoutToggle(layout: $state.overviewLayout) }
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
        let range = state.range(for: state.tab)
        switch state.tab {
        case .cpu: CPUWindowTab(monitor: monitor, range: range)
        case .memory: MemoryWindowTab(monitor: monitor, range: range)
        case .gpu: GPUWindowTab(monitor: monitor, range: range)
        case .network: NetworkWindowTab(monitor: monitor, range: range)
        case .disk: DiskWindowTab(monitor: monitor, range: range)
        case .battery: BatteryWindowTab(monitor: monitor, range: range)
        case .temperature: TemperatureWindowTab(monitor: monitor, range: range)
        case .overview: OverviewWindowTab(monitor: monitor)
        case .projects: ProjectsWindowTab(monitor: monitor)
        case .bluetooth, .sound, .settings: ComingSoon(title: state.tab.title)
        }
    }
}

private struct Sidebar: View {
    @Binding var selection: WindowTab
    let isShown: (WindowTab) -> Bool

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
                ForEach(group.tabs.filter(isShown)) { item($0) }
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
