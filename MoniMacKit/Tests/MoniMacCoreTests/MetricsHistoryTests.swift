import Foundation
import Testing
@testable import MoniMacCore

@MainActor
struct MetricsHistoryTests {
    let clock = TestClock()

    private func snapshot(cpu total: Double?) -> Snapshot {
        Snapshot(timestamp: clock.now, cpu: total.map { .cpu(user: $0, system: 0) } ?? .unavailable(.warmingUp))
    }

    /// Records `values` every `interval` seconds, advancing the clock after each.
    private func record(_ values: [Double?], every interval: TimeInterval, into history: MetricsHistory) throws {
        for value in values {
            try history.record(snapshot(cpu: value))
            clock.advance(by: interval)
        }
    }

    @Test func shortRangesReturnRawSamplesWithAverageAndPeak() throws {
        let history = try MetricsHistory(.inMemory)
        let start = clock.now
        try record([0.2, 0.9, 0.4], every: 2, into: history)

        let summary = try history.summary(.cpuTotal, over: .oneMinute, endingAt: clock.now)

        #expect(summary.points.map(\.value) == [0.2, 0.9, 0.4])
        #expect(abs(summary.average! - 0.5) < 1e-9)
        #expect(summary.peak == SeriesPoint(time: start + 2, value: 0.9))
    }

    @Test func excludesSamplesOutsideTheRange() throws {
        let history = try MetricsHistory(.inMemory)
        try record([0.9], every: 120, into: history)
        try record([0.1, 0.3], every: 2, into: history)

        let summary = try history.summary(.cpuTotal, over: .oneMinute, endingAt: clock.now)

        #expect(summary.points.map(\.value) == [0.1, 0.3])
        #expect(summary.peak?.value == 0.3)
    }

    @Test func unavailableReadingsLeaveAGap() throws {
        let history = try MetricsHistory(.inMemory)
        try record([nil, 0.5, nil], every: 2, into: history)

        let summary = try history.summary(.cpuTotal, over: .oneMinute, endingAt: clock.now)

        #expect(summary.points.map(\.value) == [0.5])
    }

    @Test func emptyRangeHasNoAverageOrPeak() throws {
        let history = try MetricsHistory(.inMemory)

        let summary = try history.summary(.cpuTotal, over: .twentyFourHours, endingAt: clock.now)

        #expect(summary.points.isEmpty)
        #expect(summary.average == nil)
        #expect(summary.peak == nil)
    }

    @Test func longRangesUseMinuteBucketsWithExactAverageAndPeakTime() throws {
        let history = try MetricsHistory(.inMemory)
        // Align to a minute boundary so buckets are predictable.
        clock.advance(by: 60 - clock.now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60))
        let start = clock.now
        // Minute 1: 0.1 ×30. Minute 2: 0.3 ×29 then a 0.95 spike.
        try record(Array(repeating: 0.1, count: 30), every: 2, into: history)
        try record(Array(repeating: 0.3, count: 29) + [0.95], every: 2, into: history)

        let summary = try history.summary(.cpuTotal, over: .twelveHours, endingAt: clock.now)

        #expect(summary.points.count == 2)
        #expect(summary.points[0].time == start)
        #expect(abs(summary.points[0].value - 0.1) < 1e-9)
        #expect(abs(summary.average! - (0.1 * 30 + 0.3 * 29 + 0.95) / 60) < 1e-9)
        #expect(summary.peak == SeriesPoint(time: start + 118, value: 0.95))
    }

    @Test func oldDataSurvivesOnlyDownsampled() throws {
        let history = try MetricsHistory(.inMemory)
        try record([0.2, 0.8], every: 2, into: history)

        // Two hours later, raw samples are pruned but the minute buckets still cover 24H.
        clock.advance(by: 2 * 3600)
        try record([0.5], every: 2, into: history)

        let hour = try history.summary(.cpuTotal, over: .oneHour, endingAt: clock.now)
        let day = try history.summary(.cpuTotal, over: .twentyFourHours, endingAt: clock.now)
        #expect(hour.points.map(\.value) == [0.5])
        #expect(day.peak?.value == 0.8)
        #expect(abs(day.average! - 0.5) < 1e-9)

        // Two days later, minute buckets are gone but 15-minute buckets cover 7D.
        clock.advance(by: 2 * 86400)
        try record([0.1], every: 2, into: history)

        let week = try history.summary(.cpuTotal, over: .sevenDays, endingAt: clock.now)
        let today = try history.summary(.cpuTotal, over: .twentyFourHours, endingAt: clock.now)
        #expect(week.peak?.value == 0.8)
        #expect(today.points.map(\.value) == [0.1])
    }

    @Test func prunesDataOlderThanRetention() throws {
        let history = try MetricsHistory(.inMemory)
        try record([0.9], every: 2, into: history)

        clock.advance(by: 31 * 86400)
        try record([0.2], every: 2, into: history)

        let month = try history.summary(.cpuTotal, over: .thirtyDays, endingAt: clock.now)
        #expect(month.points.map(\.value) == [0.2])
    }

    @Test func shorteningRetentionPrunesImmediately() throws {
        let history = try MetricsHistory(.inMemory)
        try record([0.9], every: 2, into: history)
        clock.advance(by: 10 * 86400)
        try record([0.2], every: 2, into: history)

        history.retention = TimeRange.sevenDays.duration

        let month = try history.summary(.cpuTotal, over: .thirtyDays, endingAt: clock.now)
        #expect(month.peak?.value == 0.2)
    }

    @Test func peaksKeepTheirContributorInEveryTier() throws {
        let history = try MetricsHistory(.inMemory)
        let busy = Snapshot(timestamp: clock.now, cpu: .cpu(user: 0.9, system: 0), processes: .value([
            ProcessSample(pid: 1, name: "Xcode", path: "/Applications/Xcode.app/Contents/MacOS/Xcode", cpu: 4),
        ]))
        try history.record(busy)
        clock.advance(by: 2)
        try record([0.1], every: 2, into: history)

        let minute = try history.summary(.cpuTotal, over: .oneMinute, endingAt: clock.now)
        let day = try history.summary(.cpuTotal, over: .twentyFourHours, endingAt: clock.now)
        let week = try history.summary(.cpuTotal, over: .sevenDays, endingAt: clock.now)
        #expect([minute, day, week].map(\.peak?.contributor) == ["Xcode", "Xcode", "Xcode"])
    }

    @Test func sumsRecordedAmountsOverAnyRange() throws {
        let history = try MetricsHistory(.inMemory)
        let start = clock.now
        try record([0.2, 0.3, 0.5], every: 2, into: history)

        #expect(abs(try history.sum(.cpuTotal, from: start.addingTimeInterval(-1), to: clock.now)! - 1.0) < 1e-9)
        #expect(abs(try history.sum(.cpuTotal, from: start.addingTimeInterval(1), to: clock.now)! - 0.8) < 1e-9)
        #expect(try history.sum(.cpuUser, from: clock.now, to: clock.now.addingTimeInterval(10)) == nil)
    }

    @Test func dailyTotalsSplitAtLocalMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let history = try MetricsHistory(.inMemory)
        // Start 30 minutes before a UTC midnight: two samples on day 1, one on day 2.
        let midnight = calendar.startOfDay(for: clock.now).addingTimeInterval(86400)
        clock.advance(by: midnight.timeIntervalSince(clock.now) - 1800)
        try record([0.25, 0.25], every: 900, into: history)
        try record([0.5], every: 900, into: history)

        let totals = try history.dailyTotals(.cpuTotal, days: 3, endingAt: midnight.addingTimeInterval(3600), calendar: calendar)

        #expect(totals.map(\.day) == [midnight.addingTimeInterval(-2 * 86400), midnight.addingTimeInterval(-86400), midnight])
        #expect(totals.map(\.total) == [nil, 0.5, 0.5])
    }

    @Test func addsContributorColumnsToOlderDatabases() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("monimac-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("History.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        do {
            // The schema before contributors existed.
            let old = try Database(.file(url))
            try old.execute("""
                CREATE TABLE raw (series TEXT NOT NULL, t REAL NOT NULL, v REAL NOT NULL);
                CREATE TABLE buckets (
                    tier INTEGER NOT NULL, series TEXT NOT NULL, start REAL NOT NULL,
                    sum REAL NOT NULL, count INTEGER NOT NULL, max REAL NOT NULL, max_t REAL NOT NULL,
                    PRIMARY KEY (tier, series, start)
                ) WITHOUT ROWID;
                """)
        }

        let history = try MetricsHistory(.file(url))
        try record([0.4], every: 2, into: history)

        #expect(try history.summary(.cpuTotal, over: .oneMinute, endingAt: clock.now).points.map(\.value) == [0.4])
    }

    @Test func historySurvivesReopening() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("monimac-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("History.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        do {
            let history = try MetricsHistory(.file(url))
            try record([0.4, 0.6], every: 2, into: history)
        }
        let reopened = try MetricsHistory(.file(url))

        let summary = try reopened.summary(.cpuTotal, over: .oneMinute, endingAt: clock.now)
        #expect(summary.points.map(\.value) == [0.4, 0.6])
    }
}
