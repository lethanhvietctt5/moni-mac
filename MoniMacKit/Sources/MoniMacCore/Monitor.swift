import Foundation
import Observation
import os

private let log = Logger(subsystem: "io.github.lethanhvietctt5.MoniMac", category: "Monitor")

/// Drives sampling and exposes the feature state every surface renders.
@MainActor
@Observable
public final class Monitor {
    public private(set) var latest: Snapshot?
    public private(set) var menuBarItems: [MenuBarItem] = []

    @ObservationIgnored private let sampler: any SystemSampler
    @ObservationIgnored private let history: MetricsHistory
    @ObservationIgnored private let preferences: Preferences

    public init(sampler: any SystemSampler, history: MetricsHistory, preferences: Preferences) {
        self.sampler = sampler
        self.history = history
        self.preferences = preferences
        rebuildMenuBarItems()
    }

    /// Takes one sample and records it. The refresh loop calls this; tests call it directly.
    public func tick() {
        let snapshot = sampler.sample()
        latest = snapshot
        do {
            try history.record(snapshot)
        } catch {
            // History is best effort: a failed write leaves a gap but must not stop live values.
            log.error("Failed to record history: \(String(describing: error), privacy: .public)")
        }
        rebuildMenuBarItems()
    }

    /// Samples immediately, then every `interval`, until the task is cancelled.
    public func run(every interval: Duration) async {
        while !Task.isCancelled {
            tick()
            try? await Task.sleep(for: interval)
        }
    }

    public func setMenuBarStyle(_ style: MenuBarStyle, for metric: Metric) {
        preferences.setMenuBarStyle(style, for: metric)
        rebuildMenuBarItems()
    }

    private func rebuildMenuBarItems() {
        menuBarItems = Metric.allCases.map { metric in
            let style = preferences.menuBarStyle(for: metric)
            return MenuBarItem(
                metric: metric,
                style: style,
                text: text(for: metric),
                bars: style == .value ? [] : bars(for: metric)
            )
        }
    }

    private func text(for metric: Metric) -> String {
        switch metric {
        case .cpu: latest?.cpu.value.map { Format.percent($0.total) } ?? Format.placeholder
        }
    }

    private func bars(for metric: Metric) -> [Double?] {
        let empty = [Double?](repeating: nil, count: Sparkline.barCount)
        guard let now = latest?.timestamp else { return empty }
        let series: SeriesKey = switch metric {
        case .cpu: .cpuTotal
        }
        let points = (try? history.summary(series, over: .oneMinute, endingAt: now).points) ?? []
        return Sparkline.bars(points, endingAt: now)
    }
}
