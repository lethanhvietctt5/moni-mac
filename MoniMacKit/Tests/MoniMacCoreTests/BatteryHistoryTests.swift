import Foundation
import Testing
@testable import MoniMacCore

struct BatteryHistoryTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    /// One point per `step` seconds with the given values.
    private func points(_ values: [Double], step: TimeInterval = 60) -> [SeriesPoint] {
        values.enumerated().map { SeriesPoint(time: start.addingTimeInterval(Double($0.offset) * step), value: $0.element) }
    }

    @Test func countsEachMoveFromBatteryToPower() {
        #expect(BatteryHistory.plugInCount(points([0, 0, 1, 1, 0, 1, 0])) == 2)
    }

    @Test func pluggedInFromTheStartIsNotAPlugIn() {
        #expect(BatteryHistory.plugInCount(points([1, 1, 0, 0])) == 0)
        #expect(BatteryHistory.plugInCount([]) == 0)
    }

    /// Long ranges come back as bucket averages: the plugged-in series is a share of each bucket.
    @Test func bucketAveragesCountAsPluggedInFromHalfTheBucket() {
        #expect(BatteryHistory.plugInCount(points([0, 0.2, 0.6, 1, 0.4, 0.5])) == 2)
    }

    @Test func drainIsChargeLostPerHourOnBattery() throws {
        // 30 minutes on battery, losing 5%: 10 %/h.
        let charge = points((0...30).map { 0.8 - Double($0) * 0.05 / 30 })
        let drain = try #require(BatteryHistory.averageDrain(
            charge: charge, pluggedIn: points(Array(repeating: 0, count: 31)), maxGap: 120))

        #expect(abs(drain - 0.10) < 1e-9)
    }

    @Test func drainIgnoresTimeOnPower() throws {
        // 20 min on battery losing 4% (12 %/h), then 20 min charging +10%.
        let charge = points((0...20).map { 0.8 - Double($0) * 0.002 } + (1...20).map { 0.76 + Double($0) * 0.005 })
        let plugged = points(Array(repeating: 0, count: 21) + Array(repeating: 1, count: 20))
        let drain = try #require(BatteryHistory.averageDrain(charge: charge, pluggedIn: plugged, maxGap: 120))

        #expect(abs(drain - 0.12) < 1e-9)
    }

    @Test func drainIgnoresBucketsPartlyOnPower() throws {
        let charge = points((0...20).map { 0.8 - Double($0) * 0.002 } + [0.9, 0.5])
        let plugged = points(Array(repeating: 0, count: 21) + [0.3, 0])
        let drain = try #require(BatteryHistory.averageDrain(charge: charge, pluggedIn: plugged, maxGap: 120))

        #expect(abs(drain - 0.12) < 1e-9)
    }

    @Test func drainSkipsGapsInHistory() throws {
        // 20 minutes on battery, then the Mac sleeps for 8 hours and wakes 10% lower.
        var charge = points((0...20).map { 0.8 - Double($0) * 0.002 })
        charge.append(SeriesPoint(time: charge.last!.time.addingTimeInterval(8 * 3600), value: 0.66))
        let plugged = charge.map { SeriesPoint(time: $0.time, value: 0) }
        let drain = try #require(BatteryHistory.averageDrain(charge: charge, pluggedIn: plugged, maxGap: 120))

        #expect(abs(drain - 0.12) < 1e-9)
    }

    @Test func noDrainWithoutEnoughTimeOnBattery() {
        let charge = points([0.8, 0.79, 0.78, 0.77, 0.76])
        #expect(BatteryHistory.averageDrain(charge: charge, pluggedIn: points([1, 1, 1, 1, 1]), maxGap: 120) == nil)
        #expect(BatteryHistory.averageDrain(charge: charge, pluggedIn: points([0, 0, 0, 0, 0]), maxGap: 120) == nil)
        #expect(BatteryHistory.averageDrain(charge: [], pluggedIn: [], maxGap: 120) == nil)
    }

    @Test func barsMarkSlotsMostlyOnPowerAsCharging() {
        let now = start.addingTimeInterval(3 * 60)
        let bars = BatteryHistory.bars(
            charge: points([0.5, 0.6, 0.7, 0.8]), pluggedIn: points([0, 0.4, 0.6, 1]),
            endingAt: now, window: 5 * 60, count: 5)

        #expect(bars == [
            nil,
            BatteryHistory.Bar(charge: 0.5, isPluggedIn: false),
            BatteryHistory.Bar(charge: 0.6, isPluggedIn: false),
            BatteryHistory.Bar(charge: 0.7, isPluggedIn: true),
            BatteryHistory.Bar(charge: 0.8, isPluggedIn: true),
        ])
    }
}
