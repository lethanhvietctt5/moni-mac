import AppKit
import MoniMacCore

/// Template images for menu bar items. Template images adapt to light, dark, and highlighted menu bars.
@MainActor
enum MenuBarGraphics {
    private static let height: CGFloat = 16
    private static let iconSize: CGFloat = 16
    private static let barWidth: CGFloat = 2
    private static let barGap: CGFloat = 1
    private static let iconGap: CGFloat = 4

    static func icon(for metric: Metric) -> NSImage? {
        NSImage(systemSymbolName: metric.symbolName, accessibilityDescription: metric.title)
    }

    static func sparkline(_ bars: [Double?]) -> NSImage {
        let width = sparklineWidth(bars.count)
        return template(width: width) { drawBars(bars, originX: 0) }
    }

    static func iconAndSparkline(for metric: Metric, bars: [Double?]) -> NSImage {
        let width = iconSize + iconGap + sparklineWidth(bars.count)
        return template(width: width) {
            if let icon = icon(for: metric) {
                let size = icon.size
                let scale = min(iconSize / size.width, iconSize / size.height)
                let drawn = NSSize(width: size.width * scale, height: size.height * scale)
                icon.draw(in: NSRect(x: (iconSize - drawn.width) / 2, y: (height - drawn.height) / 2,
                                     width: drawn.width, height: drawn.height))
            }
            drawBars(bars, originX: iconSize + iconGap)
        }
    }

    private static func sparklineWidth(_ count: Int) -> CGFloat {
        CGFloat(count) * barWidth + CGFloat(max(count - 1, 0)) * barGap
    }

    private static func drawBars(_ bars: [Double?], originX: CGFloat) {
        let maxHeight = height - 2
        for (index, bar) in bars.enumerated() {
            let x = originX + CGFloat(index) * (barWidth + barGap)
            // Empty slots draw a faint baseline so the graph's extent stays visible.
            guard let bar else {
                NSColor.black.withAlphaComponent(0.25).setFill()
                NSRect(x: x, y: 1, width: barWidth, height: 1).fill()
                continue
            }
            NSColor.black.setFill()
            let barHeight = max(1, (CGFloat(min(max(bar, 0), 1)) * maxHeight).rounded())
            NSRect(x: x, y: 1, width: barWidth, height: barHeight).fill()
        }
    }

    private static func template(width: CGFloat, draw: @escaping () -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            draw()
            return true
        }
        image.isTemplate = true
        return image
    }
}

extension Metric {
    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network"
        case .gpu: "GPU"
        case .temperature: "Temperature"
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .network: "arrow.up.arrow.down"
        case .gpu: "rectangle.3.group"
        case .temperature: "thermometer.medium"
        }
    }
}
