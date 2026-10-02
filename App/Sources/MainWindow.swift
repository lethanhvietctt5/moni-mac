import AppKit
import MoniMacCore
import Observation
import SwiftUI

extension WindowTab {
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

    /// `sortedBy` opens Overview › List with every app, sorted by that column (as "Show All" does).
    func show(tab: WindowTab? = nil, layout: OverviewLayout? = nil, sortedBy column: OverviewListColumn? = nil,
              expanding expanded: Set<AppUsage.ID> = []) {
        if let tab { state.tab = tab }
        if let layout { state.overviewLayout = layout }
        if let column { state.showList(sortedBy: column) }
        state.listQuery.expanded.formUnion(expanded)
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Whether `tab` is on screen: the window is open on it and not minimized or fully covered.
    func isShowing(_ tab: WindowTab) -> Bool {
        guard let window, state.tab == tab else { return false }
        return window.occlusionState.contains(.visible)
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
            Sidebar(selection: $state.tab, monitor: monitor)
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
                            .environment(\.sectionArranger, SectionArranger(monitor: monitor, tab: state.tab))
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
        case .bluetooth: monitor.bluetoothSubtitle
        case .temperature: monitor.temperatureSubtitle
        case .overview: monitor.overviewSubtitle
        case .projects: monitor.projectsSubtitle
        case .settings: SettingsWindowTab.subtitle
        case .sound: nil
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
            Button {
                ShareCardWindowController.shared.show(monitor: monitor)
            } label: {
                Image(systemName: "square.and.arrow.up").font(.system(size: 14))
                    .frame(width: 30, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textSecondary)
            .help("Share your week")
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
        case .bluetooth: BluetoothWindowTab(monitor: monitor)
        case .temperature: TemperatureWindowTab(monitor: monitor, range: range)
        case .overview: OverviewWindowTab(monitor: monitor)
        case .projects: ProjectsWindowTab(monitor: monitor)
        case .settings: SettingsWindowTab(monitor: monitor)
        case .sound: ComingSoon(title: state.tab.title)
        }
    }
}

/// Tabs can be dragged to reorder them within their group; the order persists.
private struct Sidebar: View {
    @Binding var selection: WindowTab
    let monitor: Monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Room for the window's traffic lights.
            Spacer().frame(height: 36)
            ForEach(monitor.sidebarGroups, id: \.title) { group in
                Text(group.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                ForEach(group.tabs) { tab in
                    item(tab)
                        .draggable(ReorderPayload.tab.payload(tab.rawValue))
                        .reorderDropTarget(.tab, cornerRadius: 6) { dropped in
                            WindowTab(rawValue: dropped).map { monitor.moveTab($0, onto: tab) }
                        }
                }
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
