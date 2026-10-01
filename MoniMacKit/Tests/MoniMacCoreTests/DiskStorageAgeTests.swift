import Foundation
import Testing
import MoniMacCore

struct DiskStorageAgeTests {
    let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test(arguments: [(0.0, nil), (599, nil), (600, "Scanned 10m ago"), (7500, "Scanned 2h 5m ago")] as [(Double, String?)])
    func olderScansSayHowOldTheyAre(age: Double, label: String?) {
        let scan = StorageScan(applications: 1, appCount: 1, developer: [], scannedAt: now.addingTimeInterval(-age))

        #expect(scan.age(at: now) == label)
    }

    @Test func scansWithoutATimeHaveNoAge() {
        #expect(StorageScan(applications: 1, appCount: 1, developer: []).age(at: now) == nil)
    }
}
