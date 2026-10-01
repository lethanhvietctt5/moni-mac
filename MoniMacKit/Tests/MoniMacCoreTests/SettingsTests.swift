import Foundation
import Observation
import Testing
@testable import MoniMacCore

@MainActor
struct SettingsTests {
    let clock = TestClock()
    let defaults = UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!
    let actions = RecordingActions()
    /// 12 cores.
    let mac = SystemInfo(chipName: "Mac", performanceCores: 6, efficiencyCores: 6, bootTime: nil)
    let xcode = "/Applications/Xcode.app/Contents/MacOS/Xcode"

    private func monitor(history: MetricsHistory? = nil) throws -> Monitor {
        Monitor(
            sampler: ScriptedSampler(clock: clock, script: [snapshot()]),
            history: try history ?? MetricsHistory(.inMemory),
            preferences: Preferences(defaults: defaults),
            actions: actions
        )
    }

    /// 32% CPU on 12 cores, Xcode using 1.44 cores, 56 °C, 4.2 MB/s down and 0.38 MB/s up.
    private func snapshot() -> Snapshot {
        Snapshot(
            timestamp: clock.now,
            system: mac,
            cpu: .cpu(user: 0.21, system: 0.11),
            processes: .value([
                ProcessSample(pid: 1, name: "Xcode", path: xcode, cpu: 1.44, isRegularApp: true),
            ]),
            network: .value(NetworkReading(interface: nil, downloadPerSecond: 4_200_000, uploadPerSecond: 380_000,
                                           received: 0, sent: 0)),
            battery: .value(BatteryReading(charge: 0.84, isPluggedIn: true, isCharging: true, temperature: 31.4)),
            thermal: .value(ThermalReading(
                state: .nominal,
                sensors: .value([ThermalSensor(name: "Tp01", celsius: 56)]),
                fans: .unavailable(.unsupported)
            ))
        )
    }

    private func menuBarText(_ monitor: Monitor, _ metric: Metric) -> String? {
        monitor.menuBarItems.first { $0.metric == metric }?.text
    }

    /// Every CPU figure a user can see, one per surface.
    private func cpuFigures(_ monitor: Monitor) -> [String?] {
        [
            menuBarText(monitor, .cpu),
            monitor.cpuPanel(range: .fiveMinutes).total,
            monitor.cpuDetail(range: .twentyFourHours).total,
            monitor.cpuDetail(range: .twentyFourHours).topApps.first?.value,
            monitor.overviewTiles().metricTiles.first { $0.metric == .cpu }?.value,
            monitor.overviewPanel().rows.first { $0.metric == .cpu }?.value,
            monitor.overviewTiles().busiest.first?.value,
        ]
    }

    /// Fires `onChange` if anything `read` touched changes.
    private func observes(_ read: () -> Void, after change: () -> Void) -> Bool {
        let changed = Flag()
        withObservationTracking(read) { changed.isSet = true }
        change()
        return changed.isSet
    }

    // MARK: CPU mode

    @Test func switchingCPUModeChangesTheMenuBarPopoverWindowAndOverview() throws {
        let monitor = try monitor()
        monitor.tick()
        #expect(cpuFigures(monitor) == ["32%", "32%", "32%", "12.0%", "32%", "32%", "12% CPU"])

        monitor.setCPUMode(.perCore)

        #expect(cpuFigures(monitor) == ["384%", "384%", "384%", "144.0%", "384%", "384%", "144% CPU"])
        #expect(monitor.settingsPanel(version: "1.0").cpuMode == .perCore)
    }

    @Test func cpuModeChangesReachOpenSurfacesWithoutWaitingForATick() throws {
        let monitor = try monitor()
        monitor.tick()

        #expect(observes({ _ = cpuFigures(monitor) }, after: { monitor.setCPUMode(.perCore) }))
        #expect(observes({ _ = monitor.menuBarItems }, after: { monitor.setCPUMode(.system) }))
    }

    @Test func projectBookkeepingDoesNotRepaintSurfaces() throws {
        let monitor = try monitor()
        monitor.tick()
        let preferences = Preferences(defaults: defaults)

        #expect(!observes({ _ = preferences.cpuMode }, after: { preferences.projectsLastActive = ["/p": clock.now] }))
    }

    @Test func perCoreWidensTheCPUMenuBarItem() throws {
        let monitor = try monitor()
        #expect(monitor.menuBarItems.first?.widestText == "100%")

        monitor.setCPUMode(.perCore)

        #expect(monitor.menuBarItems.first?.widestText == "1000%")
    }

    @Test func theCPUModeNoteNamesThisMacsCores() throws {
        let monitor = try monitor()
        #expect(monitor.settingsPanel(version: "1.0").cpuModeNote == "Per-core counts each core as 100%")

        monitor.tick()

        #expect(monitor.settingsPanel(version: "1.0").cpuModeNote == "Per-core shows up to 1200% on 12 cores")
    }

    // MARK: Units

    @Test func temperatureUnitAppliesEverywhereATemperatureAppears() throws {
        let monitor = try monitor()
        monitor.setMenuBarItemEnabled(true, for: .temperature)
        monitor.tick()
        let figures = {
            [
                menuBarText(monitor, .temperature),
                monitor.overviewTiles().metricTiles.first { $0.metric == .temperature }?.value,
                monitor.overviewPanel().rows.first { $0.metric == .temperature }?.value,
                monitor.temperatureDetail(range: .twentyFourHours).sensors.first?.value,
                monitor.batteryDetail(range: .twentyFourHours, layout: .window).stats.last?.value,
            ]
        }
        #expect(figures() == ["56°C", "56°C", "56 °C", "56 °C", "31.4 °C"])

        monitor.setTemperatureUnit(.fahrenheit)

        #expect(figures() == ["133°F", "133°F", "133 °F", "133 °F", "88.5 °F"])
        #expect(monitor.menuBarItems.first { $0.metric == .temperature }?.widestText == "212°F")
        #expect(monitor.temperatureDetail(range: .twentyFourHours).cards.first?.unit == "°F")
    }

    @Test func networkUnitsApplyEverywhereASpeedAppears() throws {
        let monitor = try monitor()
        monitor.setMenuBarItemEnabled(true, for: .network)
        monitor.tick()
        let figures = {
            [
                menuBarText(monitor, .network),
                monitor.overviewTiles().metricTiles.first { $0.metric == .network }?.value,
                monitor.networkDetail().summary.download.text,
                monitor.networkPanel(range: .fiveMinutes).summary.upload.text,
            ]
        }
        #expect(figures() == ["4.6 MB/s", "4.6 MB/s", "4.2 MB/s", "380 KB/s"])

        monitor.setNetworkUnits(.bits)

        #expect(figures() == ["37 Mbps", "37 Mbps", "34 Mbps", "3.0 Mbps"])
        #expect(monitor.menuBarItems.first { $0.metric == .network }?.widestText == "999 Mbps")
    }

    // MARK: General

    @Test func refreshIntervalDefaultsToTwoSecondsAndPersists() throws {
        let monitor = try monitor()
        #expect(monitor.refreshInterval == .twoSeconds)
        #expect(monitor.refreshInterval.duration == .seconds(2))

        monitor.setRefreshInterval(.fiveSeconds)

        let relaunched = try self.monitor()
        #expect(relaunched.refreshInterval.duration == .seconds(5))
        #expect(relaunched.settingsPanel(version: "1.0").refreshInterval == .fiveSeconds)
        #expect(RefreshInterval.allCases.map(\.title) == ["1s", "2s", "5s"])
    }

    @Test func refreshIntervalChangesAreObserved() throws {
        let monitor = try monitor()

        #expect(observes({ _ = monitor.refreshInterval }, after: { monitor.setRefreshInterval(.oneSecond) }))
    }

    @Test func dockIconIsOffByDefault() throws {
        let monitor = try monitor()
        #expect(!monitor.showsDockIcon)

        monitor.setShowsDockIcon(true)

        #expect(try self.monitor().showsDockIcon)
    }

    @Test func launchAtLoginGoesThroughSystemActions() throws {
        let monitor = try monitor()
        #expect(!monitor.settingsPanel(version: "1.0").launchesAtLogin)

        monitor.setLaunchAtLogin(true)

        #expect(actions.recorded == [.setLaunchAtLogin(true)])
        #expect(monitor.settingsPanel(version: "1.0").launchesAtLogin)
    }

    @Test func aboutShowsTheVersion() throws {
        #expect(try monitor().settingsPanel(version: "1.4.2").about == "MoniMac 1.4.2")
    }

    // MARK: Menu bar items

    @Test func menuBarRowsShareStateWithTheMenuBar() throws {
        let monitor = try monitor()
        monitor.setMenuBarItemEnabled(true, for: .memory)
        monitor.setMenuBarStyle(.both, for: .memory)

        let rows = monitor.settingsPanel(version: "1.0").menuBarRows

        #expect(rows.map(\.metric) == Metric.allCases)
        #expect(rows.filter(\.isEnabled).map(\.metric) == [.cpu, .memory])
        #expect(rows.first { $0.metric == .memory }?.style == .both)
        #expect(rows.allSatisfy { $0.canToggle })
    }

    @Test func theLastEnabledMenuBarItemCantBeTurnedOff() throws {
        let monitor = try monitor()

        let cpu = monitor.settingsPanel(version: "1.0").menuBarRows.first { $0.metric == .cpu }
        monitor.setMenuBarItemEnabled(false, for: .cpu)

        #expect(cpu?.canToggle == false)
        #expect(monitor.menuBarItems.map(\.metric) == [.cpu])
    }

    // MARK: Keep history

    @Test func keepHistoryDefaultsToThirtyDays() throws {
        let history = try MetricsHistory(.inMemory)
        _ = try monitor(history: history)

        #expect(history.retention == HistoryRetention.thirtyDays.duration)
        #expect(HistoryRetention.allCases.map(\.title) == ["7 days", "30 days", "90 days"])
    }

    @Test func shorteningKeepHistoryPrunesOlderData() throws {
        let history = try MetricsHistory(.inMemory)
        let monitor = try monitor(history: history)
        let start = clock.now
        monitor.tick()
        clock.advance(by: 10 * 86_400)
        monitor.tick()
        #expect(try history.peak(.cpuTotal, from: start - 60, to: start + 60) != nil)

        monitor.setKeepHistory(.sevenDays)

        #expect(try history.peak(.cpuTotal, from: start - 60, to: start + 60) == nil)
        #expect(try history.peak(.cpuTotal, from: clock.now - 60, to: clock.now) != nil)
    }

    @Test func ninetyDaysKeepsDataFromTwoMonthsAgo() throws {
        let history = try MetricsHistory(.inMemory)
        let monitor = try monitor(history: history)
        monitor.setKeepHistory(.ninetyDays)
        let start = clock.now
        monitor.tick()

        clock.advance(by: 60 * 86_400)
        monitor.tick()

        let kept = try history.peak(.cpuTotal, from: start - 60, to: start + 60)
        #expect(kept != nil)
    }

    @Test func keepHistoryAppliesAtLaunch() throws {
        try monitor().setKeepHistory(.ninetyDays)
        let history = try MetricsHistory(.inMemory)

        _ = try monitor(history: history)

        #expect(history.retention == HistoryRetention.ninetyDays.duration)
    }
}

/// Set from an Observation `onChange`, which runs synchronously on the mutating thread in these tests.
private final class Flag: @unchecked Sendable {
    var isSet = false
}
