import Darwin
import Foundation
import IOKit
import MoniMacCore

/// Reads the startup disk for each snapshot.
///
/// Each tick costs a `statfs` and one IOKit property read. Everything slower (SSD health,
/// purgeable space, folder sizes) comes from `DiskBackgroundReader` and is repeated between its runs.
@MainActor
final class DiskReader {
    private let drive = StartupDrive.find()
    private let background: DiskBackgroundReader
    /// Volume name and format don't change while MoniMac runs, so they're read once.
    private lazy var identity: (name: String, format: String) = {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey, .volumeLocalizedFormatDescriptionKey])
        return (values?.volumeName ?? "Startup Disk", values?.volumeLocalizedFormatDescription ?? "Unknown format")
    }()
    private var previous: (counters: DriveCounters, uptime: UInt64)?

    init() {
        background = DiskBackgroundReader(nvmeDevice: drive?.nvmeDevice)
    }

    func sample() -> Reading<DiskReading> {
        background.refreshIfDue()
        var fs = statfs()
        guard statfs("/", &fs) == 0 else { return .unavailable(.failed("statfs(/) failed: errno \(errno)")) }
        let blockSize = UInt64(fs.f_bsize)
        let volume = DiskVolume(
            name: identity.name, format: identity.format,
            capacity: UInt64(fs.f_blocks) * blockSize, free: UInt64(fs.f_bavail) * blockSize,
            driveSize: drive?.size, isSolidState: drive?.isSolidState ?? false
        )
        let slow = background.latest()
        return .value(DiskReading(volume: volume, io: sampleIO(), health: slow.health, space: slow.space, scan: slow.scan))
    }

    private func sampleIO() -> Reading<DiskIO> {
        guard let drive else { return .unavailable(.failed("the startup volume's drive wasn't found")) }
        guard let counters = drive.counters() else { return .unavailable(.failed("the drive's statistics aren't readable")) }
        let uptime = DispatchTime.now().uptimeNanoseconds
        defer { previous = (counters, uptime) }
        guard let previous, uptime > previous.uptime else { return .unavailable(.warmingUp) }
        // Counters only grow; a smaller value means the driver restarted, so count from zero.
        func delta(_ now: UInt64, _ then: UInt64) -> UInt64 { now >= then ? now - then : now }
        return .value(DiskIO(
            bytesRead: delta(counters.read, previous.counters.read),
            bytesWritten: delta(counters.written, previous.counters.written),
            interval: Double(uptime - previous.uptime) / 1_000_000_000
        ))
    }
}

struct DriveCounters {
    var read: UInt64
    var written: UInt64
}

/// The physical drive holding the startup volume, found by walking up the IOKit service plane
/// from the volume's media to its block storage driver. This skips disk images (whose reads are
/// re-reads of the drive) and other drives.
struct StartupDrive {
    /// The IOBlockStorageDriver whose "Statistics" count the drive's bytes. Kept for the app's life.
    let driver: io_object_t
    /// Whole-drive size, e.g. 1 TB.
    let size: UInt64?
    let isSolidState: Bool
    /// Registry entry ID of the NVMe device, for SMART. Nil for other drive types.
    let nvmeDevice: UInt64?

    static func find() -> StartupDrive? {
        var fs = statfs()
        guard statfs("/", &fs) == 0 else { return nil }
        // e.g. "/dev/disk3s1s1" → "disk3s1s1".
        let device = withUnsafeBytes(of: fs.f_mntfromname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let bsdName = device.hasPrefix("/dev/") ? String(device.dropFirst(5)) : device
        var entry = IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, bsdName))
        guard entry != 0 else { return nil }
        var wholeMedia: io_object_t = 0
        defer { if wholeMedia != 0 { IOObjectRelease(wholeMedia) } }
        while entry != 0, IOObjectConformsTo(entry, "IOBlockStorageDriver") == 0 {
            if IOObjectConformsTo(entry, "IOMedia") != 0 {
                if wholeMedia != 0 { IOObjectRelease(wholeMedia) }
                wholeMedia = entry
                IOObjectRetain(wholeMedia)
            }
            var parent: io_registry_entry_t = 0
            let result = IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
            IOObjectRelease(entry)
            entry = result == KERN_SUCCESS ? parent : 0
        }
        guard entry != 0 else { return nil }

        var deviceEntry: io_registry_entry_t = 0
        IORegistryEntryGetParentEntry(entry, kIOServicePlane, &deviceEntry)
        defer { if deviceEntry != 0 { IOObjectRelease(deviceEntry) } }
        let characteristics = property(deviceEntry, "Device Characteristics") as? [String: Any]
        var nvmeID: UInt64 = 0
        let isNVMe = deviceEntry != 0 && IOObjectConformsTo(deviceEntry, "IONVMeBlockStorageDevice") != 0
            && IORegistryEntryGetRegistryEntryID(deviceEntry, &nvmeID) == KERN_SUCCESS
        return StartupDrive(
            driver: entry,
            size: (property(wholeMedia, "Size") as? NSNumber)?.uint64Value,
            isSolidState: characteristics?["Medium Type"] as? String == "Solid State",
            nvmeDevice: isNVMe ? nvmeID : nil
        )
    }

    /// Cumulative bytes since the driver started.
    func counters() -> DriveCounters? {
        guard let statistics = Self.property(driver, "Statistics") as? [String: Any],
              let read = (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value,
              let written = (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value
        else { return nil }
        return DriveCounters(read: read, written: written)
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        guard entry != 0 else { return nil }
        return IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
