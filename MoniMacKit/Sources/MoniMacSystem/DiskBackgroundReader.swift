import Darwin
import Foundation
import MoniMacCore
import os

private let log = Logger(subsystem: "io.github.lethanhvietctt5.MoniMac", category: "Disk")

/// Disk figures too slow for the refresh loop, read on background queues at utility QoS.
///
/// - Every `spaceInterval` (5 min): purgeable space (~15 ms, as macOS computes it on demand), the
///   space macOS takes, and SSD health.
/// - `scanDelay` after launch, then every `scanInterval` (6 h): the storage scan, which walks about
///   a million files and costs several seconds of CPU. Free space and the Documents remainder stay
///   current between scans because they're derived from live figures. A scan also runs early when
///   free space moves by more than `rescanThreshold` since the last one (a big install or cleanup).
///   With a `cache`, the result is saved, so a relaunch within `scanInterval` shows it at once.
///
/// `refreshIfDue` only starts work; the refresh loop never waits for it.
final class DiskBackgroundReader: Sendable {
    struct Latest: Sendable {
        var health: Reading<SSDHealth> = .unavailable(.warmingUp)
        var space: Reading<VolumeSpace> = .unavailable(.warmingUp)
        var scan: Reading<StorageScan> = .unavailable(.warmingUp)
    }

    private struct State {
        var latest = Latest()
        var spaceRunning = false
        var lastSpace: Date?
        var scanRunning = false
        var lastScan: Date?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let nvmeDevice: UInt64?
    private let scanner: DiskStorageScanner
    private let cache: StorageScanCache?
    private let started: Date
    private let spaceInterval: TimeInterval
    private let scanDelay: TimeInterval
    private let scanInterval: TimeInterval

    init(
        nvmeDevice: UInt64?, scanner: DiskStorageScanner = DiskStorageScanner(), cache: StorageScanCache? = nil,
        spaceInterval: TimeInterval = 300, scanDelay: TimeInterval = 10, scanInterval: TimeInterval = 6 * 3600,
        now: Date = Date()
    ) {
        self.nvmeDevice = nvmeDevice
        self.scanner = scanner
        self.cache = cache
        self.started = now
        self.spaceInterval = spaceInterval
        self.scanDelay = scanDelay
        self.scanInterval = scanInterval
        if let saved = cache?.load(), isFresh(saved, at: now) {
            state.withLock {
                $0.latest.scan = .value(saved)
                $0.lastScan = saved.scannedAt
            }
        }
    }

    /// A scan is fresh for `scanInterval`. One dated in the future (the clock was moved back) isn't.
    private func isFresh(_ scan: StorageScan, at now: Date) -> Bool {
        guard let scannedAt = scan.scannedAt else { return false }
        return (0..<scanInterval).contains(now.timeIntervalSince(scannedAt))
    }

    /// Free space moving by more than max(5 GB, 2% of capacity) since the scan means its sizes are off.
    static func freeSpaceMoved(since scan: StorageScan, free: UInt64, capacity: UInt64) -> Bool {
        guard let before = scan.freeAtScan else { return false }
        let threshold = max(5_000_000_000, capacity / 50)
        return (free > before ? free - before : before - free) > threshold
    }

    /// The most recent results.
    func latest() -> Latest {
        state.withLock { $0.latest }
    }

    /// Starts whichever background reads are due and not already running. `free` and `capacity`
    /// are the volume's live figures, used to spot a big change since the last scan.
    func refreshIfDue(now: Date = Date(), free: UInt64? = nil, capacity: UInt64 = 0) {
        let (space, scan) = state.withLock { state in
            let space = !state.spaceRunning && state.lastSpace.map { now.timeIntervalSince($0) >= spaceInterval } ?? true
            if space { (state.spaceRunning, state.lastSpace) = (true, now) }
            let moved = free.flatMap { free in
                state.latest.scan.value.map { Self.freeSpaceMoved(since: $0, free: free, capacity: capacity) }
            } ?? false
            let scan = !state.scanRunning && (moved || state.lastScan.map { now.timeIntervalSince($0) >= scanInterval }
                ?? (now.timeIntervalSince(started) >= scanDelay))
            if scan { (state.scanRunning, state.lastScan) = (true, now) }
            return (space, scan)
        }
        if space {
            DispatchQueue.global(qos: .utility).async { [self] in
                let health = DiskHealthReader.read(device: nvmeDevice)
                let space = DiskSpaceReader.read()
                state.withLock {
                    ($0.latest.health, $0.latest.space) = (health, space)
                    $0.spaceRunning = false
                }
            }
        }
        if scan {
            DispatchQueue.global(qos: .utility).async { [self] in
                let cpuStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                let wallStart = Date()
                let freeAtScan = DiskSpaceReader.freeBytes()
                var (scanned, entries) = scanner.scan()
                (scanned.scannedAt, scanned.freeAtScan) = (wallStart, freeAtScan)
                let result = scanned
                let cpu = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpuStart) / 1_000_000_000
                let wall = Date().timeIntervalSince(wallStart)
                log.notice("""
                    Storage scan: \(entries) entries in \(wall, format: .fixed(precision: 1)) s, \
                    \(cpu, format: .fixed(precision: 2)) s CPU, partial: \(result.isPartial)
                    """)
                state.withLock {
                    $0.latest.scan = .value(result)
                    $0.scanRunning = false
                }
                cache?.save(result)
            }
        }
    }
}

/// Where the last storage scan is saved, so relaunches don't rescan. The app passes `.standard`;
/// everything else (tests included) passes nothing and never touches the user's files.
public struct StorageScanCache: Sendable {
    let url: URL

    public static let standard = StorageScanCache(url: AppFiles.directory.appending(path: "StorageScan.json"))

    init(url: URL) {
        self.url = url
    }

    func load() -> StorageScan? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StorageScan.self, from: data)
    }

    func save(_ scan: StorageScan) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(scan).write(to: url, options: .atomic)
        } catch {
            log.error("Couldn't save the storage scan: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Purgeable space and the space macOS's own volumes take.
enum DiskSpaceReader {
    /// Free bytes on the startup volume, as `statfs` reports them.
    static func freeBytes() -> UInt64? {
        var fs = statfs()
        guard statfs("/", &fs) == 0 else { return nil }
        return UInt64(fs.f_bavail) * UInt64(fs.f_bsize)
    }

    static func read() -> Reading<VolumeSpace> {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity.map(Int64.init), let available = values.volumeAvailableCapacity,
              let important = values.volumeAvailableCapacityForImportantUsage
        else { return .unavailable(.failed("the startup volume's space isn't readable")) }
        guard let dataUsed = spaceUsed(byVolumeAt: "/System/Volumes/Data") else {
            return .unavailable(.failed("the Data volume's size isn't readable"))
        }
        let used = total - Int64(available)
        return .value(VolumeSpace(
            purgeable: UInt64(max(0, important - Int64(available))),
            system: UInt64(max(0, used - dataUsed))
        ))
    }

    /// Bytes used by one APFS volume (`ATTR_VOL_SPACEUSED`); statfs only reports the whole container.
    static func spaceUsed(byVolumeAt path: String) -> Int64? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_SPACEUSED)
        // A UInt32 length, then the off_t, packed without alignment.
        var buffer = [UInt8](repeating: 0, count: 16)
        guard getattrlist(path, &request, &buffer, buffer.count, 0) == 0 else { return nil }
        return buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
    }
}
