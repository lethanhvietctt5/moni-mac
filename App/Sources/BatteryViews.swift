import AppKit
import MoniMacCore
import SwiftUI

// Battery (ticket 09). Both tabs render `BatteryDetail`; they hold no logic.

/// The popover's Battery tab: a compact version of the window tab.
struct BatteryPopoverTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the popover so it survives switching tabs.
    @Binding var range: TimeRange

    var body: some View {
        // Built once per render: building it queries history.
        BatteryPopoverContent(
            monitor: monitor, detail: monitor.batteryDetail(range: range, layout: .popover), range: $range
        )
    }
}

/// The main window's Battery tab.
struct BatteryWindowTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the window so it survives switching tabs.
    @Binding var range: TimeRange

    var body: some View {
        // Built once per render: building it queries history.
        BatteryWindowContent(detail: monitor.batteryDetail(range: range, layout: .window), range: $range)
    }
}

// MARK: Popover

private struct BatteryPopoverContent: View {
    let monitor: Monitor
    let detail: BatteryDetail
    @Binding var range: TimeRange

    var body: some View {
        VStack(spacing: 12) {
            hero
            history
            stats
            energy
        }
    }

    private var hero: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.source)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                HStack(alignment: .center, spacing: 10) {
                    Text(detail.charge)
                        .font(.system(size: 34, weight: .bold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                    BatteryGlyph(level: detail.level, isCharging: detail.isCharging, width: 44, height: 20)
                }
                Text(detail.status).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            RangePicker(detail: detail, range: $range, horizontalPadding: 8)
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 6) {
            ChargeBars(bars: detail.history, cornerRadius: 1.5, spacing: 2)
                .frame(height: 56)
                .padding([.top, .horizontal], 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
            HStack {
                Text(detail.historyCaption).lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                ChargeLegend()
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.textSecondary)
        }
    }

    private var stats: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach([0, 2], id: \.self) { row in
                GridRow {
                    ForEach(detail.stats[row..<row + 2], id: \.label) { stat in
                        VStack(alignment: .leading, spacing: 2) {
                            StatHead(stat: stat, size: 11)
                            Text(stat.value).font(.system(size: 14, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Palette.textPrimary)
                            Text(stat.caption).font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .help(stat.help ?? "")
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.surface))
    }

    private var energy: some View {
        VStack(spacing: 2) {
            EnergyHeader(size: 13)
                .padding(.bottom, 6)
            if detail.energyApps.isEmpty {
                NoEnergyApps()
            }
            ForEach(detail.energyApps) { app in
                HStack(spacing: 4) {
                    EnergyRow(app: app).padding(.vertical, 6)
                    QuitButton(app: app) { monitor.quitApp(id: app.id) }
                }
            }
        }
    }
}

private struct QuitButton: View {
    let app: BatteryDetail.EnergyApp
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
        .help("Quit \(app.name)")
        .opacity(app.canQuit ? 1 : 0)
        .disabled(!app.canQuit)
    }
}

// MARK: Window

private struct BatteryWindowContent: View {
    let detail: BatteryDetail
    @Binding var range: TimeRange

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            hero
            HStack(alignment: .top, spacing: 24) {
                history
                energy.frame(width: 360)
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 14) {
                BatteryGlyph(level: detail.level, isCharging: detail.isCharging, width: 200, height: 90)
                HStack(alignment: .bottom, spacing: 10) {
                    Text(detail.charge)
                        .font(.system(size: 44, weight: .bold).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail.source).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                        Text(detail.status).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.bottom, 8)
                }
                .fixedSize()
            }
            .frame(minWidth: 235, alignment: .leading)
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach([0, 2], id: \.self) { row in
                    GridRow {
                        ForEach(Array(detail.stats[row..<row + 2].enumerated()), id: \.element.label) { column, stat in
                            statCell(stat)
                                .overlay(alignment: .trailing) {
                                    if column == 0 { Rectangle().fill(Palette.separator).frame(width: 1) }
                                }
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if row == 0 { Rectangle().fill(Palette.separator).frame(height: 1) }
                    }
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 20)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.separator).frame(height: 1)
        }
    }

    private func statCell(_ stat: BatteryDetail.Stat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            StatHead(stat: stat, size: 12)
            Text(stat.value).font(.system(size: 24, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
            Text(stat.caption).font(.system(size: 11)).foregroundStyle(Palette.textSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .help(stat.help ?? "")
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Charge Level").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                    Text(detail.historyCaption).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                RangePicker(detail: detail, range: $range, horizontalPadding: 10)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .trailing) {
                    ForEach(Array(detail.yAxis.enumerated()), id: \.offset) { index, label in
                        if index > 0 { Spacer() }
                        Text(label)
                    }
                }
                .frame(width: 27, height: 312, alignment: .trailing)
                VStack(spacing: 6) {
                    ChargeBars(bars: detail.history, cornerRadius: 3, spacing: 4)
                        .frame(height: 312)
                    HStack {
                        ForEach(Array(detail.xAxis.enumerated()), id: \.offset) { index, label in
                            if index > 0 { Spacer() }
                            Text(label)
                        }
                    }
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(Palette.textTertiary)
            ChargeLegend().font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
    }

    private var energy: some View {
        VStack(alignment: .leading, spacing: 2) {
            EnergyHeader(size: 13)
            if detail.energyApps.isEmpty {
                NoEnergyApps()
            }
            ForEach(detail.energyApps) { app in
                EnergyRow(app: app).frame(height: 44)
            }
        }
    }
}

// MARK: Shared pieces

private enum BatteryColors {
    static let level = Palette.success
    static let onBattery = Palette.success.opacity(0.4)
    static let power = Color(nsColor: .systemOrange)
    static let temperature = Color(nsColor: .systemRed)

    static func icon(for stat: BatteryDetail.Stat) -> (symbol: String, color: Color) {
        switch stat.kind {
        case .power: ("bolt.fill", power)
        case .health: ("heart.fill", level)
        case .cycles: ("repeat", Palette.cpu)
        case .temperature: ("thermometer.medium", temperature)
        }
    }
}

private struct StatHead: View {
    let stat: BatteryDetail.Stat
    let size: CGFloat

    var body: some View {
        let icon = BatteryColors.icon(for: stat)
        HStack(spacing: 6) {
            Image(systemName: icon.symbol).font(.system(size: size)).foregroundStyle(icon.color)
            Text(stat.label).font(.system(size: size, weight: .semibold)).foregroundStyle(Palette.textSecondary)
        }
    }
}

/// The range control, showing the range the detail resolved to.
private struct RangePicker: View {
    let detail: BatteryDetail
    @Binding var range: TimeRange
    let horizontalPadding: CGFloat

    var body: some View {
        SegmentedPicker(options: detail.ranges, selection: Binding { detail.range } set: { range = $0 },
                        label: \.shortLabel, horizontalPadding: horizontalPadding)
            .fixedSize()
    }
}

/// A battery outline filled to the charge level, with a bolt while charging.
private struct BatteryGlyph: View {
    let level: Double?
    let isCharging: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let stroke = max(height / 30, 1.5)
        let inset = height * 7 / 90
        HStack(spacing: stroke + 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.2).strokeBorder(Palette.textTertiary, lineWidth: stroke)
                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: height * 0.12)
                        .fill(LinearGradient(colors: [BatteryColors.level, BatteryColors.level.opacity(0.75)],
                                             startPoint: .bottom, endPoint: .top))
                        .frame(width: geometry.size.width * min(max(level ?? 0, 0), 1))
                }
                .padding(inset)
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: height * 0.33, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.15), radius: 1)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: width, height: height)
            UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3)
                .fill(Palette.textTertiary)
                .frame(width: max(height / 15, 3), height: height / 3)
        }
        .accessibilityElement()
        .accessibilityLabel(isCharging ? "Battery, charging" : "Battery")
    }
}

/// Charge level columns: solid while on power, faded on battery.
private struct ChargeBars: View {
    let bars: [BatteryHistory.Bar?]
    let cornerRadius: CGFloat
    let spacing: CGFloat

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if let bar {
                            UnevenRoundedRectangle(topLeadingRadius: cornerRadius, topTrailingRadius: cornerRadius)
                                .fill(bar.isPluggedIn ? BatteryColors.level : BatteryColors.onBattery)
                                .frame(height: geometry.size.height * min(max(bar.charge, 0), 1))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct ChargeLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            item("On power", BatteryColors.level)
            item("On battery", BatteryColors.onBattery)
        }
    }

    private func item(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}

private struct EnergyHeader: View {
    let size: CGFloat

    var body: some View {
        HStack {
            Text("Using Significant Energy").font(.system(size: size, weight: .bold)).foregroundStyle(Palette.textPrimary)
            Spacer()
            Text("Watts (est.)").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.textSecondary)
                .help(BatteryDetail.appEstimateHelp)
        }
        .frame(height: 22)
    }
}

private struct NoEnergyApps: View {
    var body: some View {
        Text("No apps are using significant energy.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

private struct EnergyRow: View {
    let app: BatteryDetail.EnergyApp

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIcons.icon(for: app.bundlePath)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(app.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                UsageBar(share: app.share, color: BatteryColors.level)
            }
            Text(app.value).font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
                .frame(minWidth: 48, alignment: .trailing)
                .help(BatteryDetail.appEstimateHelp)
        }
    }
}
