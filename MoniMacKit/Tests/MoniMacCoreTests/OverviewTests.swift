import Foundation
import Testing
@testable import MoniMacCore

@MainActor
struct OverviewTests {
    let clock = TestClock()
    let preferences = Preferences(defaults: UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!)
    /// 12 cores. The chip name is generic so the thermal sensor table is the one ThermalDetailTests use.
    let mac = SystemInfo(chipName: "Mac", performanceCores: 6, efficiencyCores: 6, bootTime: nil)
    static let gib: UInt64 = 1 << 30

    // Paths for the design's sample apps.
    let xcode = "/Applications/Xcode.app/Contents/MacOS/Xcode"
    let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    let finalCut = "/Applications/Final Cut Pro.app/Contents/MacOS/Final Cut Pro"
    let safari = "/Applications/Safari.app/Contents/MacOS/Safari"
    let timeMachine = "/System/Library/CoreServices/backupd.bundle/Contents/Resources/backupd"
    let windowServer = "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"

    private func process(
        _ pid: Int32, _ path: String, cpu: Double = 0, regular: Bool = false, otherUser: Bool = false,
        _ resources: ResourceUse = ResourceUse()
    ) -> ProcessSample {
        ProcessSample(pid: pid, name: String(path.split(separator: "/").last!), path: path, cpu: cpu,
                      isRegularApp: regular, isOtherUser: otherUser, resources: resources)
    }

    /// Each sample app is busiest at a different resource.
    var designProcesses: [ProcessSample] {
        [
            // 12% of 12 cores.
            process(1, xcode, cpu: 1.44, regular: true, ResourceUse(memory: 900 << 20)),
            // 1.9 GB of 18 GB beats 2% CPU.
            process(2, chrome, cpu: 0.24, regular: true, ResourceUse(memory: UInt64(1.9 * Double(Self.gib)))),
            process(3, finalCut, cpu: 0.12, regular: true, ResourceUse(memory: 200 << 20, gpu: 0.12)),
            process(4, safari, cpu: 0.06, regular: true, ResourceUse(memory: 100 << 20, network: 3_200_000)),
            process(5, timeMachine, cpu: 0.06, otherUser: true,
                    ResourceUse(memory: 50 << 20, diskReadPerSecond: 1_400_000, diskWritePerSecond: 8_000_000)),
            process(6, windowServer, cpu: 0.36, otherUser: true, ResourceUse(memory: 100 << 20)),
            process(7, "/Applications/Rectangle.app/Contents/MacOS/Rectangle", ResourceUse(memory: 30 << 20)),
            process(8, "/usr/libexec/trustd", ResourceUse(memory: 10 << 20)),
            process(9, "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
                    ResourceUse(memory: 40 << 20)),
        ]
    }

    private func snapshot(
        processes: [ProcessSample]? = nil, battery: Reading<BatteryReading>? = nil, fans: Reading<[Fan]>? = nil
    ) -> Snapshot {
        Snapshot(
            timestamp: clock.now,
            system: mac,
            cpu: .cpu(user: 0.21, system: 0.11),
            taskCounts: .value(TaskCounts(processes: 1048, threads: 4212)),
            processes: .value(processes ?? designProcesses),
            memory: .value(MemoryReading(
                total: 18 * Self.gib, app: 8 * Self.gib, wired: 2 * Self.gib, compressed: Self.gib + Self.gib / 5,
                compressedOriginal: 0, cached: 0, pressureLevel: .normal, pressure: 0.3, swap: nil
            )),
            gpu: .value(GPUReading(model: "Apple M3 Pro", coreCount: 18, utilization: 0.18,
                                   memoryInUse: UInt64(2.1 * Double(Self.gib)))),
            network: .value(NetworkReading(interface: nil, downloadPerSecond: 4_200_000, uploadPerSecond: 380_000,
                                           received: 0, sent: 0)),
            disk: .value(DiskReading(
                volume: DiskVolume(name: "Macintosh HD", format: "APFS", capacity: 994_000_000_000,
                                   free: 312_000_000_000),
                io: .value(DiskIO(bytesRead: 0, bytesWritten: 24_000_000, interval: 2))
            )),
            battery: battery ?? .value(BatteryReading(
                charge: 0.84, isPluggedIn: true, isCharging: true, timeRemaining: .minutes(38)
            )),
            thermal: .value(ThermalReading(
                state: .nominal,
                sensors: .value([ThermalSensor(name: "Tp01", celsius: 56), ThermalSensor(name: "Te05", celsius: 48)]),
                fans: fans ?? .value([Fan(rpm: 2140, minimumRPM: 1200, maximumRPM: 6550)])
            ))
        )
    }

    private func monitor(_ script: [Snapshot]) throws -> Monitor {
        Monitor(sampler: ScriptedSampler(clock: clock, script: script), history: try MetricsHistory(.inMemory),
                preferences: preferences, actions: RecordingActions())
    }

    private func tile(_ metric: OverviewMetric, in tiles: OverviewTiles) -> OverviewTiles.Tile? {
        tiles.metricTiles.first { $0.metric == metric }
    }

    // MARK: Tiles

    @Test func tilesShowEachMetricsValueAndCaption() throws {
        let monitor = try monitor([snapshot()])
        monitor.tick()

        let tiles = monitor.overviewTiles()

        #expect(tiles.metricTiles.map(\.metric) == OverviewMetric.allCases)
        let figures = tiles.metricTiles.map { [$0.value, $0.caption] }
        #expect(figures == [
            ["32%", "User 21% · System 11%"],
            ["11.2 GB", "of 18 GB · Pressure normal"],
            ["18%", "2.1 GB VRAM · 1 app"],
            ["4.6 MB/s", "↓ 4.2 MB/s · ↑ 380 KB/s"],
            ["312 GB", "free of 994 GB · W 12 MB/s"],
            ["84%", "Charging · Full in 38 min"],
            ["52°C", "CPU die · Fan 2,140 rpm"],
        ])
    }

    @Test func perCoreModeAppliesToTheCPUTileAndBusiestLabels() throws {
        preferences.cpuMode = .perCore
        let monitor = try monitor([snapshot()])
        monitor.tick()

        let tiles = monitor.overviewTiles()

        #expect(tile(.cpu, in: tiles)?.value == "384%")
        #expect(tile(.cpu, in: tiles)?.caption == "User 252% · System 132%")
        #expect(tiles.busiest.first { $0.name == "Xcode" }?.value == "144% CPU")
        #expect(monitor.overviewPanel().rows.first?.value == "384%")
    }

    @Test func batteryIsHiddenOnMacsWithoutOne() throws {
        let monitor = try monitor([snapshot(battery: .unavailable(.unsupported))])
        monitor.tick()

        #expect(!monitor.overviewTiles().metricTiles.map(\.metric).contains(.battery))
        #expect(!monitor.overviewPanel().rows.map(\.metric).contains(.battery))
    }

    @Test func aBatteryThatFailedToReadStillShowsWhy() throws {
        let monitor = try monitor([snapshot(battery: .unavailable(.failed("IOKit error")))])
        monitor.tick()

        let battery = tile(.battery, in: monitor.overviewTiles())
        #expect(battery?.value == Format.placeholder)
        #expect(battery?.caption == "Battery unavailable: IOKit error")
    }

    @Test(arguments: [
        (BatteryReading(charge: 0.76, isPluggedIn: false, isCharging: false, timeRemaining: .minutes(252)),
         "On battery · 4 h 12 min remaining", "76% · 4:12 left"),
        (BatteryReading(charge: 1, isPluggedIn: true, isCharging: false, isFullyCharged: true),
         "Fully charged", "100% · Charged"),
        (BatteryReading(charge: 0.5, isPluggedIn: true, isCharging: true, timeRemaining: .calculating),
         "Charging · Calculating…", "50%"),
    ])
    func batteryStates(reading: BatteryReading, caption: String, row: String) throws {
        let monitor = try monitor([snapshot(battery: .value(reading))])
        monitor.tick()

        #expect(tile(.battery, in: monitor.overviewTiles())?.caption == caption)
        #expect(monitor.overviewPanel().rows.first { $0.metric == .battery }?.value == row)
    }

    @Test(arguments: [
        (Reading<[Fan]>.unavailable(.unsupported), "CPU die"),
        (.value([Fan(rpm: 0, minimumRPM: 0, maximumRPM: 6550)]), "CPU die · Fan off"),
        (.value([Fan(rpm: 2000, minimumRPM: 1200, maximumRPM: 6550), Fan(rpm: 2200, minimumRPM: 1200, maximumRPM: 6550)]),
         "CPU die · Fans 2,100 rpm"),
    ])
    func temperatureCaptionDescribesTheFans(fans: Reading<[Fan]>, caption: String) throws {
        let monitor = try monitor([snapshot(fans: fans)])
        monitor.tick()

        #expect(tile(.temperature, in: monitor.overviewTiles())?.caption == caption)
    }

    @Test func missingFiguresArePlaceholdersNotZero() throws {
        var bare = Snapshot(timestamp: clock.now, system: mac, cpu: .unavailable(.warmingUp),
                            gpu: .unavailable(.unsupported))
        bare.battery = .value(BatteryReading(charge: 0.5, isPluggedIn: false, isCharging: false))
        let monitor = try monitor([bare])
        monitor.tick()

        let tiles = monitor.overviewTiles()
        #expect(tile(.cpu, in: tiles)?.value == Format.placeholder)
        #expect(tile(.gpu, in: tiles)?.value == Format.placeholder)
        #expect(tile(.gpu, in: tiles)?.caption == "Not reported on this Mac")
        #expect(tile(.temperature, in: tiles)?.value == Format.placeholder)
        #expect(tiles.processes.value == Format.placeholder)
        #expect(tiles.processes.caption == Format.placeholder)
        let panel = monitor.overviewPanel()
        #expect(panel.rows.first { $0.metric == .gpu } == OverviewPanel.Row(metric: .gpu, value: Format.placeholder, share: nil))
        #expect(panel.busiest.isEmpty)
    }

    @Test func sparklinesComeFromHistory() throws {
        let monitor = try monitor([snapshot()])
        for _ in 0..<5 {
            monitor.tick()
            clock.advance(by: 2)
        }

        let tiles = monitor.overviewTiles()

        for tile in tiles.metricTiles {
            #expect(tile.bars.count == OverviewTiles.sparklineBarCount)
            #expect(tile.bars.last! != nil, "\(tile.metric) has no recent bar")
        }
        #expect(abs((tile(.cpu, in: tiles)?.bars.last ?? nil)! - 0.32) < 1e-9)
        #expect(abs((tile(.battery, in: tiles)?.bars.last ?? nil)! - 0.84) < 1e-9)
        // Throughput has no capacity: steady traffic fills the bar.
        #expect(tile(.network, in: tiles)?.bars.last! == 1)
    }

    // MARK: Processes

    @Test func processesTileSplitsAppsAgentsAndSystem() throws {
        let monitor = try monitor([snapshot()])
        monitor.tick()

        let processes = monitor.overviewTiles().processes

        // Xcode, Chrome, Final Cut, Safari; Rectangle; ControlCenter. Bare daemons (backupd, WindowServer,
        // trustd) count only as processes.
        #expect(processes.value == "6 apps")
        #expect(processes.groups.map(\.label) == ["4 apps", "1 agent", "1 system"])
        let shares: [Double] = [4.0 / 6, 1.0 / 6, 1.0 / 6]
        #expect(processes.groups.map(\.share) == shares)
        #expect(processes.caption == "1,048 processes · 4,212 threads")
        #expect(monitor.overviewTiles().showAll == "Show All 6 Apps")
    }

    // MARK: Busiest Right Now

    @Test func busiestLabelsEachAppByItsDominantResource() throws {
        let monitor = try monitor([snapshot()])
        monitor.tick()

        let busiest = monitor.overviewTiles().busiest
        let labels = Dictionary(uniqueKeysWithValues: busiest.map { ($0.name, [$0.resource.metric.title, $0.value]) })

        #expect(labels["Xcode"] == ["CPU", "12% CPU"])
        #expect(labels["Google Chrome"] == ["Memory", "1.9 GB"])
        #expect(labels["Final Cut Pro"] == ["GPU", "12% GPU"])
        #expect(labels["Safari"] == ["Network", "3.2 MB/s"])
        #expect(labels["backupd"] == ["Disk", "9.4 MB/s"])
        #expect(labels["WindowServer"] == ["CPU", "3% CPU"])
    }

    @Test func busiestRanksByScoreAndScalesBarsToTheTop() throws {
        let monitor = try monitor([snapshot()])
        monitor.tick()

        let busiest = monitor.overviewTiles().busiest

        // Scores: Safari 3.2 of 12.5 MB/s = 0.256; Xcode 12% CPU and Final Cut 12% GPU tie at 0.12, and ties keep
        // the CPU order; backupd 9.4 of 100 MB/s = 0.094; WindowServer 3% CPU; Chrome holds 1.9 of 18 GB = 0.026.
        #expect(busiest.prefix(6).map(\.name) == ["Safari", "Xcode", "Final Cut Pro", "backupd", "WindowServer", "Google Chrome"])
        #expect(busiest.first?.share == 1)
        #expect(abs(busiest[1].share - 0.12 / 0.256) < 1e-9)
        #expect(busiest.allSatisfy { $0.share > 0 && $0.share <= 1 })
        #expect(busiest.first?.help == "Safari: busiest at Network")
        let columns = monitor.overviewTiles().busiestColumns
        #expect(columns.map(\.count) == [5, 4])
        #expect(columns[1].first?.name == busiest[5].name)
    }

    @Test func anAppDoingWorkOutranksOneOnlyHoldingMemory() throws {
        // On 12 cores and 18 GB: half a core (4.2%) beats an idle app holding 1.9 GB (10.6%, counted at a quarter).
        let monitor = try monitor([snapshot(processes: [
            process(1, chrome, regular: true, ResourceUse(memory: UInt64(1.9 * Double(Self.gib)))),
            process(2, xcode, cpu: 0.5, regular: true, ResourceUse(memory: 100 << 20)),
        ])])
        monitor.tick()

        #expect(monitor.overviewTiles().busiest.map(\.name) == ["Xcode", "Google Chrome"])
    }

    @Test func groupsWithoutBundlesCountAsZeroAppsNotWarmingUp() {
        let daemon = AppUsage(id: "/usr/libexec/trustd", name: "trustd", processCount: 1, cpu: 0, kind: .system)

        let processes = OverviewTiles.processes(groups: [daemon], counts: nil)

        #expect(processes.value == "0 apps")
        #expect(processes.groups.map(\.label) == ["0 apps", "0 agents", "0 system"])
    }

    @Test func busiestListsAreCappedAndShowProcessCounts() throws {
        let helpers = (0..<3).map { ProcessSample(pid: 100 + $0, responsiblePID: 1, name: "Helper", path: nil, cpu: 0.1) }
        let many = designProcesses + helpers + (0..<12).map {
            process(200 + Int32($0), "/opt/tool\($0)", ResourceUse(memory: 1 << 20))
        }
        let monitor = try monitor([snapshot(processes: many)])
        monitor.tick()

        #expect(monitor.overviewTiles().busiest.count == OverviewTiles.busiestCount)
        let panel = monitor.overviewPanel()
        #expect(panel.busiest.count == OverviewPanel.busiestCount)
        #expect(panel.busiest.first { $0.name == "Xcode" }?.processes == "4 processes")
        #expect(panel.busiest.first { $0.name == "Safari" }?.processes == "1 process")
    }

    // MARK: Popover

    @Test func popoverRowsShowEveryMetricWithABar() throws {
        let monitor = try monitor([snapshot()])
        monitor.tick()

        let rows = monitor.overviewPanel().rows

        #expect(rows.map(\.value) == [
            "32%", "11.2 / 18 GB", "18%", "↓ 4.2 MB/s  ↑ 380 KB/s", "682 / 994 GB", "84% · 0:38 to full", "52 °C",
        ])
        let shares = rows.map(\.share)
        #expect(shares[0] == 0.32)
        #expect(abs(shares[1]! - 11.2 / 18) < 1e-9)
        #expect(shares[2] == 0.18)
        // The only traffic seen is the current traffic, so it is the recent peak.
        #expect(shares[3] == 1)
        #expect(abs(shares[4]! - 682.0 / 994) < 1e-9)
        #expect(shares[5] == 0.84)
        #expect(shares[6] == 0.4)
    }

    @Test func usedOfTotalKeepsBothUnitsWhenTheyDiffer() {
        #expect(OverviewPanel.usedOfTotal(("512", "MB"), ("1", "TB")) == "512 MB / 1 TB")
        #expect(OverviewPanel.usedOfTotal(("412", "GB"), ("994", "GB")) == "412 / 994 GB")
    }

    @Test func subtitleNamesTheChipAndMemory() throws {
        let monitor = try monitor([snapshot()])
        #expect(monitor.overviewSubtitle == nil)
        monitor.tick()

        #expect(monitor.overviewSubtitle == "Mac · 18 GB")
    }
}
