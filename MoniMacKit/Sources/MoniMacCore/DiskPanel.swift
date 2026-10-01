import Foundation

/// Everything the popover's Disk tab shows: a compact version of `DiskDetail`.
public struct DiskPanel: Equatable, Sendable {
    /// The ranges the popover chart offers.
    public static let ranges = CPUPanel.ranges
    public static let historyBarCount = 30
    public static let topAppCount = 4

    /// e.g. "Macintosh HD · APFS · 1 TB SSD".
    public var volumeLine: String
    /// e.g. "312 GB".
    public var free: String
    /// e.g. "free of 994 GB".
    public var freeCaption: String
    public var usedShare: Double?
    public var range: TimeRange
    /// `historyBarCount` bars over `range`, oldest first; nil where there's no data.
    public var history: [DiskDetail.Bar?]
    /// The chart's top, e.g. "2 GB/s".
    public var scale: String
    public var read: DiskDetail.Stat
    public var write: DiskDetail.Stat
    public var writtenToday: DiskDetail.Stat
    public var storage: StorageBreakdown?
    public var storageStatus: String?
    public var writesToday: [DiskDetail.AppRow]
}

extension DiskPanel {
    @MainActor
    static func make(
        snapshot: Snapshot?, history: MetricsHistory, range: TimeRange, calendar: Calendar = .current
    ) -> DiskPanel {
        let disk = snapshot?.disk.value
        let today = DiskToday(disk: disk, history: history, now: snapshot?.timestamp, calendar: calendar)
        let chart = DiskChart(history: history, range: range, endingAt: snapshot?.timestamp, count: historyBarCount)
        let storage = disk.map(StorageBreakdown.make) ?? .unavailable(.warmingUp)

        return DiskPanel(
            volumeLine: disk.map { DiskDetail.subtitle(for: $0.volume) } ?? "Disk",
            free: disk.map { DiskFormat.bytes($0.volume.free) } ?? Format.placeholder,
            freeCaption: disk.map { DiskDetail.freeOf($0.volume) } ?? "free",
            usedShare: disk.map { DiskDetail.usedShare($0.volume) },
            range: range,
            history: chart.bars,
            scale: chart.yAxis[0],
            read: today.read,
            write: today.write,
            writtenToday: today.written,
            storage: storage.value,
            storageStatus: DiskToday.storageStatus(storage),
            writesToday: today.writers(history: history, count: topAppCount)
        )
    }
}
