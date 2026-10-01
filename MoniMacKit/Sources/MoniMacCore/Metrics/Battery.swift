import Foundation

// Battery: filled in by ticket 09. The scaffold keeps every hook in this file so tickets
// built in parallel don't edit shared code.

/// What SystemSampler reads for battery on each tick.
public struct BatteryReading: Equatable, Sendable {
    public init() {}
}

extension Snapshot {
    /// Values MetricsHistory records for battery.
    var batterySeries: [(SeriesKey, Double)] { [] }
}
