import AppKit
import MoniMacCore
import SwiftUI

extension Palette {
    /// The design's `disk` token.
    static let disk = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x7D / 255, green: 0x7A / 255, blue: 0xFF / 255, alpha: 1)
            : NSColor(srgbRed: 0x5E / 255, green: 0x5C / 255, blue: 0xE6 / 255, alpha: 1)
    })
    /// Writes are drawn lighter than reads.
    static let diskWrite = disk.opacity(0.45)
}

extension StorageBreakdown.Category {
    /// Fill for the category's bar segment and legend swatch, as in the design.
    var color: Color {
        switch self {
        case .applications: Palette.disk
        case .developer: Palette.disk.opacity(0.7)
        case .documents: Palette.disk.opacity(0.42)
        case .macOS: Palette.textTertiary.opacity(0.9)
        case .purgeable: Palette.textTertiary.opacity(0.45)
        case .free: Palette.track
        }
    }
}

/// Columns of reads under writes; nil bars are empty.
struct DiskBars: View {
    let bars: [DiskDetail.Bar?]
    let cornerRadius: CGFloat
    let spacing: CGFloat

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    VStack(spacing: 1) {
                        Spacer(minLength: 0)
                        if let bar, bar.read + bar.write > 0 {
                            UnevenRoundedRectangle(topLeadingRadius: cornerRadius, topTrailingRadius: cornerRadius)
                                .fill(Palette.diskWrite)
                                .frame(height: geometry.size.height * min(bar.write, 1))
                            Rectangle()
                                .fill(Palette.disk)
                                .frame(height: geometry.size.height * min(bar.read, 1))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// The storage breakdown as one segmented bar; Free fills the rest.
struct StorageBar: View {
    let storage: StorageBreakdown?
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                if let storage {
                    let used = storage.segments.filter { $0.category != .free && $0.bytes > 0 }
                    // Leave room for the gaps so the segments keep their proportions.
                    let width = max(geometry.size.width - 2 * CGFloat(used.count), 0)
                    ForEach(used, id: \.category) { segment in
                        Rectangle().fill(segment.category.color).frame(width: width * segment.share)
                    }
                }
                Rectangle().fill(StorageBreakdown.Category.free.color)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// A row in "Disk Writes Today".
struct DiskWriterRow: View {
    let app: DiskDetail.AppRow

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: AppIcons.icon(for: app.bundlePath)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(app.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                UsageBar(share: app.share, color: Palette.disk)
            }
            Text(app.value).font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
                .frame(minWidth: 56, alignment: .trailing)
        }
    }
}

/// Shown in place of the writers list before any app has written today.
struct NoWritesYet: View {
    var body: some View {
        Text("No app has written to disk today yet.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

extension View {
    /// A tooltip, when there is one.
    @ViewBuilder
    func help(ifPresent text: String?) -> some View {
        if let text { help(text) } else { self }
    }
}
