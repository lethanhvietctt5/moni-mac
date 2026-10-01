import Foundation

/// Disk sizes and rates in decimal units (1 GB = 10⁹ bytes), as Finder and drive makers count.
public enum DiskFormat {
    private static let units = ["KB", "MB", "GB", "TB", "PB"]

    /// A number and its unit: one decimal below 10 unless it's whole, whole numbers above,
    /// e.g. ("9.8", "GB"), ("2", "GB"), ("312", "GB").
    public static func parts(_ bytes: Double) -> (number: String, unit: String) {
        var value = max(bytes, 0) / 1000
        var index = 0
        // Pick the unit after rounding, so 999.7 MB reads "1.0 GB", not "1000 MB".
        while index < units.count - 1, rounded(value) >= 1000 {
            value /= 1000
            index += 1
        }
        return (number(value), units[index])
    }

    /// e.g. "312 GB", "9.8 GB", "640 KB".
    public static func bytes(_ bytes: Double) -> String {
        let (number, unit) = parts(bytes)
        return "\(number) \(unit)"
    }

    public static func bytes(_ bytes: UInt64) -> String {
        self.bytes(Double(bytes))
    }

    /// e.g. "48 MB/s", "1.9 GB/s".
    public static func rate(_ bytesPerSecond: Double) -> String {
        bytes(bytesPerSecond) + "/s"
    }

    /// A drive's marketed size in whole units, e.g. "1 TB", "512 GB".
    public static func driveSize(_ bytes: UInt64) -> String {
        var value = Double(bytes) / 1000
        var index = 0
        while index < units.count - 1, value.rounded() >= 1000 {
            value /= 1000
            index += 1
        }
        return "\(Int(value.rounded())) \(units[index])"
    }

    private static func rounded(_ value: Double) -> Double {
        value < 10 ? (value * 10).rounded() / 10 : value.rounded()
    }

    private static func number(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        return value < 9.95 && tenths % 10 != 0 ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }
}
