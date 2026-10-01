import Foundation
import Testing
import MoniMacCore
@testable import MoniMacSystem

/// The saved storage scan, through DiskBackgroundReader's behaviour. Everything lives in a temp folder:
/// the scanner only walks it, and the saved scan is written there, never to the user's files.
struct StorageScanCacheTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("monimac-tests-\(UUID().uuidString)")
    let capacity: UInt64 = 1_000_000_000_000
    let free: UInt64 = 400_000_000_000

    private var cache: StorageScanCache { StorageScanCache(url: folder.appendingPathComponent("StorageScan.json")) }

    /// Scans only `folder`, which holds nothing but the saved scan, so a rescan finds a few KB of "apps".
    private var scanner: DiskStorageScanner {
        var scanner = DiskStorageScanner(home: folder.path, maxEntries: 200)
        scanner.applications = [folder.path]
        scanner.developer = []
        return scanner
    }

    /// A saved scan that's easy to tell apart from a rescan of the empty folder.
    private func savedScan(age: TimeInterval) -> StorageScan {
        StorageScan(applications: 7_000_000_000, appCount: 3, developer: [], scannedAt: Date().addingTimeInterval(-age),
                    freeAtScan: free)
    }

    private func reader(scanDelay: TimeInterval = 0) -> DiskBackgroundReader {
        DiskBackgroundReader(nvmeDevice: nil, scanner: scanner, cache: cache, spaceInterval: .infinity, scanDelay: scanDelay)
    }

    private func waitForScan(_ reader: DiskBackgroundReader, until done: (StorageScan) -> Bool) async throws {
        for _ in 0..<100 {
            if let scan = reader.latest().scan.value, done(scan) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func cleanUp() { try? FileManager.default.removeItem(at: folder) }

    @Test func aFreshSavedScanIsShownAtOnceAndNotRescanned() async throws {
        defer { cleanUp() }
        cache.save(savedScan(age: 3600))
        let reader = reader()

        #expect(reader.latest().scan.value?.applications == 7_000_000_000)
        reader.refreshIfDue(free: free, capacity: capacity)
        try await Task.sleep(for: .seconds(1))

        #expect(reader.latest().scan.value?.applications == 7_000_000_000)
    }

    @Test func aBigChangeInFreeSpaceTriggersARescan() async throws {
        defer { cleanUp() }
        cache.save(savedScan(age: 3600))
        let reader = reader()

        reader.refreshIfDue(free: free - 50_000_000_000, capacity: capacity)
        try await waitForScan(reader) { $0.applications != 7_000_000_000 }

        #expect((reader.latest().scan.value?.applications ?? .max) < 1_000_000)
        #expect((cache.load()?.applications ?? .max) < 1_000_000, "the rescan replaces the saved one")
    }

    @Test func aSmallChangeInFreeSpaceDoesNot() async throws {
        defer { cleanUp() }
        cache.save(savedScan(age: 3600))
        let reader = reader()

        reader.refreshIfDue(free: free - 1_000_000_000, capacity: capacity)
        try await Task.sleep(for: .seconds(1))

        #expect(reader.latest().scan.value?.applications == 7_000_000_000)
    }

    @Test func aScanIsSavedForTheNextLaunch() async throws {
        defer { cleanUp() }
        let first = reader()
        first.refreshIfDue(free: free, capacity: capacity)
        try await waitForScan(first) { _ in true }
        try await Task.sleep(for: .milliseconds(200))

        let relaunched = reader(scanDelay: 3600)

        let scan = try #require(relaunched.latest().scan.value)
        #expect(scan.scannedAt != nil)
        #expect(scan.freeAtScan != nil)
    }

    @Test(arguments: [7 * 3600.0, -3600.0])
    func staleOrFutureDatedScansAreIgnored(age: TimeInterval) {
        defer { cleanUp() }
        cache.save(savedScan(age: age))

        #expect(reader(scanDelay: 3600).latest().scan == .unavailable(.warmingUp))
    }

    @Test func aCorruptSavedScanIsIgnored() throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: cache.url)

        #expect(reader(scanDelay: 3600).latest().scan == .unavailable(.warmingUp))
    }
}
