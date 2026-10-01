import Foundation

/// Display strings for network figures. Units are decimal (1 MB = 1,000,000 bytes), as macOS uses.
public enum NetworkFormat {
    /// A rate split into number and unit, e.g. ("4.2", "MB/s").
    public struct Rate: Equatable, Sendable {
        public var value: String
        public var unit: String

        public var text: String { "\(value) \(unit)" }
    }

    /// e.g. `0.4 KB/s`, `380 KB/s`, `2.4 MB/s`; in bits, `19 Mbps`. At most three digits, so the
    /// menu bar item has a fixed widest text.
    public static func rate(_ bytesPerSecond: Double, units: NetworkUnits) -> Rate {
        switch units {
        case .bytes: scaled(max(bytesPerSecond, 0) / 1000, units: ["KB/s", "MB/s", "GB/s"], decimalsBelow: 10)
        case .bits: scaled(max(bytesPerSecond, 0) * 8 / 1000, units: ["kbps", "Mbps", "Gbps"], decimalsBelow: 10)
        }
    }

    /// An amount of data, e.g. `612 MB`, `3.8 GB`, `85.5 GB`, `20 GB`.
    public static func bytes(_ bytes: Double) -> String {
        trimmed(scaled(max(bytes, 0) / 1000, units: ["KB", "MB", "GB", "TB"], decimalsBelow: 100))
    }

    /// A link rate in bits per second, e.g. `1.2 Gb/s`, `866 Mb/s`, `1 Gb/s`.
    public static func linkRate(_ bitsPerSecond: Double) -> String {
        trimmed(scaled(max(bitsPerSecond, 0) / 1_000_000, units: ["Mb/s", "Gb/s"], decimalsBelow: 10))
    }

    /// Drops a trailing ".0": `20 GB`, not `20.0 GB`. Rates keep it, so the menu bar holds its shape.
    private static func trimmed(_ amount: Rate) -> String {
        var amount = amount
        if amount.value.hasSuffix(".0") { amount.value.removeLast(2) }
        return amount.text
    }

    /// e.g. "Wi-Fi 6E · Studio-5G · 1.2 Gb/s link". The network name is left out when it's unknown.
    public static func interfaceLine(_ reading: Reading<NetworkReading>) -> String {
        switch reading {
        case .unavailable(.warmingUp): Format.placeholder
        case .unavailable: "Network unavailable"
        case .value(let network):
            network.interface.map { interface in
                ([interface.name, interface.networkName] + [interface.linkRate.map { "\(linkRate($0)) link" }])
                    .compactMap { $0 }
                    .joined(separator: " · ")
            } ?? "Not connected"
        }
    }

    /// Steps up through `units` (each 1000× the previous) until the value is under 1000.
    /// One decimal below `decimalsBelow`, a whole number otherwise. Zero is plain "0".
    private static func scaled(_ value: Double, units: [String], decimalsBelow: Double) -> Rate {
        var value = value
        var index = 0
        while value.rounded() >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        if value == 0 { return Rate(value: "0", unit: units[index]) }
        let oneDecimal = (value * 10).rounded() / 10 < decimalsBelow
        let text = oneDecimal ? String(format: "%.1f", value) : String(Int(value.rounded()))
        return Rate(value: text, unit: units[index])
    }
}
