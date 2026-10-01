import MoniMacCore
import MoniMacSystem
import SwiftUI

/// The popover's Network tab. Renders `NetworkPanel`; holds no logic.
struct NetworkPopoverTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the popover so it survives switching tabs.
    @Binding var range: TimeRange

    var body: some View {
        // Built once per render: building it queries history.
        NetworkPopoverContent(monitor: monitor, panel: monitor.networkPanel(range: range), range: $range)
            .onAppear(perform: NetworkNamePermission.requestIfNeeded)
    }
}

/// The main window's Network tab. Renders `NetworkDetail`; holds no logic.
struct NetworkWindowTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the window so it survives switching tabs. The Network tab's
    /// charts have fixed spans (60 seconds, 7 and 30 days), so it's unused.
    @Binding var range: TimeRange

    var body: some View {
        NetworkWindowContent(detail: monitor.networkDetail())
            .onAppear(perform: NetworkNamePermission.requestIfNeeded)
    }
}

// MARK: Popover

private struct NetworkPopoverContent: View {
    let monitor: Monitor
    let panel: NetworkPanel
    @Binding var range: TimeRange

    var body: some View {
        VStack(spacing: 12) {
            hero
            ThroughputBars(bars: panel.history, cornerRadius: 1.5, spacing: 2)
                .frame(height: 56)
                .padding([.top, .horizontal], 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
            session
            lastWeek
            topApps
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(panel.summary.interfaceLine)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            HStack(alignment: .bottom, spacing: 14) {
                rate("arrow.down", panel.summary.download, opacity: 1)
                rate("arrow.up", panel.summary.upload, opacity: 0.55)
                Spacer(minLength: 8)
                SegmentedPicker(options: NetworkPanel.ranges, selection: $range, label: \.shortLabel, horizontalPadding: 8)
                    .fixedSize()
            }
        }
    }

    private func rate(_ symbol: String, _ rate: NetworkFormat.Rate, opacity: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.network.opacity(opacity))
            Text(rate.value)
                .font(.system(size: 26, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
            Text(rate.unit)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var session: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("This Session").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                Text(panel.summary.sessionStart).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            HStack(spacing: 16) {
                total(panel.summary.downloaded, "Downloaded")
                total(panel.summary.uploaded, "Uploaded")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
    }

    private func total(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(Palette.textPrimary)
            Text(label).font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
        }
    }

    private var lastWeek: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Last 7 Days").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(panel.lastWeek.totals).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.textSecondary)
            }
            ThroughputBars(bars: panel.lastWeek.bars, cornerRadius: 2, spacing: 6)
                .frame(height: 40)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.separator).frame(height: 1) }
            AxisLabels(labels: panel.lastWeek.xAxis, spacing: 6)
        }
    }

    private var topApps: some View {
        VStack(spacing: 2) {
            HStack {
                Text("Top Apps by Network").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Button("Activity Monitor", action: monitor.openActivityMonitor)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.accent)
            }
            .padding(.bottom, 6)
            if panel.topApps.isEmpty {
                NoNetworkApps()
            }
            ForEach(panel.topApps) { app in
                HStack(spacing: 4) {
                    NetworkAppRowView(app: app).padding(.vertical, 6)
                    Button { monitor.quitApp(id: app.id) } label: {
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

/// The tab's sections in default order; the user can rearrange them.
private enum NetworkSection: String, WindowSection {
    case summary, live, lastWeek, lastMonth, topApps

    var width: SectionWidth {
        self == .lastWeek || self == .lastMonth ? .half : .full
    }
}

private struct NetworkWindowContent: View {
    let detail: NetworkDetail

    var body: some View {
        ReorderableSections { (section: NetworkSection) in
            switch section {
            case .summary: summary
            case .live: live
            case .lastWeek: DailyChartView(title: "Last 7 Days", chart: detail.lastWeek, spacing: 10)
            case .lastMonth: DailyChartView(title: "Last 30 Days", chart: detail.lastMonth, spacing: 3)
            case .topApps: topApps
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 24) {
            rate("arrow.down", "Download", detail.summary.download, opacity: 1)
            rate("arrow.up", "Upload", detail.summary.upload, opacity: 0.55)
            total("Downloaded", detail.summary.downloaded, caption: "This session · \(detail.summary.sessionStart)",
                  opacity: 1)
            total("Uploaded", detail.summary.uploaded, caption: "This session", opacity: 0.45)
        }
    }

    private func rate(_ symbol: String, _ label: String, _ rate: NetworkFormat.Rate, opacity: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.network.opacity(opacity))
                Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.textSecondary)
            }
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(rate.value)
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
                Text(rate.unit).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func total(_ label: String, _ value: String, caption: String, opacity: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(Palette.network.opacity(opacity)).frame(width: 8, height: 8)
                Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.textSecondary)
            }
            Text(value).font(.system(size: 20, weight: .semibold).monospacedDigit()).foregroundStyle(Palette.textPrimary)
            Text(caption).font(.system(size: 11)).foregroundStyle(Palette.textTertiary).lineLimit(1)
        }
        .padding(.leading, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle().fill(Palette.separator).frame(width: 1)
        }
    }

    private var live: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Live Throughput").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Text("Last 60 seconds").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
            ThroughputBars(bars: detail.live, cornerRadius: 1.5, spacing: 2)
                .frame(height: 56)
        }
    }

    private var topApps: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Top Apps by Network").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                // Opens the Overview list sorted by network once it exists (ticket 12).
                Text("Show All").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
                    .help("Coming soon")
            }
            .padding(.bottom, 4)
            if detail.topApps.isEmpty {
                NoNetworkApps()
            }
            let half = (detail.topApps.count + 1) / 2
            HStack(alignment: .top, spacing: 24) {
                column(detail.topApps.prefix(half))
                column(detail.topApps.dropFirst(half))
            }
        }
    }

    private func column(_ apps: ArraySlice<NetworkAppRow>) -> some View {
        VStack(spacing: 0) {
            ForEach(apps) { app in
                NetworkAppRowView(app: app).padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: Shared pieces

/// Download (solid) under upload (lighter), one column per bar; nil bars are empty.
private struct ThroughputBars: View {
    let bars: [ThroughputBar?]
    let cornerRadius: CGFloat
    let spacing: CGFloat

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    VStack(spacing: 1) {
                        Spacer(minLength: 0)
                        if let bar, bar.down + bar.up > 0 {
                            if bar.up > 0 {
                                Rectangle()
                                    .fill(Palette.network.opacity(0.45))
                                    .frame(height: max(geometry.size.height * min(bar.up, 1), 1))
                            }
                            Rectangle()
                                .fill(Palette.network)
                                .frame(height: geometry.size.height * min(bar.down, 1))
                        }
                    }
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: cornerRadius, topTrailingRadius: cornerRadius))
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// One label per bar, centered under it; nil labels leave a gap.
private struct AxisLabels: View {
    let labels: [String?]
    let spacing: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let count = CGFloat(max(labels.count, 1))
            let slot = (geometry.size.width - spacing * (count - 1)) / count
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                if let label, index == labels.count - 1 {
                    // "Today" ends at the chart's edge rather than overhanging it.
                    Text(label).fixedSize()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .trailing)
                } else if let label {
                    Text(label)
                        .fixedSize()
                        .position(x: CGFloat(index) * (slot + spacing) + slot / 2, y: geometry.size.height / 2)
                }
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(Palette.textTertiary)
        .frame(height: 12)
    }
}

/// "Last 7 Days" / "Last 30 Days": per-day download and upload with totals.
private struct DailyChartView: View {
    let title: String
    let chart: DailyUsageChart
    let spacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(chart.totals).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.textSecondary)
            }
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    VStack(alignment: .trailing) {
                        ForEach(Array(chart.yAxis.enumerated()), id: \.offset) { index, label in
                            if index > 0 { Spacer() }
                            Text(label)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(width: 44, alignment: .trailing)
                    ThroughputBars(bars: chart.bars, cornerRadius: 2, spacing: spacing)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Palette.separator).frame(height: 1)
                        }
                }
                .frame(height: 160)
                AxisLabels(labels: chart.xAxis, spacing: spacing)
                    .padding(.leading, 52)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct NetworkAppRowView: View {
    let app: NetworkAppRow

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIcons.icon(for: app.bundlePath))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                UsageBar(share: app.share, color: Palette.network)
            }
            Text(app.value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
                .frame(minWidth: 64, alignment: .trailing)
        }
    }
}

private struct NoNetworkApps: View {
    var body: some View {
        Text("No apps are using the network right now.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 40)
    }
}
