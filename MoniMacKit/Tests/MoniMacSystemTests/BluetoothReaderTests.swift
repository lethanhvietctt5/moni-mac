import Foundation
import MoniMacCore
import Testing
@testable import MoniMacSystem

/// `system_profiler SPBluetoothDataType -json` as macOS writes it. The connected devices follow output
/// published by others (nothing was connected to the Mac this was written on); the disconnected ones are
/// as observed on macOS 27.
private let fixture = """
{
  "SPBluetoothDataType" : [
    {
      "controller_properties" : {
        "controller_address" : "70:8C:F2:CB:DA:75",
        "controller_state" : "attrib_on",
        "controller_vendorID" : "0x004C (Apple)"
      },
      "device_connected" : [
        { "Maya's AirPods Pro" : {
            "device_address" : "AA:BB:CC:00:00:08",
            "device_batteryLevelCase" : "41%",
            "device_batteryLevelLeft" : "82%",
            "device_batteryLevelRight" : "78%",
            "device_firmwareVersion" : "7A305",
            "device_minorType" : "Headphones",
            "device_productID" : "0x2014",
            "device_vendorID" : "0x004C"
        } },
        { "MX Master 3S" : {
            "device_address" : "aa-bb-cc-00-00-0a",
            "device_batteryLevelMain" : 91,
            "device_minorType" : "Mouse",
            "device_vendorID" : "0x046D"
        } },
        { "Magic Trackpad" : {
            "device_address" : "AA:BB:CC:00:00:03",
            "device_firmwareVersion" : "3.1.8",
            "device_minorType" : "Magic Trackpad",
            "device_vendorID" : "0x004C"
        } }
      ],
      "device_not_connected" : [
        { "iPhone" : { "device_address" : "68:A7:29:EF:4E:0A", "device_rssi" : "-51" } },
        { "soundcore" : {
            "device_address" : "7C:E9:13:10:08:A2",
            "device_firmwareVersion" : "0.0.0",
            "device_minorType" : "Headset"
        } },
        { "Broken" : { "device_address" : "not an address" } },
        { "Odd level" : { "device_address" : "AA:BB:CC:00:00:0F", "device_batteryLevelMain" : "140%" } }
      ]
    }
  ]
}
"""

struct BluetoothReaderTests {
    let readAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func parse(_ json: String) -> Reading<BluetoothReading> {
        BluetoothReader.parse(Data(json.utf8), readAt: readAt)
    }

    @Test func parsesConnectedAndPairedDevices() throws {
        let reading = try #require(parse(fixture).value)

        #expect(reading.isPoweredOn)
        #expect(reading.readAt == readAt)
        #expect(reading.devices.map(\.name) == ["Maya's AirPods Pro", "MX Master 3S", "Magic Trackpad", "iPhone", "soundcore", "Odd level"])
        #expect(reading.connected.count == 3)

        let airPods = reading.devices[0]
        #expect(airPods.address == "AA:BB:CC:00:00:08")
        #expect(airPods.battery == BluetoothBattery(left: 82, right: 78, case: 41))
        #expect(airPods.firmware == "7A305")
        #expect(airPods.vendorID == 0x4C)
        #expect(airPods.kind == .earbuds)

        // Dashed lowercase addresses are normalized; numeric levels are accepted.
        #expect(reading.devices[1].address == "AA:BB:CC:00:00:0A")
        #expect(reading.devices[1].battery.main == 91)
        // No level is nil, never zero.
        #expect(reading.devices[2].battery.isEmpty)
        #expect(reading.devices[3].minorType == nil && !reading.devices[3].isConnected)
        // "0.0.0" isn't a firmware version.
        #expect(reading.devices[4].firmware == nil)
        // An impossible level is dropped.
        #expect(reading.devices[5].battery.main == nil)
    }

    @Test func bluetoothOffAndNoBluetoothAndGarbage() {
        let off = fixture.replacingOccurrences(of: "\"attrib_on\"", with: "\"attrib_off\"")
        #expect(parse(off).value?.isPoweredOn == false)
        #expect(parse(#"{ "SPBluetoothDataType" : [] }"#) == .unavailable(.unsupported))
        #expect(parse("not json") == .unavailable(.failed("system_profiler's output wasn't readable")))
    }

    @Test func hidLevelsFillInWhatSystemProfilerLacks() throws {
        let reading = try #require(parse(fixture).value)
        let merged = BluetoothReader.merge(reading, hid: [
            "AA:BB:CC:00:00:03": .init(percent: 14, isCharging: false),
            // system_profiler's own level wins.
            "AA:BB:CC:00:00:0A": .init(percent: 50, isCharging: true),
        ])
        #expect(merged.devices[2].battery.main == 14)
        #expect(merged.devices[2].isCharging == false)
        #expect(merged.devices[1].battery.main == 91)
        #expect(merged.devices[1].isCharging == true)
    }

    @Test func addressesNormalize() {
        #expect(BluetoothReader.normalizedAddress("30-82-16-f2-24-90") == "30:82:16:F2:24:90")
        #expect(BluetoothReader.normalizedAddress("30:82:16:F2:24:90") == "30:82:16:F2:24:90")
        #expect(BluetoothReader.normalizedAddress("30:82:16:F2:24") == nil)
        #expect(BluetoothReader.normalizedAddress("zz:82:16:F2:24:90") == nil)
    }

    /// Against the real Mac: system_profiler answers and parses, with or without devices.
    @Test func readsThisMac() {
        let reading = BluetoothReader.read(timeout: 15)
        switch reading {
        case .value(let reading):
            #expect(reading.devices.allSatisfy { BluetoothReader.normalizedAddress($0.address) == $0.address })
        case .unavailable(let reason):
            #expect(reason == .unsupported, "Bluetooth read failed: \(reason)")
        }
    }
}
