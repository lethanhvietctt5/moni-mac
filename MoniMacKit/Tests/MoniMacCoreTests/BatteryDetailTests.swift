import Foundation
import Testing
@testable import MoniMacCore

@MainActor
struct BatteryDetailTests {
    let clock = TestClock()
    let utc = TimeZone(identifier: "UTC")!
    let preferences = Preferences(defaults: UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!)

    private let charging = BatteryReading(
        charge: 0.86, isPluggedIn: true, isCharging: true, timeRemaining: .minutes(72), adapterWatts: 96,
        batteryPower: 14.2, systemPower: 21.6, designCapacity: 5030, maxCapacity: 4627, cycleCount: 214,
        ratedCycles: 1000, temperature: 31.4
    )

    private func snapshot(
        _ battery: Reading<BatteryReading>, at time: Date? = nil, processes: [ProcessSample] = []
    ) -> Snapshot {
        Snapshot(timestamp: time ?? clock.now, cpu: .cpu(user: 0.1, system: 0.1), processes: .value(processes),
                 battery: battery)
    }

    private func monitor(_ script: [Snapshot]) throws -> Monitor {
        Monitor(sampler: ScriptedSampler(clock: clock, script: script), history: try MetricsHistory(.inMemory),
                preferences: preferences, actions: RecordingActions())
    }

    private func detail(
        _ latest: Snapshot, history snapshots: [Snapshot] = [], range: TimeRange = .twentyFourHours,
        layout: BatteryDetail.Layout = .window
    ) throws -> BatteryDetail {
        let history = try MetricsHistory(.inMemory)
        for snapshot in snapshots { try history.record(snapshot) }
        let apps = AppGrouping.apps(from: latest.processes.value ?? [])
        return BatteryDetail.make(snapshot: latest, apps: apps, history: history, range: range, layout: layout,
                                  timeZone: utc)
    }

    // MARK: Hiding

    @Test func aMacWithoutABatteryHidesBattery() throws {
        // The fake sampler's snapshots leave battery at its default: unsupported.
        let monitor = try monitor([Snapshot(timestamp: clock.now, cpu: .cpu(user: 0.2, system: 0.1))])
        monitor.tick()

        #expect(!monitor.hasBattery)
    }

    @Test func aMacWithABatteryShowsBattery() throws {
        let monitor = try monitor([snapshot(.value(charging))])
        monitor.tick()

        #expect(monitor.hasBattery)
    }

    @Test func aBatteryThatFailedToReadStillShowsWithTheReason() throws {
        let monitor = try monitor([snapshot(.unavailable(.failed("IOKit said no")))])
        monitor.tick()

        #expect(monitor.hasBattery)
        #expect(monitor.batteryPanel(range: .oneHour).status == "Battery unavailable: IOKit said no")
    }

    @Test func batteryStaysHiddenUntilTheFirstSample() throws {
        let monitor = try monitor([snapshot(.value(charging))])
        #expect(!monitor.hasBattery)
    }

    // MARK: Live values

    @Test func chargingMatchesTheDesign() throws {
        let detail = try detail(snapshot(.value(charging)))

        #expect(detail.subtitle == "Charging · 1 h 12 min until full")
        #expect(detail.charge == "86%")
        #expect(detail.isCharging)
        #expect(detail.source == "Power Adapter · 96 W")
        #expect(detail.status == "Full in 1 h 12 min")
        #expect(detail.stats.map(\.label) == ["Power Draw", "Health", "Cycle Count", "Temperature"])
        #expect(detail.stats.map(\.value) == ["14.2 W", "92%", "214", "31.4 °C"])
        #expect(detail.stats.map(\.caption) == [
            "System using 21.6 W", "Normal · 4,627 of 5,030 mAh", "of 1,000 rated cycles", "Within normal range",
        ])
    }

    @Test func powerFiguresAreLabelledAsEstimates() throws {
        let detail = try detail(snapshot(.value(charging)))

        #expect(detail.stats[0].help?.contains("Estimated") == true)
        #expect(BatteryDetail.appEstimateHelp.hasPrefix("Estimated"))
    }

    @Test func onBatteryShowsTimeToEmptyAndDischargeAsPositiveDraw() throws {
        var battery = charging
        battery.isPluggedIn = false
        battery.isCharging = false
        battery.timeRemaining = .minutes(200)
        battery.batteryPower = -9.5
        let detail = try detail(snapshot(.value(battery)))

        #expect(detail.subtitle == "On battery · 3 h 20 min left")
        #expect(detail.source == "On battery")
        #expect(detail.status == "3 h 20 min remaining")
        #expect(detail.stats[0].value == "9.5 W")
    }

    @Test func timeStillBeingEstimatedSaysCalculatingNeverZero() throws {
        var battery = charging
        battery.timeRemaining = .calculating
        #expect(try detail(snapshot(.value(battery))).status == "Calculating…")
        #expect(try detail(snapshot(.value(battery))).subtitle == "Charging · Calculating…")

        battery.isPluggedIn = false
        battery.isCharging = false
        #expect(try detail(snapshot(.value(battery))).status == "Calculating…")
    }

    @Test func pluggedInButNotChargingSaysWhy() throws {
        var battery = charging
        battery.isCharging = false
        battery.timeRemaining = nil
        #expect(try detail(snapshot(.value(battery))).status == "Not charging")

        battery.isFullyCharged = true
        battery.charge = 1
        let full = try detail(snapshot(.value(battery)))
        #expect(full.status == "Fully charged")
        #expect(full.subtitle == "Fully charged")
    }

    @Test func missingFiguresShowPlaceholdersNotZero() throws {
        let detail = try detail(snapshot(.value(BatteryReading(charge: 0.5, isPluggedIn: true, isCharging: true))))

        #expect(detail.source == "Power Adapter")
        #expect(detail.stats.map(\.value) == ["—", "—", "—", "—"])
        #expect(detail.stats[0].caption == "System power unavailable")
    }

    @Test func wornBatteryRecommendsService() throws {
        var battery = charging
        battery.maxCapacity = 3800
        #expect(try detail(snapshot(.value(battery))).stats[1].caption == "Service recommended · 3,800 of 5,030 mAh")
    }

    @Test func hotBatteryIsFlagged() throws {
        var battery = charging
        battery.temperature = 46
        #expect(try detail(snapshot(.value(battery))).stats[3].caption == "Above normal range")
    }

    // MARK: History

    @Test func historyMarksChargingAndOnBatteryPeriods() throws {
        var onBattery = charging
        onBattery.isPluggedIn = false
        onBattery.isCharging = false
        let now = clock.now
        let history = [
            snapshot(.value(onBattery), at: now.addingTimeInterval(-20 * 3600)),
            snapshot(.value(charging), at: now.addingTimeInterval(-2 * 3600)),
        ]
        let detail = try detail(snapshot(.value(charging)), history: history)

        #expect(detail.history.count == 24)
        #expect(detail.history.compactMap { $0?.isPluggedIn } == [false, true])
    }

    @Test func historyCaptionCountsPlugInsAndDrain() throws {
        var onBattery = charging
        onBattery.isPluggedIn = false
        onBattery.isCharging = false
        let start = clock.now.addingTimeInterval(-3 * 3600)
        // An hour on battery losing 10%, one minute per sample, then plugged in.
        let drained = (0...60).map { minute in
            var battery = onBattery
            battery.charge = 0.9 - Double(minute) / 600
            return snapshot(.value(battery), at: start.addingTimeInterval(Double(minute) * 60))
        }
        let pluggedIn = snapshot(.value(charging), at: start.addingTimeInterval(61 * 60))
        let detail = try detail(snapshot(.value(charging)), history: drained + [pluggedIn])

        #expect(detail.historyCaption == "Plugged in 1 time · Avg drain 10.0 %/h on battery")
    }

    @Test func historyCaptionWhenAlwaysOnPower() throws {
        let detail = try detail(snapshot(.value(charging)),
                                history: [snapshot(.value(charging), at: clock.now.addingTimeInterval(-60))])
        #expect(detail.historyCaption == "On power the whole time")
        #expect(try self.detail(snapshot(.value(charging))).historyCaption == "No history yet")
    }

    @Test func popoverFallsBackToItsDefaultRangeForRangesItDoesNotOffer() throws {
        let panel = try detail(snapshot(.value(charging)), range: .fiveMinutes, layout: .popover)

        #expect(panel.range == .twentyFourHours)
        #expect(panel.ranges == [.oneHour, .twelveHours, .twentyFourHours])
        #expect(panel.history.count == 30)
    }

    // MARK: Energy

    @Test func energyListsAppsByEstimatedWatts() throws {
        let processes = [
            ProcessSample(pid: 1, name: "Xcode", path: "/Applications/Xcode.app/Contents/MacOS/Xcode", cpu: 0.5,
                          isRegularApp: true, resources: ResourceUse(power: 3.4)),
            ProcessSample(pid: 2, name: "Google Chrome", path: "/Applications/Google Chrome.app/Contents/MacOS/Chrome",
                          cpu: 0.2, isRegularApp: true, resources: ResourceUse(power: 3)),
            ProcessSample(pid: 3, responsiblePID: 2, name: "Helper",
                          path: "/Applications/Google Chrome.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper",
                          cpu: 0.1, resources: ResourceUse(power: 1.8)),
            ProcessSample(pid: 4, name: "sipper", path: "/usr/bin/sipper", cpu: 0, resources: ResourceUse(power: 0.04)),
            ProcessSample(pid: 5, name: "rootd", path: "/usr/sbin/rootd", cpu: 0.3),
        ]
        let apps = try detail(snapshot(.value(charging), processes: processes)).energyApps

        #expect(apps.map(\.name) == ["Google Chrome", "Xcode"])
        #expect(apps.map(\.value) == ["4.8 W", "3.4 W"])
        #expect(apps.first?.share == 1)
        #expect(abs((apps.last?.share ?? 0) - 3.4 / 4.8) < 1e-9)
        #expect(apps.map(\.canQuit) == [true, true])
    }
}
