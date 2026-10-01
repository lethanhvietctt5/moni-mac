import Foundation

// Battery: filled in by ticket 09. The scaffold keeps every hook in this file so tickets
// built in parallel don't edit shared code.

/// What SystemSampler reads for battery on each tick.
public struct BatteryReading: Equatable, Sendable {
    public init() {}
}

extension Snapshot {
    /// Values MetricsHistory records for battery.
    var batterySeries: [SeriesSample] { [] }
}

extension Monitor {
    /// The main window toolbar subtitle for the Battery tab, e.g. hardware details.
    public var batterySubtitle: String? { nil }
}

extension Monitor {
    /// Whether this Mac has a battery. Every battery surface is hidden when it doesn't.
    public var hasBattery: Bool { true }
}
