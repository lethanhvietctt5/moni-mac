import AppKit
import MoniMacCore
import SwiftUI

/// The main window's Overview tab in the Tiles view. Renders `OverviewTiles`; holds no logic.
struct OverviewWindowTab: View {
    let monitor: Monitor

    var body: some View {
        // Built once per render: building it queries history.
        OverviewWindowContent(tiles: monitor.overviewTiles())
    }
}

/// The popover's Overview tab. Renders `OverviewPanel`; holds no logic.
struct OverviewPopoverTab: View {
    let monitor: Monitor
    let openWindow: () -> Void

    var body: some View {
        // Built once per render: building it queries history.
        OverviewPopoverContent(panel: monitor.overviewPanel(), openWindow: openWindow)
    }
}

/// The toolbar's Tiles / List switch.
struct OverviewLayoutToggle: View {
    @Binding var layout: OverviewLayout

    var body: some View {
        HStack(spacing: 10) {
            button("square.grid.2x2", help: "Tiles", for: .tiles)
            button("list.bullet", help: "List", for: .list)
        }
    }

    private func button(_ symbol: String, help: String, for option: OverviewLayout) -> some View {
        Button { layout = option } label: {
            Image(systemName: symbol).font(.system(size: 14))
                .frame(width: 30, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(layout == option ? Palette.track : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.textSecondary)
        .help(help)
    }
}

// MARK: Colors and symbols

extension OverviewMetric {
    var color: Color {
        switch self {
        case .cpu: Palette.cpu
        case .memory: Palette.memory
        case .gpu: Palette.gpu
        case .network: Palette.network
        case .disk: Palette.disk
        case .battery: Palette.success
        case .temperature: TemperaturePalette.temp
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .gpu: "rectangle.3.group"
        case .network: "arrow.up.arrow.down"
        case .disk: "internaldrive"
        case .battery: "battery.75percent"
        case .temperature: "thermometer.medium"
        }
    }
}

extension AppKind {
    /// The Processes tile's stacked bar.
    var color: Color {
        switch self {
        case .app: Palette.accent
        case .agent: Palette.textTertiary
        case .system: Palette.separator
        }
    }
}

// MARK: Window

/// The tab's sections in default order; the user can rearrange them.
private enum OverviewSection: String, WindowSection {
    case tiles, busiest

    var width: SectionWidth {
        .full
    }
}

private struct OverviewWindowContent: View {
    let tiles: OverviewTiles
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 4)

    var body: some View {
        ReorderableSections { (section: OverviewSection) in
            switch section {
            case .tiles:
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(tiles.metricTiles) { MetricTile(tile: $0) }
                    ProcessesTile(processes: tiles.processes)
                }
            case .busiest: busiest
            }
        }
    }

    private var busiest: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Busiest Right Now").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                ShowAllButton(title: tiles.showAll, column: .cpu)
            }
            HStack(alignment: .top, spacing: 24) {
                ForEach(Array(tiles.busiestColumns.enumerated()), id: \.offset) { _, apps in column(apps) }
            }
        }
    }

    private func column(_ apps: [OverviewBusyApp]) -> some View {
        VStack(spacing: 0) {
            ForEach(apps) { app in
                BusyAppRow(app: app, iconSize: 28, showsProcesses: false)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// The design's Metric Tile: icon and title, big value, sparkline, caption.
private struct MetricTile: View {
    let tile: OverviewTiles.Tile

    var body: some View {
        TileFrame(symbol: tile.metric.symbol, color: tile.metric.color, title: tile.metric.title, value: tile.value,
                  caption: tile.caption) {
            TileSparkline(bars: tile.bars, color: tile.metric.color)
        }
    }
}

private struct ProcessesTile: View {
    let processes: OverviewTiles.Processes

    var body: some View {
        TileFrame(symbol: "square.stack.3d.up", color: Palette.textSecondary, title: "Processes",
                  value: processes.value, caption: processes.caption) {
            VStack(spacing: 6) {
                GeometryReader { geometry in
                    let gaps = CGFloat(max(processes.groups.count - 1, 0)) * 2
                    HStack(spacing: 2) {
                        ForEach(processes.groups) { group in
                            // Wide enough to see even when another kind dwarfs it.
                            Rectangle().fill(group.kind.color)
                                .frame(width: group.share > 0 ? max(max(geometry.size.width - gaps, 0) * group.share, 3) : 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(processes.groups.isEmpty ? Palette.track : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .frame(height: 8)
                HStack {
                    ForEach(Array(processes.groups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 { Spacer(minLength: 4) }
                        Text(group.label)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .frame(height: 12)
            }
            .padding(.top, 2)
        }
    }
}

private struct TileFrame<Graphic: View>: View {
    let symbol: String
    let color: Color
    let title: String
    let value: String
    let caption: String
    @ViewBuilder let graphic: () -> Graphic

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(color).frame(width: 14)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textSecondary)
            }
            Text(value)
                .font(.system(size: 28, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            graphic().frame(height: 28)
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(caption)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.separator))
    }
}

/// Columns rising from the bottom; slots without data show a faint baseline.
private struct TileSparkline: View {
    let bars: [Double?]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    if let bar {
                        RoundedRectangle(cornerRadius: 1.5).fill(color)
                            .frame(height: max(geometry.size.height * min(max(bar, 0), 1), 2))
                    } else {
                        Rectangle().fill(Palette.track).frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: geometry.size.height, alignment: .bottom)
        }
    }
}

/// An app in Busiest Right Now: icon, name (and process count), a bar in its dominant resource's color, value.
private struct BusyAppRow: View {
    let app: OverviewBusyApp
    let iconSize: CGFloat
    let showsProcesses: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIcons.icon(for: app.bundlePath)).resizable().frame(width: iconSize, height: iconSize)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(app.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textPrimary)
                    if showsProcesses {
                        Text(app.processes).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                    }
                }
                .lineLimit(1)
                UsageBar(share: app.share, color: app.resource.metric.color)
            }
            Text(app.value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 56, alignment: .trailing)
        }
        .help(app.help)
    }
}

// MARK: Popover

private struct OverviewPopoverContent: View {
    let panel: OverviewPanel
    let openWindow: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                ForEach(panel.rows) { MetricRow(row: $0).frame(height: 36) }
            }
            Rectangle().fill(Palette.separator).frame(height: 1)
            VStack(spacing: 2) {
                HStack {
                    Text("Busiest Right Now").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Button("Open MoniMac", action: openWindow)
                        .accessibilityIdentifier("overview.openWindow")
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }
                .padding(.bottom, 2)
                ForEach(panel.busiest) { app in
                    BusyAppRow(app: app, iconSize: 28, showsProcesses: true).frame(height: 40)
                }
            }
        }
    }
}

private struct MetricRow: View {
    let row: OverviewPanel.Row

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.metric.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(row.metric.color))
            VStack(alignment: .leading, spacing: 5) {
                Text(row.metric.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.textPrimary)
                UsageBar(share: row.share ?? 0, color: row.metric.color)
            }
            .frame(width: 140)
            Text(row.value)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
