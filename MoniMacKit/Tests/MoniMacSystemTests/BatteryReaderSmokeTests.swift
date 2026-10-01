import Foundation
import IOKit.ps
import Testing
import MoniMacCore
@testable import MoniMacSystem

/// Runs against the real Mac. Checks fields are present and in range, not exact values.
@MainActor
struct BatteryReaderSmokeTests {
    /// Whether IOPS lists an internal battery, independently of the reader.
    private var macHasBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        return sources.contains {
            (IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any])?[kIOPSTypeKey] as? String
                == kIOPSInternalBatteryType
        }
    }

    @Test func readsTheBatteryOrReportsItUnsupported() throws {
        let reading = BatteryReader().sample()
        guard macHasBattery else {
            #expect(reading == .unavailable(.unsupported))
            return
        }

        let battery = try #require(reading.value, "battery reading: \(reading)")
        #expect((0...1).contains(battery.charge))
        if battery.isCharging { #expect(battery.isPluggedIn) }
        if battery.isPluggedIn && !battery.isCharging { #expect(battery.timeRemaining == nil) }
        if case .minutes(let minutes) = battery.timeRemaining { #expect(minutes >= 0) }
        let design = try #require(battery.designCapacity)
        let max = try #require(battery.maxCapacity)
        #expect((1000...20000).contains(design))
        #expect((design / 2...design).contains(max))
        #expect((battery.cycleCount ?? -1) >= 0)
        #expect((battery.ratedCycles ?? BatteryReading.appleSiliconRatedCycles) == 1000)
        #expect((10...50).contains(try #require(battery.temperature)))
        #expect(abs(try #require(battery.batteryPower)) < 150)
        #expect((1...300).contains(try #require(battery.systemPower)))
        if battery.isPluggedIn { #expect((5...300).contains(try #require(battery.adapterWatts))) }
    }
}
