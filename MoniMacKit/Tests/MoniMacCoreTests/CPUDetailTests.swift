import Foundation
import Testing
@testable import MoniMacCore

@MainActor
struct CPUDetailTests {
    let utc = TimeZone(identifier: "UTC")!
    let preferences = Preferences(defaults: UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!)
    let m3Pro = SystemInfo(chipName: "Apple M3 Pro", performanceCores: 6, efficiencyCores: 6, bootTime: nil)
    /// 2026-10-01 09:41 UTC.
    let now = Date(timeIntervalSince1970: 1_790_847_660)

    private func snapshot(at time: Date, user: Double = 0.21, system: Double = 0.11, processes: [ProcessSample] = []) -> Snapshot {
        Snapshot(
            timestamp: time,
            system: m3Pro,
            cpu: .cpu(user: user, system: system),
            cores: .value((0..<6).map { CoreUsage(kind: .efficiency, usage: 0.3 + Double($0) / 100) }
                + (0..<6).map { CoreUsage(kind: .performance, usage: 0.72 - Double($0) / 10) }),
            loadAverage: .value(LoadAverage(one: 3.42, five: 2.91, fifteen: 2.66)),
            taskCounts: .value(TaskCounts(processes: 1048, threads: 4212)),
            processes: .value(processes)
        )
    }

    private func detail(
        history snapshots: [Snapshot], latest: Snapshot, range: TimeRange = .twentyFourHours
    ) throws -> CPUDetail {
        let history = try MetricsHistory(.inMemory)
        for snapshot in snapshots { try history.record(snapshot) }
        let apps = AppGrouping.apps(from: latest.processes.value ?? [])
        return CPUDetail.make(snapshot: latest, apps: apps, history: history, range: range,
                              mode: preferences.cpuMode, timeZone: utc)
    }

    @Test func statsMatchTheDesign() throws {
        let detail = try detail(history: [], latest: snapshot(at: now))

        #expect(detail.subtitle == "Apple M3 Pro · 12 cores (6P + 6E)")
        #expect(detail.total == "32%")
        #expect(detail.stats.map(\.label) == ["User", "System", "Idle", "Load Average", "Threads"])
        #expect(detail.stats.map(\.value) == ["21%", "11%", "68%", "3.42", "4,212"])
        #expect(detail.stats.map(\.detail) == [
            "Apps & services", "macOS kernel", "8.2 of 12 cores", "5m 2.91 · 15m 2.66", "1,048 processes",
        ])
        #expect(detail.coreSummary == "6 performance · 6 efficiency")
    }

    @Test func peakNamesTheHighestSampleAndItsTime() throws {
        let spike = now.addingTimeInterval(-(19 * 3600 + 29 * 60))  // 14:12 the previous day
        let detail = try detail(
            history: [snapshot(at: spike, user: 0.6, system: 0.27), snapshot(at: now, user: 0.2, system: 0.1)],
            latest: snapshot(at: now)
        )

        #expect(detail.peak == "Peak 87% at 14:12")
    }

    @Test func noPeakWithoutHistory() throws {
        #expect(try detail(history: [], latest: snapshot(at: now)).peak == nil)
    }

    @Test func historyHasAFixedBarCountWithTheLatestOnTheRight() throws {
        let detail = try detail(history: [snapshot(at: now, user: 0.5, system: 0.25)], latest: snapshot(at: now))

        #expect(detail.history.count == CPUDetail.historyBarCount)
        #expect(detail.history.last??.user == 0.5)
        #expect(detail.history.dropLast().allSatisfy { $0 == nil })
    }

    @Test(arguments: [
        (TimeRange.twentyFourHours, ["09:00", "15:00", "21:00", "03:00", "Now"]),
        (.twelveHours, ["21:00", "00:00", "03:00", "06:00", "Now"]),
        (.sevenDays, ["Thu", "Sat", "Sun", "Tue", "Now"]),
        (.thirtyDays, ["1 Sep", "8 Sep", "16 Sep", "23 Sep", "Now"]),
    ])
    func xAxisLabelsSpanTheRange(range: TimeRange, labels: [String]) throws {
        #expect(try detail(history: [], latest: snapshot(at: now), range: range).xAxis == labels)
    }

    @Test func yAxisFollowsTheCPUMode() throws {
        #expect(try detail(history: [], latest: snapshot(at: now)).yAxis == ["100%", "50%", "0%"])
        preferences.cpuMode = .perCore
        #expect(try detail(history: [], latest: snapshot(at: now)).yAxis == ["1200%", "600%", "0%"])
    }

    @Test func coresShowTheirPercentPerformanceFirst() throws {
        let cores = try detail(history: [], latest: snapshot(at: now)).cores

        #expect(cores.prefix(2).map(\.label) == ["P1", "P2"])
        #expect(cores.prefix(2).map(\.value) == ["72%", "62%"])
        #expect(cores.last?.label == "E6")
    }

    @Test func topAppsShowOneDecimal() throws {
        let latest = snapshot(at: now, processes: [
            ProcessSample(pid: 1, name: "Xcode", path: "/Applications/Xcode.app/Contents/MacOS/Xcode", cpu: 1.488),
            ProcessSample(pid: 2, name: "Slack", path: "/Applications/Slack.app/Contents/MacOS/Slack", cpu: 0.384),
        ])

        let rows = try detail(history: [], latest: latest).topApps

        #expect(rows.map(\.name) == ["Xcode", "Slack"])
        #expect(rows.map(\.value) == ["12.4%", "3.2%"])
    }

    @Test func placeholdersBeforeTheFirstSample() {
        let detail = CPUDetail.make(snapshot: nil, apps: [], history: try! MetricsHistory(.inMemory),
                                    range: .twentyFourHours, mode: .system)

        #expect(detail.total == "—")
        #expect(detail.stats.allSatisfy { $0.value == "—" })
        #expect(detail.xAxis.isEmpty)
    }
}
