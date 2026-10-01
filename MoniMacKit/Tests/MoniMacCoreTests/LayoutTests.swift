import Foundation
import Testing
@testable import MoniMacCore

@MainActor
struct LayoutTests {
    let clock = TestClock()
    let defaults = UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!

    /// A Mac with a battery unless told otherwise. Each call is a fresh launch over the same settings.
    private func launch(battery: Bool = true) throws -> Monitor {
        let snapshot = Snapshot(
            timestamp: clock.now, cpu: .cpu(user: 0.2, system: 0.1),
            battery: battery ? .value(BatteryReading(charge: 0.8, isPluggedIn: true, isCharging: false))
                : .unavailable(.unsupported)
        )
        let monitor = Monitor(
            sampler: ScriptedSampler(clock: clock, script: [snapshot]), history: try MetricsHistory(.inMemory),
            preferences: Preferences(defaults: defaults), actions: RecordingActions()
        )
        monitor.tick()
        return monitor
    }

    private func sidebar(_ monitor: Monitor) -> [[WindowTab]] {
        monitor.sidebarGroups.map(\.tabs)
    }

    // MARK: Order

    @Test func savedOrderWinsAndNewItemsKeepTheirDefaultPlace() {
        #expect(LayoutOrder.arranged(["a", "b", "c", "d"], saved: ["c", "a", "b", "d"]) == ["c", "a", "b", "d"])
        // "d" is new: it goes right after "c", the item before it by default.
        #expect(LayoutOrder.arranged(["a", "b", "c", "d"], saved: ["c", "a", "b"]) == ["c", "d", "a", "b"])
        #expect(LayoutOrder.arranged(["a", "b", "c"], saved: ["gone", "b"]) == ["a", "b", "c"])
        #expect(LayoutOrder.arranged(["a", "b", "c"], saved: []) == ["a", "b", "c"])
    }

    @Test func droppingAnItemTakesTheTargetsPlace() {
        #expect(LayoutOrder.moving("a", onto: "c", in: ["a", "b", "c", "d"]) == ["b", "c", "a", "d"])
        #expect(LayoutOrder.moving("d", onto: "b", in: ["a", "b", "c", "d"]) == ["a", "d", "b", "c"])
        #expect(LayoutOrder.moving("a", onto: "a", in: ["a", "b"]) == ["a", "b"])
        #expect(LayoutOrder.moving("x", onto: "a", in: ["a", "b"]) == ["a", "b"])
    }

    // MARK: Sidebar

    @Test func theSidebarStartsInDefaultOrder() throws {
        #expect(sidebar(try launch()) == [
            [.overview, .cpu, .memory, .gpu, .network, .disk],
            [.battery, .bluetooth, .sound, .temperature],
            [.projects],
        ])
        #expect(try launch().sidebarGroups.map(\.title) == ["Monitor", "Devices", "Developer"])
    }

    @Test func hidingATabRemovesItFromTheSidebarAndItsChipShowsPlus() throws {
        let monitor = try launch()

        monitor.setTabShown(false, .gpu)

        #expect(sidebar(monitor)[0] == [.overview, .cpu, .memory, .network, .disk])
        #expect(monitor.windowTabChips.first { $0.tab == .gpu }?.isShown == false)
        #expect(sidebar(try launch())[0] == [.overview, .cpu, .memory, .network, .disk])

        monitor.setTabShown(true, .gpu)

        #expect(sidebar(monitor)[0] == [.overview, .cpu, .memory, .gpu, .network, .disk])
        #expect(monitor.windowTabChips.first { $0.tab == .gpu }?.isShown == true)
    }

    @Test func overviewAndSettingsCantBeHidden() throws {
        let monitor = try launch()

        monitor.setTabShown(false, .overview)
        monitor.setTabShown(false, .settings)

        #expect(sidebar(monitor)[0].first == .overview)
        #expect(monitor.windowTabChips.first { $0.tab == .overview }?.canToggle == false)
        #expect(!monitor.windowTabChips.contains { $0.tab == .settings })
        #expect(monitor.windowTabChips.filter(\.canToggle).count == 10)
    }

    @Test func chipsUseShortTitlesInDefaultOrder() throws {
        let chips = try launch().windowTabChips

        #expect(chips.map(\.title) == [
            "Overview", "CPU", "Memory", "GPU", "Network", "Disk", "Battery", "Bluetooth", "Sound", "Temps & Fans",
            "Projects",
        ])
        #expect(chips.allSatisfy { $0.isShown })
    }

    @Test func aMacWithoutABatteryHasNoBatteryTabOrChip() throws {
        let monitor = try launch(battery: false)

        #expect(sidebar(monitor)[1] == [.bluetooth, .sound, .temperature])
        #expect(!monitor.windowTabChips.contains { $0.tab == .battery })
    }

    @Test func sidebarOrderPersistsAcrossRelaunch() throws {
        try launch().moveTab(.disk, onto: .cpu)

        #expect(sidebar(try launch())[0] == [.overview, .disk, .cpu, .memory, .gpu, .network])
    }

    @Test func tabsDontMoveBetweenGroups() throws {
        let monitor = try launch()

        monitor.moveTab(.projects, onto: .cpu)

        #expect(sidebar(monitor) == sidebar(try launch(battery: true)))
        #expect(sidebar(monitor)[2] == [.projects])
    }

    @Test func aHiddenTabKeepsItsPlaceWhenShownAgain() throws {
        let monitor = try launch()
        monitor.moveTab(.network, onto: .cpu)
        monitor.setTabShown(false, .network)

        monitor.setTabShown(true, .network)

        #expect(sidebar(monitor)[0] == [.overview, .network, .cpu, .memory, .gpu, .disk])
    }

    @Test func aGroupWithEveryTabHiddenDisappears() throws {
        let monitor = try launch()

        monitor.setTabShown(false, .projects)

        #expect(monitor.sidebarGroups.map(\.title) == ["Monitor", "Devices"])
    }

    // MARK: Sections

    @Test func sectionOrderPersistsPerTab() throws {
        let sections = ["summary", "history", "perCore", "topApps"]
        try launch().moveSection("topApps", onto: "summary", in: .cpu, defaults: sections)

        let relaunched = try launch()

        #expect(relaunched.sectionOrder(in: .cpu, defaults: sections) == ["topApps", "summary", "history", "perCore"])
        #expect(relaunched.sectionOrder(in: .memory, defaults: sections) == sections)
    }

    @Test func sectionsAddedLaterAppearInTheirDefaultPlace() throws {
        try launch().moveSection("history", onto: "summary", in: .cpu, defaults: ["summary", "history"])

        let order = try launch().sectionOrder(in: .cpu, defaults: ["summary", "history", "perCore"])

        #expect(order == ["history", "perCore", "summary"])
    }

    @Test func halfWidthSectionsPairUpInRows() {
        let width: (String) -> SectionWidth = { $0.hasPrefix("half") ? .half : .full }

        #expect(SectionLayout.rows(["full1", "half1", "half2", "full2"], width: width)
            == [["full1"], ["half1", "half2"], ["full2"]])
        #expect(SectionLayout.rows(["half1", "full1", "half2"], width: width) == [["half1"], ["full1"], ["half2"]])
        #expect(SectionLayout.rows(["half1", "half2", "half3"], width: width) == [["half1", "half2"], ["half3"]])
        #expect(SectionLayout.rows([String](), width: width).isEmpty)
    }
}
