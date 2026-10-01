import Foundation

/// What SystemSampler reads from the GPU on each tick.
public struct GPUReading: Equatable, Sendable {
    /// e.g. "Apple M4".
    public var model: String
    /// GPU cores, when the driver reports them.
    public var coreCount: Int?
    /// Share of time the GPU was busy, 0...1.
    public var utilization: Double
    /// Share of time the renderer (fragment) stage was busy, 0...1.
    public var renderer: Double?
    /// Share of time the tiler (vertex) stage was busy, 0...1.
    public var tiler: Double?
    /// Unified memory the GPU is using, in bytes.
    public var memoryInUse: UInt64?
    /// The Mac's unified memory, which the GPU shares with the CPU, in bytes.
    public var unifiedMemory: UInt64?

    public init(
        model: String, coreCount: Int?, utilization: Double, renderer: Double? = nil, tiler: Double? = nil,
        memoryInUse: UInt64? = nil, unifiedMemory: UInt64? = nil
    ) {
        self.model = model
        self.coreCount = coreCount
        self.utilization = utilization
        self.renderer = renderer
        self.tiler = tiler
        self.memoryInUse = memoryInUse
        self.unifiedMemory = unifiedMemory
    }

    /// e.g. "Apple M4 · 10-core GPU".
    public var subtitle: String {
        coreCount.map { "\(model) · \($0)-core GPU" } ?? model
    }
}

extension SeriesKey {
    /// GPU utilization, 0...1. Samples name the busiest GPU app as the contributor.
    public static let gpuUtilization = SeriesKey(rawValue: "gpu.utilization")
    /// GPU memory in use, bytes.
    public static let gpuMemory = SeriesKey(rawValue: "gpu.memory")
}

extension Snapshot {
    /// Values MetricsHistory records for the GPU.
    var gpuSeries: [SeriesSample] {
        guard let gpu = gpu.value else { return [] }
        let busiest = AppGrouping.busiestApp(in: processes.value ?? [], by: \.resources.gpu)
        var samples = [SeriesSample(.gpuUtilization, gpu.utilization, contributor: busiest)]
        if let memory = gpu.memoryInUse { samples.append(SeriesSample(.gpuMemory, Double(memory))) }
        return samples
    }
}

/// The GPU menu bar item: utilization, e.g. `18%`.
enum GPUMenuBar: MenuBarMetric {
    static func widestText(preferences: Preferences) -> String {
        "100%"
    }

    static func text(_ snapshot: Snapshot?, preferences: Preferences) -> String {
        guard let gpu = snapshot?.gpu.value else { return Format.placeholder }
        return Format.percent(gpu.utilization)
    }

    @MainActor
    static func bars(history: MetricsHistory, endingAt now: Date?) -> [Double?] {
        guard let now else { return Sparkline.empty }
        let points = (try? history.summary(.gpuUtilization, over: .oneMinute, endingAt: now).points) ?? []
        return Sparkline.bars(points, endingAt: now)
    }
}

extension Monitor {
    /// The main window toolbar subtitle for the GPU tab, e.g. "Apple M4 · 10-core GPU".
    public var gpuSubtitle: String? {
        latest?.gpu.value?.subtitle
    }

    /// The popover GPU tab for the given chart range.
    public func gpuPanel(range: TimeRange) -> GPUPanel {
        GPUPanel.make(snapshot: latest, apps: apps, history: history, range: range)
    }

    /// The main window's GPU tab for the given chart range.
    public func gpuDetail(range: TimeRange) -> GPUDetail {
        GPUDetail.make(snapshot: latest, apps: apps, history: history, range: range)
    }
}

/// GPU figures shared by the popover and window tabs.
enum GPUFormat {
    /// Bytes in binary gigabytes, as About This Mac counts them, e.g. `"2.1 GB"`, `"18 GB"`.
    static func gigabytes(_ bytes: UInt64, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f GB", Double(bytes) / 1_073_741_824)
    }

    /// Why the GPU tab has no figures.
    static func reason(_ reading: Reading<GPUReading>?) -> String {
        switch reading {
        case nil, .value: "Waiting for the first sample"
        case .unavailable(.warmingUp): "Waiting for the first sample"
        case .unavailable(.unsupported): "This Mac doesn't report GPU statistics"
        case .unavailable(.failed(let message)): "GPU statistics unavailable: \(message)"
        }
    }

    /// Apps using the GPU, busiest first, and a note to show instead when there are none.
    static func topApps(_ apps: [AppUsage], count: Int) -> (apps: [AppUsage], note: String?) {
        // No apps yet means the process list is still warming up.
        if apps.isEmpty { return ([], nil) }
        guard apps.contains(where: { $0.resources.gpu != nil }) else {
            return ([], "Per-app GPU use isn't readable on this Mac")
        }
        // Stable for equal use: keeps the CPU order of the input.
        let ranked = apps.enumerated()
            .filter { ($0.element.resources.gpu ?? 0) > 0 }
            .sorted { lhs, rhs in
                let (a, b) = (lhs.element.resources.gpu ?? 0, rhs.element.resources.gpu ?? 0)
                return a != b ? a > b : lhs.offset < rhs.offset
            }
            .map(\.element)
        return (Array(ranked.prefix(count)), ranked.isEmpty ? "No apps are using the GPU" : nil)
    }

    /// A per-app share with one decimal, e.g. `"12.4%"`.
    static func appShare(_ share: Double) -> String {
        String(format: "%.1f%%", min(max(share, 0), 1) * 100)
    }
}
