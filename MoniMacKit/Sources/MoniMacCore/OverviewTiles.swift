import Foundation

/// The metrics Overview shows, in the design's order.
public enum OverviewMetric: CaseIterable, Sendable {
    case cpu, memory, gpu, network, disk, battery, temperature

    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .gpu: "GPU"
        case .network: "Network"
        case .disk: "Disk"
        case .battery: "Battery"
        case .temperature: "Temperature"
        }
    }
}

/// Everything the main window's Overview tab shows in the Tiles view.
public struct OverviewTiles: Equatable, Sendable {
    public static let sparklineBarCount = 16
    /// What each tile's sparkline covers. Five minutes shows a trend at a 2 s refresh; one minute
    /// (the menu bar's window) is mostly noise at this width.
    public static let sparklineRange = TimeRange.fiveMinutes
    public static let busiestCount = 10

    public struct Tile: Equatable, Sendable, Identifiable {
        public var metric: OverviewMetric
        /// e.g. "32%", "11.4 GB", "4.2 MB/s", or a placeholder.
        public var value: String
        /// e.g. "User 21% · System 11%".
        public var caption: String
        /// `sparklineBarCount` bars over `sparklineRange`, 0...1, oldest first; nil where there's no data.
        public var bars: [Double?]

        public var id: OverviewMetric { metric }
    }

    /// The Processes tile: app groups split by kind, and system-wide process and thread counts.
    public struct Processes: Equatable, Sendable {
        public struct Group: Equatable, Sendable, Identifiable {
            public var kind: AppKind
            /// e.g. "38 apps", "17 agents", "6 system".
            public var label: String
            /// Share of all app groups, 0...1, for the stacked bar.
            public var share: Double

            public var id: AppKind { kind }
        }

        /// e.g. "61 apps": every app group, whatever its kind.
        public var value: String
        /// Apps, agents, then system. Empty until the process list is read.
        public var groups: [Group]
        /// e.g. "1,048 processes · 4,212 threads".
        public var caption: String
    }

    /// CPU through Temperature; Battery is left out on Macs without one.
    public var tiles: [Tile]
    public var processes: Processes
    /// Two columns of five, busiest first, filling the left column first.
    public var busiest: [OverviewBusyApp]
    /// e.g. "Show All 61 Apps".
    public var showAll: String
}

extension OverviewTiles {
    @MainActor
    static func make(
        snapshot: Snapshot?, apps: [AppUsage], history: MetricsHistory, hasBattery: Bool, preferences: Preferences
    ) -> OverviewTiles {
        let metrics = OverviewMetric.allCases.filter { $0 != .battery || hasBattery }
        return OverviewTiles(
            tiles: metrics.map { metric in
                Tile(
                    metric: metric,
                    value: value(metric, snapshot: snapshot, preferences: preferences),
                    caption: caption(metric, snapshot: snapshot, apps: apps, preferences: preferences),
                    bars: sparkline(metric, history: history, endingAt: snapshot?.timestamp)
                )
            },
            processes: processes(apps: apps, counts: snapshot?.taskCounts),
            busiest: OverviewBusiest.rows(apps, snapshot: snapshot, mode: preferences.cpuMode,
                                          units: preferences.networkUnits, count: busiestCount),
            showAll: "Show All \(Format.count(apps.count)) Apps"
        )
    }

    /// The tile's big value.
    static func value(_ metric: OverviewMetric, snapshot: Snapshot?, preferences: Preferences) -> String {
        let dash = Format.placeholder
        guard let snapshot else { return dash }
        return switch metric {
        case .cpu: snapshot.cpu.value.map {
            Format.cpu($0.total, mode: preferences.cpuMode, logicalCores: snapshot.system.logicalCores)
        } ?? dash
        case .memory: snapshot.memory.value.map { Format.memorySize($0.used) } ?? dash
        case .gpu: snapshot.gpu.value.map { Format.percent($0.utilization) } ?? dash
        case .network: snapshot.network.value.map {
            NetworkFormat.rate($0.downloadPerSecond + $0.uploadPerSecond, units: preferences.networkUnits).text
        } ?? dash
        case .disk: snapshot.disk.value.map { DiskFormat.bytes($0.volume.free) } ?? dash
        case .battery: snapshot.battery.value.map { Format.percent($0.charge) } ?? dash
        case .temperature: snapshot.headlineTemperature.map(preferences.temperatureUnit.compact) ?? dash
        }
    }

    private static func caption(
        _ metric: OverviewMetric, snapshot: Snapshot?, apps: [AppUsage], preferences: Preferences
    ) -> String {
        guard let snapshot else { return Format.placeholder }
        switch metric {
        case .cpu:
            guard let cpu = snapshot.cpu.value else { return reason(snapshot.cpu) }
            let format = { Format.cpu($0, mode: preferences.cpuMode, logicalCores: snapshot.system.logicalCores) }
            return "User \(format(cpu.user)) · System \(format(cpu.system))"
        case .memory:
            guard let memory = snapshot.memory.value else { return reason(snapshot.memory) }
            let pressure: String? = switch memory.pressureLevel {
            case .normal: "Pressure normal"
            case .warning: "Pressure warning"
            case .critical: "Pressure critical"
            case nil: nil
            }
            return (["of \(Format.memorySize(memory.total))"] + [pressure].compactMap { $0 }).joined(separator: " · ")
        case .gpu:
            guard let gpu = snapshot.gpu.value else { return reason(snapshot.gpu) }
            let memory = gpu.memoryInUse.map { "\(GPUFormat.gigabytes($0)) VRAM" }
            // Only when per-app GPU use is readable; otherwise "0 apps" would be a guess.
            let users = apps.contains { $0.resources.gpu != nil }
                ? apps.filter { ($0.resources.gpu ?? 0) > 0 }.count : nil
            let count = users.map { "\(Format.count($0)) \($0 == 1 ? "app" : "apps")" }
            let parts = [memory, count].compactMap { $0 }
            return parts.isEmpty ? gpu.model : parts.joined(separator: " · ")
        case .network:
            guard let network = snapshot.network.value else { return reason(snapshot.network) }
            let units = preferences.networkUnits
            return "↓ \(NetworkFormat.rate(network.downloadPerSecond, units: units).text) · "
                + "↑ \(NetworkFormat.rate(network.uploadPerSecond, units: units).text)"
        case .disk:
            guard let disk = snapshot.disk.value else { return reason(snapshot.disk) }
            let write = disk.io.value.map { "W \(DiskFormat.rate($0.writePerSecond))" }
            return ([DiskDetail.freeCaption(for: disk.volume)] + [write].compactMap { $0 }).joined(separator: " · ")
        case .battery:
            guard let battery = snapshot.battery.value else { return BatteryDetail.status(for: snapshot.battery) }
            let status = BatteryDetail.status(for: snapshot.battery)
            if battery.isCharging { return "Charging · \(status)" }
            return battery.isPluggedIn ? status : "On battery · \(status)"
        case .temperature:
            guard let thermal = snapshot.thermal.value else { return reason(snapshot.thermal) }
            guard let groups = snapshot.thermalGroups, groups.cpu ?? groups.hottest != nil else { return "Not reported" }
            // Without CPU sensors the headline is the hottest sensor, so don't call it the CPU.
            let source = groups.cpu != nil ? "CPU die" : "Hottest sensor"
            guard let fans = thermal.fans.value, !fans.isEmpty else { return source }
            let rpm = Int((fans.map(\.rpm).reduce(0, +) / Double(fans.count)).rounded())
            return "\(source) · \(fans.count == 1 ? "Fan" : "Fans") \(Format.count(rpm)) rpm"
        }
    }

    /// A short reason for a missing figure that fits a tile caption.
    static func reason<Value>(_ reading: Reading<Value>) -> String {
        switch reading {
        case .value, .unavailable(.warmingUp): Format.placeholder
        case .unavailable(.unsupported): "Not reported on this Mac"
        case .unavailable(.failed): "Unavailable"
        }
    }

    /// `sparklineBarCount` bars over `sparklineRange`, each 0...1.
    ///
    /// Shares (CPU, memory, GPU, charge) are drawn as they are; temperature on the 20–100 °C scale the
    /// other temperature charts use. Network has no capacity, so its busiest bar is full height, as in
    /// the menu bar; disk uses the Disk tab's scale, which never drops below 1 MB/s.
    @MainActor
    static func sparkline(_ metric: OverviewMetric, history: MetricsHistory, endingAt now: Date?) -> [Double?] {
        let (range, count) = (sparklineRange, sparklineBarCount)
        guard let now else { return Array(repeating: nil, count: count) }
        func bars(_ series: SeriesKey) -> [Double?] {
            let points = (try? history.summary(series, over: range, endingAt: now).points) ?? []
            return Resample.bars(points, endingAt: now, window: range.duration, count: count)
        }
        return switch metric {
        case .cpu: bars(.cpuTotal)
        case .memory: bars(.memoryUsed)
        case .gpu: bars(.gpuUtilization)
        case .network: NetworkFigures.throughputBars(history: history, over: range, endingAt: now, count: count)
            .map { $0.map { $0.down + $0.up } }
        case .disk: DiskChart(history: history, range: range, endingAt: now, count: count).bars
            .map { $0.map { min($0.read + $0.write, 1) } }
        case .battery: bars(.batteryCharge)
        case .temperature: bars(.thermalCPU).map { $0.map(TemperatureScale.position) }
        }
    }

    static func processes(apps: [AppUsage], counts: Reading<TaskCounts>?) -> Processes {
        func label(_ kind: AppKind, _ count: Int) -> String {
            let noun = switch kind {
            case .app: count == 1 ? "app" : "apps"
            case .agent: count == 1 ? "agent" : "agents"
            case .system: "system"
            }
            return "\(Format.count(count)) \(noun)"
        }
        let caption = counts?.value.map {
            "\(Format.count($0.processes)) processes · \(Format.count($0.threads)) threads"
        } ?? Format.placeholder
        // No groups yet means the process list is still warming up.
        guard !apps.isEmpty else { return Processes(value: Format.placeholder, groups: [], caption: caption) }
        return Processes(
            value: "\(Format.count(apps.count)) \(apps.count == 1 ? "app" : "apps")",
            groups: AppKind.allCases.map { kind in
                let count = apps.filter { $0.kind == kind }.count
                return Processes.Group(kind: kind, label: label(kind, count), share: Double(count) / Double(apps.count))
            },
            caption: caption
        )
    }
}
