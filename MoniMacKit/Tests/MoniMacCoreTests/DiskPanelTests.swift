import Foundation
import Testing
@testable import MoniMacCore

@MainActor
struct DiskPanelTests {
    typealias F = DiskFixture

    private static let space = VolumeSpace(purgeable: 92_000_000_000, system: 46_000_000_000)
    private static let scan = StorageScan(
        applications: 182_000_000_000, appCount: 214,
        developer: [
            .init(name: "Homebrew", bytes: 20_000_000_000), .init(name: "Xcode", bytes: 90_000_000_000),
            .init(name: "Simulators", bytes: 38_000_000_000), .init(name: "npm", bytes: 0),
        ]
    )

    private func panel(_ snapshots: [Snapshot], range: TimeRange = .fiveMinutes) throws -> DiskPanel {
        let history = try MetricsHistory(.inMemory)
        for snapshot in snapshots { try history.record(snapshot) }
        return DiskPanel.make(snapshot: snapshots.last, history: history, range: range, calendar: F.utc)
    }

    @Test func compactSummary() throws {
        let writer = F.process(1, "/Applications/Xcode.app/Contents/MacOS/Xcode", writing: 2_000_000)
        let panel = try panel([F.snapshot(at: F.now, read: 96_000_000, written: 24_000_000, processes: [writer])])

        #expect(panel.volumeLine == "Macintosh HD · APFS · 1 TB SSD")
        #expect(panel.free == "312 GB")
        #expect(panel.freeCaption == "free of 994 GB")
        #expect(panel.read.value == "48 MB/s")
        #expect(panel.read.detail == "Peak 48 MB/s today")
        #expect(panel.writtenToday.value == "24 MB")
        #expect(panel.history.count == DiskPanel.historyBarCount)
        #expect(panel.scale == "100 MB/s")  // 48 + 12 MB/s, rounded up
        #expect(panel.writesToday.map(\.name) == ["Xcode"])
    }

    @Test func storageBreakdownWaitsForTheBackgroundScan() throws {
        let panel = try panel([F.snapshot(at: F.now, space: .value(Self.space))])

        #expect(panel.storage == nil)
        #expect(panel.storageStatus == "Scanning storage…")
    }

    @Test func storageBreakdownSaysWhyItFailed() throws {
        let panel = try panel([F.snapshot(at: F.now, space: .unavailable(.failed("Data volume not found")),
                                          scan: .value(Self.scan))])

        #expect(panel.storage == nil)
        #expect(panel.storageStatus == "Storage breakdown unavailable: Data volume not found")
    }

    @Test func storageBreakdownAddsUpToTheCapacity() throws {
        let panel = try panel([F.snapshot(at: F.now, space: .value(Self.space), scan: .value(Self.scan))])
        let storage = try #require(panel.storage)

        #expect(panel.storageStatus == nil)
        #expect(storage.segments.map(\.category) == StorageBreakdown.Category.allCases)
        #expect(storage.segments.map(\.value) == ["182 GB", "148 GB", "214 GB", "46 GB", "92 GB", "312 GB"])
        #expect(storage.segments.map(\.hint) == [
            "214 apps", "Xcode, Simulators", "Your files & app data", "System volumes", "Caches, snapshots",
            "Available now",
        ])
        #expect(storage.segments.reduce(0) { $0 + $1.bytes } == F.volume.capacity)
        #expect(abs(storage.segments.reduce(0) { $0 + $1.share } - 1) < 1e-9)
    }

    @Test func cappedScanShowsLowerBounds() throws {
        var scan = Self.scan
        scan.isPartial = true
        let storage = try #require(try panel([F.snapshot(at: F.now, space: .value(Self.space), scan: .value(scan))]).storage)

        #expect(storage.segments.map(\.value).prefix(3) == ["≥ 182 GB", "≥ 148 GB", "214 GB"])
    }

    /// Inputs read at different times can overlap; Documents never goes negative.
    @Test func documentsNeverGoNegative() throws {
        let full = VolumeSpace(purgeable: 600_000_000_000, system: 46_000_000_000)
        let storage = try #require(try panel([F.snapshot(at: F.now, space: .value(full), scan: .value(Self.scan))]).storage)

        #expect(storage.segments[2].bytes == 0)
    }
}

struct DiskFormatTests {
    @Test(arguments: [
        (0.0, "0 KB"), (640_000, "640 KB"), (9_840_000_000, "9.8 GB"), (2_000_000_000, "2 GB"),
        (312_400_000_000, "312 GB"), (999_700_000, "1 GB"), (9_970_000, "10 MB"), (1_200_000_000_000_000, "1.2 PB"),
    ])
    func bytes(value: Double, text: String) {
        #expect(DiskFormat.bytes(value) == text)
    }

    @Test func rates() {
        #expect(DiskFormat.rate(1_900_000_000) == "1.9 GB/s")
        #expect(DiskFormat.rate(840_000_000) == "840 MB/s")
    }

    @Test(arguments: [(UInt64(1_000_555_581_440), "1 TB"), (500_277_790_720, "500 GB"), (2_000_398_934_016, "2 TB")])
    func driveSizes(bytes: UInt64, text: String) {
        #expect(DiskFormat.driveSize(bytes) == text)
    }
}
