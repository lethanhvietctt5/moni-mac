import Foundation
import Testing
import MoniMacCore
@testable import MoniMacSystem

struct StorageScanCacheTests {
    let scan = StorageScan(
        applications: 182_000_000_000, appCount: 214,
        developer: [StorageScan.Item(name: "Xcode", bytes: 148_000_000_000)], isPartial: false
    )

    private func temporaryCache() -> StorageScanCache {
        StorageScanCache(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("monimac-tests-\(UUID().uuidString)/StorageScan.json"))
    }

    @Test func savesAndLoadsAScan() throws {
        let cache = temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.url.deletingLastPathComponent()) }
        let scannedAt = Date(timeIntervalSince1970: 1_790_000_000)

        cache.save(scan, scannedAt: scannedAt)

        let saved = try #require(cache.load())
        #expect(saved.scan == scan)
        #expect(saved.scannedAt == scannedAt)
    }

    @Test func aFreshSavedScanIsShownAtLaunchWithoutRescanning() {
        let cache = temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.url.deletingLastPathComponent()) }
        cache.save(scan, scannedAt: Date().addingTimeInterval(-3600))

        let reader = DiskBackgroundReader(nvmeDevice: nil, cache: cache, spaceInterval: .infinity, scanDelay: 0)

        #expect(reader.latest().scan == .value(scan))
    }

    @Test func aStaleSavedScanIsIgnored() {
        let cache = temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.url.deletingLastPathComponent()) }
        cache.save(scan, scannedAt: Date().addingTimeInterval(-7 * 3600))

        let reader = DiskBackgroundReader(nvmeDevice: nil, cache: cache)

        #expect(reader.latest().scan == .unavailable(.warmingUp))
    }

    @Test func aMissingOrCorruptCacheLoadsNothing() throws {
        let cache = temporaryCache()
        defer { try? FileManager.default.removeItem(at: cache.url.deletingLastPathComponent()) }
        #expect(cache.load() == nil)

        try FileManager.default.createDirectory(at: cache.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: cache.url)
        #expect(cache.load() == nil)
    }
}
