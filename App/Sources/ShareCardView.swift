import AppKit
import MoniMacCore
import SwiftUI

/// The share card's fixed colors. The card is rendered off screen, where the app's dynamic `Palette`
/// colors would follow the system appearance instead of the chosen variant, so each variant spells them out.
struct ShareCardTheme {
    let background, textPrimary, textSecondary, textTertiary, tile, stroke, accent: Color
    let cpu, memory, gpu, network, battery: Color
    let colorScheme: ColorScheme

    static let light = ShareCardTheme(
        background: Color(rgb: 0xFFFFFF), textPrimary: Color(rgb: 0x1D1D1F), textSecondary: Color(rgb: 0x6E6E73),
        textTertiary: Color(rgb: 0xAEAEB2), tile: Color(rgb: 0xF7F7F9), stroke: Color(rgb: 0xE5E5EA),
        accent: Color(rgb: 0x0A84FF), cpu: Color(rgb: 0x0A84FF), memory: Color(rgb: 0xAF52DE),
        gpu: Color(rgb: 0xFF9F0A), network: Color(rgb: 0x30B0C7), battery: Color(rgb: 0x34C759), colorScheme: .light
    )

    static let dark = ShareCardTheme(
        background: Color(rgb: 0x1E1E20), textPrimary: Color(rgb: 0xF5F5F7), textSecondary: Color(rgb: 0xA1A1A6),
        textTertiary: Color(rgb: 0x6C6C70), tile: Color(rgb: 0x2C2C2E), stroke: Color(rgb: 0x3A3A3C),
        accent: Color(rgb: 0x0A84FF), cpu: Color(rgb: 0x409CFF), memory: Color(rgb: 0xBF5AF2),
        gpu: Color(rgb: 0xFFB340), network: Color(rgb: 0x40C8E0), battery: Color(rgb: 0x30D158), colorScheme: .dark
    )

    func color(_ kind: WeeklySummary.TileKind) -> Color {
        switch kind {
        case .cpu: cpu
        case .memory: memory
        case .gpu: gpu
        case .network: network
        case .battery: battery
        }
    }
}

/// The 1200×630 share card, laid out as the design's "Share Card — Light/Dark" frames.
struct ShareCardView: View {
    static let size = CGSize(width: 1200, height: 630)

    let summary: WeeklySummary
    let theme: ShareCardTheme
    /// The busiest app's icon, when it could be found.
    let busiestIcon: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            top
            Spacer().frame(height: 52)
            headline
            Spacer(minLength: 24)
            HStack(spacing: 16) {
                ForEach(summary.tiles) { ShareCardTile(tile: $0, theme: theme) }
            }
            Spacer().frame(height: 52)
            footer
        }
        .padding(56)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(theme.background)
        .environment(\.colorScheme, theme.colorScheme)
    }

    private var top: some View {
        HStack {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: [Color(rgb: 0x3A3A3C), Color(rgb: 0x111113)], startPoint: .top,
                                         endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.stroke, lineWidth: 1))
                    .overlay(Image(systemName: "waveform.path.ecg").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(rgb: 0x30D158)))
                    .frame(width: 36, height: 36)
                Text("MoniMac").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.textPrimary)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "laptopcomputer").font(.system(size: 13))
                Text(summary.device).font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(theme.textSecondary)
        }
        .frame(height: 36)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.period).font(.system(size: 13, weight: .semibold)).kerning(0.4)
                .foregroundStyle(theme.accent)
            Text(summary.headline).font(.system(size: 56, weight: .bold)).foregroundStyle(theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(summary.summary).font(.system(size: 18)).foregroundStyle(theme.textSecondary)
                .lineSpacing(4).lineLimit(2)
                .frame(width: 640, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let line = summary.busiestLine {
                Group {
                    if let busiestIcon {
                        Image(nsImage: busiestIcon).resizable().interpolation(.high)
                    } else {
                        RoundedRectangle(cornerRadius: 5).fill(theme.accent)
                            .overlay(Image(systemName: "app.fill").font(.system(size: 10)).foregroundStyle(.white))
                    }
                }
                .frame(width: 20, height: 20)
                Text(line).font(.system(size: 14)).foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Text(WeeklySummary.projectURL).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
        }
        .frame(height: 20)
    }
}

/// One stat tile: icon and label, the big value, a 7-day sparkline, and a caption.
private struct ShareCardTile: View {
    let tile: WeeklySummary.Tile
    let theme: ShareCardTheme

    private var symbol: String {
        switch tile.kind {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .gpu: "rectangle.3.group"
        case .network: "arrow.up.arrow.down"
        case .battery: "battery.100percent"
        }
    }

    var body: some View {
        let color = theme.color(tile.kind)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(color).frame(width: 14, height: 14)
                Text(tile.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.textSecondary)
            }
            Text(tile.value).font(.system(size: 28, weight: .bold)).foregroundStyle(theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(tile.bars.enumerated()), id: \.offset) { _, bar in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color.opacity(bar == nil ? 0.2 : 1))
                        .frame(maxWidth: .infinity)
                        .frame(height: max((bar ?? 0) * 28, 2))
                }
            }
            .frame(height: 28, alignment: .bottom)
            Text(tile.caption).font(.system(size: 11)).foregroundStyle(theme.textSecondary).lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 152)
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.tile))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.stroke, lineWidth: 1))
    }
}

/// Renders the card to an image at exactly 1200×630 pixels.
@MainActor
enum ShareCardRenderer {
    static func image(_ summary: WeeklySummary, dark: Bool, busiestIcon: NSImage?) -> CGImage? {
        let view = ShareCardView(summary: summary, theme: dark ? .dark : .light, busiestIcon: busiestIcon)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(ShareCardView.size)
        return renderer.cgImage
    }

    static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// The busiest app's icon: from the running apps MoniMac grouped, else any running app by that name.
    static func icon(forApp name: String?, in apps: [AppUsage]) -> NSImage? {
        guard let name else { return nil }
        if let path = apps.first(where: { $0.name == name })?.bundlePath { return AppIcons.icon(for: path) }
        return NSWorkspace.shared.runningApplications.first { $0.localizedName == name }?.icon
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(.sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}
