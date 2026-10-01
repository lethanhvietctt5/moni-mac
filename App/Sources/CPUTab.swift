import MoniMacCore
import SwiftUI

/// The popover's CPU tab. Renders `CPUPanel`; holds no logic.
struct CPUTab: View {
    let panel: CPUPanel
    @Binding var range: TimeRange
    let quitApp: (AppUsage.ID) -> Void
    let openActivityMonitor: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            hero
            HistoryGraph(bars: panel.history)
            split
            loadAverage
            perCore
            topApps
        }
    }

    private var hero: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(panel.chipLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                Text(panel.total)
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer()
            SegmentedPicker(options: CPUPanel.ranges, selection: $range, label: \.shortLabel, horizontalPadding: 8)
                .fixedSize()
        }
    }

    private var split: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    if let split = panel.split {
                        Rectangle().fill(Palette.cpu).frame(width: geometry.size.width * split.user)
                        Rectangle().fill(Palette.memory).frame(width: geometry.size.width * split.system)
                    }
                    Spacer(minLength: 0)
                }
                .background(Palette.track)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 6)
            HStack(spacing: 16) {
                legend("User", panel.user, Palette.cpu)
                legend("System", panel.system, Palette.memory)
                legend("Idle", panel.idle, Palette.track)
                Spacer()
            }
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

    private var loadAverage: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Load Average").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                Text("Runnable threads, averaged").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            HStack(spacing: 16) {
                ForEach(Array(zip(panel.loadAverages, ["1 min", "5 min", "15 min"])), id: \.1) { value, key in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(value).font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Palette.textPrimary)
                        Text(key).font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
    }

    private var perCore: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Per-Core").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Text(panel.coreSummary).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
            HStack(spacing: 6) {
                ForEach(panel.cores, id: \.label) { core in
                    VStack(spacing: 4) {
                        GeometryReader { geometry in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 3).fill(Palette.track)
                                Rectangle()
                                    .fill(core.kind == .performance ? Palette.cpu : Palette.network)
                                    .frame(height: geometry.size.height * min(max(core.usage, 0), 1))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                        .frame(height: 44)
                        Text(core.label).font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.textTertiary)
                    }
                }
            }
        }
    }

    private var topApps: some View {
        VStack(spacing: 2) {
            HStack {
                Text("Top Apps by CPU").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Button("Activity Monitor", action: openActivityMonitor)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.accent)
            }
            .padding(.bottom, 6)
            ForEach(panel.topApps) { app in
                AppRowView(app: app, quit: { quitApp(app.id) })
            }
        }
    }
}

private struct AppRowView: View {
    let app: CPUPanel.AppRow
    let quit: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 12) {
                Image(nsImage: AppIcons.icon(for: app.bundlePath))
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    UsageBar(share: app.share, color: Palette.cpu)
                }
                Text(app.value)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
                    .frame(minWidth: 36, alignment: .trailing)
            }
            .padding(.vertical, 6)
            Button(action: quit) {
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

/// 30 stacked columns: user time (blue) under system time (purple).
private struct HistoryGraph: View {
    let bars: [CPUPanel.StackedBar?]

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    VStack(spacing: 1) {
                        Spacer(minLength: 0)
                        if let bar, bar.user + bar.system > 0 {
                            UnevenRoundedRectangle(topLeadingRadius: 1.5, topTrailingRadius: 1.5)
                                .fill(Palette.memory)
                                .frame(height: geometry.size.height * bar.system)
                            Rectangle()
                                .fill(Palette.cpu)
                                .frame(height: geometry.size.height * bar.user)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(height: 56)
        .padding([.top, .horizontal], 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
    }
}

extension TimeRange {
    var shortLabel: String {
        switch self {
        case .oneMinute: "1m"
        case .fiveMinutes: "5m"
        case .oneHour: "1H"
        case .twelveHours: "12H"
        case .twentyFourHours: "24H"
        case .sevenDays: "7D"
        case .thirtyDays: "30D"
        }
    }
}
