import AppKit
import MoniMacCore
import SwiftUI

/// The popover's GPU tab. Renders `GPUPanel`; holds no logic.
struct GPUPopoverTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the popover so it survives switching tabs.
    @Binding var range: TimeRange

    var body: some View {
        // Built once per render: building it queries history.
        GPUPopoverContent(monitor: monitor, panel: monitor.gpuPanel(range: range), range: $range)
    }
}

/// The main window's GPU tab. Renders `GPUDetail`; holds no logic.
struct GPUWindowTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the window so it survives switching tabs.
    @Binding var range: TimeRange

    var body: some View {
        // Built once per render: building it queries history.
        GPUWindowContent(detail: monitor.gpuDetail(range: range), range: $range)
    }
}

extension Palette {
    /// The design's `gpu` token.
    static let gpu = gpuColor(light: 0xFF9F0A, dark: 0xFFB340)

    // Palette's own helper is private; this file keeps a copy rather than editing the shared palette.
    private static func gpuColor(light: UInt32, dark: UInt32) -> Color {
        func color(_ rgb: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                    blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? color(dark) : color(light)
        })
    }
}

// MARK: Popover

private struct GPUPopoverContent: View {
    let monitor: Monitor
    let panel: GPUPanel
    @Binding var range: TimeRange
    @Environment(\.requestQuit) private var requestQuit

    var body: some View {
        VStack(spacing: 12) {
            hero
            GPUBars(bars: panel.history, cornerRadius: 1.5, spacing: 2)
                .frame(height: 56)
                .padding([.top, .horizontal], 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
            if let unavailable = panel.unavailable {
                GPUNote(text: unavailable)
            } else {
                stages
                memory
            }
            topApps
        }
    }

    private var hero: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(panel.modelLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                Text(panel.utilization)
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
            SegmentedPicker(options: GPUPanel.ranges, selection: $range, label: \.shortLabel, horizontalPadding: 8)
                .fixedSize()
        }
    }

    private var stages: some View {
        HStack(spacing: 16) {
            legend("Renderer", panel.renderer, Palette.gpu)
            legend("Tiler", panel.tiler, Palette.gpu.opacity(0.45))
            Spacer()
        }
    }

    private func legend(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(Palette.textSecondary)
            Text(value).fontWeight(.semibold).foregroundStyle(Palette.textPrimary).monospacedDigit()
        }
        .font(.system(size: 12))
    }

    private var memory: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GPU Memory").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                    Text(panel.memoryDetail).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Text(panel.memory).font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
            }
            if let share = panel.memoryShare {
                UsageBar(share: share, color: Palette.gpu)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
    }

    private var topApps: some View {
        VStack(spacing: 2) {
            HStack {
                Text("Top Apps by GPU").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Button("Activity Monitor", action: monitor.openActivityMonitor)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.accent)
            }
            .padding(.bottom, 6)
            if let note = panel.topAppsNote {
                GPUNote(text: note)
            }
            ForEach(panel.topApps) { app in
                HStack(spacing: 4) {
                    GPUAppRow(app: app, valueWidth: 44).padding(.vertical, 6)
                    Button { requestQuit(app.id) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Palette.track))
                    }
                    .buttonStyle(.plain)
                    .help("Quit \(app.name)")
                    .opacity(app.canQuit ? 1 : 0)
                    .disabled(!app.canQuit)
                }
            }
        }
    }
}

// MARK: Window

private struct GPUWindowContent: View {
    let detail: GPUDetail
    @Binding var range: TimeRange

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let unavailable = detail.unavailable {
                GPUNote(text: unavailable)
            }
            HStack(spacing: 16) {
                GPUTile(tile: detail.utilization, symbol: "cpu")
                GPUTile(tile: detail.memory, symbol: "memorychip")
                GPUTile(tile: detail.average, symbol: "waveform.path.ecg")
                GPUTile(tile: detail.peak, symbol: "chart.line.uptrend.xyaxis")
            }
            history
            topApps
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Utilization History").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                    if let summary = detail.historySummary {
                        Text(summary).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                    }
                }
                Spacer()
                SegmentedPicker(options: GPUDetail.ranges, selection: $range, label: \.shortLabel, horizontalPadding: 10)
                    .fixedSize()
            }
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    VStack(alignment: .trailing) {
                        ForEach(Array(detail.yAxis.enumerated()), id: \.offset) { index, label in
                            if index > 0 { Spacer() }
                            Text(label)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 36, alignment: .trailing)
                    GPUBars(bars: detail.history, cornerRadius: 2, spacing: 2)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Palette.separator).frame(height: 1)
                        }
                }
                .frame(height: 170)
                HStack {
                    ForEach(Array(detail.xAxis.enumerated()), id: \.offset) { index, label in
                        if index > 0 { Spacer() }
                        Text(label)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Palette.textTertiary)
                .padding(.leading, 44)
            }
        }
    }

    private var topApps: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Top Apps by GPU").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                ShowAllButton(column: .gpu)
            }
            .padding(.bottom, 6)
            if let note = detail.topAppsNote {
                GPUNote(text: note).padding(.horizontal, 12)
            }
            // Two columns, filled down the left first, as in the design.
            let half = (detail.topApps.count + 1) / 2
            HStack(alignment: .top, spacing: 24) {
                column(detail.topApps.prefix(half))
                column(detail.topApps.dropFirst(half))
            }
        }
    }

    private func column(_ apps: ArraySlice<GPUDetail.AppRow>) -> some View {
        VStack(spacing: 0) {
            ForEach(apps) { app in
                GPUAppRow(app: app, valueWidth: 48)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// One of the window's summary tiles: label, value, sparkline, caption.
private struct GPUTile: View {
    let tile: GPUDetail.Tile
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Palette.gpu)
                Text(tile.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textSecondary)
            }
            Text(tile.value).font(.system(size: 28, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
            GPUBars(bars: tile.bars, cornerRadius: 1.5, spacing: 3).frame(height: 28)
            Text(tile.caption).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
    }
}

// MARK: Shared

/// Utilization columns, one per bar (0...1); nil bars are empty.
private struct GPUBars: View {
    let bars: [Double?]
    let cornerRadius: CGFloat
    let spacing: CGFloat

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if let bar, bar > 0 {
                            UnevenRoundedRectangle(topLeadingRadius: cornerRadius, topTrailingRadius: cornerRadius)
                                .fill(Palette.gpu)
                                // At least a sliver, so a busy-but-tiny value still reads as data.
                                .frame(height: max(geometry.size.height * min(bar, 1), 1))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// An app's icon, name, GPU share bar, and value.
private struct GPUAppRow: View {
    let app: GPUPanel.AppRow
    let valueWidth: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIcons.icon(for: app.bundlePath)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(app.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                UsageBar(share: app.share, color: Palette.gpu)
            }
            Text(app.value).font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
                .frame(minWidth: valueWidth, alignment: .trailing)
        }
    }
}

/// Why something has no figures, in place of them.
private struct GPUNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}
