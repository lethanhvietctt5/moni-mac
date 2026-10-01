import Foundation

/// What SystemSampler reads for the startup disk on each tick. Slow figures (SSD health, purgeable
/// space, the storage scan) are read in the background and repeated until they're refreshed.
public struct DiskReading: Equatable, Sendable {
    public var volume: DiskVolume
    /// Traffic on the internal drive since the previous sample.
    public var io: Reading<DiskIO>
    public var health: Reading<SSDHealth>
    /// Purgeable space and the space taken by macOS, read every few minutes.
    public var space: Reading<VolumeSpace>
    /// Folder sizes from the background storage scan, refreshed every few hours.
    public var scan: Reading<StorageScan>

    public init(
        volume: DiskVolume, io: Reading<DiskIO> = .unavailable(.warmingUp),
        health: Reading<SSDHealth> = .unavailable(.warmingUp), space: Reading<VolumeSpace> = .unavailable(.warmingUp),
        scan: Reading<StorageScan> = .unavailable(.warmingUp)
    ) {
        self.volume = volume
        self.io = io
        self.health = health
        self.space = space
        self.scan = scan
    }
}

/// The startup volume ("/").
public struct DiskVolume: Equatable, Sendable {
    /// e.g. "Macintosh HD".
    public var name: String
    /// e.g. "APFS".
    public var format: String
    /// Bytes in the volume's container.
    public var capacity: UInt64
    /// Bytes available now, not counting purgeable space.
    public var free: UInt64
    /// The physical drive's size, e.g. 1 TB for a 994 GB container. Nil when unknown.
    public var driveSize: UInt64?
    public var isSolidState: Bool

    public init(name: String, format: String, capacity: UInt64, free: UInt64, driveSize: UInt64? = nil,
                isSolidState: Bool = true) {
        self.name = name
        self.format = format
        self.capacity = capacity
        self.free = free
        self.driveSize = driveSize
        self.isSolidState = isSolidState
    }
}

/// Bytes moved over one sampling interval.
public struct DiskIO: Equatable, Sendable {
    public var bytesRead: UInt64
    public var bytesWritten: UInt64
    /// Seconds since the previous sample.
    public var interval: TimeInterval

    public init(bytesRead: UInt64, bytesWritten: UInt64, interval: TimeInterval) {
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
        self.interval = interval
    }

    public var readPerSecond: Double { interval > 0 ? Double(bytesRead) / interval : 0 }
    public var writePerSecond: Double { interval > 0 ? Double(bytesWritten) / interval : 0 }
}

/// NVMe SMART wear figures.
public struct SSDHealth: Equatable, Sendable {
    /// The drive's own estimate of life used, in percent. Can exceed 100.
    public var percentageUsed: Int
    /// Bytes written over the drive's life.
    public var lifetimeBytesWritten: UInt64

    public init(percentageUsed: Int, lifetimeBytesWritten: UInt64) {
        self.percentageUsed = percentageUsed
        self.lifetimeBytesWritten = lifetimeBytesWritten
    }

    /// Life remaining, 0...1.
    public var remaining: Double { Double(max(0, 100 - percentageUsed)) / 100 }
}

/// Space figures that are too slow to read every tick.
public struct VolumeSpace: Equatable, Sendable {
    /// Space macOS can free on demand (caches, local snapshots), counted as used.
    public var purgeable: UInt64
    /// Space used by the container's volumes other than Data: System, Preboot, Recovery, VM, Update.
    public var system: UInt64

    public init(purgeable: UInt64, system: UInt64) {
        self.purgeable = purgeable
        self.system = system
    }
}

/// Folder sizes from one background scan. Protected folders (Documents, Desktop, other apps'
/// containers) are never read, so scanning never triggers a privacy prompt.
public struct StorageScan: Equatable, Sendable, Codable {
    /// Allocated bytes in /Applications and ~/Applications.
    public var applications: UInt64
    /// `.app` bundles found there, including one folder level down (e.g. Utilities).
    public var appCount: Int
    /// Developer data by source, e.g. ("Xcode", …), ("Simulators", …), ("Homebrew", …).
    public var developer: [Item]
    /// Whether the scan hit its work cap, so the sizes are lower bounds.
    public var isPartial: Bool

    public struct Item: Equatable, Sendable, Codable {
        public var name: String
        public var bytes: UInt64

        public init(name: String, bytes: UInt64) {
            self.name = name
            self.bytes = bytes
        }
    }

    public init(applications: UInt64, appCount: Int, developer: [Item], isPartial: Bool = false) {
        self.applications = applications
        self.appCount = appCount
        self.developer = developer
        self.isPartial = isPartial
    }
}

extension SeriesKey {
    /// Bytes read per second from the internal drive.
    public static let diskRead = SeriesKey(rawValue: "disk.read")
    /// Bytes written per second to the internal drive.
    public static let diskWrite = SeriesKey(rawValue: "disk.write")
    /// Bytes written to the internal drive since the previous sample, for "Written Today".
    public static let diskWritten = SeriesKey(rawValue: "disk.written")
    /// Prefix of the per-app write amounts, "disk.written.app:<app id>".
    static let diskWrittenByAppPrefix = "disk.written.app:"

    static func diskWritten(byApp id: String) -> SeriesKey {
        SeriesKey(rawValue: diskWrittenByAppPrefix + id)
    }
}

extension Snapshot {
    /// Values MetricsHistory records for disk.
    var diskSeries: [SeriesSample] {
        guard let io = disk.value?.io.value else { return [] }
        let processes = processes.value ?? []
        return [
            SeriesSample(.diskRead, io.readPerSecond,
                         contributor: AppGrouping.busiestApp(in: processes, by: \.resources.diskReadPerSecond)),
            SeriesSample(.diskWrite, io.writePerSecond,
                         contributor: AppGrouping.busiestApp(in: processes, by: \.resources.diskWritePerSecond)),
            SeriesSample(.diskWritten, Double(io.bytesWritten)),
        ] + appWrites(over: io.interval, processes: processes)
    }

    /// Bytes each app wrote over the interval, only for apps that wrote. The process list refreshes
    /// less often than snapshots, so its rates are applied to the time since the previous sample:
    /// a reused rate then covers only the time it was reused for, and nothing is counted twice.
    /// These are the bytes each process asked to write to any volume, so they needn't add up to the
    /// internal drive's "Written Today".
    private func appWrites(over interval: TimeInterval, processes: [ProcessSample]) -> [SeriesSample] {
        guard interval > 0 else { return [] }
        let writers = processes.filter { ($0.resources.diskWritePerSecond ?? 0) > 0 }
        guard !writers.isEmpty else { return [] }
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var bytesByApp: [String: Double] = [:]
        for process in writers {
            bytesByApp[AppGrouping.owner(of: process, byPID: byPID).id, default: 0]
                += process.resources.diskWritePerSecond! * interval
        }
        return bytesByApp.sorted { $0.key < $1.key }.map { SeriesSample(.diskWritten(byApp: $0.key), $0.value) }
    }
}

extension Monitor {
    /// The main window toolbar subtitle for the Disk tab, e.g. "Macintosh HD · APFS · 1 TB SSD".
    public var diskSubtitle: String? {
        latest?.disk.value.map { DiskDetail.subtitle(for: $0.volume) }
    }

    /// The popover Disk tab for the given chart range.
    public func diskPanel(range: TimeRange) -> DiskPanel {
        DiskPanel.make(snapshot: latest, history: history, range: range)
    }

    /// The main window's Disk tab for the given chart range.
    public func diskDetail(range: TimeRange) -> DiskDetail {
        DiskDetail.make(snapshot: latest, history: history, range: range)
    }
}
