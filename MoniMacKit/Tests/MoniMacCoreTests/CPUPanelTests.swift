import Foundation
import Testing
@testable import MoniMacCore

@MainActor
struct CPUPanelTests {
    let clock = TestClock()
    let preferences = Preferences(defaults: UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!)
    let actions = RecordingActions()
    let m3Pro = SystemInfo(chipName: "Apple M3 Pro", performanceCores: 6, efficiencyCores: 6, bootTime: nil)

    let xcode = "/Applications/Xcode.app/Contents/MacOS/Xcode"
    let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    let renderer = "/Applications/Google Chrome.app/Contents/Frameworks/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
    let windowServer = "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"

    private func snapshot(
        user: Double = 0.21, system: Double = 0.11, boot: Date? = nil, processes: [ProcessSample] = []
    ) -> Snapshot {
        var info = m3Pro
        info.bootTime = boot
        return Snapshot(
            timestamp: clock.now,
            system: info,
            cpu: .cpu(user: user, system: system),
            cores: .value(
                (0..<6).map { CoreUsage(kind: .efficiency, usage: Double($0) / 10) }
                    + (0..<6).map { CoreUsage(kind: .performance, usage: 0.5 + Double($0) / 20) }
            ),
            loadAverage: .value(LoadAverage(one: 2.844, five: 3.12, fifteen: 2.9666)),
            processes: .value(processes)
        )
    }

    private func monitor(_ script: [Snapshot]) throws -> Monitor {
        Monitor(sampler: ScriptedSampler(clock: clock, script: script), history: try MetricsHistory(.inMemory),
                preferences: preferences, actions: actions)
    }

    @Test func showsHeadlineFiguresInSystemMode() throws {
        let monitor = try monitor([snapshot()])
        monitor.tick()

        let panel = monitor.cpuPanel(range: .fiveMinutes)

        #expect(panel.chipLine == "Apple M3 Pro · 12 cores")
        #expect(panel.total == "32%")
        #expect([panel.user, panel.system, panel.idle] == ["21%", "11%", "68%"])
        #expect(panel.loadAverages == ["2.84", "3.12", "2.97"])
        #expect(panel.coreSummary == "6 Performance · 6 Efficiency")
    }

    @Test func perCoreModeScalesEveryCPUFigure() throws {
        preferences.cpuMode = .perCore
        let monitor = try monitor([snapshot(processes: [ProcessSample(pid: 1, name: "Xcode", path: xcode, cpu: 4.12)])])
        monitor.tick()

        let panel = monitor.cpuPanel(range: .oneMinute)

        #expect(panel.total == "384%")
        #expect(panel.user == "252%")
        #expect(panel.topApps.first?.value == "412%")
    }

    @Test func placeholdersBeforeTheFirstSample() throws {
        let panel = try monitor([snapshot()]).cpuPanel(range: .oneMinute)

        #expect(panel.total == "—")
        #expect(panel.loadAverages == ["—", "—", "—"])
        #expect(panel.history.allSatisfy { $0 == nil })
        #expect(panel.status == "Live")
    }

    @Test func coresArePerformanceFirstAndLabelled() throws {
        let monitor = try monitor([snapshot()])
        monitor.tick()

        let cores = monitor.cpuPanel(range: .oneMinute).cores

        #expect(cores.map(\.label) == ["P1", "P2", "P3", "P4", "P5", "P6", "E1", "E2", "E3", "E4", "E5", "E6"])
        #expect(cores.first?.usage == 0.5)
        #expect(cores.last?.kind == .efficiency)
    }

    @Test func historyStacksUserAndSystemOverTheRange() throws {
        let monitor = try monitor([snapshot(user: 0.2, system: 0.1), snapshot(user: 0.6, system: 0.3)])
        for _ in 0..<2 {
            monitor.tick()
            clock.advance(by: 2)
        }

        let history = monitor.cpuPanel(range: .oneMinute).history

        #expect(history.count == CPUPanel.historyBarCount)
        #expect(history.last??.user == 0.6)
        #expect(history.last??.system == 0.3)
        #expect(history.compactMap { $0 }.count == 2)
    }

    @Test func topAppsGroupHelpersAndShowProcessCounts() throws {
        let monitor = try monitor([snapshot(processes: [
            ProcessSample(pid: 1, name: "Xcode", path: xcode, cpu: 1.2, isRegularApp: true),
            ProcessSample(pid: 2, name: "Google Chrome", path: chrome, cpu: 0.3, isRegularApp: true),
            ProcessSample(pid: 3, responsiblePID: 2, name: "Renderer", path: renderer, cpu: 0.6),
            ProcessSample(pid: 4, name: "WindowServer", path: windowServer, cpu: 0.24),
            ProcessSample(pid: 5, name: "Music", path: "/System/Applications/Music.app/Contents/MacOS/Music", cpu: 0.01),
            ProcessSample(pid: 6, name: "Mail", path: "/System/Applications/Mail.app/Contents/MacOS/Mail", cpu: 0.001),
        ])])
        monitor.tick()

        let rows = monitor.cpuPanel(range: .oneMinute).topApps

        #expect(rows.map(\.name) == ["Xcode", "Google Chrome", "WindowServer", "Music"])
        #expect(rows.map(\.detail) == ["1 process", "2 processes", "1 process", "1 process"])
        #expect(rows.map(\.value) == ["10%", "8%", "2%", "0%"])
        #expect(rows.map(\.canQuit) == [true, true, false, false])
    }

    @Test func quitRequestsAGracefulQuitOfTheApp() throws {
        let monitor = try monitor([snapshot(processes: [
            ProcessSample(pid: 2, name: "Google Chrome", path: chrome, cpu: 0.3, isRegularApp: true),
            ProcessSample(pid: 3, responsiblePID: 2, name: "Renderer", path: renderer, cpu: 0.6),
        ])])
        monitor.tick()

        monitor.quitApp(id: monitor.cpuPanel(range: .oneMinute).topApps[0].id)

        #expect(actions.recorded == [.quitApp(pid: 2)])
    }

    @Test func quitDoesNothingForProcessesThatAreNotApps() throws {
        let monitor = try monitor([snapshot(processes: [
            ProcessSample(pid: 4, name: "WindowServer", path: windowServer, cpu: 0.24),
        ])])
        monitor.tick()

        monitor.quitApp(id: windowServer)

        #expect(actions.recorded.isEmpty)
    }

    @Test func activityMonitorLinkOpensActivityMonitor() throws {
        try monitor([snapshot()]).openActivityMonitor()

        #expect(actions.recorded == [.openActivityMonitor])
    }

    @Test func statusShowsUptime() throws {
        let monitor = try monitor([snapshot(boot: clock.now.addingTimeInterval(-(3 * 86400 + 4 * 3600 + 120)))])
        monitor.tick()

        #expect(monitor.cpuPanel(range: .oneMinute).status == "Live · uptime 3d 4h")
    }

    @Test(arguments: [(0, "0m"), (59, "0m"), (720, "12m"), (15120, "4h 12m"), (273600, "3d 4h")])
    func formatsUptime(seconds: Double, expected: String) {
        #expect(Format.uptime(seconds) == expected)
    }
}
