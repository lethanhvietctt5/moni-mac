import Foundation

/// Fixed-width bar data for a menu bar sparkline.
public enum Sparkline {
    /// The menu bar sparkline covers the last minute.
    public static let window: TimeInterval = 60
    /// Bar count is fixed so the item never changes width.
    public static let barCount = 15

    /// Splits the window ending at `now` into `barCount` equal slots, oldest first.
    /// Each bar is the average of the points in its slot, or nil when the slot has no data.
    public static func bars(_ points: [SeriesPoint], endingAt now: Date) -> [Double?] {
        let slot = window / Double(barCount)
        let start = now.timeIntervalSinceReferenceDate - window
        var sums = [Double](repeating: 0, count: barCount)
        var counts = [Int](repeating: 0, count: barCount)
        for point in points {
            let offset = point.time.timeIntervalSinceReferenceDate - start
            guard offset > 0, offset <= window else { continue }
            let index = min(Int((offset / slot).rounded(.up)) - 1, barCount - 1)
            sums[index] += point.value
            counts[index] += 1
        }
        return zip(sums, counts).map { sum, count in count == 0 ? nil : sum / Double(count) }
    }
}
