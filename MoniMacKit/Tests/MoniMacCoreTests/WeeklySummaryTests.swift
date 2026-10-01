import Foundation
import Testing
@testable import MoniMacCore

@MainActor
struct WeeklySummaryTests {
    static let gib: UInt64 = 1 << 30
    static let utc = TimeZone(identifier: "UTC")!
    /// Thursday 1 Oct 2026, 12:00 UTC, on a 15-minute boundary.
    let now = ISO8601DateFormatter().date(from: "2026-10-01T12:00:00Z")!
    let mac = SystemInfo(chipName: "Apple M3 Pro", performanceCores: 6, efficiencyCores: 6, bootTime: nil,
                         modelName: "MacBook Pro")
    let xcode = "/Applications/Xcode.app/Contents/MacOS/Xcode"
    let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

    /// What one canned sample looks like; every field can vary with the sample's time.
    struct Sample {
        var cpu = 0.32
        var busiest = "/Applications/Xcode.app/Contents/MacOS/Xcode"
        var gpu = 0.18
        var memory = 0.3
        var pressure: MemoryPressureLevel = .normal
        var thermal: ThermalState? = .nominal
        var downloaded = 1e8
        var uploaded = 1e7
        var battery: Reading<BatteryReading> = .value(BatteryReading(
            charge: 0.8, isPluggedIn: true, isCharging: false, designCapacity: 5000, maxCapacity: 4700, cycleCount: 212))
    }

    func snapshot(at time: Date, _ sample: Sample) -> Snapshot {
        let total = 36 * Self.gib
        return Snapshot(
            timestamp: time,
            system: mac,
            cpu: .cpu(user: sample.cpu * 0.7, system: sample.cpu * 0.3),
            processes: .value([ProcessSample(pid: 1, name: "app", path: sample.busiest, cpu: 2, isRegularApp: true)]),
            memory: .value(MemoryReading(
                total: total, app: UInt64(sample.memory * Double(total)), wired: 0, compressed: 0,
                compressedOriginal: 0, cached: 0, pressureLevel: sample.pressure, pressure: 0.2, swap: nil)),
            gpu: .value(GPUReading(model: "Apple M3 Pro", coreCount: 18, utilization: sample.gpu)),
            network: .value(NetworkReading(interface: nil, downloadPerSecond: sample.downloaded / 900,
                                           uploadPerSecond: sample.uploaded / 900,
                                           received: sample.downloaded, sent: sample.uploaded)),
            battery: sample.battery,
            thermal: sample.thermal.map {
                .value(ThermalReading(state: $0, sensors: .unavailable(.unsupported), fans: .unavailable(.unsupported)))
            } ?? .unavailable(.unsupported)
        )
    }

    /// A sample every 15 minutes over the last `duration`, ending at `now`. `vary` gets each sample's index.
    func history(
        covering duration: TimeInterval, _ vary: (Int, inout Sample) -> Void = { _, _ in }
    ) throws -> (MetricsHistory, Snapshot) {
        let history = try MetricsHistory(.inMemory)
        let count = Int(duration / 900) + 1
        var last: Snapshot?
        for index in 0..<count {
            var sample = Sample()
            vary(index, &sample)
            let snapshot = snapshot(at: now.addingTimeInterval(-Double(count - 1 - index) * 900), sample)
            try history.record(snapshot)
            last = snapshot
        }
        return (history, last!)
    }

    /// A full week, plus two hours before it so history is older than the window.
    func week(_ vary: (Int, inout Sample) -> Void = { _, _ in }) throws -> (MetricsHistory, Snapshot) {
        try history(covering: 7 * 86400 + 2 * 3600, vary)
    }

    func summary(
        _ history: MetricsHistory, _ snapshot: Snapshot?, mode: CPUMode = .system, hasBattery: Bool = true
    ) -> WeeklySummary {
        WeeklySummary.make(snapshot: snapshot, history: history, mode: mode, hasBattery: hasBattery, now: now,
                           timeZone: Self.utc)
    }

    // MARK: A full week

    @Test func fullWeekCoversSevenDays() throws {
        let (history, latest) = try week()
        let card = summary(history, latest)

        #expect(card.coversWindow)
        #expect(card.period == "LAST 7 DAYS · 24 SEP – 1 OCT 2026")
        #expect(card.device == "MacBook Pro · M3 Pro · 36 GB")
        #expect(card.figures.uptimeHours == 168)
        #expect(card.headline == "Busy week, cool head.")
        #expect(card.summary == "168 hours of uptime, zero thermal throttling, and Xcode doing most of the heavy lifting.")
        // Shares are drawn as they are: a steady 32% week is a row of one-third bars, not a maxed-out one.
        let cpu = try #require(card.tiles.first)
        #expect(cpu.bars.allSatisfy { abs(($0 ?? 0) - 0.32) < 1e-9 })
        // Network has no capacity, so the busiest bar is full height.
        let network = try #require(card.tiles.first { $0.kind == .network })
        #expect(network.bars.compactMap { $0 }.max() == 1)
    }

    @Test func tilesShowTheWeeksFigures() throws {
        let (history, latest) = try week { index, sample in
            if index == 300 { sample.cpu = 0.94; sample.gpu = 0.71; sample.pressure = .warning }
        }
        let card = summary(history, latest)
        let tiles = Dictionary(uniqueKeysWithValues: card.tiles.map { ($0.kind, $0) })

        #expect(card.tiles.map(\.kind) == [.cpu, .memory, .gpu, .network, .battery])
        #expect(tiles[.cpu]?.value == "32%")
        #expect(tiles[.cpu]?.caption == "avg · peak 94%")
        #expect(tiles[.memory]?.value == "10.8 GB")
        #expect(tiles[.memory]?.caption == "of 36 GB · pressure warning")
        #expect(tiles[.gpu]?.value == "18%")
        #expect(tiles[.gpu]?.caption == "avg · peak 71%")
        #expect(tiles[.battery]?.value == "94%")
        #expect(tiles[.battery]?.caption == "health · 212 cycles")
        #expect(card.tiles.allSatisfy { $0.bars.count == WeeklySummary.sparklineBarCount })
        #expect(card.tiles.allSatisfy { $0.bars.allSatisfy { ($0 ?? 0) >= 0 && ($0 ?? 0) <= 1 } })
    }

    @Test func networkTotalsTheWeek() throws {
        let (history, latest) = try week()
        let card = summary(history, latest)
        let downloaded = try #require(card.figures.downloaded)
        let uploaded = try #require(card.figures.uploaded)

        // 7 days of 15-minute samples, each 100 MB down and 10 MB up, within one sample at either end.
        #expect(abs(downloaded - 672 * 1e8) <= 1e8)
        #expect(abs(uploaded - 672 * 1e7) <= 1e7)
        let network = try #require(card.tiles.first { $0.kind == .network })
        #expect(network.value == NetworkFormat.bytes(downloaded))
        #expect(network.caption == "down · \(NetworkFormat.bytes(uploaded)) up")
    }

    @Test func cpuFollowsTheCPUMode() throws {
        let (history, latest) = try week()
        let card = summary(history, latest, mode: .perCore)

        // 32% of 12 cores.
        #expect(card.tiles.first?.value == "384%")
    }

    @Test func batteryTileIsLeftOutWithoutABattery() throws {
        let (history, latest) = try week { _, sample in sample.battery = .unavailable(.unsupported) }
        let card = summary(history, latest, hasBattery: false)

        #expect(card.tiles.map(\.kind) == [.cpu, .memory, .gpu, .network])
    }

    // MARK: Less than a week

    @Test func partialHistoryStatesTheRangeItCovers() throws {
        let (history, latest) = try history(covering: 52 * 3600)
        let card = summary(history, latest)

        #expect(!card.coversWindow)
        #expect(card.period == "LAST 2 DAYS 4 HOURS · 29 SEP – 1 OCT 2026")
        #expect(card.figures.uptimeHours == 52)
        #expect(card.summary.hasPrefix("52 hours of uptime"))
        // The sparklines span what's covered, so they start with data rather than five empty days.
        let cpu = try #require(card.tiles.first)
        #expect(cpu.bars.allSatisfy { $0 != nil })
    }

    @Test func underADayTalksAboutTheDay() throws {
        let (history, latest) = try history(covering: 3 * 3600)
        let card = summary(history, latest)

        #expect(card.period == "LAST 3 HOURS · 1 OCT 2026")
        #expect(card.headline == "Busy day, cool head.")
        #expect(card.busiestLine == "Busiest app: Xcode · top CPU user in 3 of 3 hours")
    }

    @Test func noHistoryYet() throws {
        let card = summary(try MetricsHistory(.inMemory), nil)

        #expect(card.period == "NO HISTORY YET · 1 OCT 2026")
        #expect(card.headline == "Just getting started.")
        #expect(card.busiestLine == nil)
        #expect(card.device == "Mac")
        #expect(card.tiles.allSatisfy { $0.bars.allSatisfy { $0 == nil } })
        #expect(card.tiles.first?.value == Format.placeholder)
    }

    // MARK: Throttling

    @Test func throttlingCountsSeparateSpells() throws {
        // Three spells: an hour, 30 minutes, and 15 minutes on different days.
        let (history, latest) = try week { index, sample in
            if (100..<104).contains(index) || (400..<402).contains(index) || index == 600 { sample.thermal = .serious }
        }
        let card = summary(history, latest)

        #expect(card.figures.throttlingEvents == 3)
        #expect(card.headline == "Busy week, running hot.")
        #expect(card.summary.contains("3 throttling events"))
    }

    @Test func fairIsNotThrottling() throws {
        let (history, latest) = try week { _, sample in sample.thermal = .fair }

        #expect(summary(history, latest).figures.throttlingEvents == 0)
    }

    @Test func throttlingIsLeftOutWhenTheThermalStateIsntReported() throws {
        let (history, latest) = try week { _, sample in sample.thermal = nil }
        let card = summary(history, latest)

        #expect(card.figures.throttlingEvents == nil)
        #expect(card.headline == "A busy week.")
        #expect(card.summary == "168 hours of uptime and Xcode doing most of the heavy lifting.")
    }

    @Test func spellsAreSplitByGapsInHistory() {
        let start = now
        // A spell over two buckets, a cool bucket, a spell, then the Mac sleeps and wakes up throttled.
        let offsets: [TimeInterval] = [0, 900, 1800, 2700, 2700 + 8 * 3600, 2700 + 8 * 3600 + 900]
        let values: [Double] = [1, 0.5, 0, 1, 1, 1]
        let points = zip(offsets, values).map { SeriesPoint(time: start.addingTimeInterval($0), value: $1) }

        #expect(WeeklySummary.throttlingEvents(points) == 3)
        #expect(WeeklySummary.throttlingEvents([]) == nil)
    }

    @Test func throttlingIsRecordedWithoutSensors() {
        let throttled = snapshot(at: now, Sample(thermal: .critical)).thermalSeries
        #expect(throttled.contains(SeriesSample(.thermalThrottled, 1)))
        let cool = snapshot(at: now, Sample(thermal: .nominal)).thermalSeries
        #expect(cool.contains(SeriesSample(.thermalThrottled, 0)))
    }

    // MARK: Busiest app

    @Test func busiestAppIsMostOftenBehindTheHourlyPeak() throws {
        // The window starts at sample 8, four samples an hour. Chrome is busiest two hours in three.
        let (history, latest) = try week { index, sample in
            if (index - 8) / 4 % 3 != 0 { sample.busiest = chrome }
        }
        let card = summary(history, latest)

        #expect(card.figures.busiestApp == "Google Chrome")
        #expect(card.figures.busiestHours == 112)
        #expect(card.figures.hoursWithCPU == 168)
        #expect(card.busiestLine == "Busiest app: Google Chrome · top CPU user in 112 of 168 hours")
    }

    // MARK: Headline rules

    nonisolated static func figures(
        cpu: Double? = 0.15, throttling: Int? = 0, gpu: Double? = 0.05, pressure: MemoryPressureLevel? = .normal,
        downloaded: Double? = 1e9, covered: TimeInterval = 7 * 86400
    ) -> WeeklySummary.Figures {
        var figures = WeeklySummary.Figures()
        (figures.cpuAverage, figures.throttlingEvents, figures.gpuAverage) = (cpu, throttling, gpu)
        (figures.memoryPressure, figures.downloaded, figures.covered) = (pressure, downloaded, covered)
        return figures
    }

    @Test(arguments: [
        (figures(covered: 0), WeeklySummaryHeadline.noHistory, "Just getting started."),
        (figures(cpu: 0.4, throttling: 3), .busyAndHot, "Busy week, running hot."),
        (figures(throttling: 3), .hot, "A warm week."),
        (figures(cpu: 0.4), .busyAndCool, "Busy week, cool head."),
        // A couple of spells is "low thermal events": still a cool head.
        (figures(cpu: 0.4, throttling: 2), .busyAndCool, "Busy week, cool head."),
        (figures(cpu: 0.4, throttling: nil), .busy, "A busy week."),
        (figures(pressure: .critical), .memoryTight, "Memory ran tight."),
        (figures(gpu: 0.3), .graphics, "Pixels pushed all week."),
        (figures(downloaded: 60e9), .downloads, "Downloaded half the internet."),
        (figures(cpu: 0.05), .quiet, "A quiet week."),
        (figures(), .steady, "A steady week."),
        (figures(cpu: nil, throttling: nil, gpu: nil, pressure: nil, downloaded: nil), .steady, "A steady week."),
        (figures(cpu: 0.05, covered: 3600), .quiet, "A quiet day."),
    ])
    func headlineFollowsThePhraseTable(figures: WeeklySummary.Figures, rule: WeeklySummaryHeadline, headline: String) {
        #expect(WeeklySummaryHeadline.rule(for: figures) == rule)
        #expect(WeeklySummaryHeadline.pick(figures) == headline)
    }

    // MARK: Text

    @Test func datesSpanningAYearShowBothYears() {
        let start = ISO8601DateFormatter().date(from: "2026-12-28T10:00:00Z")!
        let end = ISO8601DateFormatter().date(from: "2027-01-04T10:00:00Z")!

        #expect(WeeklySummary.dates(start, end, timeZone: Self.utc) == "28 DEC 2026 – 4 JAN 2027")
    }

    @Test func durationsReadNaturally() {
        #expect(WeeklySummary.duration(86400) == "1 day")
        #expect(WeeklySummary.duration(86400 + 3600) == "1 day 1 hour")
        #expect(WeeklySummary.duration(5 * 3600 + 600) == "5 hours")
        #expect(WeeklySummary.duration(30) == "1 minute")
        #expect(WeeklySummary.duration(12 * 60) == "12 minutes")
    }

    @Test func deviceLineNamesModelChipAndMemory() {
        #expect(mac.deviceLine(memory: 36 * Self.gib) == "MacBook Pro · M3 Pro · 36 GB")
        let noModel = SystemInfo(chipName: "Apple M4", performanceCores: 4, efficiencyCores: 6, bootTime: nil)
        #expect(noModel.deviceLine(memory: 24 * Self.gib) == "Apple M4 · 24 GB")
        #expect(noModel.deviceLine(memory: nil) == "Apple M4")
    }

    // MARK: Monitor

    @Test func monitorSummarizesItsHistory() throws {
        let clock = TestClock(start: now.addingTimeInterval(-3600))
        let sampler = ScriptedSampler(clock: clock, script: [snapshot(at: clock.now, Sample())])
        let monitor = Monitor(
            sampler: sampler, history: try MetricsHistory(.inMemory),
            preferences: Preferences(defaults: UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!),
            actions: RecordingActions(), startedAt: clock.now)
        for _ in 0..<5 {
            monitor.tick()
            clock.advance(by: 900)
        }
        let card = monitor.weeklySummary()

        #expect(card.device == "MacBook Pro · M3 Pro · 36 GB")
        #expect(!card.coversWindow)
        #expect(card.period.hasPrefix("LAST 1 HOUR · "))
        #expect(card.tiles.map(\.kind).last == .battery)
    }
}
