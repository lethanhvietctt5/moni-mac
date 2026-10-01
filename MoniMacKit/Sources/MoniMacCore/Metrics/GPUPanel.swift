import Foundation

/// Everything the popover's GPU tab shows.
public struct GPUPanel: Equatable, Sendable {
    /// The ranges the popover chart offers.
    public static let ranges: [TimeRange] = [.oneMinute, .fiveMinutes, .oneHour, .twentyFourHours]
    public static let historyBarCount = 30
    public static let topAppCount = 4

    public struct AppRow: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var bundlePath: String?
        /// e.g. "12.4%".
        public var value: String
        /// Bar length: share of the GPU, 0...1.
        public var share: Double
        public var canQuit: Bool
    }

    /// e.g. "Apple M4 · 10-core GPU".
    public var modelLine: String
    public var utilization: String
    public var range: TimeRange
    /// `historyBarCount` utilization bars over `range` (0...1), oldest first; nil where there's no data.
    public var history: [Double?]
    public var renderer: String
    public var tiler: String
    /// GPU memory in use, e.g. "2.1 GB".
    public var memory: String
    /// e.g. "of 16 GB unified".
    public var memoryDetail: String
    /// GPU memory as a share of unified memory, for the bar.
    public var memoryShare: Double?
    public var topApps: [AppRow]
    /// Shown instead of top apps when there are none, e.g. why per-app use can't be read.
    public var topAppsNote: String?
    /// Why there are no GPU figures; nil while they're live.
    public var unavailable: String?
}

extension GPUPanel {
    @MainActor
    static func make(snapshot: Snapshot?, apps: [AppUsage], history: MetricsHistory, range: TimeRange) -> GPUPanel {
        let gpu = snapshot?.gpu.value
        let dash = Format.placeholder
        let (rows, note) = GPUFormat.appRows(apps, count: topAppCount)
        let memoryShare: Double? = gpu.flatMap { gpu in
            guard let used = gpu.memoryInUse, let total = gpu.unifiedMemory, total > 0 else { return nil }
            return Double(used) / Double(total)
        }

        return GPUPanel(
            modelLine: gpu?.subtitle ?? "GPU",
            utilization: gpu.map { Format.percent($0.utilization) } ?? dash,
            range: range,
            history: utilizationBars(history, range: range, endingAt: snapshot?.timestamp, count: historyBarCount),
            renderer: gpu?.renderer.map(Format.percent) ?? dash,
            tiler: gpu?.tiler.map(Format.percent) ?? dash,
            memory: gpu?.memoryInUse.map { GPUFormat.gigabytes($0) } ?? dash,
            memoryDetail: gpu?.unifiedMemory.map { "of \(GPUFormat.gigabytes($0, decimals: 0)) unified" } ?? "",
            memoryShare: memoryShare,
            topApps: rows,
            topAppsNote: note,
            unavailable: GPUFormat.reason(snapshot?.gpu)
        )
    }

    /// Utilization as `count` bars over the range.
    @MainActor
    static func utilizationBars(_ history: MetricsHistory, range: TimeRange, endingAt now: Date?, count: Int) -> [Double?] {
        guard let now else { return Array(repeating: nil, count: count) }
        let points = (try? history.summary(.gpuUtilization, over: range, endingAt: now).points) ?? []
        return Resample.bars(points, endingAt: now, window: range.duration, count: count)
    }
}
