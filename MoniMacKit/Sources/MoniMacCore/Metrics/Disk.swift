import Foundation

// Disk: filled in by ticket 08. The scaffold keeps every hook in this file so tickets
// built in parallel don't edit shared code.

/// What SystemSampler reads for disk on each tick.
public struct DiskReading: Equatable, Sendable {
    public init() {}
}

extension Snapshot {
    /// Values MetricsHistory records for disk.
    var diskSeries: [(SeriesKey, Double)] { [] }
}
