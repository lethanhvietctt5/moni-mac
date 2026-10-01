import MoniMacCore
import SwiftUI

/// The main window's CPU tab. Renders `CPUDetail`; holds no logic.
struct CPUWindowTab: View {
    let monitor: Monitor
    @State private var range: TimeRange = .twentyFourHours

    static func subtitle(_ monitor: Monitor) -> String? {
        monitor.latest.map { CPUDetail.subtitle(for: $0.system) }
    }

    var body: some View {
        // Built once per render: building it queries history.
        CPUWindowContent(detail: monitor.cpuDetail(range: range), range: $range)
    }
}

private struct CPUWindowContent: View {
    let detail: CPUDetail
    @Binding var range: TimeRange

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            summary
            history
            HStack(alignment: .top, spacing: 32) {
                perCore
                topApps
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(detail.total)
                        .font(.system(size: 40, weight: .bold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                    Text("in use").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textSecondary)
                }
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        if let split = detail.split {
                            Rectangle().fill(Palette.cpu).frame(width: geometry.size.width * split.user)
                            Rectangle().fill(Palette.cpu.opacity(0.45)).frame(width: geometry.size.width * split.system)
                        }
                        Spacer(minLength: 0)
                    }
                    .background(Palette.track)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .frame(width: 240, height: 8)
            }
            .frame(width: 240, alignment: .leading)
            ForEach(detail.stats, id: \.label) { stat in
                VStack(alignment: .leading, spacing: 4) {
                    Text(stat.label).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.textSecondary)
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
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("History").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                    if let peak = detail.peak {
                        Text(peak).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                    }
                }
                Spacer()
                SegmentedPicker(options: CPUDetail.ranges, selection: $range, label: \.shortLabel, horizontalPadding: 10)
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
                    StackedBars(bars: detail.history, systemColor: Palette.cpu.opacity(0.45), cornerRadius: 2, spacing: 2)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Palette.separator).frame(height: 1)
                        }
                }
                .frame(height: 140)
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

    private var perCore: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Per-Core Load") {
                Text(detail.coreSummary).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.textSecondary)
            }
            HStack(spacing: 6) {
                ForEach(detail.cores, id: \.label) { core in
                    VStack(spacing: 6) {
                        GeometryReader { geometry in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 4).fill(Palette.track)
                                Rectangle().fill(Palette.cpu)
                                    .frame(height: geometry.size.height * min(max(core.usage, 0), 1))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .frame(height: 150)
                        Text(core.value).font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Palette.textPrimary)
                        Text(core.label).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.textTertiary)
                    }
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var topApps: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("Top Apps by CPU") {
                // Opens the Overview list sorted by CPU once it exists (ticket 12).
                Text("Show All").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
                    .help("Coming soon")
            }
            ForEach(detail.topApps) { app in
                HStack(spacing: 12) {
                    Image(nsImage: AppIcons.icon(for: app.bundlePath)).resizable().frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(app.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        UsageBar(share: app.share, color: Palette.cpu)
                    }
                    Text(app.value).font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                        .frame(minWidth: 48, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
            Spacer()
            trailing()
        }
        .padding(.bottom, 6)
    }
}
