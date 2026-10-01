import Foundation

/// Everything the popover's Overview tab shows: one row per metric, then Busiest Right Now.
public struct OverviewPanel: Equatable, Sendable {
    public static let busiestCount = 5

    public struct Row: Equatable, Sendable, Identifiable {
        public var metric: OverviewMetric
        /// e.g. "32%", "11.2 / 36 GB", "↓ 2.4 MB/s  ↑ 380 KB/s", "76% · 4:12 left".
        public var value: String
        /// Bar length, 0...1; nil when the figure is unavailable.
        public var share: Double?

        public var id: OverviewMetric { metric }
    }

    /// CPU through Temperature; Battery is left out on Macs without one.
    public var rows: [Row]
    public var busiest: [OverviewBusyApp]
}

extension OverviewPanel {
    @MainActor
    static func make(
        snapshot: Snapshot?, apps: [AppUsage], history: MetricsHistory, hasBattery: Bool, preferences: Preferences
    ) -> OverviewPanel {
        OverviewPanel(
            rows: OverviewMetric.shown(hasBattery: hasBattery).map { metric in
                guard let snapshot, let (value, share) = figures(metric, snapshot: snapshot, history: history,
                                                                 preferences: preferences)
                else { return Row(metric: metric, value: Format.placeholder, share: nil) }
                return Row(metric: metric, value: value, share: min(max(share, 0), 1))
            },
            busiest: OverviewBusiest.rows(apps, snapshot: snapshot, mode: preferences.cpuMode,
                                          units: preferences.networkUnits, count: busiestCount)
        )
    }

    /// A row's value and bar, or nil when the metric is unavailable.
    @MainActor
    private static func figures(
        _ metric: OverviewMetric, snapshot: Snapshot, history: MetricsHistory, preferences: Preferences
    ) -> (String, Double)? {
        switch metric {
        case .cpu:
            return snapshot.cpu.value.map {
                (Format.cpu($0.total, mode: preferences.cpuMode, logicalCores: snapshot.system.logicalCores), $0.total)
            }
        case .memory:
            return snapshot.memory.value.map { memory in
                (usedOfTotal(Format.memorySizeParts(memory.used), Format.memorySizeParts(memory.total)),
                 memory.usedFraction)
            }
        case .gpu:
            return snapshot.gpu.value.map { (Format.percent($0.utilization), $0.utilization) }
        case .network:
            guard let network = snapshot.network.value else { return nil }
            let units = preferences.networkUnits
            let rate = network.downloadPerSecond + network.uploadPerSecond
            let value = "↓ \(NetworkFormat.rate(network.downloadPerSecond, units: units).text)  "
                + "↑ \(NetworkFormat.rate(network.uploadPerSecond, units: units).text)"
            // Throughput has no capacity, so the bar compares it with the recent peak, as sparklines do.
            let peak = max(recentNetworkPeak(history, endingAt: snapshot.timestamp), rate)
            return (value, peak > 0 ? rate / peak : 0)
        case .disk:
            return snapshot.disk.value.map { disk in
                let volume = disk.volume
                let used = volume.capacity - min(volume.free, volume.capacity)
                return (usedOfTotal(DiskFormat.parts(Double(used)), DiskFormat.parts(Double(volume.capacity))),
                        DiskDetail.usedShare(volume))
            }
        case .battery:
            return snapshot.battery.value.map { (batteryValue($0), $0.charge) }
        case .temperature:
            return snapshot.headlineTemperature.map {
                (preferences.temperatureUnit.format($0), TemperatureScale.position($0))
            }
        }
    }

    /// "11.2 / 36 GB" when both share a unit, otherwise "512 MB / 1 TB".
    static func usedOfTotal(_ used: (number: String, unit: String), _ total: (number: String, unit: String)) -> String {
        used.unit == total.unit
            ? "\(used.number) / \(total.number) \(total.unit)"
            : "\(used.number) \(used.unit) / \(total.number) \(total.unit)"
    }

    /// e.g. "76% · 4:12 left", "84% · 0:38 to full", "100% · Charged", "76%" while macOS estimates.
    static func batteryValue(_ battery: BatteryReading) -> String {
        let charge = Format.percent(battery.charge)
        func clock(_ minutes: Int) -> String { String(format: "%d:%02d", max(minutes, 0) / 60, max(minutes, 0) % 60) }
        let minutes = battery.timeRemaining?.minutes
        let detail: String? = if battery.isCharging {
            minutes.map { "\(clock($0)) to full" }
        } else if battery.isPluggedIn {
            battery.isFullyCharged ? "Charged" : "Not charging"
        } else {
            minutes.map { "\(clock($0)) left" }
        }
        return detail.map { "\(charge) · \($0)" } ?? charge
    }

    /// The highest combined throughput over the sparkline window, bytes per second.
    @MainActor
    private static func recentNetworkPeak(_ history: MetricsHistory, endingAt now: Date) -> Double {
        func bars(_ series: SeriesKey) -> [Double?] { OverviewTiles.sparklineBars(series, history: history, endingAt: now) }
        return zip(bars(.networkDown), bars(.networkUp)).compactMap { down, up in
            down.map { $0 + (up ?? 0) }
        }.max() ?? 0
    }
}

extension Monitor {
    /// The main window toolbar subtitle for Overview, e.g. "MacBook Pro · M3 Pro · 18 GB".
    public var overviewSubtitle: String? {
        guard let latest else { return nil }
        return latest.system.deviceLine(memory: latest.memory.value?.total)
    }

    /// The main window's Overview tab, Tiles view.
    public func overviewTiles() -> OverviewTiles {
        OverviewTiles.make(snapshot: latest, apps: apps, history: history, hasBattery: hasBattery,
                           preferences: preferences)
    }

    /// The popover's Overview tab.
    public func overviewPanel() -> OverviewPanel {
        OverviewPanel.make(snapshot: latest, apps: apps, history: history, hasBattery: hasBattery,
                           preferences: preferences)
    }
}
