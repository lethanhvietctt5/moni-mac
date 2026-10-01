import Foundation
import Testing
@testable import MoniMacCore

@MainActor
struct NetworkTests {
    let clock = TestClock()
    let preferences = Preferences(defaults: UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!)
    let wifi = NetworkInterface(name: "Wi-Fi 6E", networkName: "Studio-5G", linkRate: 1_200_000_000)

    let safari = "/Applications/Safari.app/Contents/MacOS/Safari"
    let spotify = "/Applications/Spotify.app/Contents/MacOS/Spotify"
    let slack = "/Applications/Slack.app/Contents/MacOS/Slack"

    private func network(
        down: Double, up: Double, interface: NetworkInterface? = nil, received: Double? = nil, sent: Double? = nil
    ) -> Reading<NetworkReading> {
        .value(NetworkReading(interface: interface ?? wifi, downloadPerSecond: down, uploadPerSecond: up,
                              received: received ?? down * 2, sent: sent ?? up * 2))
    }

    private func snapshot(_ network: Reading<NetworkReading>, processes: [ProcessSample] = []) -> Snapshot {
        Snapshot(timestamp: clock.now, cpu: .cpu(user: 0.1, system: 0.1), processes: .value(processes),
                 network: network)
    }

    private func monitor(_ script: [Snapshot], history: MetricsHistory? = nil) throws -> Monitor {
        preferences.setMenuBarItemEnabled(true, for: .network)
        return Monitor(sampler: ScriptedSampler(clock: clock, script: script),
                       history: try history ?? MetricsHistory(.inMemory), preferences: preferences,
                       actions: RecordingActions(), startedAt: clock.now)
    }

    private func run(_ monitor: Monitor, ticks: Int, every interval: TimeInterval = 2) {
        for _ in 0..<ticks {
            monitor.tick()
            clock.advance(by: interval)
        }
    }

    private func networkItem(_ monitor: Monitor) -> MenuBarItem? {
        monitor.menuBarItems.first { $0.metric == .network }
    }

    // MARK: Menu bar

    @Test func menuBarItemShowsCombinedThroughput() throws {
        let monitor = try monitor([snapshot(.unavailable(.warmingUp)), snapshot(network(down: 2_100_000, up: 300_000))])
        #expect(networkItem(monitor)?.text == "—")

        monitor.tick()
        #expect(networkItem(monitor)?.text == "—")
        monitor.tick()
        #expect(networkItem(monitor)?.text == "2.4 MB/s")
        #expect(networkItem(monitor)?.widestText == "999 MB/s")
    }

    @Test func menuBarFollowsTheUnitsSetting() throws {
        preferences.networkUnits = .bits
        let monitor = try monitor([snapshot(network(down: 2_000_000, up: 375_000))])

        monitor.tick()

        #expect(networkItem(monitor)?.text == "19 Mbps")
        #expect(networkItem(monitor)?.widestText == "999 Mbps")
    }

    @Test func sparklineIsScaledToTheBusiestMomentOfTheMinute() throws {
        let monitor = try monitor([
            snapshot(network(down: 1_000_000, up: 0)),
            snapshot(network(down: 3_000_000, up: 1_000_000)),
            snapshot(network(down: 0, up: 0)),
        ])
        monitor.setMenuBarStyle(.graph, for: .network)

        // One sample per sparkline bar (each covers 4 seconds).
        run(monitor, ticks: 3, every: 4)

        let bars = try #require(networkItem(monitor)?.bars).compactMap { $0 }
        #expect(bars.count == 3)
        #expect(bars == [0.25, 1, 0])
    }

    @Test func ratesStayWithinThreeDigits() {
        let cases: [(Double, String)] = [
            (0, "0 KB/s"), (420, "0.4 KB/s"), (380_000, "380 KB/s"), (999_400, "999 KB/s"),
            (999_600, "1.0 MB/s"), (4_200_000, "4.2 MB/s"), (12_500_000, "13 MB/s"), (2_300_000_000, "2.3 GB/s"),
        ]
        for (bytes, text) in cases {
            #expect(NetworkFormat.rate(bytes, units: .bytes).text == text)
        }
        #expect(NetworkFormat.rate(125_000_000, units: .bits).text == "1.0 Gbps")
        #expect(NetworkFormat.rate(50_000, units: .bits).text == "400 kbps")
    }

    // MARK: Interface line

    @Test func subtitleNamesTheInterfaceNetworkAndLinkRate() throws {
        let monitor = try monitor([snapshot(network(down: 0, up: 0))])
        #expect(monitor.networkSubtitle == nil)

        monitor.tick()

        #expect(monitor.networkSubtitle == "Wi-Fi 6E · Studio-5G · 1.2 Gb/s link")
    }

    @Test(arguments: [
        // Location permission denied or not yet granted: no network name.
        (NetworkInterface(name: "Wi-Fi 6", networkName: nil, linkRate: 866_000_000), "Wi-Fi 6 · 866 Mb/s link"),
        (NetworkInterface(name: "Ethernet", linkRate: 1_000_000_000), "Ethernet · 1 Gb/s link"),
        (NetworkInterface(name: "iPhone USB"), "iPhone USB"),
    ])
    func interfaceLineLeavesOutWhatIsUnknown(interface: NetworkInterface, line: String) throws {
        let monitor = try monitor([snapshot(network(down: 0, up: 0, interface: interface))])

        monitor.tick()

        #expect(monitor.networkDetail().interfaceLine == line)
        #expect(monitor.networkPanel(range: .fiveMinutes).interfaceLine == line)
    }

    @Test func offlineAndUnreadableNetworksSaySo() throws {
        let offline = try monitor([snapshot(.value(NetworkReading(
            interface: nil, downloadPerSecond: 0, uploadPerSecond: 0, received: 0, sent: 0)))])
        offline.tick()
        #expect(offline.networkSubtitle == "Not connected")

        let failed = try monitor([snapshot(.unavailable(.failed("sysctl")))])
        failed.tick()
        #expect(failed.networkSubtitle == "Network unavailable")
        #expect(failed.networkDetail().download.value == "—")
    }

    // MARK: Window tab

    @Test func liveRatesSplitValueAndUnit() throws {
        let monitor = try monitor([snapshot(network(down: 4_200_000, up: 380_000))])

        monitor.tick()
        let detail = monitor.networkDetail()

        #expect(detail.download == NetworkFormat.Rate(value: "4.2", unit: "MB/s"))
        #expect(detail.upload == NetworkFormat.Rate(value: "380", unit: "KB/s"))
    }

    @Test func sessionTotalsCountOnlyThisLaunch() throws {
        let history = try MetricsHistory(.inMemory)
        // A previous session, an hour before this launch.
        try history.record(Snapshot(timestamp: clock.now.addingTimeInterval(-3600), cpu: .cpu(user: 0, system: 0),
                                    network: network(down: 0, up: 0, received: 5_000_000_000, sent: 1_000_000_000)))
        let monitor = try monitor([
            snapshot(.unavailable(.warmingUp)),
            snapshot(network(down: 0, up: 0, received: 1_900_000_000, sent: 306_000_000)),
        ], history: history)

        run(monitor, ticks: 3)
        let detail = monitor.networkDetail()

        #expect(detail.downloaded == "3.8 GB")
        #expect(detail.uploaded == "612 MB")
        #expect(monitor.networkPanel(range: .fiveMinutes).downloaded == "3.8 GB")
    }

    @Test func sessionShowsItsStartTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = clock.now
        let history = try MetricsHistory(.inMemory)
        func detail(at now: Date) -> NetworkDetail {
            NetworkDetail.make(snapshot: Snapshot(timestamp: now, cpu: .cpu(user: 0, system: 0)), apps: [],
                               history: history, units: .bytes, sessionStart: start, calendar: calendar)
        }

        #expect(detail(at: start.addingTimeInterval(600)).sessionStart == "since 14:13")
        #expect(detail(at: start.addingTimeInterval(86400)).sessionStart == "since 21 Sep 14:13")
        #expect(detail(at: start).downloaded == "—")
    }

    @Test func liveChartCoversTheLastMinuteScaledToItsPeak() throws {
        let monitor = try monitor([
            snapshot(network(down: 1_000_000, up: 200_000)),
            snapshot(network(down: 4_000_000, up: 1_000_000)),
        ])

        run(monitor, ticks: 2)
        let live = monitor.networkDetail().live

        #expect(live.count == NetworkDetail.liveBarCount)
        #expect(live.compactMap { $0 } == [ThroughputBar(down: 0.2, up: 0.04), ThroughputBar(down: 0.8, up: 0.2)])
        #expect(live.last! != nil)
    }

    @Test func dailyChartsShowPerDayDownloadAndUploadFromHistory() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_790_847_660)  // Thu 2026-10-01 09:41 UTC
        let history = try MetricsHistory(.inMemory)
        func record(daysAgo: Int, received: Double, sent: Double) throws {
            try history.record(Snapshot(timestamp: now.addingTimeInterval(-Double(daysAgo) * 86400), cpu: .cpu(user: 0, system: 0),
                                        network: network(down: 0, up: 0, received: received, sent: sent)))
        }
        try record(daysAgo: 0, received: 4_000_000_000, sent: 500_000_000)
        try record(daysAgo: 2, received: 18_000_000_000, sent: 2_000_000_000)
        try record(daysAgo: 20, received: 1_000_000_000, sent: 100_000_000)

        let detail = NetworkDetail.make(snapshot: Snapshot(timestamp: now, cpu: .cpu(user: 0, system: 0)), apps: [],
                                        history: history, units: .bytes, sessionStart: now, calendar: calendar)

        let week = detail.lastWeek
        #expect(week.totals == "↓ 22 GB · ↑ 2.5 GB")
        #expect(week.yAxis == ["20 GB", "10 GB", "0"])
        #expect(week.bars == [nil, nil, nil, nil, ThroughputBar(down: 0.9, up: 0.1), nil, ThroughputBar(down: 0.2, up: 0.025)])
        #expect(week.xAxis == ["Fri", "Sat", "Sun", "Mon", "Tue", "Wed", "Today"])

        let month = detail.lastMonth
        #expect(month.bars.count == 30)
        #expect(month.bars.compactMap { $0 }.count == 3)
        #expect(month.totals == "↓ 23 GB · ↑ 2.6 GB")
        #expect(month.xAxis.compactMap { $0 } == ["Sep 2", "Sep 9", "Sep 16", "Sep 23", "Today"])
    }

    @Test func dailyChartsWithoutHistoryAreEmpty() throws {
        let monitor = try monitor([snapshot(network(down: 0, up: 0))])

        let detail = monitor.networkDetail()

        #expect(detail.lastWeek.totals == "No history yet")
        #expect(detail.lastWeek.bars == Array(repeating: nil, count: 7))
        #expect(detail.lastWeek.yAxis.isEmpty)
    }

    @Test func topAppsShowLiveRatesBusiestFirst() throws {
        let processes = [
            ProcessSample(pid: 1, name: "Slack", path: slack, cpu: 0.9, resources: ResourceUse(network: 220_000)),
            ProcessSample(pid: 2, name: "Safari", path: safari, cpu: 0.1, isRegularApp: true,
                          resources: ResourceUse(network: 3_000_000)),
            ProcessSample(pid: 3, name: "Safari Networking", path: safari, cpu: 0, resources: ResourceUse(network: 200_000)),
            ProcessSample(pid: 4, name: "Spotify", path: spotify, cpu: 0.2, resources: ResourceUse(network: 0)),
            ProcessSample(pid: 5, name: "kernel_task", path: nil, cpu: 0.2),
        ]
        let monitor = try monitor([snapshot(network(down: 0, up: 0), processes: processes)])

        monitor.tick()
        let apps = monitor.networkDetail().topApps

        #expect(apps.map(\.name) == ["Safari", "Slack"])
        #expect(apps.map(\.value) == ["3.2 MB/s", "220 KB/s"])
        #expect(apps.map(\.share) == [1, 220_000.0 / 3_200_000])
        #expect(monitor.networkPanel(range: .fiveMinutes).topApps.first?.canQuit == true)
    }

    @Test func topAppsFollowTheUnitsSetting() throws {
        preferences.networkUnits = .bits
        let monitor = try monitor([snapshot(network(down: 0, up: 0), processes: [
            ProcessSample(pid: 1, name: "Safari", path: safari, cpu: 0, resources: ResourceUse(network: 3_000_000)),
        ])])

        monitor.tick()

        #expect(monitor.networkDetail().topApps.map(\.value) == ["24 Mbps"])
    }

    @Test func peaksNameTheBusiestApp() throws {
        let monitor = try monitor([snapshot(network(down: 5_000_000, up: 0), processes: [
            ProcessSample(pid: 1, name: "Slack", path: slack, cpu: 0.9, resources: ResourceUse(network: 10_000)),
            ProcessSample(pid: 2, name: "Safari", path: safari, cpu: 0.1, resources: ResourceUse(network: 4_000_000)),
        ])])

        monitor.tick()

        let peak = try #require(try monitor.history.summary(.networkDown, over: .oneMinute, endingAt: clock.now).peak)
        #expect(peak.contributor == "Safari")
    }

    // MARK: Popover tab

    @Test func popoverHistoryCoversTheChosenRange() throws {
        let monitor = try monitor([snapshot(network(down: 2_000_000, up: 500_000))])

        run(monitor, ticks: 3)
        let panel = monitor.networkPanel(range: .oneHour)

        #expect(panel.range == .oneHour)
        #expect(panel.history.count == NetworkPanel.historyBarCount)
        #expect(panel.history.last! == ThroughputBar(down: 0.8, up: 0.2))
        #expect(panel.download.text == "2.0 MB/s")
        #expect(panel.lastWeek.bars.count == 7)
    }
}
