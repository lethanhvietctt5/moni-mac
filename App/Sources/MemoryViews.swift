import AppKit
import MoniMacCore
import SwiftUI

/// The popover's Memory tab: a compact version of the window tab. Renders `MemoryDetail`; holds no logic.
struct MemoryPopoverTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the popover so it survives switching tabs.
    @Binding var range: TimeRange

    var body: some View {
        // Built once per render: building it queries history.
        MemoryPopoverContent(monitor: monitor, detail: monitor.memoryPanel(range: range), range: $range)
    }
}

/// The main window's Memory tab. Renders `MemoryDetail`; holds no logic.
struct MemoryWindowTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the window so it survives switching tabs.
    @Binding var range: TimeRange

    var body: some View {
        MemoryWindowContent(detail: monitor.memoryDetail(range: range), range: $range)
    }
}

// MARK: Popover

private struct MemoryPopoverContent: View {
    let monitor: Monitor
    let detail: MemoryDetail
    @Binding var range: TimeRange

    var body: some View {
        VStack(spacing: 12) {
            hero
            PressureChart(bars: detail.history, cornerRadius: 1.5, spacing: 2)
                .frame(height: 56)
                .padding([.top, .horizontal], 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
            breakdown
            stats
            topApps
        }
    }

    private var hero: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(detail.used)
                        .font(.system(size: 34, weight: .bold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                    Text("\(detail.usedUnit) of \(detail.total)").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            SegmentedPicker(options: detail.layout.ranges, selection: $range, label: \.shortLabel, horizontalPadding: 8)
                .fixedSize()
        }
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            BreakdownBar(segments: detail.breakdown, spacing: 1, cornerRadius: 3).frame(height: 6)
            HStack(alignment: .top, spacing: 6) {
                ForEach(detail.breakdown, id: \.label) { segment in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Circle().fill(segment.kind.color).frame(width: 7, height: 7)
                            Text(segment.label).font(.system(size: 10)).foregroundStyle(Palette.textSecondary)
                                .lineLimit(1).fixedSize()
                        }
                        Text(segment.value).font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Palette.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var stats: some View {
        HStack(alignment: .top) {
            stat(detail.pressure, level: detail.pressureLevel)
            Spacer()
            stat(detail.swap)
            Spacer()
            stat(detail.compression)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
    }

    private func stat(_ stat: MemoryDetail.Stat, level: MemoryPressureLevel? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                if let level { Circle().fill(level.color).frame(width: 7, height: 7) }
                Text(stat.label).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.textSecondary)
            }
            Text(stat.value).font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(Palette.textPrimary)
            Text(stat.detail).font(.system(size: 10)).foregroundStyle(Palette.textTertiary).lineLimit(1)
        }
    }

    private var topApps: some View {
        VStack(spacing: 2) {
            HStack {
                Text("Top Apps by Memory").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Button("Activity Monitor", action: monitor.openActivityMonitor)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.accent)
            }
            .padding(.bottom, 6)
            ForEach(detail.topApps) { app in
                HStack(spacing: 4) {
                    MemoryAppRow(app: app, valueWidth: 52).padding(.vertical, 6)
                    QuitButton(name: app.name, canQuit: app.canQuit) { monitor.quitApp(id: app.id) }
                }
            }
        }
    }
}

// MARK: Window

/// The tab's sections in default order; the user can rearrange them.
private enum MemorySection: String, WindowSection {
    case summary, breakdown, history, topApps

    var width: SectionWidth {
        self == .history || self == .topApps ? .half : .full
    }
}

private struct MemoryWindowContent: View {
    let detail: MemoryDetail
    @Binding var range: TimeRange

    var body: some View {
        ReorderableSections { (section: MemorySection) in
            switch section {
            case .summary: summary
            case .breakdown: breakdown
            case .history: history
            case .topApps: topApps
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(detail.used)
                        .font(.system(size: 40, weight: .bold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                    Text("\(detail.usedUnit) of \(detail.total) used")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textSecondary)
                }
                UsageBar(share: detail.usedShare, color: Palette.memory, height: 8)
            }
            .frame(width: 260, alignment: .leading)
            card(detail.pressure, level: detail.pressureLevel)
            card(detail.swap)
            card(detail.compression)
        }
    }

    private func card(_ stat: MemoryDetail.Stat, level: MemoryPressureLevel? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let level { Circle().fill(level.color).frame(width: 8, height: 8) }
                Text(stat.label).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.textSecondary)
            }
            Text(stat.value).font(.system(size: 20, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
            Text(stat.detail).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(.leading, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle().fill(Palette.separator).frame(width: 1)
        }
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            BreakdownBar(segments: detail.breakdown, spacing: 2, cornerRadius: 5).frame(height: 14)
            HStack(alignment: .top, spacing: 16) {
                ForEach(detail.breakdown, id: \.label) { segment in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 3).fill(segment.kind.color).frame(width: 10, height: 10)
                            Text(segment.label).font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Text(segment.value).font(.system(size: 15, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Palette.textPrimary)
                        Text(segment.detail).font(.system(size: 10)).foregroundStyle(Palette.textTertiary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Memory Pressure").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                SegmentedPicker(options: detail.layout.ranges, selection: $range, label: \.shortLabel,
                                horizontalPadding: 10)
                    .fixedSize()
            }
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    VStack(alignment: .trailing) {
                        ForEach(Array(MemoryDetail.yAxis.enumerated()), id: \.offset) { index, label in
                            if index > 0 { Spacer() }
                            Text(label)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 36, alignment: .trailing)
                    PressureChart(bars: detail.history, cornerRadius: 2, spacing: 2)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Palette.separator).frame(height: 1)
                        }
                }
                .frame(height: 270)
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
        .frame(maxWidth: .infinity)
    }

    private var topApps: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Top Apps by Memory").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                // Opens the Overview list sorted by memory once it exists (ticket 12).
                Text("Show All").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
                    .help("Coming soon")
            }
            .padding(.bottom, 6)
            ForEach(detail.topApps) { app in
                MemoryAppRow(app: app, valueWidth: 56)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: Shared pieces

/// Icon, name, memory bar, and value.
private struct MemoryAppRow: View {
    let app: MemoryDetail.AppRow
    let valueWidth: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIcons.icon(for: app.bundlePath)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(app.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                UsageBar(share: app.share, color: Palette.memory)
            }
            Text(app.value).font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
                .frame(minWidth: valueWidth, alignment: .trailing)
        }
    }
}

private struct QuitButton: View {
    let name: String
    let canQuit: Bool
    let quit: () -> Void

    var body: some View {
        Button(action: quit) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Palette.track))
        }
        .buttonStyle(.plain)
        .help("Quit \(name)")
        .opacity(canQuit ? 1 : 0)
        .disabled(!canQuit)
    }
}

/// App Memory, Wired, Compressed, Cached Files, and Free side by side, each as wide as its share.
private struct BreakdownBar: View {
    let segments: [MemoryDetail.Segment]
    let spacing: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width - spacing * CGFloat(max(segments.count - 1, 0)), 0)
            HStack(spacing: spacing) {
                ForEach(segments, id: \.label) { segment in
                    Rectangle().fill(segment.kind.color).frame(width: width * segment.share)
                }
                Spacer(minLength: 0)
            }
            .background(Palette.track)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

/// One column per bar, as tall as the pressure and colored by the pressure level; nil bars are empty.
private struct PressureChart: View {
    let bars: [MemoryDetail.PressureBar?]
    let cornerRadius: CGFloat
    let spacing: CGFloat

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if let bar, bar.value > 0 {
                            UnevenRoundedRectangle(topLeadingRadius: cornerRadius, topTrailingRadius: cornerRadius)
                                .fill(bar.level.color)
                                .frame(height: geometry.size.height * bar.value)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private extension MemoryDetail.SegmentKind {
    /// The design's shades of the memory color.
    var color: Color {
        switch self {
        case .app: Palette.memory
        case .wired: Palette.memory.opacity(0.65)
        case .compressed: Palette.memory.opacity(0.35)
        case .cached: Palette.textTertiary.opacity(0.6)
        case .free: Palette.track
        }
    }
}

private extension MemoryPressureLevel {
    /// The chart's Low, Med, and High.
    var color: Color {
        switch self {
        case .normal: Palette.success
        case .warning: MemoryColors.warning
        case .critical: MemoryColors.danger
        }
    }
}

/// The design's warning and danger tokens, which `Palette` doesn't have yet.
private enum MemoryColors {
    static let warning = color(light: 0xFF9F0A, dark: 0xFFB340)
    static let danger = color(light: 0xFF3B30, dark: 0xFF453A)

    private static func color(light: UInt32, dark: UInt32) -> Color {
        func nsColor(_ rgb: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                    blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            nsColor(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }
}
