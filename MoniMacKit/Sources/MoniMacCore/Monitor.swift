import Foundation
import Observation
import os

private let log = Logger(subsystem: "io.github.lethanhvietctt5.MoniMac", category: "Monitor")

/// Drives sampling and exposes the feature state every surface renders.
@MainActor
@Observable
public final class Monitor {
    public private(set) var latest: Snapshot?
    /// Running apps with their helpers rolled up, busiest first. Grouped on demand, once per snapshot.
    public var apps: [AppUsage] {
        guard let latest else { return [] }
        if let cached = appsCache, cached.timestamp == latest.timestamp { return cached.apps }
        let apps = AppGrouping.apps(from: latest.processes.value ?? [])
        appsCache = (latest.timestamp, apps)
        return apps
    }
    public private(set) var menuBarItems: [MenuBarItem] = []

    @ObservationIgnored private let sampler: any SystemSampler
    @ObservationIgnored private let history: MetricsHistory
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let actions: any SystemActions
    @ObservationIgnored private var appsCache: (timestamp: Date, apps: [AppUsage])?

    public init(
        sampler: any SystemSampler, history: MetricsHistory, preferences: Preferences, actions: any SystemActions
    ) {
        self.sampler = sampler
        self.history = history
        self.preferences = preferences
        self.actions = actions
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

    // MARK: Feature state

    /// The popover CPU tab for the given chart range.
    public func cpuPanel(range: TimeRange) -> CPUPanel {
        CPUPanel.make(snapshot: latest, apps: apps, history: history, range: range, mode: preferences.cpuMode)
    }

    /// The main window's CPU tab for the given chart range.
    public func cpuDetail(range: TimeRange) -> CPUDetail {
        CPUDetail.make(snapshot: latest, apps: apps, history: history, range: range, mode: preferences.cpuMode)
    }

    // MARK: Intents

    public func setMenuBarStyle(_ style: MenuBarStyle, for metric: Metric) {
        preferences.setMenuBarStyle(style, for: metric)
        rebuildMenuBarItems()
    }

    /// Asks the app with this id to quit normally. Does nothing for groups that can't be quit.
    public func quitApp(id: AppUsage.ID) {
        guard let pid = apps.first(where: { $0.id == id })?.quitPID else { return }
        actions.quitApp(pid: pid)
    }

    public func openActivityMonitor() {
        actions.openActivityMonitor()
    }

    // MARK: Menu bar

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
        case .cpu:
            guard let latest, let cpu = latest.cpu.value else { return Format.placeholder }
            return Format.cpu(cpu.total, mode: preferences.cpuMode, logicalCores: latest.system.logicalCores)
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
