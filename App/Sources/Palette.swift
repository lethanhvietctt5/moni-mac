import AppKit
import SwiftUI

/// The design file's color tokens, resolved for light and dark appearance.
enum Palette {
    static let windowBackground = color(light: 0xFFFFFF, dark: 0x1E1E20)
    static let sidebarBackground = color(light: 0xF2F1F6, dark: 0x262628)
    static let surface = color(light: 0xF7F7F9, dark: 0x2C2C2E)
    static let surfaceRaised = color(light: 0xFFFFFF, dark: 0x323234)
    static let separator = color(light: 0xE5E5EA, dark: 0x3A3A3C)
    static let textPrimary = color(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let textSecondary = color(light: 0x6E6E73, dark: 0xA1A1A6)
    static let textTertiary = color(light: 0xAEAEB2, dark: 0x6C6C70)
    static let accent = color(light: 0x0A84FF, dark: 0x0A84FF)
    static let track = color(light: 0xE9E9EE, dark: 0x3A3A3C)
    static let cpu = color(light: 0x0A84FF, dark: 0x409CFF)
    static let memory = color(light: 0xAF52DE, dark: 0xBF5AF2)
    static let network = color(light: 0x30B0C7, dark: 0x40C8E0)
    static let success = color(light: 0x34C759, dark: 0x30D158)

    private static func color(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
