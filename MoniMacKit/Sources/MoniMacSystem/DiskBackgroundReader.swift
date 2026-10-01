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
///   current between scans because they're derived from live figures.
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
    private let started = Date()
    private let spaceInterval: TimeInterval
    private let scanDelay: TimeInterval
    private let scanInterval: TimeInterval

    init(
        nvmeDevice: UInt64?, scanner: DiskStorageScanner = DiskStorageScanner(),
        spaceInterval: TimeInterval = 300, scanDelay: TimeInterval = 10, scanInterval: TimeInterval = 6 * 3600
    ) {
        self.nvmeDevice = nvmeDevice
        self.scanner = scanner
        self.spaceInterval = spaceInterval
        self.scanDelay = scanDelay
        self.scanInterval = scanInterval
    }

    /// The most recent results.
    func latest() -> Latest {
        state.withLock { $0.latest }
    }

    /// Starts whichever background reads are due and not already running.
    func refreshIfDue(now: Date = Date()) {
        let (space, scan) = state.withLock { state in
            let space = !state.spaceRunning && state.lastSpace.map { now.timeIntervalSince($0) >= spaceInterval } ?? true
            if space { (state.spaceRunning, state.lastSpace) = (true, now) }
            let scan = !state.scanRunning && (state.lastScan.map { now.timeIntervalSince($0) >= scanInterval }
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
                let (result, entries) = scanner.scan()
                let cpu = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpuStart) / 1_000_000_000
                let wall = Date().timeIntervalSince(wallStart)
                log.info("""
                    Storage scan: \(entries) entries in \(wall, format: .fixed(precision: 1)) s, \
                    \(cpu, format: .fixed(precision: 2)) s CPU, partial: \(result.isPartial)
                    """)
                state.withLock {
                    $0.latest.scan = .value(result)
                    $0.scanRunning = false
                }
            }
        }
    }
}

/// Purgeable space and the space macOS's own volumes take.
enum DiskSpaceReader {
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
