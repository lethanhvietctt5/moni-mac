import Foundation
import Testing
@testable import MoniMacCore

private let gb: UInt64 = 1 << 30
private let mb: UInt64 = 1 << 20

/// The design's sample Mac: 18 GB, 11.4 GB used.
private func designMemory(
    pressureLevel: MemoryPressureLevel? = .normal, pressure: Double? = 0.24,
    swap: MemoryReading.Swap? = .init(used: 512 * mb, total: 2 * gb)
) -> MemoryReading {
    MemoryReading(
        total: 18 * gb, app: 68 * gb / 10, wired: 23 * gb / 10, compressed: 23 * gb / 10,
        compressedOriginal: 59 * gb / 10, cached: 49 * gb / 10,
        pressureLevel: pressureLevel, pressure: pressure, swap: swap
    )
}

@MainActor
struct MemoryDetailTests {
    let utc = TimeZone(identifier: "UTC")!
    /// 2026-10-01 09:41 UTC.
    let now = Date(timeIntervalSince1970: 1_790_847_660)

    let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    let renderer = "/Applications/Google Chrome.app/Contents/Frameworks/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
    let xcode = "/Applications/Xcode.app/Contents/MacOS/Xcode"
    let windowServer = "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"

    private func snapshot(
        at time: Date, memory: MemoryReading = designMemory(), processes: [ProcessSample] = []
    ) -> Snapshot {
        Snapshot(timestamp: time, cpu: .cpu(user: 0.2, system: 0.1), processes: .value(processes), memory: .value(memory))
    }

    private func detail(
        history snapshots: [Snapshot] = [], latest: Snapshot, range: TimeRange = .twentyFourHours,
        layout: MemoryDetail.Layout = .window
    ) throws -> MemoryDetail {
        let history = try MetricsHistory(.inMemory)
        for snapshot in snapshots { try history.record(snapshot) }
        return MemoryDetail.make(
            snapshot: latest, apps: AppGrouping.apps(from: latest.processes.value ?? []), history: history,
            range: range, layout: layout, timeZone: utc
        )
    }

    @Test func headlineMatchesTheDesign() throws {
        let detail = try detail(latest: snapshot(at: now))

        #expect(detail.subtitle == "18 GB unified memory")
        #expect(detail.used == "11.4")
        #expect(detail.usedUnit == "GB")
        #expect(detail.total == "18 GB")
        #expect(abs(detail.usedShare - 11.4 / 18) < 0.001)
    }

    @Test func cardsShowPressureSwapAndCompression() throws {
        let detail = try detail(latest: snapshot(at: now))

        #expect([detail.pressure.label, detail.pressure.value, detail.pressure.detail]
            == ["Memory Pressure", "Normal", "24% · no throttling"])
        #expect(detail.pressureLevel == .normal)
        #expect([detail.swap.label, detail.swap.value, detail.swap.detail] == ["Swap Used", "512 MB", "of 2 GB swap file"])
        #expect([detail.compression.label, detail.compression.value, detail.compression.detail]
            == ["Compression", "2.6×", "5.9 GB → 2.3 GB"])
    }

    @Test(arguments: [
        (MemoryPressureLevel.normal, "Normal", "no throttling"),
        (.warning, "Warning", "some throttling"),
        (.critical, "Critical", "heavy throttling"),
    ])
    func pressureCardFollowsTheKernelLevel(level: MemoryPressureLevel, value: String, state: String) throws {
        let detail = try detail(latest: snapshot(at: now, memory: designMemory(pressureLevel: level, pressure: 0.6)))

        #expect(detail.pressure.value == value)
        #expect(detail.pressure.detail == "60% · \(state)")
        #expect(detail.pressureLevel == level)
    }

    @Test func unreadablePressureAndSwapShowPlaceholders() throws {
        let detail = try detail(latest: snapshot(at: now, memory: designMemory(pressureLevel: nil, pressure: nil, swap: nil)))

        #expect(detail.pressure.value == "—")
        #expect(detail.pressure.detail == "—")
        #expect(detail.pressureLevel == nil)
        #expect(detail.swap.value == "—")
    }

    @Test func breakdownAddsUpToInstalledMemory() throws {
        let latest = snapshot(at: now, processes: [
            ProcessSample(pid: 1, name: "Google Chrome", path: chrome, cpu: 0.1, resources: ResourceUse(memory: 900 * mb)),
            ProcessSample(pid: 2, name: "Xcode", path: xcode, cpu: 0.1, resources: ResourceUse(memory: 1 * gb)),
            ProcessSample(pid: 3, name: "WindowServer", path: windowServer, cpu: 0.1, resources: ResourceUse(memory: 300 * mb)),
        ])

        let breakdown = try detail(latest: latest).breakdown

        #expect(breakdown.map(\.label) == ["App Memory", "Wired", "Compressed", "Cached Files", "Free"])
        #expect(breakdown.map(\.value) == ["6.8 GB", "2.3 GB", "2.3 GB", "4.9 GB", "1.7 GB"])
        #expect(breakdown.map(\.detail) == [
            "Used by 2 apps", "Kernel, can't page out", "Saved 3.6 GB", "Reclaimable", "Available now",
        ])
        #expect(abs(breakdown.map(\.share).reduce(0, +) - 1) < 1e-9)
    }

    @Test func freeIsNeverNegative() {
        let overcounted = MemoryReading(
            total: 8 * gb, app: 5 * gb, wired: 2 * gb, compressed: 1 * gb, compressedOriginal: 2 * gb, cached: 1 * gb,
            pressureLevel: .normal, pressure: 0.5, swap: nil
        )

        #expect(overcounted.free == 0)
        #expect(overcounted.usedFraction == 1)
    }

    /// Bars are as tall as the pressure and colored by the kernel's level, not by their height.
    @Test func pressureHistoryColorsBucketsByLevel() throws {
        let samples: [(Double, MemoryPressureLevel)] = [
            (0.55, .normal), (0.3, .warning), (0.7, .warning), (0.8, .critical), (0.4, .normal),
        ]
        // One sample per bar slot of the last minute, oldest first.
        let history = samples.enumerated().map { index, sample in
            snapshot(at: now.addingTimeInterval(-Double(samples.count - 1 - index) * 2),
                     memory: designMemory(pressureLevel: sample.1, pressure: sample.0))
        }

        let bars = try detail(history: history, latest: snapshot(at: now), range: .oneMinute, layout: .popover).history

        #expect(bars.count == MemoryDetail.historyBarCount)
        #expect(bars.suffix(5).map { $0?.level } == samples.map(\.1))
        #expect(bars.suffix(5).map { $0?.value } == samples.map(\.0))
        #expect(bars.dropLast(5).allSatisfy { $0 == nil })
    }

    /// A long-range bar averages the pressure over its span but shows the worst level in it, so a spike isn't lost.
    @Test(arguments: [
        ([MemoryPressureLevel.normal, .normal, .normal], MemoryPressureLevel.normal),
        ([.normal, .warning, .normal], .warning),
        ([.normal, .normal, .critical], .critical),
        ([.warning, .critical, .warning], .critical),
    ])
    func longRangeBarsShowTheWorstLevel(levels: [MemoryPressureLevel], worst: MemoryPressureLevel) throws {
        // All within the minute before `now`, so one bucket.
        let history = zip([-30.0, -20, -10], zip(levels, [0.6, 0.9, 0.9])).map { offset, sample in
            snapshot(at: now.addingTimeInterval(offset), memory: designMemory(pressureLevel: sample.0, pressure: sample.1))
        }

        let last = try #require(try detail(history: history, latest: snapshot(at: now)).history.last ?? nil)

        #expect(abs(last.value - 0.8) < 1e-9)
        #expect(last.level == worst)
    }

    @Test(arguments: [
        (TimeRange.twentyFourHours, ["09:00", "15:00", "21:00", "03:00", "Now"]),
        (.sevenDays, ["Thu", "Sat", "Sun", "Tue", "Now"]),
    ])
    func xAxisSpansTheRange(range: TimeRange, labels: [String]) throws {
        #expect(try detail(latest: snapshot(at: now), range: range).xAxis == labels)
    }

    @Test func topAppsAreGroupedAndSortedByMemory() throws {
        let latest = snapshot(at: now, processes: [
            ProcessSample(pid: 10, name: "Xcode", path: xcode, cpu: 2.0, isRegularApp: true,
                          resources: ResourceUse(memory: 1 * gb)),
            ProcessSample(pid: 20, name: "Google Chrome", path: chrome, cpu: 0.1, isRegularApp: true,
                          resources: ResourceUse(memory: 800 * mb)),
            ProcessSample(pid: 21, responsiblePID: 20, name: "Google Chrome Helper (Renderer)", path: renderer, cpu: 0.1,
                          resources: ResourceUse(memory: 1100 * mb)),
            ProcessSample(pid: 30, name: "WindowServer", path: windowServer, cpu: 0.5, resources: ResourceUse(memory: 210 * mb)),
            ProcessSample(pid: 40, name: "mystery", path: nil, cpu: 0.0),
        ])

        let rows = try detail(latest: latest).topApps

        #expect(rows.map(\.name) == ["Google Chrome", "Xcode", "WindowServer"])
        #expect(rows.map(\.value) == ["1.9 GB", "1 GB", "210 MB"])
        #expect(rows.map(\.canQuit) == [true, true, false])
        #expect(abs(rows[0].share - 1900.0 / 1024 / 18) < 1e-9)
    }

    @Test func popoverShowsFewerApps() throws {
        let processes = (0..<10).map {
            ProcessSample(pid: Int32($0), name: "app\($0)", path: "/usr/bin/app\($0)", cpu: 0,
                          resources: ResourceUse(memory: UInt64($0 + 1) * mb))
        }

        #expect(try detail(latest: snapshot(at: now, processes: processes), layout: .popover).topApps.count == 4)
        #expect(try detail(latest: snapshot(at: now, processes: processes), layout: .window).topApps.count == 8)
    }

    @Test func placeholdersBeforeTheFirstSample() throws {
        let detail = MemoryDetail.make(snapshot: nil, apps: [], history: try MetricsHistory(.inMemory),
                                       range: .twentyFourHours, layout: .window)

        #expect(detail.used == "—")
        #expect(detail.pressure.value == "—")
        #expect(detail.compression.value == "—")
        #expect(detail.breakdown.isEmpty)
        #expect(detail.history.allSatisfy { $0 == nil })
        #expect(detail.xAxis.isEmpty)
    }
}

@MainActor
struct MemoryMonitorTests {
    let clock = TestClock()
    let preferences = Preferences(defaults: UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!)

    private func monitor(_ memory: Reading<MemoryReading>, processes: [ProcessSample] = []) throws -> (Monitor, MetricsHistory) {
        let history = try MetricsHistory(.inMemory)
        let snapshot = Snapshot(timestamp: clock.now, cpu: .cpu(user: 0.1, system: 0.1), processes: .value(processes),
                                memory: memory)
        let monitor = Monitor(sampler: ScriptedSampler(clock: clock, script: [snapshot]), history: history,
                              preferences: preferences, actions: RecordingActions())
        return (monitor, history)
    }

    @Test func menuBarItemShowsUsedMemoryAlongsideCPU() throws {
        let (monitor, _) = try monitor(.value(designMemory()))
        monitor.setMenuBarItemEnabled(true, for: .memory)
        monitor.setMenuBarStyle(.both, for: .memory)
        monitor.tick()

        #expect(monitor.menuBarItems.map(\.metric) == [.cpu, .memory])
        let item = try #require(monitor.menuBarItems.last)
        #expect(item.text == "11.4 GB")
        #expect(item.widestText == "88.8 GB")
        #expect(item.bars.count == Sparkline.barCount)
        #expect(abs((item.bars.last ?? nil).map { $0 - 11.4 / 18 } ?? 1) < 0.001)
    }

    @Test func menuBarShowsAPlaceholderWithoutAReading() throws {
        let (monitor, _) = try monitor(.unavailable(.failed("host_statistics64 failed")))
        monitor.setMenuBarItemEnabled(true, for: .memory)
        monitor.tick()

        #expect(monitor.menuBarItems.last?.text == "—")
        #expect(monitor.memorySubtitle == nil)
    }

    @Test func recordsUsedAndPressureWithTheBiggestApp() throws {
        let xcode = ProcessSample(pid: 1, name: "Xcode", path: "/Applications/Xcode.app/Contents/MacOS/Xcode", cpu: 0,
                                  resources: ResourceUse(memory: 3 * gb))
        let small = ProcessSample(pid: 2, name: "zsh", path: "/bin/zsh", cpu: 1, resources: ResourceUse(memory: 4 * mb))
        let (monitor, history) = try monitor(.value(designMemory(pressure: 0.3)), processes: [small, xcode])
        monitor.tick()

        let pressure = try history.summary(.memoryPressure, over: .oneMinute, endingAt: clock.now)
        #expect(pressure.points.map(\.value) == [0.3])
        let used = try history.summary(.memoryUsed, over: .oneMinute, endingAt: clock.now)
        #expect(used.peak?.contributor == "Xcode")
        #expect(monitor.memorySubtitle == "18 GB unified memory")
        #expect(monitor.memoryDetail(range: .twentyFourHours).layout == .window)
        #expect(monitor.memoryPanel(range: .fiveMinutes).layout == .popover)
    }

    @Test func noPressureSampleWhenPressureIsUnreadable() throws {
        let (monitor, history) = try monitor(.value(designMemory(pressureLevel: nil, pressure: nil)))
        monitor.tick()

        #expect(try history.summary(.memoryPressure, over: .oneMinute, endingAt: clock.now).points.isEmpty)
        #expect(try history.summary(.memoryUsed, over: .oneMinute, endingAt: clock.now).points.count == 1)
    }
}

struct MemoryFormatTests {
    static let sizes: [(UInt64, String)] = [
        (18 * gb, "18 GB"), (11_400 * mb, "11.1 GB"), (11_674 * mb, "11.4 GB"), (512 * mb, "512 MB"),
        (210 * mb, "210 MB"), (999 * mb, "999 MB"), (1000 * mb, "1 GB"), (25_769_803_776, "24 GB"),
        (128 * gb, "128 GB"), (102_298 * mb, "99.9 GB"), (0, "0 MB"),
    ]

    @Test(arguments: sizes)
    func usesBinaryUnits(bytes: UInt64, text: String) {
        #expect(Format.memorySize(bytes) == text)
    }

    /// The menu bar item is sized for its widest text; no Mac's used memory may exceed it.
    @Test func neverWiderThanTheMenuBarItem() {
        let widest = MemoryMenuBar.widestText(preferences: Preferences(defaults: UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!))
        for gigabytes in stride(from: 0.0, through: 512, by: 0.05) {
            #expect(Format.memorySize(UInt64(gigabytes * Double(gb))).count <= widest.count)
        }
    }
}
