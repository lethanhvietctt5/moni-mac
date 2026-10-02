import AppKit
import MoniMacCore
import SwiftUI

// Bluetooth (ticket 15). The window tab renders `BluetoothDetail`; it holds no logic.

/// The main window's Bluetooth tab.
struct BluetoothWindowTab: View {
    let monitor: Monitor

    var body: some View {
        BluetoothWindowContent(detail: monitor.bluetoothDetail, monitor: monitor)
    }
}

/// The tab's sections in default order; the user can rearrange them.
private enum BluetoothSection: String, WindowSection {
    case featured, devices, notifications

    var width: SectionWidth { .full }
}

private struct BluetoothWindowContent: View {
    let detail: BluetoothDetail
    let monitor: Monitor

    var body: some View {
        ReorderableSections { (section: BluetoothSection) in
            switch section {
            case .featured:
                if let featured = detail.featured { FeaturedCard(featured: featured) }
            case .devices: devices
            case .notifications: notifications
            }
        }
    }

    private var devices: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(detail.devicesTitle)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.textPrimary)
                Spacer()
                Button("Open Bluetooth Settings…", action: monitor.openBluetoothSettings)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.accent)
            }
            .padding(.bottom, 6)
            if let message = detail.message {
                Text(message)
                    .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            if !detail.rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(detail.rows.enumerated()), id: \.element.id) { index, row in
                        DeviceRow(row: row)
                            .overlay(alignment: .bottom) {
                                if index < detail.rows.count - 1 {
                                    Rectangle().fill(Palette.separator).frame(height: 1)
                                }
                            }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.separator, lineWidth: 1))
            }
        }
    }

    private var notifications: some View {
        HStack(spacing: 14) {
            Image(systemName: "bell").font(.system(size: 15)).foregroundStyle(Palette.accent).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(BluetoothDetail.lowBatteryTitle)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                Text(BluetoothDetail.lowBatteryDescription)
                    .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { detail.lowBatteryAlerts }, set: monitor.setBluetoothLowBatteryAlerts))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .tint(Palette.success)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
    }
}

// MARK: Featured card

private struct FeaturedCard: View {
    let featured: BluetoothDetail.Featured

    var body: some View {
        HStack(spacing: 28) {
            Image(systemName: featured.kind.symbol)
                .font(.system(size: 40))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 96, height: 96)
                .background(RoundedRectangle(cornerRadius: 24).fill(Palette.surfaceRaised))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.separator, lineWidth: 1))
            VStack(alignment: .leading, spacing: 6) {
                Text(featured.name)
                    .font(.system(size: 20, weight: .bold)).tracking(-0.3)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(featured.isConnected ? Palette.success : Palette.textTertiary).frame(width: 7, height: 7)
                    Text(featured.status).foregroundStyle(Palette.textSecondary)
                    if let source = featured.source {
                        Text("·").foregroundStyle(Palette.textSecondary)
                        FactText(fact: source, known: Palette.textSecondary)
                    }
                }
                .font(.system(size: 12))
                HStack(spacing: 4) {
                    ForEach(Array(featured.facts.enumerated()), id: \.element.id) { index, fact in
                        if index > 0 { Text("·") }
                        FactText(fact: fact, known: Palette.textTertiary)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 22) {
                ForEach(featured.rings) { ring in
                    VStack(spacing: 8) {
                        BatteryRing(ring: ring)
                        Text(ring.label).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.surface))
    }
}

/// A fact the Mac can't provide reads in italics, with why in its tooltip.
private struct FactText: View {
    let fact: BluetoothDetail.Fact
    let known: Color

    var body: some View {
        Text(fact.text)
            .italic(!fact.isKnown)
            .foregroundStyle(fact.isKnown ? known : Palette.textTertiary)
            .lineLimit(1)
            .help(fact.help ?? "")
    }
}

private struct BatteryRing: View {
    let ring: BluetoothDetail.Ring

    var body: some View {
        ZStack {
            Circle().stroke(Palette.track, lineWidth: 6)
            Circle()
                .trim(from: 0, to: min(max(ring.level ?? 0, 0), 1))
                .stroke(BluetoothColors.color(ring.tone), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(ring.text).font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(3)
        .frame(width: 76, height: 76)
        .accessibilityElement()
        .accessibilityLabel("\(ring.label) battery \(ring.text)")
    }
}

// MARK: Other Devices

private struct DeviceRow: View {
    let row: BluetoothDetail.Row

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: row.kind.symbol)
                .font(.system(size: 16))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9).fill(Palette.track))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(row.status).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let hint = row.hint {
                Text(hint)
                    .font(.system(size: 11, weight: row.isHintLow ? .semibold : .regular))
                    .foregroundStyle(row.isHintLow ? BluetoothColors.danger : Palette.textSecondary)
                    .lineLimit(1)
            }
            BatteryBar(level: row.level, color: BluetoothColors.color(row.tone))
            Text(row.levelText)
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 40, alignment: .trailing)
        }
        .help(row.levelHelp ?? "")
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        // A disconnected device is dimmed, as the design draws it.
        .opacity(row.isConnected ? 1 : 0.6)
    }
}

/// A small battery outline filled to the level.
private struct BatteryBar: View {
    let level: Double?
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Palette.textTertiary, lineWidth: 1.5)
                .frame(width: 30, height: 14)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: 26 * min(max(level ?? 0, 0), 1), height: 10)
                        .padding(.leading, 2)
                }
            RoundedRectangle(cornerRadius: 1).fill(Palette.textTertiary).frame(width: 2, height: 5)
        }
    }
}

// MARK: Shared pieces

private extension BluetoothDeviceKind {
    var symbol: String {
        switch self {
        case .earbuds: "airpodspro"
        case .headphones: "headphones"
        case .keyboard: "keyboard"
        case .mouse: "computermouse"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .gameController: "gamecontroller"
        case .speaker: "hifispeaker"
        case .phone: "iphone"
        case .other: "dot.radiowaves.left.and.right"
        }
    }
}

/// The design's battery, warning, and danger tokens, which `Palette` doesn't have.
private enum BluetoothColors {
    static let warning = color(light: 0xFF9F0A, dark: 0xFFB340)
    static let danger = color(light: 0xFF3B30, dark: 0xFF453A)

    static func color(_ tone: BluetoothDetail.Tone) -> Color {
        switch tone {
        case .normal: Palette.success
        case .warning: warning
        case .low: danger
        case .inactive: Palette.textTertiary
        }
    }

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
