import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The design's segmented control: a track with the selected segment raised.
struct SegmentedPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    var isEnabled: (Value) -> Bool = { _ in true }
    var horizontalPadding: CGFloat = 6

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.system(size: 11, weight: selected ? .semibold : .medium))
                        .foregroundStyle(isEnabled(option) ? Palette.textPrimary : Palette.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, horizontalPadding)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Palette.surfaceRaised)
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.track))
    }
}

/// A thin horizontal usage bar.
struct UsageBar: View {
    let share: Double
    let color: Color
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule().fill(color).frame(width: geometry.size.width * min(max(share, 0), 1))
            }
        }
        .frame(height: height)
    }
}

/// App icons for bundle paths, cached. Processes outside a bundle get the generic executable icon.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]
    private static let executable = NSWorkspace.shared.icon(for: .unixExecutable)

    static func icon(for bundlePath: String?) -> NSImage {
        guard let bundlePath else { return executable }
        if let cached = cache[bundlePath] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: bundlePath)
        cache[bundlePath] = icon
        return icon
    }
}
