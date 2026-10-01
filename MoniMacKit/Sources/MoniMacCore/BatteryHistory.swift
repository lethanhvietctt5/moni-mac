import Foundation

/// Pure math over battery history: chart bars, plug-in count, and drain rate.
///
/// Inputs are `MetricsHistory` points, which are raw samples for short ranges and bucket averages
/// for long ones, so the plugged-in series can arrive as a share (e.g. 0.4) rather than 0 or 1.
public enum BatteryHistory {
    /// One column of the charge chart.
    public struct Bar: Equatable, Sendable {
        /// Average charge in the slot, 0...1.
        public var charge: Double
        /// Whether the Mac was on power for most of the slot.
        public var isPluggedIn: Bool

        public init(charge: Double, isPluggedIn: Bool) {
            self.charge = charge
            self.isPluggedIn = isPluggedIn
        }
    }

    /// A point counts as plugged in when the adapter was connected for at least half of it.
    static func isPluggedIn(_ share: Double) -> Bool { share >= 0.5 }

    /// The shortest time on battery that gives a meaningful drain rate. Charge is reported in whole
    /// percent, so a few minutes on battery reads as either no drain or a wild one.
    public static let minimumDrainWindow: TimeInterval = 15 * 60

    /// `count` bars over the `window` ending at `now`, oldest first; nil where there's no charge data.
    public static func bars(
        charge: [SeriesPoint], pluggedIn: [SeriesPoint], endingAt now: Date, window: TimeInterval, count: Int
    ) -> [Bar?] {
        let levels = Resample.bars(charge, endingAt: now, window: window, count: count)
        let power = Resample.bars(pluggedIn, endingAt: now, window: window, count: count)
        return zip(levels, power).map { level, share in
            level.map { Bar(charge: $0, isPluggedIn: share.map(isPluggedIn) ?? false) }
        }
    }

    /// How many times the Mac went from battery to power, oldest first.
    public static func plugInCount(_ pluggedIn: [SeriesPoint]) -> Int {
        zip(pluggedIn, pluggedIn.dropFirst()).count { !isPluggedIn($0.value) && isPluggedIn($1.value) }
    }

    /// Average charge lost per hour while on battery, as a fraction of full charge (0.098 = 9.8 %/h).
    ///
    /// Only intervals that are entirely on battery count, and intervals longer than `maxGap` are
    /// skipped: those are gaps in the history (MoniMac not running, or the Mac asleep). Nil with
    /// less than `minimumDrainWindow` on battery.
    public static func averageDrain(
        charge: [SeriesPoint], pluggedIn: [SeriesPoint], maxGap: TimeInterval
    ) -> Double? {
        let onBattery = Set(pluggedIn.filter { $0.value == 0 }.map(\.time))
        var drop = 0.0
        var duration: TimeInterval = 0
        for (previous, next) in zip(charge, charge.dropFirst()) {
            let gap = next.time.timeIntervalSince(previous.time)
            guard gap > 0, gap <= maxGap, onBattery.contains(previous.time), onBattery.contains(next.time) else {
                continue
            }
            drop += previous.value - next.value
            duration += gap
        }
        guard duration >= minimumDrainWindow else { return nil }
        return drop / (duration / 3600)
    }

    /// The longest step between points that still counts as continuous history for a range.
    /// Raw samples come every few seconds; long ranges are served as 1- or 15-minute buckets.
    static func maxGap(for range: TimeRange) -> TimeInterval {
        switch range.duration {
        case ...TimeRange.oneHour.duration: 30
        case ...TimeRange.twentyFourHours.duration: 2 * 60
        default: 2 * 15 * 60
        }
    }
}
