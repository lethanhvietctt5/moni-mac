import Foundation

/// The share card's headline: a rule-based phrase table, no LLM and no network.
/// Rules are tried in order and the first match wins; the last always matches.
public enum WeeklySummaryHeadline: CaseIterable, Sendable {
    case noHistory
    case busyAndHot
    case hot
    case busyAndCool
    case busy
    case memoryTight
    case graphics
    case downloads
    case quiet
    case steady

    /// Average CPU (share of the whole CPU) at which the week counts as busy.
    static let busyCPU = 0.25
    /// Average CPU below which the week counts as quiet.
    static let quietCPU = 0.08
    /// Throttling spells from which the week counts as hot. Fewer is "low" and still a cool head.
    static let hotThrottling = 3
    static let heavyGPU = 0.25
    /// Downloaded bytes that make a week download-heavy.
    static let heavyDownload = 50e9

    func matches(_ figures: WeeklySummary.Figures) -> Bool {
        let busy = (figures.cpuAverage ?? 0) >= Self.busyCPU
        let hot = (figures.throttlingEvents ?? 0) >= Self.hotThrottling
        // Unknown throttling (no thermal state recorded) is neither hot nor cool.
        let cool = figures.throttlingEvents.map { $0 < Self.hotThrottling } ?? false
        return switch self {
        case .noHistory: figures.covered <= 0
        case .busyAndHot: busy && hot
        case .hot: hot
        case .busyAndCool: busy && cool
        case .busy: busy
        case .memoryTight: figures.memoryPressure == .critical
        case .graphics: (figures.gpuAverage ?? 0) >= Self.heavyGPU
        case .downloads: (figures.downloaded ?? 0) >= Self.heavyDownload
        case .quiet: figures.cpuAverage.map { $0 < Self.quietCPU } ?? false
        case .steady: true
        }
    }

    /// The phrase, with "week" or "day" for the span history covers.
    func phrase(span: String) -> String {
        switch self {
        case .noHistory: "Just getting started."
        case .busyAndHot: "Busy \(span), running hot."
        case .hot: "A warm \(span)."
        case .busyAndCool: "Busy \(span), cool head."
        case .busy: "A busy \(span)."
        case .memoryTight: "Memory ran tight."
        case .graphics: "Pixels pushed all \(span)."
        case .downloads: "Downloaded half the internet."
        case .quiet: "A quiet \(span)."
        case .steady: "A steady \(span)."
        }
    }

    static func rule(for figures: WeeklySummary.Figures) -> WeeklySummaryHeadline {
        allCases.first { $0.matches(figures) } ?? .steady
    }

    /// The headline for these figures. Under a day and a half of history it speaks of a day, not a week.
    static func pick(_ figures: WeeklySummary.Figures) -> String {
        rule(for: figures).phrase(span: figures.covered < 36 * 3600 ? "day" : "week")
    }
}
