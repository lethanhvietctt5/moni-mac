import Foundation
import Testing
@testable import MoniMacCore

/// The popover GPU tab, the GPU menu bar item, and the toolbar subtitle, driven through Monitor.
@MainActor
struct GPUPanelTests {
    let clock = TestClock()
    let preferences = Preferences(defaults: UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!)

    private func snapshot(_ gpu: Reading<GPUReading>, processes: [ProcessSample] = []) -> Snapshot {
        Snapshot(timestamp: clock.now, cpu: .cpu(user: 0.2, system: 0.1), processes: .value(processes), gpu: gpu)
    }

    private func makeMonitor(_ script: [Snapshot]) throws -> Monitor {
        Monitor(sampler: ScriptedSampler(clock: clock, script: script), history: try MetricsHistory(.inMemory),
                preferences: preferences, actions: RecordingActions())
    }

    private func run(_ monitor: Monitor, ticks: Int, every interval: TimeInterval = 2) {
        for _ in 0..<ticks {
            monitor.tick()
            clock.advance(by: interval)
        }
    }

    private func gpuItem(_ monitor: Monitor) -> MenuBarItem? {
        monitor.menuBarItems.first { $0.metric == .gpu }
    }

    @Test func gpuMenuBarItemCanBeShownWithUtilization() throws {
        let monitor = try makeMonitor([snapshot(.value(GPUDetailTests.reading(0.18)))])

        monitor.setMenuBarItemEnabled(true, for: .gpu)
        #expect(gpuItem(monitor)?.text == "—")
        monitor.tick()

        #expect(monitor.menuBarItems.map(\.metric) == [.cpu, .gpu])
        #expect(gpuItem(monitor)?.text == "18%")
        #expect(gpuItem(monitor)?.widestText == "100%")
    }

    @Test func gpuGraphStyleShowsTheLastMinuteOfUtilization() throws {
        let monitor = try makeMonitor([
            snapshot(.value(GPUDetailTests.reading(0.1))), snapshot(.value(GPUDetailTests.reading(0.6))),
        ])
        monitor.setMenuBarItemEnabled(true, for: .gpu)
        monitor.setMenuBarStyle(.graph, for: .gpu)

        run(monitor, ticks: 3, every: 4)

        let bars = try #require(gpuItem(monitor)?.bars)
        #expect(bars.count == Sparkline.barCount)
        #expect(bars.compactMap { $0 } == [0.1, 0.6, 0.6])
    }

    @Test func menuBarShowsAPlaceholderWithoutAGPU() throws {
        let monitor = try makeMonitor([snapshot(.unavailable(.unsupported))])
        monitor.setMenuBarItemEnabled(true, for: .gpu)

        monitor.tick()

        #expect(gpuItem(monitor)?.text == "—")
    }

    @Test func subtitleNamesTheModelAndCores() throws {
        let monitor = try makeMonitor([snapshot(.value(GPUDetailTests.reading(0.18)))])
        #expect(monitor.gpuSubtitle == nil)

        monitor.tick()

        #expect(monitor.gpuSubtitle == "Apple M4 · 10-core GPU")
    }

    @Test func panelShowsLiveValues() throws {
        let processes = [
            GPUDetailTests.app(1, "Final Cut Pro", gpu: 0.124),
            GPUDetailTests.app(2, "Safari", cpu: 1.5, gpu: 0.012),
        ]
        let monitor = try makeMonitor([snapshot(.value(GPUDetailTests.reading(0.18)), processes: processes)])

        run(monitor, ticks: 2)
        let panel = monitor.gpuPanel(range: .fiveMinutes)

        #expect(panel.modelLine == "Apple M4 · 10-core GPU")
        #expect(panel.utilization == "18%")
        #expect(panel.renderer == "18%")
        #expect(panel.tiler == "6%")
        #expect(panel.memory == "2.1 GB")
        #expect(panel.memoryDetail == "of 16 GB unified")
        #expect(panel.history.count == GPUPanel.historyBarCount)
        #expect(panel.history.compactMap { $0 } == [0.18])
        #expect(panel.topApps.map(\.name) == ["Final Cut Pro", "Safari"])
        #expect(panel.topApps.map(\.value) == ["12.4%", "1.2%"])
        #expect(panel.unavailable == nil)
    }

    @Test func panelShowsTheReasonWhenGPUIsUnreadable() throws {
        let monitor = try makeMonitor([snapshot(.unavailable(.failed("IOAccelerator not found")))])

        monitor.tick()
        let panel = monitor.gpuPanel(range: .fiveMinutes)

        #expect(panel.utilization == "—")
        #expect(panel.unavailable == "GPU statistics unavailable: IOAccelerator not found")
    }

    @Test func historyRecordsTheTopGPUAppAsThePeakContributor() throws {
        let monitor = try makeMonitor([snapshot(.value(GPUDetailTests.reading(0.9)), processes: [
            GPUDetailTests.app(1, "Final Cut Pro", cpu: 0.1, gpu: 0.7),
            GPUDetailTests.app(2, "Xcode", cpu: 4, gpu: 0.01),
        ])])

        monitor.tick()

        let peak = try monitor.history.summary(.gpuUtilization, over: .oneMinute, endingAt: clock.now).peak
        #expect(peak?.contributor == "Final Cut Pro")
    }
}
