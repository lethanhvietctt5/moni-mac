import Testing
@testable import MoniMacCore

@MainActor
struct MenuBarTests {
    let clock = TestClock()

    private func cpuText(_ monitor: Monitor) -> String? {
        monitor.menuBarItems.first { $0.metric == .cpu }?.text
    }

    @Test func showsPlaceholderBeforeTheFirstSample() {
        let monitor = Monitor(sampler: ScriptedSampler(clock: clock, cpu: [.cpu(user: 0.2, system: 0.1)]))

        #expect(cpuText(monitor) == "—")
    }

    @Test func showsTotalCPUPercent() {
        let monitor = Monitor(sampler: ScriptedSampler(clock: clock, cpu: [.cpu(user: 0.21, system: 0.11)]))

        monitor.tick()

        #expect(cpuText(monitor) == "32%")
    }

    @Test func updatesOnEachRefresh() {
        let sampler = ScriptedSampler(clock: clock, cpu: [
            .unavailable(.warmingUp),
            .cpu(user: 0.21, system: 0.11),
            .cpu(user: 0.70, system: 0.28),
        ])
        let monitor = Monitor(sampler: sampler)

        var shown: [String?] = []
        for _ in 0..<3 {
            monitor.tick()
            shown.append(cpuText(monitor))
            clock.advance(by: 2)
        }

        #expect(shown == ["—", "32%", "98%"])
        #expect(monitor.latest?.timestamp == clock.now.addingTimeInterval(-2))
    }

    @Test func showsPlaceholderWhenCPUIsUnavailable() {
        let monitor = Monitor(sampler: ScriptedSampler(clock: clock, cpu: [.unavailable(.failed("boom"))]))

        monitor.tick()

        #expect(cpuText(monitor) == "—")
    }

    @Test(arguments: [
        (0.0, "0%"), (0.004, "0%"), (0.005, "1%"), (0.317, "32%"), (1.0, "100%"), (1.2, "100%"), (-0.1, "0%"),
    ])
    func formatsPercentCompactly(fraction: Double, expected: String) {
        #expect(Format.percent(fraction) == expected)
    }
}
