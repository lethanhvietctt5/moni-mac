import Foundation

/// A resource an app can be busiest at.
public enum OverviewResource: CaseIterable, Sendable {
    case cpu, memory, gpu, network, disk

    /// The Overview metric this resource is part of, which gives it its title and color.
    public var metric: OverviewMetric {
        switch self {
        case .cpu: .cpu
        case .memory: .memory
        case .gpu: .gpu
        case .network: .network
        case .disk: .disk
        }
    }
}

/// One app in Busiest Right Now, labelled by the resource it uses most, e.g. "Xcode 12% CPU".
public struct OverviewBusyApp: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var bundlePath: String?
    /// e.g. "14 processes".
    public var processes: String
    public var resource: OverviewResource
    /// The dominant resource's figure, e.g. "12% CPU", "1.9 GB", "9.4 MB/s".
    public var value: String
    /// Bar length relative to the busiest app in the list, 0...1.
    public var share: Double
    /// Tooltip, e.g. "Xcode: busiest at CPU".
    public var help: String
}

/// Picks each app's dominant resource and ranks apps by it.
///
/// CPU, memory, and GPU figures are in different units, so each is scored as a share of what the
/// Mac has: CPU of all cores, memory of installed memory, GPU of its time. Network and disk have no
/// fixed capacity, so their rates are scored against reference rates instead. Scoring against the
/// Mac's current total would make a trickle look busy on an idle Mac.
///
/// Memory is held rather than used: an idle browser keeps gigabytes. It counts at `memoryWeight`,
/// so an app doing work outranks one that only holds memory, and memory leads when nothing is busy.
public enum OverviewBusiest {
    static let memoryWeight = 0.25
    /// Network traffic that scores as fully busy: 100 Mbps, a typical home connection.
    static let networkReference = 12_500_000.0
    /// Disk traffic that scores as fully busy: a heavy, sustained copy for an internal SSD.
    static let diskReference = 100_000_000.0

    /// The `count` apps with the highest dominant-resource score, highest first.
    static func rows(
        _ apps: [AppUsage], snapshot: Snapshot?, mode: CPUMode, units: NetworkUnits, count: Int
    ) -> [OverviewBusyApp] {
        let cores = max(snapshot?.system.logicalCores ?? 1, 1)
        let memoryTotal = snapshot?.memory.value?.total
        // Stable for equal scores: keeps the CPU order of the input.
        let ranked = apps.compactMap { app in
            dominant(app, logicalCores: cores, memoryTotal: memoryTotal).map { (app: app, resource: $0.resource, score: $0.score) }
        }
            .enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .prefix(count)
            .map(\.element)
        let top = ranked.first?.score ?? 0
        return ranked.map { entry in
            let app = entry.app
            return OverviewBusyApp(
                id: app.id, name: app.name, bundlePath: app.bundlePath,
                processes: app.processCount == 1 ? "1 process" : "\(app.processCount) processes",
                resource: entry.resource,
                value: value(of: entry.resource, for: app, logicalCores: cores, mode: mode, units: units),
                share: top > 0 ? min(entry.score / top, 1) : 0,
                help: "\(app.name): busiest at \(entry.resource.metric.title)"
            )
        }
    }

    /// The resource with the highest score and that score, or nil when the app uses nothing measurable.
    static func dominant(
        _ app: AppUsage, logicalCores: Int, memoryTotal: UInt64?
    ) -> (resource: OverviewResource, score: Double)? {
        let resources = app.resources
        let scores: [(OverviewResource, Double?)] = [
            (.cpu, app.cpu / Double(max(logicalCores, 1))),
            (.memory, memoryTotal.flatMap { total in
                resources.memory.map { total > 0 ? memoryWeight * Double($0) / Double(total) : 0 }
            }),
            (.gpu, resources.gpu),
            (.network, resources.network.map { $0 / networkReference }),
            (.disk, diskRate(resources).map { $0 / diskReference }),
        ]
        // Ties go to the earlier resource, so the order above is the tie-break.
        let best = scores.compactMap { resource, score in score.map { (resource: resource, score: $0) } }
            .reduce(nil as (resource: OverviewResource, score: Double)?) { best, next in
                best.map { $0.score >= next.score ? $0 : next } ?? next
            }
        guard let best, best.score > 0 else { return nil }
        return best
    }

    private static func diskRate(_ resources: ResourceUse) -> Double? {
        switch (resources.diskReadPerSecond, resources.diskWritePerSecond) {
        case (nil, nil): nil
        case let (read, write): (read ?? 0) + (write ?? 0)
        }
    }

    private static func value(
        of resource: OverviewResource, for app: AppUsage, logicalCores: Int, mode: CPUMode, units: NetworkUnits
    ) -> String {
        let resources = app.resources
        return switch resource {
        case .cpu: Format.cpu(app.cpu / Double(logicalCores), mode: mode, logicalCores: logicalCores) + " CPU"
        case .memory: Format.memorySize(resources.memory ?? 0)
        case .gpu: Format.percent(resources.gpu ?? 0) + " GPU"
        case .network: NetworkFormat.rate(resources.network ?? 0, units: units).text
        case .disk: DiskFormat.rate(diskRate(resources) ?? 0)
        }
    }
}
