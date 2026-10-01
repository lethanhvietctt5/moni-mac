import Foundation
import Testing
@testable import MoniMacCore

@MainActor
struct QuitSheetTests {
    let clock = TestClock()
    let preferences = Preferences(defaults: UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!)
    let actions = RecordingActions()
    /// 12 cores.
    let mac = SystemInfo(chipName: "Apple M3 Pro", performanceCores: 6, efficiencyCores: 6, bootTime: nil)
    let chromeID = "/Applications/Google Chrome.app"

    private typealias Fixture = OverviewListTests

    private func monitor(_ processes: [ProcessSample] = OverviewListTests.processes) throws -> Monitor {
        let snapshot = Snapshot(timestamp: clock.now, system: mac, cpu: .cpu(user: 0.21, system: 0.11),
                                processes: .value(processes))
        let monitor = Monitor(sampler: ScriptedSampler(clock: clock, script: [snapshot]),
                              history: try MetricsHistory(.inMemory), preferences: preferences, actions: actions)
        monitor.tick()
        return monitor
    }

    // MARK: Contents

    @Test func showsTheAppsUsageAndBusiestProcesses() throws {
        let sheet = try #require(try monitor().quitSheet(for: chromeID))

        #expect(sheet.title == "Quit Google Chrome and its 6 processes?")
        #expect(sheet.message == "Google Chrome is using 6.5% CPU and 1.2 GB of memory. "
            + "Quitting asks the app to close normally so you can save your work.")
        #expect(sheet.processes.map(\.name) == ["Google Chrome"]
            + Array(repeating: "Google Chrome Helper (Renderer)", count: 4))
        #expect(sheet.processes.map(\.pid) == ["2", "10", "11", "12", "13"])
        #expect(sheet.processes.first.map { [$0.cpu, $0.memory] } == ["2.0%", "800 MB"])
        #expect(sheet.more == "and 1 more helper process")
        #expect(sheet.total == "Total  6.5% · 1.2 GB")
        #expect(sheet.reopenLabel == "Reopen Google Chrome windows next time")
    }

    @Test func countsTheProcessesBeyondTheListed() throws {
        // Chrome and 22 helpers: 5 listed, "and 18 more", as in the design.
        let helpers = (100..<122).map { Fixture.process($0, Fixture.renderer, responsible: 2, cpu: 0.01) }
        let sheet = try #require(try monitor([Fixture.processes[1]] + helpers).quitSheet(for: chromeID))

        #expect(sheet.title == "Quit Google Chrome and its 23 processes?")
        #expect(sheet.processes.count == QuitSheet.processLimit)
        #expect(sheet.more == "and 18 more helper processes")
    }

    @Test func aSingleProcessAppHasNoMoreLine() throws {
        let sheet = try #require(try monitor().quitSheet(for: "/Applications/Xcode.app"))

        #expect(sheet.title == "Quit Xcode?")
        #expect(sheet.more == nil)
        #expect(sheet.total == nil)
        #expect(sheet.processes.map(\.name) == ["Xcode"])
    }

    @Test func cpuFiguresFollowTheCPUMode() throws {
        preferences.cpuMode = .perCore
        let sheet = try #require(try monitor().quitSheet(for: chromeID))

        #expect(sheet.total == "Total  78% · 1.2 GB")
        #expect(sheet.processes.first?.cpu == "24.0%")
    }

    @Test func onlyRunningAppsGetASheet() throws {
        let monitor = try monitor()

        #expect(monitor.quitSheet(for: Fixture.windowServer) == nil)
        #expect(monitor.quitSheet(for: "/Applications/Gone.app") == nil)
    }

    // MARK: Choices

    @Test(arguments: [true, false])
    func quitRecordsAGracefulQuitWithTheReopenChoice(reopenWindows: Bool) throws {
        try monitor().resolveQuit(appID: chromeID, choice: .quit(reopenWindows: reopenWindows))

        #expect(actions.recorded == [.quitApp(pid: 2, reopenWindows: reopenWindows)])
    }

    @Test func forceQuitRecordsAForceQuit() throws {
        try monitor().resolveQuit(appID: chromeID, choice: .forceQuit)

        #expect(actions.recorded == [.forceQuitApp(pid: 2)])
    }

    @Test func cancelRecordsNothing() throws {
        let monitor = try monitor()
        _ = monitor.quitSheet(for: chromeID)

        monitor.resolveQuit(appID: chromeID, choice: .cancel)

        #expect(actions.recorded.isEmpty)
    }

    @Test func quittingFromAHelperRowTargetsTheResponsibleApp() throws {
        let monitor = try monitor()
        let grouped = monitor.overviewList(OverviewListQuery(search: "renderer"))
        let flat = monitor.overviewList(OverviewListQuery(search: "renderer", grouped: false))
        let helperRow = try #require(grouped.rows.first { $0.kind == .helper })
        let processRow = try #require(flat.rows.first)

        monitor.resolveQuit(appID: helperRow.appID, choice: .quit(reopenWindows: false))
        monitor.resolveQuit(appID: processRow.appID, choice: .forceQuit)

        // Chrome's own process (pid 2), never renderer 10–13.
        #expect(actions.recorded == [.quitApp(pid: 2, reopenWindows: false), .forceQuitApp(pid: 2)])
    }

    @Test func groupsThatCantBeQuitRecordNothing() throws {
        let monitor = try monitor()

        monitor.resolveQuit(appID: Fixture.windowServer, choice: .quit(reopenWindows: true))
        monitor.resolveQuit(appID: Fixture.trustd, choice: .forceQuit)

        #expect(actions.recorded.isEmpty)
    }
}
