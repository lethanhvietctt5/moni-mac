import Foundation
import Testing
@testable import MoniMacCore

@MainActor
struct ThermalDetailTests {
    let clock = TestClock(start: Date(timeIntervalSince1970: 1_790_847_660))  // 2026-10-01 09:41 UTC
    let preferences = Preferences(defaults: UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!)
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    let oneFan = [Fan(rpm: 3200, minimumRPM: 1200, maximumRPM: 6550)]

    private func thermal(
        cpu: Double = 62, gpu: Double = 54, extra: [ThermalSensor] = [], fans: Reading<[Fan]>? = nil,
        state: ThermalState = .nominal
    ) -> Reading<ThermalReading> {
        .value(ThermalReading(
            state: state,
            sensors: .value([
                ThermalSensor(name: "Tp01", celsius: cpu + 4), ThermalSensor(name: "Te05", celsius: cpu - 4),
                ThermalSensor(name: "Tg0D", celsius: gpu), ThermalSensor(name: "TH0x", celsius: 41),
                ThermalSensor(name: "TB0T", celsius: 31),
            ] + extra),
            fans: fans ?? .value(oneFan)
        ))
    }

    private func snapshot(at time: Date, cpu: Double = 62, processes: [ProcessSample] = [],
                          fans: Reading<[Fan]>? = nil) -> Snapshot {
        Snapshot(timestamp: time, cpu: .cpu(user: 0.2, system: 0.1), processes: .value(processes),
                 thermal: thermal(cpu: cpu, fans: fans))
    }

    private func detail(history snapshots: [Snapshot], latest: Snapshot, range: TimeRange = .twentyFourHours,
                        unit: TemperatureUnit = .celsius) throws -> TemperatureDetail {
        let history = try MetricsHistory(.inMemory)
        for snapshot in snapshots + [latest] { try history.record(snapshot) }
        return TemperatureDetail.make(snapshot: latest, history: history, range: range, unit: unit, calendar: utc)
    }

    private func makeMonitor(_ script: [Snapshot]) throws -> Monitor {
        Monitor(sampler: ScriptedSampler(clock: clock, script: script), history: try MetricsHistory(.inMemory),
                preferences: preferences, actions: RecordingActions())
    }

    @Test func cardsShowLiveValuesWithAGauge() throws {
        let cards = try detail(history: [], latest: snapshot(at: clock.now)).cards

        #expect(cards.map(\.title) == ["CPU", "GPU", "SSD", "Battery"])
        #expect(cards.map(\.value) == ["62", "54", "41", "31"])
        #expect(cards.allSatisfy { $0.unit == "°C" })
        #expect(cards[0].gauge == 0.525)  // 62 °C on the 20–100 °C scale
    }

    @Test func cardsShowTodaysPeakButNotYesterdays() throws {
        let yesterday = clock.now.addingTimeInterval(-10 * 3600)  // 23:41 the previous day
        let thisMorning = clock.now.addingTimeInterval(-3600)
        let cards = try detail(
            history: [snapshot(at: yesterday, cpu: 90), snapshot(at: thisMorning, cpu: 81)],
            latest: snapshot(at: clock.now)
        ).cards

        #expect(cards[0].caption == "Peak 81° today")
    }

    @Test func todaysPeakWhenTheDaysPeakIsOutsideRawHistory() throws {
        let yesterday = clock.now.addingTimeInterval(-10 * 3600)
        let early = clock.now.addingTimeInterval(-5 * 3600)  // 04:41, one-minute buckets only
        let cards = try detail(
            history: [snapshot(at: yesterday, cpu: 90), snapshot(at: early, cpu: 75)],
            latest: snapshot(at: clock.now)
        ).cards

        #expect(cards[0].caption == "Peak 75° today")
    }

    @Test func missingSensorsSayNotReported() throws {
        let latest = Snapshot(timestamp: clock.now, cpu: .cpu(user: 0.2, system: 0.1), thermal: .value(ThermalReading(
            state: .nominal, sensors: .value([ThermalSensor(name: "Tp01", celsius: 60)]), fans: .unavailable(.unsupported))))

        let cards = try detail(history: [], latest: latest).cards

        #expect(cards.map(\.value) == ["60", "—", "—", "—"])
        #expect(cards[1].caption == "Not reported")
        #expect(cards[1].gauge == nil)
    }

    @Test func fahrenheitEverywhere() throws {
        let detail = try detail(history: [], latest: snapshot(at: clock.now), unit: .fahrenheit)

        #expect(detail.cards[0].value == "144")
        #expect(detail.cards[0].unit == "°F")
        #expect(detail.cards[0].caption == "Peak 144° today")
        #expect(detail.sensors.first == .init(name: "CPU Performance Cores", value: "151 °F"))
    }

    @Test func chartNamesThePeakAndTheBusiestAppThen() throws {
        let spike = clock.now.addingTimeInterval(-(19 * 3600 + 29 * 60))  // 14:12 the previous day
        let xcode = ProcessSample(pid: 1, name: "Xcode", path: "/Applications/Xcode.app/Contents/MacOS/Xcode", cpu: 6)
        let detail = try detail(
            history: [snapshot(at: spike, cpu: 81, processes: [xcode])],
            latest: snapshot(at: clock.now, cpu: 35)
        )

        #expect(detail.chartSummary == "Avg 58 °C · Peak 81 °C at 14:12 while Xcode was busiest")
    }

    @Test func chartBarsAreScaledAndColoredByHeat() throws {
        let detail = try detail(history: [], latest: snapshot(at: clock.now, cpu: 85))

        #expect(detail.history.count == TemperatureDetail.historyBarCount)
        #expect(detail.history.last == .init(height: 0.8125, level: .hot))
        #expect(detail.history.dropLast().allSatisfy { $0 == nil })
        #expect(detail.xAxis.last == "Now")
    }

    @Test func fansShowSpeedShareAndRange() throws {
        let fans = try detail(history: [], latest: snapshot(at: clock.now)).fans

        #expect(fans == .speeds([.init(id: 0, name: "Fan", rpm: "3,200", percent: "49%", share: 3200.0 / 6550,
                                       minimum: "1,200 RPM", maximum: "6,550 RPM")]))
    }

    @Test func severalFansAreNumberedUnlessTheSMCNamesThem() throws {
        let fans = try detail(history: [], latest: snapshot(at: clock.now, fans: .value([
            Fan(rpm: 0, minimumRPM: 1200, maximumRPM: 6550), Fan(name: "Right", rpm: 2400, minimumRPM: 1200, maximumRPM: 6000),
        ]))).fans

        guard case .speeds(let rows) = fans else { Issue.record("fans: \(String(describing: fans))"); return }
        #expect(rows.map(\.name) == ["Fan 1", "Right"])
        #expect(rows.map(\.percent) == ["0%", "40%"])
    }

    /// Fans that exist but can't be read keep the card and say why, rather than vanishing.
    @Test func unreadableFansSayWhy() throws {
        let fans = try detail(history: [], latest: snapshot(at: clock.now, fans: .unavailable(.failed("AppleSMC couldn't be opened")))).fans

        #expect(fans == .unreadable("Fan speeds couldn't be read: AppleSMC couldn't be opened."))
    }

    /// Ticket criterion: with a fake sampler reporting no fans, the Fans card is hidden.
    @Test func fanlessMacHidesTheFansCard() throws {
        let monitor = try makeMonitor([snapshot(at: clock.now, fans: .unavailable(.unsupported))])

        monitor.tick()

        #expect(monitor.temperatureDetail(range: .twentyFourHours).fans == nil)
        #expect(monitor.temperatureSubtitle == "Thermal state: Nominal")
    }

    @Test func emptyFanListAlsoHidesTheCard() throws {
        let monitor = try makeMonitor([snapshot(at: clock.now, fans: .value([]))])

        monitor.tick()

        #expect(monitor.temperatureDetail(range: .twentyFourHours).fans == nil)
    }

    @Test func subtitleShowsStateAndFanCount() throws {
        let monitor = try makeMonitor([snapshot(at: clock.now)])
        #expect(monitor.temperatureSubtitle == nil)

        monitor.tick()

        #expect(monitor.temperatureSubtitle == "Thermal state: Nominal · 1 fan")
        let two = ThermalReading(state: .serious, sensors: .value([]), fans: .value(oneFan + oneFan))
        #expect(TemperatureDetail.subtitle(for: two) == "Thermal state: Serious · 2 fans")
        let unknown = ThermalReading(state: nil, sensors: .value([]), fans: .unavailable(.unsupported))
        #expect(TemperatureDetail.subtitle(for: unknown) == "Thermal state: Unknown")
    }

    @Test func sensorListGroupsAndCountsUnnamedSensors() throws {
        let latest = Snapshot(timestamp: clock.now, cpu: .cpu(user: 0.2, system: 0.1), thermal: thermal(extra: [
            ThermalSensor(name: "TW0P", celsius: 40), ThermalSensor(name: "TPD0", celsius: 47),
            ThermalSensor(name: "TRD0", celsius: 42), ThermalSensor(name: "Tz11", celsius: 0),
        ]))

        let detail = try detail(history: [], latest: latest)

        #expect(detail.sensors.map(\.name) == [
            "CPU Performance Cores", "CPU Efficiency Cores", "GPU Cluster", "SSD", "Battery", "Wireless Module",
        ])
        #expect(detail.sensors.map(\.value) == ["66 °C", "58 °C", "54 °C", "41 °C", "31 °C", "40 °C"])
        #expect(detail.unnamedSensors == "Plus 2 sensors without a known location")
    }

    @Test func placeholdersBeforeTheFirstSample() throws {
        let detail = TemperatureDetail.make(snapshot: nil, history: try MetricsHistory(.inMemory),
                                            range: .twentyFourHours, unit: .celsius)

        #expect(detail.subtitle == nil)
        #expect(detail.cards.allSatisfy { $0.value == "—" })
        #expect(detail.fans == nil)
        #expect(detail.sensors.isEmpty)
        #expect(detail.chartSummary == nil)
    }
}
