import Foundation

extension TemperatureUnit {
    /// A Celsius temperature in this unit, unrounded.
    public func converted(_ celsius: Double) -> Double {
        self == .celsius ? celsius : celsius * 9 / 5 + 32
    }

    /// With one decimal, e.g. "31.4 °C" or "88.5 °F"; for readings that change slowly, like the battery.
    public func precise(_ celsius: Double) -> String {
        String(format: "%.1f %@", converted(celsius), symbol)
    }
}
