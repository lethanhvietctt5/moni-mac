import AppKit
import MoniMacCore
import SwiftUI

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

    /// The warning badge, e.g. "⚠ CPU 98%": dark text and a warning sign on amber, as the design draws it.
    /// Not a template: it keeps its colors on any menu bar. Sized for `widestText` so it never changes width.
    static func warningBadge(_ text: String, widestText: String) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let ink = NSColor(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255, alpha: 1)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
        let symbolSize: CGFloat = 12
        let (padding, gap): (CGFloat, CGFloat) = (6, 5)
        let textWidth = ceil((widestText as NSString).size(withAttributes: attributes).width)
        let width = padding + symbolSize + gap + textWidth + padding
        let symbol = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [ink])))
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor(red: 1, green: 0xB3 / 255, blue: 0x40 / 255, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            if let symbol {
                let size = symbol.size
                symbol.draw(in: NSRect(x: padding + (symbolSize - size.width) / 2, y: (height - size.height) / 2,
                                       width: size.width, height: size.height))
            }
            let textSize = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: NSPoint(x: padding + symbolSize + gap, y: (height - textSize.height) / 2),
                                    withAttributes: attributes)
            return true
        }
        image.isTemplate = false
        return image
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

    /// The metric's accent, as on the Overview tiles.
    var color: Color {
        switch self {
        case .cpu: Palette.cpu
        case .memory: Palette.memory
        case .network: Palette.network
        case .gpu: Palette.gpu
        case .temperature: TemperaturePalette.temp
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
