import Foundation

/// Fixed-width bar data for a menu bar sparkline.
public enum Sparkline {
    /// The menu bar sparkline covers the last minute.
    public static let window: TimeInterval = 60
    /// Bar count is fixed so the item never changes width.
    public static let barCount = 15

    /// The last minute as `barCount` bars, oldest first.
    public static func bars(_ points: [SeriesPoint], endingAt now: Date) -> [Double?] {
        Resample.bars(points, endingAt: now, window: window, count: barCount)
    }
}

/// Turns a series into a fixed number of chart bars.
public enum Resample {
    /// Splits the `window` ending at `now` into `count` equal slots, oldest first.
    /// Each bar is the average of the points in its slot, or nil when the slot has no data.
    public static func bars(_ points: [SeriesPoint], endingAt now: Date, window: TimeInterval, count: Int) -> [Double?] {
        let slot = window / Double(count)
        let start = now.timeIntervalSinceReferenceDate - window
        var sums = [Double](repeating: 0, count: count)
        var counts = [Int](repeating: 0, count: count)
        for point in points {
            let offset = point.time.timeIntervalSinceReferenceDate - start
            guard offset > 0, offset <= window else { continue }
            let index = min(Int((offset / slot).rounded(.up)) - 1, count - 1)
            sums[index] += point.value
            counts[index] += 1
        }
        return zip(sums, counts).map { sum, n in n == 0 ? nil : sum / Double(n) }
    }
}
