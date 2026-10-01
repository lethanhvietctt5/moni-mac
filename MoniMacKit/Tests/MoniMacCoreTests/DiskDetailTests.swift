import Foundation
import Testing
@testable import MoniMacCore

/// Builds disk snapshots for the Disk tests.
struct DiskFixture {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    /// 2026-10-01 09:41 UTC.
    static let now = Date(timeIntervalSince1970: 1_790_847_660)
    static let midnight = Date(timeIntervalSince1970: 1_790_812_800)
    static let volume = DiskVolume(
        name: "Macintosh HD", format: "APFS", capacity: 994_000_000_000, free: 312_000_000_000,
        driveSize: 1_000_555_581_440
    )

    static func process(_ pid: Int32, _ path: String, writing bytesPerSecond: Double, reading: Double = 0,
                        responsible: Int32? = nil) -> ProcessSample {
        ProcessSample(pid: pid, responsiblePID: responsible, name: (path as NSString).lastPathComponent, path: path,
                      cpu: 0, resources: ResourceUse(diskReadPerSecond: reading, diskWritePerSecond: bytesPerSecond))
    }

    static func snapshot(
        at time: Date, read: UInt64 = 0, written: UInt64 = 0, interval: TimeInterval = 2,
        processes: [ProcessSample] = [], volume: DiskVolume = volume,
        health: Reading<SSDHealth> = .value(SSDHealth(percentageUsed: 2, lifetimeBytesWritten: 54_050_000_000_000)),
        space: Reading<VolumeSpace> = .unavailable(.warmingUp), scan: Reading<StorageScan> = .unavailable(.warmingUp)
    ) -> Snapshot {
        Snapshot(
            timestamp: time, cpu: .unavailable(.warmingUp), processes: .value(processes),
            disk: .value(DiskReading(
                volume: volume, io: .value(DiskIO(bytesRead: read, bytesWritten: written, interval: interval)),
                health: health, space: space, scan: scan
            ))
        )
    }
}

@MainActor
struct DiskDetailTests {
    typealias F = DiskFixture

    private func detail(history snapshots: [Snapshot], latest: Snapshot? = nil, range: TimeRange = .twentyFourHours)
        throws -> DiskDetail {
        let history = try MetricsHistory(.inMemory)
        for snapshot in snapshots { try history.record(snapshot) }
        return DiskDetail.make(snapshot: latest ?? snapshots.last, history: history, range: range, calendar: F.utc)
    }

    @Test func summaryMatchesTheDesign() throws {
        let detail = try detail(history: [F.snapshot(at: F.now, read: 96_000_000, written: 24_000_000)])

        #expect(detail.subtitle == "Macintosh HD · APFS · 1 TB SSD")
        #expect(detail.free == "312")
        #expect(detail.freeCaption == "GB free of 994 GB")
        #expect(abs(detail.usedShare! - 682.0 / 994) < 1e-9)
        #expect(detail.read.value == "48 MB/s")
        #expect(detail.write.value == "12 MB/s")
        #expect(detail.writtenToday.label == "Written Today")
        #expect(detail.writtenToday.value == "24 MB")
        #expect(detail.writtenToday.detail == "SSD health 98% · 54 TB lifetime")
    }

    @Test func missingDiskShowsPlaceholders() throws {
        let latest = Snapshot(timestamp: F.now, cpu: .unavailable(.warmingUp))
        let detail = try detail(history: [], latest: latest)

        #expect(detail.free == "—")
        #expect(detail.read.value == "—")
        #expect(detail.writtenToday.value == "—")
        #expect(detail.usedShare == nil)
        #expect(detail.storageStatus == "Scanning storage…")
    }

    @Test func ratesWarmUpWhileTheVolumeIsAlreadyKnown() throws {
        var latest = F.snapshot(at: F.now)
        latest.disk = .value(DiskReading(volume: F.volume))
        let detail = try detail(history: [latest])

        #expect(detail.free == "312")
        #expect(detail.read.value == "—")
        #expect(detail.read.detail == "No data today")
        #expect(detail.writtenToday.detail == "SSD health —")
    }

    @Test func peaksAreTodaysWithTheirContributor() throws {
        let xcode = F.process(1, "/Applications/Xcode.app/Contents/MacOS/Xcode", writing: 800_000_000)
        let detail = try detail(history: [
            // Yesterday's bigger burst doesn't count.
            F.snapshot(at: F.midnight - 60, read: 9_000_000_000, written: 9_000_000_000),
            F.snapshot(at: F.midnight + 3600, read: 3_800_000_000, written: 1_680_000_000, processes: [xcode]),
            F.snapshot(at: F.now, read: 2_000_000, written: 2_000_000),
        ])

        #expect(detail.read.detail == "Peak 1.9 GB/s today")
        #expect(detail.write.detail == "Peak 840 MB/s today")
        #expect(detail.write.help == "Peak at 01:00 · Xcode")
    }

    @Test func writtenTodayResetsAtLocalMidnight() throws {
        let detail = try detail(history: [
            F.snapshot(at: F.midnight - 2, written: 5_000_000_000),
            F.snapshot(at: F.midnight + 3600, written: 1_000_000_000),
            F.snapshot(at: F.now, written: 400_000_000),
        ])

        #expect(detail.writtenToday.value == "1.4 GB")
    }

    @Test func writesTodayRankAppsAndKeepAppsThatQuit() throws {
        let compiler = F.process(10, "/usr/bin/swift-frontend", writing: 6_000_000)
        let chrome = F.process(20, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", writing: 1_000_000)
        let helper = F.process(
            21, "/Applications/Google Chrome.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper",
            writing: 500_000, responsible: 20
        )
        let idle = F.process(30, "/Applications/Notes.app/Contents/MacOS/Notes", writing: 0)
        let detail = try detail(history: [
            F.snapshot(at: F.midnight + 600, processes: [compiler, chrome, helper, idle]),
            // The compiler exited; Chrome keeps writing.
            F.snapshot(at: F.now - 2, processes: [chrome, helper, idle]),
            F.snapshot(at: F.now, processes: [chrome, helper, idle]),
        ])

        #expect(detail.writesToday.map(\.name) == ["swift-frontend", "Google Chrome"])
        #expect(detail.writesToday.map(\.value) == ["12 MB", "9 MB"])
        #expect(detail.writesToday.map(\.bundlePath) == [nil, "/Applications/Google Chrome.app"])
        #expect(detail.writesToday.map(\.share) == [1, 0.75])
    }

    /// The process list refreshes every ~4 s and is repeated on the 2 s ticks between. Each tick
    /// counts its rate for its own 2 s, so a reused rate is never counted twice.
    @Test func reusedProcessRatesAreNotDoubleCounted() throws {
        let writer = F.process(10, "/usr/local/bin/writer", writing: 1_000_000)
        let detail = try detail(history: (0..<4).map {
            F.snapshot(at: F.now - Double(6 - 2 * $0), interval: 2, processes: [writer])
        })

        // 4 ticks × 2 s × 1 MB/s.
        #expect(detail.writesToday.first?.value == "8 MB")
    }

    /// Shortly after midnight, today is summed from raw samples.
    @Test func justAfterMidnightOnlyTodayCounts() throws {
        let writer = F.process(10, "/usr/local/bin/writer", writing: 1_000_000)
        let early = F.midnight + 300
        let detail = try detail(history: [
            F.snapshot(at: F.midnight - 2, written: 7_000_000, processes: [writer]),
            F.snapshot(at: early, written: 3_000_000, processes: [writer]),
        ])

        #expect(detail.writesToday.map(\.value) == ["2 MB"])
        #expect(detail.writtenToday.value == "3 MB")
    }

    @Test func nothingWrittenYetTodayRanksNoApps() throws {
        let writer = F.process(10, "/usr/local/bin/writer", writing: 1_000_000)
        let detail = try detail(history: [F.snapshot(at: F.midnight - 2, processes: [writer]), F.snapshot(at: F.now)])

        #expect(detail.writesToday.isEmpty)
        #expect(detail.writtenToday.value == "0 KB")
    }

    @Test func perAppWritesSurviveOlderThanAnHour() throws {
        let writer = F.process(10, "/usr/local/bin/writer", writing: 1_000_000)
        let detail = try detail(history: [
            F.snapshot(at: F.midnight + 3600, processes: [writer]),
            F.snapshot(at: F.now, processes: [writer]),
        ])

        // Older samples are summed from minute buckets.
        #expect(detail.writesToday.first?.value == "4 MB")
    }

    @Test func atMostSevenAppsAreRanked() throws {
        let writers = (1...9).map { F.process(Int32($0), "/usr/bin/tool\($0)", writing: Double($0) * 1_000_000) }
        let detail = try detail(history: [F.snapshot(at: F.now, processes: writers)])

        #expect(detail.writesToday.count == DiskDetail.topAppCount)
        #expect(detail.writesToday.first?.name == "tool9")
    }

    @Test(arguments: [
        (Reading<SSDHealth>.unavailable(.unsupported), "SSD health unavailable: the drive doesn't report it"),
        (.unavailable(.failed("no permission to read SMART")), "SSD health unavailable: no permission to read SMART"),
        (.value(SSDHealth(percentageUsed: 120, lifetimeBytesWritten: 1_200_000_000_000_000)),
         "SSD health 0% · 1.2 PB lifetime"),
    ])
    func ssdHealthSaysWhyItIsUnavailable(health: Reading<SSDHealth>, text: String) throws {
        let detail = try detail(history: [F.snapshot(at: F.now, health: health)])

        #expect(detail.writtenToday.detail == text)
    }

    @Test func historyStacksReadUnderWriteOnARoundedScale() throws {
        let detail = try detail(history: [F.snapshot(at: F.now, read: 2_400_000_000, written: 600_000_000)])

        #expect(detail.yAxis == ["2 GB/s", "1 GB/s", "0"])
        #expect(detail.history.count == DiskDetail.historyBarCount)
        #expect(detail.history.last == DiskDetail.Bar(read: 0.6, write: 0.15))
        #expect(detail.history.dropLast().allSatisfy { $0 == nil })
        #expect(detail.xAxis == ["09:00", "15:00", "21:00", "03:00", "Now"])
    }

    @Test(arguments: [(0.0, 1_000_000.0), (1_000_001, 2_000_000), (2_400_000, 5_000_000), (9e9, 1e10)])
    func chartScaleRoundsUp(peak: Double, scale: Double) {
        #expect(DiskChart.scale(for: peak) == scale)
    }
}
