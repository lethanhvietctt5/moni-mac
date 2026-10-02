import Foundation

/// The rules behind notifications and the menu bar warning badge: a state machine over snapshots and time.
///
/// Every condition has a stable identity, (rule, app), and alerts once when it starts; it re-arms only after
/// it clears, so an ongoing condition never repeats. Disabling a rule, or an app quitting, clears its conditions.
///
/// Cost: the system rule reads each snapshot's CPU total. Per-app rules run at most every `appInterval`
/// (the process list's own cadence) over the app grouping the Monitor already caches, and keep their
/// rolling windows in memory as at most 60 buckets per app and rule: nothing is read back from history.
struct AlertEngine {
    /// How often per-app rules run: the process list refreshes about every 4 s, so evaluating more often
    /// would only see the same figures again.
    static let appInterval: TimeInterval = 4
    /// The menu bar warning: the whole CPU above 90% (of all cores) for 2 minutes.
    static let strainThreshold = 0.9
    static let strainDuration: TimeInterval = 120
    /// A longer gap between evaluations means the Mac slept (or the app stalled): sustained conditions start
    /// over rather than count the gap, and no writes are attributed to it.
    static let maxGap: TimeInterval = 60

    /// A condition that just started and should alert.
    struct Event: Equatable {
        var rule: AlertRule
        var app: AppUsage
        /// The rule's figure for the app: cores, bytes of growth, bytes written in the window, or bytes per second.
        var value: Double
    }

    private var strainedSince: Date?
    private(set) var isStrained = false
    private var lastAppEvaluation: Date?
    private var trackers: [AppUsage.ID: AppTracker] = [:]

    /// Feeds one snapshot's CPU total (share of the whole CPU, nil when unavailable) to the system rule.
    mutating func observeSystemCPU(_ total: Double?, at now: Date) {
        guard let total, total >= Self.strainThreshold else {
            strainedSince = nil
            isStrained = false
            return
        }
        let since = strainedSince ?? now
        strainedSince = since
        isStrained = now.timeIntervalSince(since) >= Self.strainDuration
    }

    /// Whether per-app rules are due, i.e. at least `appInterval` (less a little timer jitter) has passed.
    func isAppEvaluationDue(at now: Date) -> Bool {
        guard let lastAppEvaluation else { return true }
        return now.timeIntervalSince(lastAppEvaluation) >= Self.appInterval - 0.5
    }

    /// Runs the per-app rules over the current app groups and returns the conditions that just started.
    /// macOS's own processes (`AppKind.system`) are left out: they can't be quit, and some (kernel_task)
    /// run hot by design.
    mutating func observeApps(_ apps: [AppUsage], at now: Date, settings: [AlertRule: AlertRuleSettings]) -> [Event] {
        let gap = lastAppEvaluation.map { now.timeIntervalSince($0) } ?? 0
        let isContinuous = gap >= 0 && gap <= Self.maxGap
        lastAppEvaluation = now
        if !isContinuous { trackers = [:] }

        var events: [Event] = []
        var seen: Set<AppUsage.ID> = []
        for app in apps where app.kind != .system {
            seen.insert(app.id)
            var tracker = trackers[app.id] ?? AppTracker()
            for rule in AlertRule.allCases {
                guard let setting = settings[rule], setting.isEnabled else {
                    tracker.reset(rule)
                    continue
                }
                if let value = tracker.update(rule, app: app, threshold: setting.threshold, at: now,
                                              elapsed: isContinuous ? gap : 0) {
                    events.append(Event(rule: rule, app: app, value: value))
                }
            }
            trackers[app.id] = tracker
        }
        // Apps that quit (or became system) take their conditions with them.
        trackers = trackers.filter { seen.contains($0.key) }
        // Stable for tests and for notification order: rules in declaration order, then apps by name.
        return events.sorted {
            let (l, r) = (AlertRule.allCases.firstIndex(of: $0.rule)!, AlertRule.allCases.firstIndex(of: $1.rule)!)
            return l != r ? l < r : $0.app.name < $1.app.name
        }
    }
}

/// One app's rolling state for every rule.
private struct AppTracker {
    var cpuSince: Date?
    var networkSince: Date?
    var memory = RollingBuckets(window: AlertRule.memoryGrowth.duration)
    var written = RollingBuckets(window: AlertRule.diskWrites.duration)
    /// Rules whose condition is ongoing and has already alerted.
    var firing: Set<AlertRule> = []

    mutating func reset(_ rule: AlertRule) {
        firing.remove(rule)
        switch rule {
        case .appCPU: cpuSince = nil
        case .network: networkSince = nil
        case .memoryGrowth: memory = RollingBuckets(window: rule.duration)
        case .diskWrites: written = RollingBuckets(window: rule.duration)
        }
    }

    /// Updates one rule and returns its figure when the condition has just started.
    mutating func update(_ rule: AlertRule, app: AppUsage, threshold: Double, at now: Date,
                         elapsed: TimeInterval) -> Double? {
        let value: Double?
        switch rule {
        case .appCPU:
            value = Self.sustained(app.cpu, threshold: threshold, for: rule.duration, since: &cpuSince, at: now)
        case .network:
            value = Self.sustained(app.resources.network ?? 0, threshold: threshold, for: rule.duration,
                                   since: &networkSince, at: now)
        case .memoryGrowth:
            if let current = app.resources.memory.map({ Double($0) }) {
                memory.add(current, at: now, combine: min)
                let growth = current - (memory.minimum ?? current)
                value = growth >= threshold ? growth : nil
            } else {
                memory = RollingBuckets(window: rule.duration)
                value = nil
            }
        case .diskWrites:
            // The app's latest write rate, applied to the time since the previous evaluation.
            let bytes = (app.resources.diskWritePerSecond ?? 0) * elapsed
            if bytes > 0 || !written.isEmpty { written.add(bytes, at: now, combine: +) }
            let total = written.sum
            value = total >= threshold ? total : nil
        }
        guard let value else {
            firing.remove(rule)
            return nil
        }
        return firing.insert(rule).inserted ? value : nil
    }

    /// The figure, once it has been at or above the threshold for `duration` without a break.
    private static func sustained(_ figure: Double, threshold: Double, for duration: TimeInterval,
                                  since: inout Date?, at now: Date) -> Double? {
        guard figure >= threshold else {
            since = nil
            return nil
        }
        let start = since ?? now
        since = start
        return now.timeIntervalSince(start) >= duration ? figure : nil
    }
}

/// Values over a rolling window, kept in 60 buckets so memory stays bounded however often values arrive.
/// Every bucket that overlaps the window counts, so a rule never misses its threshold at the edge: the window
/// spans its length plus at most one bucket (10 s on 10 minutes, 1 minute on an hour).
struct RollingBuckets {
    let window: TimeInterval
    private let bucketWidth: TimeInterval
    private var buckets: [(start: TimeInterval, value: Double)] = []

    init(window: TimeInterval) {
        self.window = window
        bucketWidth = window / 60
    }

    var isEmpty: Bool { buckets.isEmpty }
    var sum: Double { buckets.reduce(0) { $0 + $1.value } }
    var minimum: Double? { buckets.map(\.value).min() }

    mutating func add(_ value: Double, at now: Date, combine: (Double, Double) -> Double) {
        let time = now.timeIntervalSinceReferenceDate
        let start = (time / bucketWidth).rounded(.down) * bucketWidth
        if let last = buckets.indices.last, buckets[last].start == start {
            buckets[last].value = combine(buckets[last].value, value)
        } else {
            buckets.append((start, value))
        }
        let oldest = time - window
        if let first = buckets.firstIndex(where: { $0.start + bucketWidth > oldest }), first > 0 {
            buckets.removeFirst(first)
        }
    }
}
