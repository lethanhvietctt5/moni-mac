import Foundation
import Testing
import MoniMacCore
@testable import MoniMacSystem

/// Runs against the real Mac. Checks fields are present and in range, not exact values.
@MainActor
struct ThermalReaderSmokeTests {
    @Test func readsNamedTemperaturesInRange() throws {
        let reading = try #require(ThermalReader().sample().value)
        let sensors = try #require(reading.sensors.value, "sensors: \(reading.sensors)")

        let groups = ThermalGroups(sensors, chip: SystemInfoReader.read().chipName)
        let cpu = try #require(groups.cpu, "no CPU sensors among \(sensors.map(\.name))")
        #expect((15...110).contains(cpu))
    }

    @Test func fansAreReadOrAbsentWithAReason() throws {
        let reading = try #require(ThermalReader().sample().value)

        switch reading.fans {
        case .value(let fans):
            #expect(!fans.isEmpty)
            for fan in fans {
                #expect(fan.maximumRPM > fan.minimumRPM)
                #expect(fan.minimumRPM >= 0)
                #expect((0...fan.maximumRPM * 1.2).contains(fan.rpm))
            }
        case .unavailable(let reason):
            #expect(reason == .unsupported, "a fanless Mac reports no fans: \(reason)")
        }
    }

    /// Between throttled reads the reader repeats the last values rather than dropping them.
    @Test func repeatsSensorsBetweenReads() throws {
        let reader = ThermalReader(sensorInterval: 60)
        let first = try #require(reader.sample().value?.sensors.value)
        let second = try #require(reader.sample().value?.sensors.value)

        #expect(second.map(\.name) == first.map(\.name))
    }

    @Test func iohidFallbackReadsSensors() throws {
        let hid = try #require(ThermalHID(), "IOHID temperature symbols missing")

        let sensors = hid.read()

        #expect(sensors.contains {
            ThermalSensorGroup.of(sensorNamed: $0.name, chip: "") != nil && (1...125).contains($0.celsius)
        })
    }

    @Test(arguments: [
        ([0x00, 0x00, 0xA0, 0x42] as [UInt8], "flt ", 80.0),
        ([0x19, 0x00], "fpe2", 1600),
        ([0x3A, 0x80], "sp78", 58.5),
        ([0x01], "ui8 ", 1),
    ])
    func decodesSMCTypes(bytes: [UInt8], type: String, value: Double) {
        #expect(SMC.decode(bytes, type: type) == value)
    }

    @Test func unknownSMCTypesDontDecode() {
        #expect(SMC.decode([1, 2, 3, 4], type: "{fds") == nil)
    }
}
