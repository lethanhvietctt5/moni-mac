import Foundation
import Testing
@testable import MoniMacCore

private let gib: Double = 1_073_741_824

/// A sampler whose next reading the test sets, stamped with the test clock.
@MainActor
private final class SteerableSampler: SystemSampler {
    let clock: TestClock
    var next: Snapshot

    init(clock: TestClock, next: Snapshot) {
        self.clock = clock
        self.next = next
    }

    func sample() -> Snapshot {
        var snapshot = next
        snapshot.timestamp = clock.now
        return snapshot
    }
}

@MainActor
struct AlertTests {
    let clock = TestClock()
    let preferences = Preferences(defaults: UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!)
    let actions = RecordingActions()
    /// 12 cores.
    let mac = SystemInfo(chipName: "Apple M3 Pro", performanceCores: 6, efficiencyCores: 6, bootTime: nil)
    static let xcodeID = "/Applications/Xcode.app"

    /// What Xcode (a regular app) and kernel_task (macOS's own) are doing on one reading.
    struct Load {
        var systemCPU = 0.3
        var xcodeCPU = 0.1
        var xcodeMemory: Double = 2 * gib
        var xcodeWrites: Double = 0
        var xcodeNetwork: Double = 0
        var kernelCPU = 0.1
    }

    private func snapshot(_ load: Load) -> Snapshot {
        Snapshot(
            timestamp: clock.now, system: mac,
            cpu: .cpu(user: load.systemCPU * 0.7, system: load.systemCPU * 0.3),
            processes: .value([
                ProcessSample(pid: 10, name: "Xcode", path: "/Applications/Xcode.app/Contents/MacOS/Xcode",
                              cpu: load.xcodeCPU, isRegularApp: true,
                              resources: ResourceUse(memory: UInt64(load.xcodeMemory), network: load.xcodeNetwork,
                                                     diskWritePerSecond: load.xcodeWrites)),
                ProcessSample(pid: 0, name: "kernel_task", path: nil, cpu: load.kernelCPU, isOtherUser: true,
                              resources: ResourceUse(memory: 1_000_000, network: 50_000_000,
                                                     diskWritePerSecond: 50_000_000)),
            ])
        )
    }

    private func makeMonitor(_ load: Load = Load()) throws -> (Monitor, SteerableSampler) {
        let sampler = SteerableSampler(clock: clock, next: snapshot(load))
        let monitor = Monitor(sampler: sampler, history: try MetricsHistory(.inMemory), preferences: preferences,
                              actions: actions)
        return (monitor, sampler)
    }

    /// Ticks every `interval` seconds for `seconds`, with `load` at each tick (given the seconds elapsed so far).
    private func run(_ monitor: Monitor, _ sampler: SteerableSampler, for seconds: TimeInterval,
                     every interval: TimeInterval = 4, _ load: (TimeInterval) -> Load) {
        var elapsed: TimeInterval = 0
        while elapsed < seconds {
            sampler.next = snapshot(load(elapsed))
            monitor.tick()
            clock.advance(by: interval)
            elapsed += interval
        }
    }

    private func run(_ monitor: Monitor, _ sampler: SteerableSampler, for seconds: TimeInterval,
                     every interval: TimeInterval = 4, _ load: Load) {
        run(monitor, sampler, for: seconds, every: interval) { _ in load }
    }

    private var delivered: [Alert] { actions.delivered }

    // MARK: App CPU

    @Test func appCPUFiresAtItsThresholdAfterTwoMinutes() throws {
        let (monitor, sampler) = try makeMonitor()
        // 0.8 cores, exactly the default threshold. Ticks at 0, 4, … 116 s: just short of 2 minutes.
        run(monitor, sampler, for: 120, Load(xcodeCPU: 0.8))
        #expect(delivered.isEmpty)

        run(monitor, sampler, for: 4, Load(xcodeCPU: 0.8))

        let alert = try #require(delivered.first)
        #expect(delivered.count == 1)
        #expect(alert.id == "appCPU:\(Self.xcodeID)")
        #expect(alert.title == "Xcode is using a lot of CPU")
        // System mode on 12 cores: 0.8 of a core is 6.7% of the Mac.
        #expect(alert.chip == "6.7%")
        #expect(alert.body == "6.7% for the last 2 minutes. Your Mac may feel slower and run warmer.")
        #expect(alert.quitTitle == "Quit Xcode")
        #expect(alert.target == .app(Self.xcodeID, column: .cpu))
        #expect(alert.bundlePath == Self.xcodeID)
    }

    @Test func appCPUDoesNotFireBelowItsThresholdOrDuration() throws {
        let (monitor, sampler) = try makeMonitor()
        run(monitor, sampler, for: 600, Load(xcodeCPU: 0.79))
        // Above the threshold for 1 min 56 s, then a dip, then another 1 min 56 s.
        run(monitor, sampler, for: 240) { t in Load(xcodeCPU: t == 116 ? 0.5 : 3) }

        #expect(delivered.isEmpty)
    }

    @Test func aSustainedConditionAlertsOnceAndReArmsAfterClearing() throws {
        let (monitor, sampler) = try makeMonitor()
        run(monitor, sampler, for: 600, Load(xcodeCPU: 4.12))
        #expect(delivered.count == 1)

        run(monitor, sampler, for: 4, Load(xcodeCPU: 0.2))
        run(monitor, sampler, for: 116, Load(xcodeCPU: 4.12))
        #expect(delivered.count == 1)
        run(monitor, sampler, for: 8, Load(xcodeCPU: 4.12))

        #expect(delivered.map(\.id) == ["appCPU:\(Self.xcodeID)", "appCPU:\(Self.xcodeID)"])
    }

    @Test func macOSOwnProcessesNeverAlert() throws {
        // kernel_task runs at 3 cores, writes 50 MB/s, and moves 50 MB/s for an hour.
        preferences.setAlertEnabled(true, for: .network)
        let (monitor, sampler) = try makeMonitor()
        run(monitor, sampler, for: 3600, every: 8, Load(kernelCPU: 3))

        #expect(delivered.isEmpty)
    }

    // MARK: Memory growth

    @Test func memoryGrowthFiresAtOneGigabyteWithinTenMinutes() throws {
        let (monitor, sampler) = try makeMonitor()
        // From 2 GB, +0.2 GB a minute: +1 GB after 5 minutes.
        run(monitor, sampler, for: 296) { t in Load(xcodeMemory: (2 + 0.2 * t / 60) * gib) }
        #expect(delivered.isEmpty)
        run(monitor, sampler, for: 600) { t in Load(xcodeMemory: (2 + 0.2 * (t + 296) / 60) * gib) }

        let alert = try #require(delivered.first)
        #expect(delivered.count == 1)
        #expect(alert.title == "Xcode memory is growing fast")
        #expect(alert.chip == "+1 GB")
        #expect(alert.body == "+1 GB within 10 minutes, now 3 GB. A steady climb can mean a memory leak.")
        #expect(alert.target == .app(Self.xcodeID, column: .memory))
    }

    @Test func aSteadyLeakOfExactlyOneGigabytePerTenMinutesFires() throws {
        let (monitor, sampler) = try makeMonitor()
        run(monitor, sampler, for: 1800) { t in Load(xcodeMemory: (2 + 0.1 * t / 60) * gib) }

        #expect(delivered.map(\.rule) == [.memoryGrowth])
    }

    @Test func memoryGrowthDoesNotFireBelowItsThresholdOrOverLongerThanTenMinutes() throws {
        let (monitor, sampler) = try makeMonitor()
        // +0.9 GB in 5 minutes, then flat.
        run(monitor, sampler, for: 900) { t in Load(xcodeMemory: (2 + 0.18 * min(t, 300) / 60) * gib) }
        // +1.5 GB over 30 minutes: only 0.5 GB in any 10.
        run(monitor, sampler, for: 1800) { t in Load(xcodeMemory: (2.9 + 0.05 * t / 60) * gib) }

        #expect(delivered.isEmpty)
    }

    @Test func memoryGrowthReArmsOnceTheGrowthLeavesTheWindow() throws {
        let (monitor, sampler) = try makeMonitor()
        // A 1.5 GB jump, then flat for 15 minutes, then another.
        run(monitor, sampler, for: 4, Load(xcodeMemory: 2 * gib))
        run(monitor, sampler, for: 900, Load(xcodeMemory: 3.5 * gib))
        #expect(delivered.count == 1)
        run(monitor, sampler, for: 8, Load(xcodeMemory: 5 * gib))

        #expect(delivered.count == 2)
    }

    // MARK: Disk writes

    @Test func diskWritesFireAboveTenGigabytesInAnHour() throws {
        let (monitor, sampler) = try makeMonitor()
        // 6 MB/s: 10 GB after about 28 minutes.
        run(monitor, sampler, for: 1600, Load(xcodeWrites: 6_000_000))
        #expect(delivered.isEmpty)
        run(monitor, sampler, for: 1200, Load(xcodeWrites: 6_000_000))

        let alert = try #require(delivered.first)
        #expect(delivered.count == 1)
        #expect(alert.title == "Heavy disk writes from Xcode")
        #expect(alert.chip == "6 MB/s")
        #expect(alert.body.hasSuffix("written in the last hour. Heavy writing wears out an SSD over time."))
        #expect(alert.target == .app(Self.xcodeID, column: .disk))
    }

    @Test func diskWritesDoNotFireBelowTenGigabytesAnHour() throws {
        let (monitor, sampler) = try makeMonitor()
        // 2.5 MB/s for two hours: 9 GB in any hour.
        run(monitor, sampler, for: 7200, every: 8, Load(xcodeWrites: 2_500_000))

        #expect(delivered.isEmpty)
    }

    // MARK: Network

    @Test func networkIsOffByDefaultAndFiresAfterFourMinutesOnceEnabled() throws {
        let (monitor, sampler) = try makeMonitor()
        run(monitor, sampler, for: 600, Load(xcodeNetwork: 18_000_000))
        #expect(delivered.isEmpty)

        monitor.setAlertEnabled(true, for: .network)
        run(monitor, sampler, for: 240, Load(xcodeNetwork: 18_000_000))
        #expect(delivered.isEmpty)
        run(monitor, sampler, for: 4, Load(xcodeNetwork: 18_000_000))

        let alert = try #require(delivered.first)
        #expect(alert.title == "Xcode is using the network heavily")
        #expect(alert.chip == "18 MB/s")
        #expect(alert.body == "Sustained 18 MB/s for 4 minutes.")
        #expect(alert.target == .app(Self.xcodeID, column: .network))
    }

    @Test func networkDoesNotFireBelowItsThreshold() throws {
        let (monitor, sampler) = try makeMonitor()
        monitor.setAlertEnabled(true, for: .network)
        run(monitor, sampler, for: 900, Load(xcodeNetwork: 9_900_000))

        #expect(delivered.isEmpty)
    }

    // MARK: Settings

    @Test func aDisabledRuleNeverFires() throws {
        let (monitor, sampler) = try makeMonitor()
        monitor.setAlertEnabled(false, for: .appCPU)
        run(monitor, sampler, for: 600, Load(xcodeCPU: 4))

        #expect(delivered.isEmpty)
    }

    @Test func disablingARuleTakesEffectImmediatelyAndReEnablingReArmsIt() throws {
        let (monitor, sampler) = try makeMonitor()
        run(monitor, sampler, for: 100, Load(xcodeCPU: 4))
        monitor.setAlertEnabled(false, for: .appCPU)
        run(monitor, sampler, for: 100, Load(xcodeCPU: 4))
        #expect(delivered.isEmpty)

        // Back on, the condition starts over: two more minutes.
        monitor.setAlertEnabled(true, for: .appCPU)
        run(monitor, sampler, for: 120, Load(xcodeCPU: 4))
        #expect(delivered.isEmpty)
        run(monitor, sampler, for: 4, Load(xcodeCPU: 4))
        #expect(delivered.count == 1)
    }

    @Test func aThresholdChangeTakesEffectImmediately() throws {
        let (monitor, sampler) = try makeMonitor()
        monitor.setAlertThreshold(2, for: .appCPU)
        run(monitor, sampler, for: 600, Load(xcodeCPU: 1.5))
        #expect(delivered.isEmpty)

        monitor.setAlertThreshold(1, for: .appCPU)
        run(monitor, sampler, for: 124, Load(xcodeCPU: 1.5))
        #expect(delivered.count == 1)
    }

    @Test func flippingTheCPUModeChangesTheWordingButNotWhenTheRuleFires() throws {
        func fireTime(_ mode: CPUMode) throws -> (TimeInterval?, String?) {
            let preferences = Preferences(defaults: UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!)
            let actions = RecordingActions()
            let sampler = SteerableSampler(clock: clock, next: snapshot(Load()))
            let monitor = Monitor(sampler: sampler, history: try MetricsHistory(.inMemory), preferences: preferences,
                                  actions: actions)
            monitor.setCPUMode(mode)
            var elapsed: TimeInterval = 0
            while elapsed < 300, actions.delivered.isEmpty {
                // 4.12 cores from 20 s on.
                sampler.next = snapshot(Load(xcodeCPU: elapsed >= 20 ? 4.12 : 0.1))
                monitor.tick()
                clock.advance(by: 4)
                elapsed += 4
            }
            return (actions.delivered.isEmpty ? nil : elapsed, actions.delivered.first?.chip)
        }

        let system = try fireTime(.system)
        let perCore = try fireTime(.perCore)

        #expect(system.0 == 144)
        #expect(perCore.0 == system.0)
        #expect(system.1 == "34%")
        #expect(perCore.1 == "412%")
    }

    @Test func aGapLikeSleepStartsSustainedConditionsOver() throws {
        let (monitor, sampler) = try makeMonitor()
        run(monitor, sampler, for: 100, Load(xcodeCPU: 4))
        clock.advance(by: 3600)
        run(monitor, sampler, for: 100, Load(xcodeCPU: 4))

        #expect(delivered.isEmpty)
    }

    // MARK: Permission

    @Test func permissionIsNeverAskedAtLaunchOrWhileNothingFires() throws {
        let (monitor, sampler) = try makeMonitor()
        run(monitor, sampler, for: 600, Load())

        #expect(actions.recorded.isEmpty)
    }

    @Test func permissionIsAskedOnceBeforeTheFirstAlert() throws {
        let (monitor, sampler) = try makeMonitor()
        run(monitor, sampler, for: 600) { t in Load(xcodeCPU: 4, xcodeWrites: t >= 300 ? 50_000_000 : 0) }

        #expect(actions.recorded.first == .requestNotificationAuthorization)
        #expect(actions.recorded.filter { $0 == .requestNotificationAuthorization }.count == 1)
        #expect(delivered.map(\.rule) == [.appCPU, .diskWrites])
    }

    @Test func turningARuleOnAsksForPermission() throws {
        let (monitor, _) = try makeMonitor()
        monitor.setAlertThreshold(2, for: .appCPU)
        monitor.setAlertEnabled(false, for: .appCPU)
        monitor.setAlertThreshold(5_000_000, for: .network)
        #expect(actions.recorded.isEmpty)

        monitor.setAlertEnabled(true, for: .network)
        monitor.setAlertEnabled(true, for: .appCPU)

        #expect(actions.recorded == [.requestNotificationAuthorization])
    }

    // MARK: Notification actions

    @Test func notificationsCarryTheAppAndWhereShowLands() throws {
        let (monitor, sampler) = try makeMonitor()
        run(monitor, sampler, for: 124, Load(xcodeCPU: 4))
        let alert = try #require(delivered.first)

        let target = try #require(AlertNotification.target(from: AlertNotification.userInfo(for: alert)))
        #expect(target == .app(Self.xcodeID, column: .cpu))
        #expect(AlertNotification.target(from: ["app": "x"]) == nil)
        // "Quit Xcode" goes through the quit sheet, which acts only on the app's own process.
        #expect(monitor.quitSheet(for: Self.xcodeID)?.title == "Quit Xcode?")
    }

    @Test func appsThatCannotBeQuitOfferOnlyShow() throws {
        let sampler = SteerableSampler(clock: clock, next: Snapshot(
            timestamp: clock.now, system: mac, cpu: .cpu(user: 0.2, system: 0.1),
            processes: .value([ProcessSample(pid: 30, name: "node", path: "/opt/homebrew/bin/node", cpu: 2)])
        ))
        let monitor = Monitor(sampler: sampler, history: try MetricsHistory(.inMemory), preferences: preferences,
                              actions: actions)
        for _ in 0...31 {
            monitor.tick()
            clock.advance(by: 4)
        }

        let alert = try #require(delivered.first)
        #expect(alert.title == "node is using a lot of CPU")
        #expect(alert.quitTitle == nil)
    }

    // MARK: Menu bar warning

    private func cpuItem(_ monitor: Monitor) -> MenuBarItem? {
        monitor.menuBarItems.first { $0.metric == .cpu }
    }

    @Test func theCPUItemBecomesAWarningBadgeUnderStrainAndRecovers() throws {
        let (monitor, sampler) = try makeMonitor()
        let strained = Load(systemCPU: 0.98, xcodeCPU: 4.12)
        run(monitor, sampler, for: 120, every: 2, strained)
        #expect(cpuItem(monitor)?.warning == nil)

        run(monitor, sampler, for: 2, every: 2, strained)
        let warning = try #require(cpuItem(monitor)?.warning)
        #expect(warning.text == "CPU 98%")
        #expect(warning.widestText == "CPU 100%")
        #expect(warning.title == "CPU above 90% for 2 min")
        #expect(warning.detail == "Xcode is using 34% · click for details")

        monitor.setCPUMode(.perCore)
        #expect(cpuItem(monitor)?.warning?.text == "CPU 1176%")
        #expect(cpuItem(monitor)?.warning?.title == "CPU above 1080% for 2 min")
        #expect(cpuItem(monitor)?.warning?.detail == "Xcode is using 412% · click for details")

        run(monitor, sampler, for: 2, every: 2, Load(systemCPU: 0.5))
        #expect(cpuItem(monitor)?.warning == nil)
        #expect(cpuItem(monitor)?.text == "600%")
    }

    @Test func theBadgeNeedsTwoUnbrokenMinutesAboveNinetyPercent() throws {
        let (monitor, sampler) = try makeMonitor()
        run(monitor, sampler, for: 600, every: 2) { t in Load(systemCPU: t.truncatingRemainder(dividingBy: 100) == 0 ? 0.6 : 0.99) }
        run(monitor, sampler, for: 600, every: 2, Load(systemCPU: 0.89))

        #expect(monitor.menuBarItems.allSatisfy { $0.warning == nil })
    }

    @Test func withoutACPUItemTheFirstItemCarriesTheBadge() throws {
        let (monitor, sampler) = try makeMonitor()
        // Every rule off: the badge still names the culprit.
        for rule in AlertRule.allCases { monitor.setAlertEnabled(false, for: rule) }
        monitor.setMenuBarItemEnabled(true, for: .memory)
        monitor.setMenuBarItemEnabled(true, for: .network)
        monitor.setMenuBarItemEnabled(false, for: .cpu)
        run(monitor, sampler, for: 124, every: 2, Load(systemCPU: 0.95, xcodeCPU: 6))

        #expect(monitor.menuBarItems.map(\.metric) == [.memory, .network])
        #expect(monitor.menuBarItems.map { $0.warning?.text } == ["CPU 95%", nil])
        #expect(monitor.menuBarItems.first?.warning?.detail == "Xcode is using 50% · click for details")
    }

    // MARK: Settings › Notifications

    @Test func settingsShowEachRuleWithItsThresholdInTheUsersUnits() throws {
        let (monitor, _) = try makeMonitor()
        monitor.tick()

        var rows = monitor.settingsPanel(version: "1.0").alertRules
        #expect(rows.map(\.label) == ["App exceeds CPU threshold", "Rapid memory growth", "Heavy disk writes",
                                      "Heavy network activity"])
        #expect(rows.map(\.isEnabled) == [true, true, true, false])
        #expect(rows.map(\.thresholdTitle) == ["6.7%", "1 GB", "10 GB", "10 MB/s"])
        #expect(rows.map(\.description) == [
            "Alert when one app stays above the limit for 2 min", "Possible leak: +1 GB within 10 minutes",
            "More than 10 GB written in an hour", "One app above 10 MB/s for 4 minutes",
        ])
        #expect(rows.map(\.hasSwitch) == [false, false, true, true])
        #expect(rows[0].options.map(\.title) == ["4.2%", "6.7%", "8.3%", "17%", "33%"])
        #expect(rows[1].options.map(\.title) == ["512 MB", "1 GB", "2 GB", "4 GB"])

        monitor.setCPUMode(.perCore)
        monitor.setNetworkUnits(.bits)
        monitor.setAlertThreshold(1.5, for: .appCPU)
        monitor.setAlertEnabled(false, for: .memoryGrowth)
        rows = monitor.settingsPanel(version: "1.0").alertRules
        #expect(rows[0].thresholdTitle == "150%")
        #expect(rows[0].options.map(\.title) == ["50%", "80%", "100%", "150%", "200%", "400%"])
        #expect(rows[1].isEnabled == false)
        #expect(rows[3].thresholdTitle == "80 Mbps")
        #expect(rows[0].options.filter(\.isSelected).map(\.title) == ["150%"])
    }

    @Test func cpuAndMemoryTurnOffFromTheirMenuAndBackOnByPickingAThreshold() throws {
        let (monitor, _) = try makeMonitor()
        monitor.tick()
        monitor.setAlertEnabled(false, for: .memoryGrowth)
        monitor.setAlertEnabled(false, for: .diskWrites)

        var rows = monitor.settingsPanel(version: "1.0").alertRules
        #expect(rows.map(\.menuTitle) == ["6.7%", "Off", "10 GB", "10 MB/s"])
        #expect(rows[1].options.allSatisfy { !$0.isSelected })
        #expect(rows.map(\.isOffSelected) == [false, true, false, false])
        #expect(rows.map(\.isMenuDisabled) == [false, false, true, true])
        // Disk has its own switch: its menu still shows the threshold it will use.
        #expect(rows[2].options.filter(\.isSelected).map(\.title) == ["10 GB"])

        monitor.setAlertThreshold(2 * gib, for: .memoryGrowth)
        monitor.setAlertThreshold(20_000_000_000, for: .diskWrites)
        rows = monitor.settingsPanel(version: "1.0").alertRules
        #expect(rows[1].isEnabled)
        #expect(rows[1].menuTitle == "2 GB")
        #expect(rows[2].isEnabled == false)
        #expect(rows[2].description == "More than 20 GB written in an hour")
    }
}
