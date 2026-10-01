import Darwin
import Foundation
import Testing
import MoniMacCore
@testable import MoniMacSystem

/// Runs against the real Mac. Checks fields are present and in range, not exact values.
@MainActor
struct DiskReaderSmokeTests {
    @Test func readsTheStartupVolumeAndItsTraffic() async throws {
        let reader = DiskReader()
        let first = try #require(reader.sample().value)
        #expect(first.io == .unavailable(.warmingUp))
        #expect(!first.volume.name.isEmpty)
        #expect(first.volume.capacity > 10_000_000_000)
        #expect((1..<first.volume.capacity).contains(first.volume.free))
        let driveSize = try #require(first.volume.driveSize)
        #expect(driveSize >= first.volume.capacity)

        // 32 MB flushed to the drive must show up, catching unit or counter mistakes.
        let file = FileManager.default.temporaryDirectory.appending(path: "monimac-disk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        for _ in 0..<32 { handle.write(Data((0..<1_000_000).map { UInt8(truncatingIfNeeded: $0 &* 7919) })) }
        _ = fcntl(handle.fileDescriptor, F_FULLFSYNC)
        try handle.close()
        try await Task.sleep(for: .milliseconds(200))

        let second = try #require(reader.sample().value)
        let io = try #require(second.io.value, "io: \(second.io)")
        #expect(io.interval > 0.1 && io.interval < 30)
        #expect(io.bytesWritten >= 16_000_000, "wrote \(io.bytesWritten) bytes")
    }

    @Test func readsSSDHealthOrSaysWhyNot() {
        let drive = StartupDrive.find()
        #expect(drive != nil)
        let health = DiskHealthReader.read(device: drive?.nvmeDevice)
        switch health {
        case .value(let health):
            #expect((0...255).contains(health.percentageUsed))
            #expect(health.lifetimeBytesWritten > 0)
        case .unavailable(let reason):
            // Only drives that aren't NVMe may lack it.
            #expect(drive?.nvmeDevice == nil && reason == .unsupported, "\(reason)")
        }
    }

    @Test func readsPurgeableAndSystemSpace() throws {
        let space = try #require(DiskSpaceReader.read().value)
        #expect(space.system > 1_000_000_000, "macOS takes more than 1 GB")
        #expect(space.purgeable < 10_000_000_000_000)
    }
}

/// Builds a small folder tree with known sizes.
private struct Fixture {
    let root = FileManager.default.temporaryDirectory.appending(path: "monimac-scan-\(UUID().uuidString)")

    init() throws {
        for (path, bytes) in [
            ("a.bin", 10_000), ("sub/b.bin", 20_000),
            ("Foo.app/Contents/MacOS/Foo", 1_000), ("Foo.app/Contents/Helpers/Helper.app/Contents/x", 1_000),
            ("Utilities/Bar.app/Contents/MacOS/Bar", 1_000), ("deep/er/Baz.app/x", 1_000),
            ("excluded/big.bin", 500_000),
        ] {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: bytes).write(to: url)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

struct DiskStorageScannerSmokeTests {
    @Test func sizesAFolderAndCountsItsApps() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var budget = 1000

        let size = DiskStorageScanner.size(of: fixture.root.path, excluding: [fixture.root.appending(path: "excluded").path],
                                           budget: &budget)

        // Allocated sizes round each file up to whole blocks.
        #expect((34_000..<200_000).contains(size.bytes), "\(size.bytes) bytes")
        #expect(size.apps == 2, "Foo.app and Utilities/Bar.app, not nested or deeper bundles")
        #expect(budget > 900)
    }

    @Test func missingFoldersAreEmpty() {
        var budget = 10
        let size = DiskStorageScanner.size(of: "/nonexistent-\(UUID().uuidString)", budget: &budget)
        #expect(size.bytes == 0 && size.apps == 0)
    }

    @Test func cappedScanIsMarkedPartial() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var scanner = DiskStorageScanner(home: fixture.root.path, maxEntries: 3)
        scanner.applications = [fixture.root.path]
        scanner.developer = []

        #expect(scanner.scan().0.isPartial)
    }

    /// The background reader returns at once and publishes the scan when it finishes.
    @Test func backgroundScanDoesNotBlockTheCaller() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var scanner = DiskStorageScanner(home: fixture.root.path)
        scanner.applications = [fixture.root.path]
        scanner.developer = [.init(name: "Tools", path: fixture.root.appending(path: "excluded").path)]
        let reader = DiskBackgroundReader(nvmeDevice: nil, scanner: scanner, scanDelay: 0)

        let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        reader.refreshIfDue()
        #expect(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start < 5_000_000, "refreshIfDue returned within 5 ms")

        var scan: StorageScan?
        for _ in 0..<100 where scan == nil {
            try await Task.sleep(for: .milliseconds(50))
            scan = reader.latest().scan.value
        }
        let result = try #require(scan)
        #expect(result.appCount == 2)
        #expect(result.developer.map(\.name) == ["Tools"])
        #expect(result.developer[0].bytes >= 500_000)
        #expect(reader.latest().health == .unavailable(.unsupported))
    }
}
