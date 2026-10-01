import Foundation
import Testing
@testable import MoniMacCore

@MainActor
struct OverviewListTests {
    let clock = TestClock()
    let preferences = Preferences(defaults: UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!)
    let actions = RecordingActions()
    /// 12 cores.
    let mac = SystemInfo(chipName: "Apple M3 Pro", performanceCores: 6, efficiencyCores: 6, bootTime: nil)

    static let xcode = "/Applications/Xcode.app/Contents/MacOS/Xcode"
    static let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    static let chromeHelpers = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers"
    static let renderer = "\(chromeHelpers)/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
    static let gpuHelper = "\(chromeHelpers)/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU)"
    static let safari = "/Applications/Safari.app/Contents/MacOS/Safari"
    static let windowServer = "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"
    static let backupd = "/System/Library/CoreServices/backupd.bundle/Contents/Resources/backupd"
    static let trustd = "/usr/libexec/trustd"

    static func process(
        _ pid: Int32, _ path: String, responsible: Int32? = nil, cpu: Double, regular: Bool = false,
        otherUser: Bool = false, _ resources: ResourceUse = ResourceUse()
    ) -> ProcessSample {
        ProcessSample(pid: pid, responsiblePID: responsible, name: String(path.split(separator: "/").last!),
                      path: path, cpu: cpu, isRegularApp: regular, isOtherUser: otherUser, resources: resources)
    }

    /// Three apps (Xcode, Chrome with five helpers, Safari) and three bare daemons: 11 processes.
    static let processes: [ProcessSample] = [
        process(1, xcode, cpu: 1.44, regular: true, ResourceUse(memory: 900 << 20, power: 6.1)),
        process(2, chrome, cpu: 0.24, regular: true, ResourceUse(memory: 800 << 20, network: 10_000, power: 1)),
        process(4, safari, cpu: 0.06, regular: true, ResourceUse(memory: 300 << 20, network: 3_200_000)),
        process(5, backupd, cpu: 0.03, otherUser: true,
                ResourceUse(memory: 50 << 20, diskReadPerSecond: 1_400_000, diskWritePerSecond: 8_000_000)),
        process(6, windowServer, cpu: 0.36, otherUser: true, ResourceUse(memory: 100 << 20, gpu: 0.031)),
        process(8, trustd, cpu: 0, ResourceUse(memory: 10 << 20)),
    ] + (10...13).map { process($0, renderer, responsible: 2, cpu: 0.12, ResourceUse(memory: 100 << 20)) }
        + [process(14, gpuHelper, responsible: 2, cpu: 0.06, ResourceUse(gpu: 0.003))]

    private func snapshot(processes: Reading<[ProcessSample]> = .value(processes)) -> Snapshot {
        Snapshot(
            timestamp: clock.now,
            system: mac,
            cpu: .cpu(user: 0.21, system: 0.11),
            processes: processes,
            memory: .value(MemoryReading(
                total: 18 << 30, app: 8 << 30, wired: 2 << 30, compressed: (1 << 30) + (1 << 30) / 5,
                compressedOriginal: 0, cached: 0, pressureLevel: .normal, pressure: 0.3, swap: nil
            )),
            gpu: .value(GPUReading(model: "Apple M3 Pro", coreCount: 18, utilization: 0.18, memoryInUse: nil)),
            network: .value(NetworkReading(interface: nil, downloadPerSecond: 4_200_000, uploadPerSecond: 380_000,
                                           received: 0, sent: 0)),
            battery: .value(BatteryReading(charge: 0.84, isPluggedIn: true, isCharging: false, systemPower: 38))
        )
    }

    private func monitor(_ snapshot: Snapshot? = nil) throws -> Monitor {
        let monitor = Monitor(sampler: ScriptedSampler(clock: clock, script: [snapshot ?? self.snapshot()]),
                              history: try MetricsHistory(.inMemory), preferences: preferences, actions: actions)
        monitor.tick()
        return monitor
    }

    private func names(_ list: OverviewList) -> [String] { list.rows.map(\.name) }

    // MARK: Rows and sorting

    @Test func groupsByAppBusiestCPUFirstWithEveryFigure() throws {
        let list = try monitor().overviewList(OverviewListQuery())

        #expect(names(list) == ["Xcode", "Google Chrome", "WindowServer", "Safari", "backupd", "trustd"])
        #expect(list.sortLabel == "Sorted by CPU")
        let chrome = try #require(list.rows.first { $0.name == "Google Chrome" })
        #expect(chrome.kind == .app)
        #expect(chrome.isExpandable && !chrome.isExpanded && chrome.canQuit)
        #expect(chrome.values == [.processes: "6", .cpu: "6.5%", .memory: "1.2 GB", .gpu: "0.3%",
                                  .network: "10 KB/s", .power: "1.0 W"])
        let backupd = try #require(list.rows.first { $0.name == "backupd" })
        #expect(backupd.values[.disk] == "9.4 MB/s")
        #expect(!backupd.canQuit && !backupd.isExpandable)
    }

    @Test(arguments: [
        (OverviewListColumn.app, ["backupd", "Google Chrome", "Safari", "trustd", "WindowServer", "Xcode"]),
        (.processes, ["Google Chrome", "Xcode", "WindowServer", "Safari", "backupd", "trustd"]),
        (.cpu, ["Xcode", "Google Chrome", "WindowServer", "Safari", "backupd", "trustd"]),
        (.memory, ["Google Chrome", "Xcode", "Safari", "WindowServer", "backupd", "trustd"]),
        // Unreadable figures go last, in CPU order.
        (.gpu, ["WindowServer", "Google Chrome", "Xcode", "Safari", "backupd", "trustd"]),
        (.network, ["Safari", "Google Chrome", "Xcode", "WindowServer", "backupd", "trustd"]),
        (.disk, ["backupd", "Xcode", "Google Chrome", "WindowServer", "Safari", "trustd"]),
        (.power, ["Xcode", "Google Chrome", "WindowServer", "Safari", "backupd", "trustd"]),
    ])
    func sortsByEveryColumn(column: OverviewListColumn, expected: [String]) throws {
        let list = try monitor().overviewList(OverviewListQuery(sort: column))

        #expect(names(list) == expected)
        #expect(list.sortLabel == column.sortLabel)
    }

    @Test func anExpandedGroupListsItsProcessesCollapsedByName() throws {
        let chromeID = "/Applications/Google Chrome.app"
        let list = try monitor().overviewList(OverviewListQuery(expanded: [chromeID]))

        #expect(names(list) == ["Xcode", "Google Chrome", "Google Chrome Helper (Renderer) ×4", "Google Chrome",
                                "Google Chrome Helper (GPU)", "WindowServer", "Safari", "backupd", "trustd"])
        let helpers = list.rows[2...4]
        #expect(helpers.allSatisfy { $0.kind == .helper && $0.appID == chromeID && $0.canQuit })
        #expect(list.rows[2].values[.processes] == "4")
        #expect(list.rows[2].values[.cpu] == "4.0%")
        #expect(list.rows[2].values[.memory] == "400 MB")
        #expect(list.rows[1].isExpanded)
    }

    @Test func helpersFollowTheChosenSort() throws {
        let chromeID = "/Applications/Google Chrome.app"
        let list = try monitor().overviewList(OverviewListQuery(sort: .gpu, expanded: [chromeID]))

        let helpers = list.rows.filter { $0.kind == .helper }.map(\.name)
        #expect(helpers == ["Google Chrome Helper (GPU)", "Google Chrome Helper (Renderer) ×4", "Google Chrome"])
    }

    @Test func ungroupedListsEveryProcess() throws {
        let list = try monitor().overviewList(OverviewListQuery(grouped: false))

        #expect(list.rows.count == 11)
        #expect(Array(names(list).prefix(3)) == ["Xcode", "WindowServer", "Google Chrome"])
        #expect(list.rows.allSatisfy { $0.kind == .process && !$0.isExpandable })
        #expect(list.footer == "Showing 11 of 11 processes")
        // A helper's row quits its app.
        let renderer = try #require(list.rows.first { $0.name == "Google Chrome Helper (Renderer)" })
        #expect(renderer.appID == "/Applications/Google Chrome.app")
        #expect(renderer.canQuit)
    }

    // MARK: Search

    @Test func searchingAHelperNameShowsItsAppOpenAtThatHelper() throws {
        let list = try monitor().overviewList(OverviewListQuery(search: "renderer"))

        #expect(names(list) == ["Google Chrome", "Google Chrome Helper (Renderer) ×4"])
        #expect(list.rows[0].isExpanded)
        #expect(list.rows[0].values[.processes] == "6")
        #expect(list.footer == "Showing 1 of 3 apps · 6 processes grouped")
    }

    @Test func searchingAnAppNameKeepsItCollapsed() throws {
        let list = try monitor().overviewList(OverviewListQuery(search: " XCODE "))

        #expect(names(list) == ["Xcode"])
        #expect(!list.rows[0].isExpanded)
    }

    @Test func searchSortAndGroupingWorkTogether() throws {
        let monitor = try monitor()

        let grouped = monitor.overviewList(OverviewListQuery(sort: .memory, search: "chrome"))
        #expect(names(grouped) == ["Google Chrome"])
        #expect(grouped.footer == "Showing 1 of 3 apps · 6 processes grouped")

        let flat = monitor.overviewList(OverviewListQuery(sort: .memory, search: "chrome", grouped: false))
        #expect(names(flat) == ["Google Chrome"] + Array(repeating: "Google Chrome Helper (Renderer)", count: 4)
            + ["Google Chrome Helper (GPU)"])
        #expect(flat.footer == "Showing 6 of 11 processes")
    }

    @Test func searchWithoutMatchesSaysSo() throws {
        let list = try monitor().overviewList(OverviewListQuery(search: "zzz"))

        #expect(list.rows.isEmpty)
        #expect(list.emptyMessage == "No apps or processes match “zzz”")
        #expect(list.footer == "Showing 0 of 3 apps · 0 processes grouped")
    }

    // MARK: Footer

    @Test func footerCountsAppsLikeTheProcessesTile() throws {
        let monitor = try monitor()
        let list = monitor.overviewList(OverviewListQuery())

        // Bare daemons are rows, but only `.app` bundles count as apps, as in "Show All 3 Apps".
        #expect(list.footer == "Showing 3 of 3 apps · 11 processes grouped")
        #expect(monitor.overviewTiles().showAll == "Show All 3 Apps")
        #expect(list.emptyMessage == nil)
    }

    @Test func footerShowsSystemTotals() throws {
        let list = try monitor().overviewList(OverviewListQuery())

        #expect(list.totals.map(\.text) == ["CPU 32%", "Memory 11.2 GB", "GPU 18%", "Network 4.6 MB/s",
                                            "Power 38.0 W"])
    }

    @Test func cpuModeAndNetworkUnitsApplyToRowsAndTotals() throws {
        preferences.cpuMode = .perCore
        preferences.networkUnits = .bits
        let list = try monitor().overviewList(OverviewListQuery())

        let xcode = try #require(list.rows.first { $0.name == "Xcode" })
        let safari = try #require(list.rows.first { $0.name == "Safari" })
        #expect(xcode.values[.cpu] == "144.0%")
        #expect(safari.values[.network] == "26 Mbps")
        #expect(list.totals.map(\.text).prefix(4) == ["CPU 384%", "Memory 11.2 GB", "GPU 18%", "Network 37 Mbps"])
    }

    @Test func waitsForTheProcessList() throws {
        let list = try monitor(snapshot(processes: .unavailable(.warmingUp))).overviewList(OverviewListQuery())

        #expect(list.rows.isEmpty)
        #expect(list.emptyMessage == "Waiting for the process list…")
    }
}
