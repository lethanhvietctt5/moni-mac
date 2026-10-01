import Foundation
import Testing
@testable import MoniMacCore

@MainActor
struct MenuBarTests {
    let clock = TestClock()
    let preferences = Preferences(defaults: UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!)

    private func makeMonitor(cpu: [Reading<CPUUsage>]) throws -> Monitor {
        Monitor(
            sampler: ScriptedSampler(clock: clock, cpu: cpu),
            history: try MetricsHistory(.inMemory),
            preferences: preferences
        )
    }

    private func cpuItem(_ monitor: Monitor) -> MenuBarItem? {
        monitor.menuBarItems.first { $0.metric == .cpu }
    }

    /// Ticks once per scripted reading, `interval` seconds apart.
    private func run(_ monitor: Monitor, ticks: Int, every interval: TimeInterval = 2) {
        for _ in 0..<ticks {
            monitor.tick()
            clock.advance(by: interval)
        }
    }

    @Test func showsPlaceholderBeforeTheFirstSample() throws {
        let monitor = try makeMonitor(cpu: [.cpu(user: 0.2, system: 0.1)])

        #expect(cpuItem(monitor)?.text == "—")
    }

    @Test func showsTotalCPUPercent() throws {
        let monitor = try makeMonitor(cpu: [.cpu(user: 0.21, system: 0.11)])

        monitor.tick()

        #expect(cpuItem(monitor)?.text == "32%")
    }

    @Test func updatesOnEachRefresh() throws {
        let monitor = try makeMonitor(cpu: [
            .unavailable(.warmingUp),
            .cpu(user: 0.21, system: 0.11),
            .cpu(user: 0.70, system: 0.28),
        ])

        var shown: [String?] = []
        for _ in 0..<3 {
            monitor.tick()
            shown.append(cpuItem(monitor)?.text)
            clock.advance(by: 2)
        }

        #expect(shown == ["—", "32%", "98%"])
        #expect(monitor.latest?.timestamp == clock.now.addingTimeInterval(-2))
    }

    @Test func showsPlaceholderWhenCPUIsUnavailable() throws {
        let monitor = try makeMonitor(cpu: [.unavailable(.failed("boom"))])

        monitor.tick()

        #expect(cpuItem(monitor)?.text == "—")
    }

    @Test func valueStyleIsTheDefaultAndHasNoBars() throws {
        let monitor = try makeMonitor(cpu: [.cpu(user: 0.5, system: 0)])

        monitor.tick()

        #expect(cpuItem(monitor)?.style == .value)
        #expect(cpuItem(monitor)?.bars == [])
    }

    @Test func graphStyleShowsTheLastMinuteAsBars() throws {
        let monitor = try makeMonitor(cpu: [.cpu(user: 0.1, system: 0), .cpu(user: 0.9, system: 0)])
        monitor.setMenuBarStyle(.graph, for: .cpu)

        run(monitor, ticks: 4, every: 4)  // 0.1 then 0.9 ×3, one per 4-second slot

        let bars = try #require(cpuItem(monitor)?.bars)
        #expect(bars.count == Sparkline.barCount)
        #expect(bars.compactMap { $0 } == [0.1, 0.9, 0.9, 0.9])
        #expect(bars.last == 0.9)
    }

    @Test func bothStyleShowsTextAndBars() throws {
        let monitor = try makeMonitor(cpu: [.cpu(user: 0.32, system: 0)])
        monitor.setMenuBarStyle(.both, for: .cpu)

        monitor.tick()

        #expect(cpuItem(monitor)?.text == "32%")
        #expect(cpuItem(monitor)?.bars.last == 0.32)
    }

    @Test func styleChangeAppliesImmediatelyAndPersists() throws {
        let monitor = try makeMonitor(cpu: [.cpu(user: 0.5, system: 0)])
        monitor.tick()

        monitor.setMenuBarStyle(.both, for: .cpu)

        #expect(cpuItem(monitor)?.style == .both)
        #expect(try makeMonitor(cpu: [.cpu(user: 0.5, system: 0)]).menuBarItems.first?.style == .both)
    }

    @Test(arguments: [
        (0.0, "0%"), (0.004, "0%"), (0.005, "1%"), (0.317, "32%"), (1.0, "100%"), (1.2, "100%"), (-0.1, "0%"),
    ])
    func formatsPercentCompactly(fraction: Double, expected: String) {
        #expect(Format.percent(fraction) == expected)
    }
}
