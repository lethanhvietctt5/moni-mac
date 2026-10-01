import AppKit
import MoniMacCore
import SwiftUI

/// The main window's Temperature & Fans tab. Renders `TemperatureDetail`; holds no logic.
/// Read-only: fans are shown, never controlled.
struct TemperatureWindowTab: View {
    let monitor: Monitor
    /// The tab's chart range, kept by the window so it survives switching tabs.
    @Binding var range: TimeRange

    var body: some View {
        // Built once per render: building it queries history.
        TemperatureWindowContent(detail: monitor.temperatureDetail(range: range), range: $range)
    }
}

/// The tab's sections in default order; the user can rearrange them.
private enum TemperatureSection: String, WindowSection {
    case readouts, historyAndFans, sensors

    var width: SectionWidth {
        .full
    }
}

private struct TemperatureWindowContent: View {
    let detail: TemperatureDetail
    @Binding var range: TimeRange

    var body: some View {
        ReorderableSections { (section: TemperatureSection) in
            switch section {
            case .readouts: readouts
            // Fans may be absent, so the chart and the fans card move together.
            case .historyAndFans:
                HStack(alignment: .top, spacing: 20) {
                    history
                    if let fans = detail.fans {
                        FansCard(fans: fans)
                    }
                }
                .frame(height: 415)
            case .sensors: sensors
            }
        }
    }

    private var readouts: some View {
        HStack(spacing: 0) {
            ForEach(Array(detail.cards.enumerated()), id: \.offset) { index, card in
                ReadoutCard(card: card)
                    .overlay(alignment: .trailing) {
                        if index < detail.cards.count - 1 {
                            Rectangle().fill(Palette.separator).frame(width: 1)
                        }
                    }
            }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface))
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CPU Temperature").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                    Text(detail.chartSummary ?? "No history yet").font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                SegmentedPicker(options: TemperatureDetail.ranges, selection: $range, label: \.shortLabel,
                                horizontalPadding: 10)
                    .fixedSize()
            }
            TemperatureBars(bars: detail.history)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Palette.separator).frame(height: 1)
                }
            HStack {
                ForEach(Array(detail.xAxis.enumerated()), id: \.offset) { index, label in
                    if index > 0 { Spacer() }
                    Text(label)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(Palette.textTertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.separator, lineWidth: 1))
    }

    private var sensors: some View {
        let columns = 3
        let perColumn = max(1, (detail.sensors.count + columns - 1) / columns)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 20) {
                ForEach(0..<columns, id: \.self) { column in
                    VStack(spacing: 0) {
                        ForEach(Array(detail.sensors.dropFirst(column * perColumn).prefix(perColumn).enumerated()),
                                id: \.offset) { _, row in
                            HStack {
                                Text(row.name).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                                Spacer()
                                Text(row.value).font(.system(size: 12, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Palette.textPrimary)
                            }
                            .padding(.vertical, 7)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Palette.separator).frame(height: 1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            if let unnamed = detail.unnamedSensors {
                Text(unnamed).font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

/// One of the CPU, GPU, SSD, and Battery readouts: value, gauge, and today's peak.
private struct ReadoutCard: View {
    let card: TemperatureDetail.Card

    /// Matches the sidebar's symbols for these parts.
    private var symbol: String {
        switch card.kind {
        case .cpu: "cpu"
        case .gpu: "rectangle.3.group"
        case .ssd: "internaldrive"
        case .battery: "battery.75percent"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(TemperaturePalette.temp)
                Text(card.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(card.value).font(.system(size: 30, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.textPrimary)
                Text(card.unit).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.textSecondary)
            }
            HeatGauge(position: card.gauge)
            Text(card.caption).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A cool-to-hot gradient with a marker at the current temperature.
    private struct HeatGauge: View {
        let position: Double?

        var body: some View {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(stops: [
                            .init(color: Palette.network, location: 0),
                            .init(color: TemperaturePalette.yellow, location: 0.55),
                            .init(color: TemperaturePalette.temp, location: 1),
                        ], startPoint: .leading, endPoint: .trailing))
                        .frame(height: 6)
                        .opacity(position == nil ? 0.35 : 1)
                    if let position {
                        RoundedRectangle(cornerRadius: 2).fill(Palette.textPrimary)
                            .frame(width: 4, height: 14)
                            .offset(x: (geometry.size.width - 4) * position)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 14)
        }
    }
}

/// CPU temperature columns, colored by how hot each was; nil bars are empty.
private struct TemperatureBars: View {
    let bars: [TemperatureDetail.Bar?]

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if let bar {
                            UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                                .fill(Self.color(bar.level))
                                .frame(height: max(geometry.size.height * bar.height, 2))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private static func color(_ level: TemperatureDetail.Level) -> Color {
        switch level {
        case .cool: Palette.network
        case .warm: TemperaturePalette.warning
        case .hot: TemperaturePalette.temp
        }
    }
}

/// The read-only Fans card: each fan's speed, share of its maximum, and range. No controls.
private struct FansCard: View {
    let fans: TemperatureDetail.Fans

    private var rows: [TemperatureDetail.FanRow] {
        if case .speeds(let rows) = fans { rows } else { [] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Fans").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Text("Managed by macOS").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.textSecondary)
            }
            if case .unreadable(let reason) = fans {
                Text(reason).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(rows) { fan in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "fan")
                            .font(.system(size: 18))
                            .foregroundStyle(Palette.network)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Palette.surfaceRaised))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fan.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(fan.rpm).font(.system(size: 22, weight: .bold).monospacedDigit())
                                    .foregroundStyle(Palette.textPrimary)
                                Text("RPM").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.textSecondary)
                            }
                        }
                        Spacer()
                        Text(fan.percent).font(.system(size: 12, weight: .bold).monospacedDigit())
                            .foregroundStyle(Palette.network)
                    }
                    UsageBar(share: fan.share, color: Palette.network)
                    HStack {
                        Text(fan.minimum)
                        Spacer()
                        Text(fan.maximum)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                }
                .padding(.top, 14)
                .overlay(alignment: .top) {
                    Rectangle().fill(Palette.separator).frame(height: 1)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                Text("Read-only. MoniMac shows fan speeds but doesn't control them.")
                    .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.track))
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 330)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface))
    }
}

/// Design tokens `Palette` doesn't have yet, resolved for light and dark appearance.
enum TemperaturePalette {
    static let temp = color(light: 0xFF453A, dark: 0xFF6961)
    static let warning = color(light: 0xFF9F0A, dark: 0xFFB340)
    /// The gauge gradient's middle stop.
    static let yellow = color(light: 0xFFD60A, dark: 0xFFD60A)

    private static func color(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                           blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        })
    }
}
