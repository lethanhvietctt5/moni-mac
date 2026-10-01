import Foundation
import Testing
@testable import MoniMacCore

@MainActor
struct ThermalMenuBarTests {
    let clock = TestClock()
    let preferences = Preferences(defaults: UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!)

    private func snapshot(_ sensors: [ThermalSensor]) -> Snapshot {
        Snapshot(timestamp: clock.now, cpu: .cpu(user: 0.2, system: 0.1), thermal: .value(ThermalReading(
            state: .nominal, sensors: .value(sensors), fans: .unavailable(.unsupported))))
    }

    /// Ticks once per sparkline slot, so each reading gets its own bar.
    private func temperatureItem(_ script: [Snapshot], ticks: Int) throws -> MenuBarItem? {
        preferences.setMenuBarItemEnabled(true, for: .temperature)
        let monitor = Monitor(sampler: ScriptedSampler(clock: clock, script: script), history: try MetricsHistory(.inMemory),
                              preferences: preferences, actions: RecordingActions())
        for _ in 0..<ticks {
            monitor.tick()
            clock.advance(by: Sparkline.window / Double(Sparkline.barCount))
        }
        return monitor.menuBarItems.first { $0.metric == .temperature }
    }

    @Test func showsTheCPUTemperature() throws {
        let item = try temperatureItem([snapshot([ThermalSensor(name: "Tp01", celsius: 58.3), ThermalSensor(name: "Tg0D", celsius: 70)])], ticks: 1)

        #expect(item?.text == "58°C")
        #expect(item?.widestText == "100°C")
    }

    @Test func followsTheFahrenheitSetting() throws {
        preferences.temperatureUnit = .fahrenheit

        let item = try temperatureItem([snapshot([ThermalSensor(name: "Tp01", celsius: 58)])], ticks: 1)

        #expect(item?.text == "136°F")
        #expect(item?.widestText == "212°F")
    }

    @Test func withoutCPUSensorsShowsTheHottestKnownSensor() throws {
        let item = try temperatureItem([snapshot([ThermalSensor(name: "TB0T", celsius: 31), ThermalSensor(name: "TH0x", celsius: 40)])], ticks: 1)

        #expect(item?.text == "40°C")
    }

    @Test func placeholderWithoutSensors() throws {
        #expect(try temperatureItem([snapshot([])], ticks: 1)?.text == "—")
        #expect(try temperatureItem([Snapshot(timestamp: clock.now, cpu: .cpu(user: 0.2, system: 0.1))], ticks: 1)?.text == "—")
    }

    @Test func sparklineSpansTwentyToOneHundredDegrees() throws {
        preferences.setMenuBarStyle(.graph, for: .temperature)

        let item = try temperatureItem([
            snapshot([ThermalSensor(name: "Tp01", celsius: 20)]),
            snapshot([ThermalSensor(name: "Tp01", celsius: 60)]),
            snapshot([ThermalSensor(name: "Tp01", celsius: 110)]),
        ], ticks: 3)

        let bars = try #require(item?.bars)
        #expect(bars.count == Sparkline.barCount)
        #expect(bars.compactMap { $0 } == [0, 0.5, 1])
    }
}
