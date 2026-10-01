import Foundation
import Testing
@testable import MoniMacCore

@MainActor
struct GPUDetailTests {
    let utc = TimeZone(identifier: "UTC")!
    /// 2026-10-01 09:41 UTC.
    let now = Date(timeIntervalSince1970: 1_790_847_660)
    static let gib: UInt64 = 1 << 30

    static func reading(_ utilization: Double, renderer: Double = 0.18, tiler: Double = 0.06) -> GPUReading {
        GPUReading(model: "Apple M4", coreCount: 10, utilization: utilization, renderer: renderer, tiler: tiler,
                   memoryInUse: 2_254_857_830, unifiedMemory: 16 * gib)
    }

    static func app(_ pid: Int32, _ name: String, cpu: Double = 0, gpu: Double?) -> ProcessSample {
        ProcessSample(pid: pid, name: name, path: "/Applications/\(name).app/Contents/MacOS/\(name)", cpu: cpu,
                      resources: ResourceUse(gpu: gpu))
    }

    private func snapshot(at time: Date, utilization: Double = 0.18, processes: [ProcessSample] = []) -> Snapshot {
        Snapshot(timestamp: time, cpu: .cpu(user: 0.2, system: 0.1), processes: .value(processes),
                 gpu: .value(Self.reading(utilization)))
    }

    private func detail(
        history snapshots: [Snapshot], latest: Snapshot, range: TimeRange = .twentyFourHours
    ) throws -> GPUDetail {
        let history = try MetricsHistory(.inMemory)
        for snapshot in snapshots { try history.record(snapshot) }
        let apps = AppGrouping.apps(from: latest.processes.value ?? [])
        return GPUDetail.make(snapshot: latest, apps: apps, history: history, range: range, timeZone: utc)
    }

    @Test func liveTilesMatchTheDesign() throws {
        let detail = try detail(history: [], latest: snapshot(at: now))

        #expect(detail.subtitle == "Apple M4 · 10-core GPU")
        #expect(detail.utilization.value == "18%")
        #expect(detail.utilization.caption == "Renderer 18% · Tiler 6%")
        #expect(detail.memory.value == "2.1 GB")
        #expect(detail.memory.caption == "Shared from 16 GB unified")
        #expect(detail.unavailable == nil)
    }

    @Test func peakNamesTheTopGPUAppAtThePeakAndItsTime() throws {
        let spike = now.addingTimeInterval(-(19 * 3600 + 29 * 60))  // 14:12 the previous day
        let atSpike = [
            Self.app(1, "Final Cut Pro", cpu: 0.5, gpu: 0.8),
            Self.app(2, "Safari", cpu: 2.0, gpu: 0.05),  // busiest by CPU, not by GPU
        ]
        let detail = try detail(
            history: [
                snapshot(at: spike, utilization: 0.91, processes: atSpike),
                snapshot(at: now, utilization: 0.12, processes: [Self.app(2, "Safari", gpu: 0.1)]),
            ],
            latest: snapshot(at: now)
        )

        #expect(detail.peak.value == "91%")
        #expect(detail.peak.caption == "Final Cut Pro · 14:12")
    }

    @Test func peakShowsOnlyTheTimeWhenNoAppUsedTheGPU() throws {
        let detail = try detail(history: [snapshot(at: now, utilization: 0.4)], latest: snapshot(at: now))

        #expect(detail.peak.caption == "at 09:41")
    }

    @Test func averageIsComparedWithTheDayBeforeFromHistory() throws {
        // Yesterday's window is old enough that its one-minute buckets get pruned by today's writes.
        let yesterday = (0..<10).map { snapshot(at: now.addingTimeInterval(-30 * 3600 + Double($0) * 60), utilization: 0.17) }
        let today = (0..<10).map { snapshot(at: now.addingTimeInterval(-Double(9 - $0) * 60), utilization: 0.14) }

        let detail = try detail(history: yesterday + today, latest: snapshot(at: now))

        #expect(detail.average.value == "14%")
        #expect(detail.average.caption == "3 pts lower than yesterday")
    }

    @Test(arguments: [
        (0.14, 0.17, "3 pts lower than yesterday"),
        (0.20, 0.19, "1 pt higher than yesterday"),
        (0.142, 0.138, "Same as yesterday"),
    ])
    func comparisonUsesDisplayedPoints(today: Double, yesterday: Double, text: String) {
        #expect(GPUDetail.comparison(today: today, yesterday: yesterday) == text)
    }

    @Test func comparisonSaysWhenYesterdayIsMissing() throws {
        let detail = try detail(history: [snapshot(at: now)], latest: snapshot(at: now))

        #expect(detail.average.caption == "No history from yesterday")
    }

    @Test func historyFollowsTheRangeWithItsSummary() throws {
        let earlier = now.addingTimeInterval(-3 * 86400)
        let snapshots = [snapshot(at: earlier, utilization: 0.9), snapshot(at: now, utilization: 0.1)]

        let day = try detail(history: snapshots, latest: snapshot(at: now))
        let week = try detail(history: snapshots, latest: snapshot(at: now), range: .sevenDays)

        #expect(day.history.count == GPUDetail.historyBarCount)
        #expect(day.history.last == 0.1)
        #expect(day.historySummary == "Avg 10% · Peak 10%")
        #expect(week.historySummary == "Avg 50% · Peak 90%")
        #expect(week.xAxis == ["Thu", "Sat", "Sun", "Tue", "Now"])
    }

    @Test func topAppsAreRankedByGPUWithOneDecimal() throws {
        let latest = snapshot(at: now, processes: [
            Self.app(1, "Xcode", cpu: 3.0, gpu: 0.003),
            Self.app(2, "Final Cut Pro", cpu: 0.2, gpu: 0.124),
            Self.app(3, "Notes", cpu: 0.1, gpu: 0),
            Self.app(4, "Safari", cpu: 0.4, gpu: 0.012),
        ])

        let rows = try detail(history: [], latest: latest).topApps

        #expect(rows.map(\.name) == ["Final Cut Pro", "Safari", "Xcode"])
        #expect(rows.map(\.value) == ["12.4%", "1.2%", "0.3%"])
    }

    @Test func topAppsExplainWhenPerAppUseIsUnreadable() throws {
        let latest = snapshot(at: now, processes: [Self.app(1, "Xcode", cpu: 3.0, gpu: nil)])

        let detail = try detail(history: [], latest: latest)

        #expect(detail.topApps.isEmpty)
        #expect(detail.topAppsNote == "Per-app GPU use isn't readable on this Mac")
    }

    @Test func topAppsSayWhenNothingUsesTheGPU() throws {
        let latest = snapshot(at: now, processes: [Self.app(1, "Notes", gpu: 0)])

        #expect(try detail(history: [], latest: latest).topAppsNote == "No apps are using the GPU")
    }

    @Test func unavailableGPUShowsPlaceholdersAndTheReason() throws {
        let latest = Snapshot(timestamp: now, cpu: .cpu(user: 0.2, system: 0.1), gpu: .unavailable(.unsupported))

        let detail = try detail(history: [], latest: latest)

        #expect(detail.subtitle == nil)
        #expect(detail.utilization.value == "—")
        #expect(detail.memory.value == "—")
        #expect(detail.unavailable == "This Mac doesn't report GPU statistics")
    }
}
