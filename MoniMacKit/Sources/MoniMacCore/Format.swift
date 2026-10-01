import Foundation

/// How CPU percentages are expressed. One setting, applied on every surface.
public enum CPUMode: String, CaseIterable, Sendable {
    /// Share of the whole CPU: 0–100%.
    case system
    /// Share of one core: up to 100% × core count (e.g. 1200% on 12 cores).
    case perCore
}

/// Compact display strings shared by every surface.
public enum Format {
    /// Shown wherever a value is unavailable.
    public static let placeholder = "—"

    /// A 0...1 fraction as a whole percentage, e.g. `0.317` → `"32%"`.
    public static func percent(_ fraction: Double) -> String {
        let clamped = min(max(fraction, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// CPU use given as a share of the whole CPU (0...1), in the user's CPU mode.
    /// `decimals` adds precision for small per-app values, e.g. `"12.4%"`.
    public static func cpu(_ shareOfWholeCPU: Double, mode: CPUMode, logicalCores: Int, decimals: Int = 0) -> String {
        let share = max(shareOfWholeCPU, 0)
        let percent = switch mode {
        case .system: min(share, 1) * 100
        case .perCore: share * Double(logicalCores) * 100
        }
        return decimals == 0 ? "\(Int(percent.rounded()))%" : String(format: "%.\(decimals)f%%", percent)
    }

    /// Whole numbers with a thousands separator, e.g. `"4,212"`.
    public static func count(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
    }

    /// Clock time for chart labels: `"14:12"` within a day, `"Tue 14:12"` within a week, else `"24 Sep"`.
    public static func time(_ date: Date, within range: TimeRange, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = switch range {
        case .sevenDays: "EEE HH:mm"
        case .thirtyDays: "d MMM"
        default: "HH:mm"
        }
        return formatter.string(from: date)
    }

    /// e.g. `"3d 4h"`, `"4h 12m"`, `"12m"`.
    public static func uptime(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(seconds, 0)) / 60
        let (days, hours, mins) = (minutes / 1440, minutes / 60 % 24, minutes % 60)
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    /// Load average with two decimals, e.g. `"2.84"`.
    public static func load(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
