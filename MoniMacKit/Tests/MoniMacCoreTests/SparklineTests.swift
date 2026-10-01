import Foundation
import Testing
import MoniMacCore

struct SparklineTests {
    let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func point(secondsAgo: TimeInterval, _ value: Double) -> SeriesPoint {
        SeriesPoint(time: now - secondsAgo, value: value)
    }

    @Test func alwaysHasTheSameNumberOfBars() {
        #expect(Sparkline.bars([], endingAt: now).count == Sparkline.barCount)
        #expect(Sparkline.bars([point(secondsAgo: 1, 0.5)], endingAt: now).count == Sparkline.barCount)
    }

    @Test func newestSampleIsTheLastBar() {
        let bars = Sparkline.bars([point(secondsAgo: 0, 0.7)], endingAt: now)

        #expect(bars.last == 0.7)
        #expect(bars.dropLast().allSatisfy { $0 == nil })
    }

    @Test func averagesSamplesWithinASlot() {
        // Slots are 4 s wide; samples 1 s and 3 s ago share the last slot.
        let bars = Sparkline.bars([point(secondsAgo: 3, 0.2), point(secondsAgo: 1, 0.6)], endingAt: now)

        #expect(abs(bars.last!! - 0.4) < 1e-9)
    }

    @Test func oldestSlotCoversTheStartOfTheWindow() {
        let bars = Sparkline.bars([point(secondsAgo: 59, 0.3)], endingAt: now)

        #expect(bars.first == 0.3)
    }

    @Test func ignoresSamplesOutsideTheWindow() {
        let bars = Sparkline.bars([point(secondsAgo: 61, 0.9), point(secondsAgo: -1, 0.9)], endingAt: now)

        #expect(bars.allSatisfy { $0 == nil })
    }
}
