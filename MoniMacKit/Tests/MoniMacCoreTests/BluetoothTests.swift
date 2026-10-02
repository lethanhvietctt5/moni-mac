import Foundation
import Testing
@testable import MoniMacCore

/// A sampler whose Bluetooth reading the test sets. Each new reading is stamped with the clock, as the
/// reader stamps its own; `repeatLast()` hands back the same reading, as the ticks between reads do.
@MainActor
private final class BluetoothSampler: SystemSampler {
    let clock: TestClock
    private var reading: Reading<BluetoothReading> = .unavailable(.warmingUp)

    init(clock: TestClock) {
        self.clock = clock
    }

    func set(_ devices: [BluetoothDevice], poweredOn: Bool = true) {
        reading = .value(BluetoothReading(devices: devices, isPoweredOn: poweredOn, readAt: clock.now))
    }

    func sample() -> Snapshot {
        Snapshot(timestamp: clock.now, cpu: .cpu(user: 0.1, system: 0.1), bluetooth: reading)
    }
}

private let airPodsAddress = "AA:BB:CC:00:00:08"

private func airPods(left: Int? = 82, right: Int? = 78, case: Int? = 41, connected: Bool = true,
                     firmware: String? = "7A305") -> BluetoothDevice {
    BluetoothDevice(address: airPodsAddress, name: "Maya's AirPods Pro", minorType: "Headphones", vendorID: 0x4C,
                    isConnected: connected, firmware: firmware,
                    battery: BluetoothBattery(left: left, right: right, case: `case`))
}

private func device(_ name: String, _ address: String, type: String?, level: Int? = nil, connected: Bool = true,
                    charging: Bool? = nil) -> BluetoothDevice {
    BluetoothDevice(address: address, name: name, minorType: type, isConnected: connected,
                    battery: BluetoothBattery(main: level), isCharging: charging)
}

private func trackpad(_ level: Int?) -> BluetoothDevice {
    device("Magic Trackpad", "AA:BB:CC:00:00:03", type: "Magic Trackpad", level: level)
}

private func keyboard(_ level: Int?) -> BluetoothDevice {
    device("Magic Keyboard", "AA:BB:CC:00:00:02", type: "Keyboard", level: level)
}

@MainActor
struct BluetoothTests {
    let clock = TestClock()
    let defaults = UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!
    let actions = RecordingActions()
    /// 2026-09-30 15:00 UTC, a Wednesday.
    let now = Date(timeIntervalSince1970: 1_790_780_400)
    let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func makeMonitor() throws -> (Monitor, BluetoothSampler) {
        let sampler = BluetoothSampler(clock: clock)
        let monitor = Monitor(sampler: sampler, history: try MetricsHistory(.inMemory),
                              preferences: Preferences(defaults: defaults), actions: actions)
        return (monitor, sampler)
    }

    private func detail(_ devices: [BluetoothDevice], records: [String: BluetoothDeviceRecord] = [:],
                        poweredOn: Bool = true) -> BluetoothDetail {
        BluetoothDetail.make(reading: .value(BluetoothReading(devices: devices, isPoweredOn: poweredOn, readAt: now)),
                             records: records, now: now, lowBatteryAlerts: true, calendar: utc)
    }

    private var delivered: [Alert] { actions.delivered }

    // MARK: Device kinds

    @Test func kindsComeFromMacOSTypeAndEarbudLevels() {
        #expect(BluetoothDeviceKind(minorType: "Headphones", hasEarbuds: false) == .headphones)
        #expect(BluetoothDeviceKind(minorType: "Headset", hasEarbuds: false) == .headphones)
        #expect(BluetoothDeviceKind(minorType: "Headphones", hasEarbuds: true) == .earbuds)
        #expect(BluetoothDeviceKind(minorType: "Magic Trackpad", hasEarbuds: false) == .trackpad)
        #expect(BluetoothDeviceKind(minorType: "Keyboard", hasEarbuds: false) == .keyboard)
        #expect(BluetoothDeviceKind(minorType: "Mouse", hasEarbuds: false) == .mouse)
        #expect(BluetoothDeviceKind(minorType: "Gamepad", hasEarbuds: false) == .gameController)
        #expect(BluetoothDeviceKind(minorType: "Loudspeaker", hasEarbuds: false) == .speaker)
        // Unknown types keep macOS's word; no type at all is never guessed from the name.
        #expect(BluetoothDeviceKind(minorType: "Pen", hasEarbuds: false).title == "Pen")
        #expect(BluetoothDeviceKind(minorType: nil, hasEarbuds: false).title == "Device")
        #expect(BluetoothDeviceKind.gameController.title == "Game Controller")
    }

    // MARK: Header

    @Test func subtitleCountsConnectedDevicesOrSaysWhyNot() {
        func subtitle(_ reading: Reading<BluetoothReading>) -> String { BluetoothDetail.subtitle(for: reading) }
        let devices = [airPods(), keyboard(64), trackpad(14), device("DualSense", "AA:BB:CC:00:00:0C", type: "Gamepad", connected: false)]
        #expect(subtitle(.value(BluetoothReading(devices: devices, readAt: now))) == "3 devices connected")
        #expect(subtitle(.value(BluetoothReading(devices: [keyboard(64)], readAt: now))) == "1 device connected")
        #expect(subtitle(.value(BluetoothReading(devices: [], readAt: now))) == "No devices connected")
        #expect(subtitle(.value(BluetoothReading(devices: [], isPoweredOn: false, readAt: now))) == "Bluetooth is off")
        #expect(subtitle(.unavailable(.warmingUp)) == "Looking for devices…")
        #expect(subtitle(.unavailable(.failed("x"))) == "Devices unavailable")
    }

    @Test func emptyStatesSayWhy() {
        #expect(detail([]).message == "No Bluetooth devices are paired with this Mac.")
        #expect(detail([keyboard(nil)], poweredOn: false).message?.hasPrefix("Bluetooth is off.") == true)
        #expect(detail([keyboard(64)]).message == nil)
        let failed = BluetoothDetail.make(reading: .unavailable(.failed("system_profiler didn't answer")), records: [:],
                                          now: now, lowBatteryAlerts: true, calendar: utc)
        #expect(failed.message == "Bluetooth devices can't be read: system_profiler didn't answer.")
        #expect(failed.rows.isEmpty && failed.featured == nil)
    }

    // MARK: Featured card

    @Test func connectedEarbudsAreFeaturedWithLeftRightAndCaseRings() throws {
        let detail = detail([keyboard(64), airPods(), trackpad(14)])
        let featured = try #require(detail.featured)

        #expect(featured.name == "Maya's AirPods Pro")
        #expect(featured.kind == .earbuds)
        #expect(featured.status == "Connected")
        #expect(featured.rings.map(\.label) == ["Left", "Right", "Case"])
        #expect(featured.rings.map(\.text) == ["82%", "78%", "41%"])
        #expect(featured.rings.map(\.tone) == [.normal, .normal, .warning])
        #expect(featured.rings[0].level == 0.82)
        // The featured device isn't listed again.
        #expect(detail.rows.map(\.name) == ["Magic Keyboard", "Magic Trackpad"])
    }

    @Test func whatTheMacCannotProvideIsAbsentWithAReason() throws {
        let featured = try #require(detail([airPods(firmware: nil)]).featured)

        let source = try #require(featured.source)
        #expect(source.text == "Audio source unknown" && !source.isKnown && source.help != nil)
        #expect(featured.facts.map(\.text) == ["Noise control unknown", "Firmware unknown", "Listening time left: estimating…"])
        #expect(featured.facts.allSatisfy { !$0.isKnown && $0.help != nil })

        let withFirmware = try #require(detail([airPods()]).featured)
        #expect(withFirmware.facts[1] == BluetoothDetail.Fact(text: "Firmware 7A305", isKnown: true))
    }

    @Test func missingEarbudLevelsShowEmptyRingsAndLowOnesRed() throws {
        let featured = try #require(detail([airPods(left: 15, right: nil, case: nil)]).featured)
        #expect(featured.rings.map(\.text) == ["15%", "—", "—"])
        #expect(featured.rings.map(\.level) == [0.15, nil, nil])
        #expect(featured.rings[0].tone == .low)
    }

    @Test func singleBatteryHeadphonesHaveOneRing() throws {
        let headset = device("WH-CH720N", "00:A4:1C:D3:C3:45", type: "Headset", level: 60)
        let featured = try #require(detail([headset]).featured)
        #expect(featured.kind == .headphones)
        #expect(featured.rings.map(\.label) == ["Battery"])
        #expect(featured.rings.map(\.text) == ["60%"])
    }

    @Test func featuredPrefersConnectedThenEarbudsThenMostRecentlySeen() {
        let headset = device("WH-CH720N", "00:A4:1C:D3:C3:45", type: "Headset", level: 60)
        let soundcore = device("soundcore", "7C:E9:13:10:08:A2", type: "Headset", connected: false)
        let sony = device("WH-CH720N", "00:A4:1C:D3:C3:45", type: "Headset", connected: false)

        #expect(detail([airPods(connected: false), headset]).featured?.name == "WH-CH720N")
        #expect(detail([headset, airPods()]).featured?.name == "Maya's AirPods Pro")
        // Disconnected: earbuds first, then the one seen most recently, then by name.
        #expect(detail([soundcore, sony]).featured?.name == "soundcore")
        let records = [sony.address: BluetoothDeviceRecord(name: "WH-CH720N", lastSeen: now - 3600)]
        #expect(detail([soundcore, sony], records: records).featured?.name == "WH-CH720N")
        // Nothing headphone-like: no card, and the list says "Devices".
        #expect(detail([keyboard(64)]).featured == nil)
    }

    @Test func disconnectedFeaturedDeviceShowsLastSeenAndLastLevelsGreyed() throws {
        let records = [airPodsAddress: BluetoothDeviceRecord(
            name: "Maya's AirPods Pro", lastSeen: now - 86400 + 3600 * 7.7, battery: BluetoothBattery(left: 70, right: 72, case: 30)
        )]
        let featured = try #require(detail([airPods(left: nil, right: nil, case: nil, connected: false)], records: records).featured)
        #expect(featured.kind == .earbuds)
        #expect(featured.status == "Not connected · Last seen yesterday, 22:42")
        #expect(featured.source == nil)
        #expect(featured.rings.map(\.text) == ["70%", "72%", "30%"])
        #expect(featured.rings.allSatisfy { $0.tone == .inactive })
    }

    @Test func listeningTimeIsEstimatedFromTheDrainOnceItHasDroppedEnough() throws {
        func listening(from: BluetoothBattery, now left: Int?, _ right: Int?) throws -> String? {
            let record = BluetoothDeviceRecord(name: "AirPods", drain: .init(from: from, since: now - 3600))
            let featured = try #require(detail([airPods(left: left, right: right)], records: [airPodsAddress: record]).featured)
            return featured.facts.last?.text
        }
        // Left 90% → 80% in an hour: 80% lasts 8 hours. Right drained slower, so left runs out first.
        #expect(try listening(from: BluetoothBattery(left: 90, right: 90), now: 80, 85) == "Approx. 8 h listening left")
        // 2 points isn't enough to go on.
        #expect(try listening(from: BluetoothBattery(left: 82, right: 86), now: 80, 85) == "Listening time left: estimating…")
        // Each earbud is measured against itself: the left one dropping out leaves the right one's estimate.
        #expect(try listening(from: BluetoothBattery(left: 50, right: 90), now: nil, 80) == "Approx. 8 h listening left")
    }

    // MARK: Other Devices

    @Test func rowsShowTypeConnectionLevelAndRedWhenLow() {
        let rows = detail([trackpad(14), keyboard(64)]).rows

        #expect(rows.map(\.name) == ["Magic Keyboard", "Magic Trackpad"])
        #expect(rows.map(\.status) == ["Keyboard · Connected", "Trackpad · Connected"])
        #expect(rows.map(\.levelText) == ["64%", "14%"])
        #expect(rows.map(\.tone) == [.normal, .low])
        #expect(rows[1].hint == "Low — charge soon")
        #expect(rows[1].isHintLow)
        // 19% is low; 20% isn't.
        #expect(detail([keyboard(19)]).rows[0].tone == .low)
        #expect(detail([keyboard(20)]).rows[0].tone == .normal)
        // Rows never go amber: that's for rings.
        #expect(detail([keyboard(41)]).rows[0].tone == .normal)
    }

    @Test func aDeviceWithoutALevelSaysSo() {
        let row = detail([keyboard(nil)]).rows[0]
        #expect(row.levelText == "—")
        #expect(row.level == nil)
        #expect(row.levelHelp != nil)
    }

    @Test func connectedDevicesComeFirstByNameThenDisconnectedByLastSeen() {
        let dualSense = device("DualSense", "AA:BB:CC:00:00:0C", type: "Gamepad", connected: false)
        let nuphy = device("NuPhy Air75", "AA:BB:CC:00:00:0D", type: "Keyboard", connected: false)
        let ipad = device("iPad", "AA:BB:CC:00:00:0E", type: nil, connected: false)
        let mouse = device("MX Master 3S", "AA:BB:CC:00:00:0A", type: "Mouse", level: 91)
        let records = [
            dualSense.address: BluetoothDeviceRecord(name: "DualSense", lastSeen: now - 86400),
            nuphy.address: BluetoothDeviceRecord(name: "NuPhy Air75", lastSeen: now - 3600),
        ]
        let rows = detail([ipad, dualSense, mouse, nuphy, trackpad(14), keyboard(64)], records: records).rows
        #expect(rows.map(\.name) == ["Magic Keyboard", "Magic Trackpad", "MX Master 3S", "NuPhy Air75", "DualSense", "iPad"])
        #expect(rows.last?.status == "Device · Not connected")
        #expect(rows.last?.hint == nil)
    }

    @Test func disconnectedDevicesShowWhenTheyWereLastSeenIn24HourTime() {
        func hint(seen: TimeInterval) -> String? {
            let pad = device("DualSense", "AA:BB:CC:00:00:0C", type: "Gamepad", connected: false)
            return detail([pad], records: [pad.address: BluetoothDeviceRecord(
                name: "DualSense", lastSeen: now - seen, battery: BluetoothBattery(main: 37))]).rows[0].hint
        }
        // now is Wednesday 15:00 UTC.
        #expect(hint(seen: 3600 * 5.5) == "Last seen today, 09:30")
        #expect(hint(seen: 86400 - 3600 * 7.7) == "Last seen yesterday, 22:42")
        #expect(hint(seen: 3 * 86400) == "Last seen Sun 15:00")
        #expect(hint(seen: 9 * 86400) == "Last seen 21 Sep")

        let pad = device("DualSense", "AA:BB:CC:00:00:0C", type: "Gamepad", connected: false)
        let row = detail([pad], records: [pad.address: BluetoothDeviceRecord(name: "DualSense", battery: BluetoothBattery(main: 37))]).rows[0]
        // Its last known level, greyed.
        #expect(row.levelText == "37%")
        #expect(row.tone == .inactive)
    }

    @Test func connectedDevicesSayWhenChargedOrHowLongTheyLast() {
        func hint(_ record: BluetoothDeviceRecord, level: Int = 64, charging: Bool? = nil) -> String? {
            let keyboard = device("Magic Keyboard", "AA:BB:CC:00:00:02", type: "Keyboard", level: level, charging: charging)
            return detail([keyboard], records: [keyboard.address: record]).rows[0].hint
        }
        #expect(hint(BluetoothDeviceRecord(name: "K", chargedAt: now - 6 * 86400)) == "Charged 6 days ago")
        #expect(hint(BluetoothDeviceRecord(name: "K", chargedAt: now - 86400)) == "Charged yesterday")
        #expect(hint(BluetoothDeviceRecord(name: "K", chargedAt: now - 3600)) == "Charged today")
        #expect(hint(BluetoothDeviceRecord(name: "K")) == nil)
        #expect(hint(BluetoothDeviceRecord(name: "K"), charging: true) == "Charging")
        // 100% → 91% in 6 days: 91% lasts about 60 days.
        let draining = BluetoothDeviceRecord(name: "K", chargedAt: now - 6 * 86400, drain: .init(from: BluetoothBattery(main: 100), since: now - 6 * 86400))
        #expect(hint(draining, level: 91) == "Est. 60 days left")
        // Under a day of drain says nothing yet, however steep.
        let fresh = BluetoothDeviceRecord(name: "K", chargedAt: now - 3600, drain: .init(from: BluetoothBattery(main: 100), since: now - 3600))
        #expect(hint(fresh, level: 80) == "Charged today")
        // Low beats everything.
        #expect(hint(draining, level: 12) == "Low — charge soon")
    }

    // MARK: Memory across readings and relaunches

    @Test func lastSeenAndLevelsSurviveARelaunch() throws {
        let (monitor, sampler) = try makeMonitor()
        sampler.set([keyboard(64), airPods()])
        monitor.tick()
        let seen = clock.now
        clock.advance(by: 300)
        sampler.set([keyboard(nil).with(connected: false), airPods(left: nil, right: nil, case: nil, connected: false)])
        monitor.tick()

        let (relaunched, sampler2) = try makeMonitor()
        sampler2.set([keyboard(nil).with(connected: false), airPods(left: nil, right: nil, case: nil, connected: false)])
        relaunched.tick()
        let records = relaunched.bluetoothTracker.records
        #expect(records[keyboard(nil).address]?.lastSeen == seen)
        #expect(records[keyboard(nil).address]?.battery.main == 64)
        #expect(records[airPodsAddress]?.battery == BluetoothBattery(left: 82, right: 78, case: 41))
        #expect(relaunched.bluetoothDetail.rows.first?.levelText == "64%")
    }

    @Test func aRisingLevelOrTheChargingFlagCountsAsACharge() throws {
        let (monitor, sampler) = try makeMonitor()
        let address = keyboard(nil).address
        sampler.set([keyboard(50)])
        monitor.tick()
        #expect(monitor.bluetoothTracker.records[address]?.chargedAt == nil)
        #expect(monitor.bluetoothTracker.records[address]?.drain?.from.main == 50)

        clock.advance(by: 3600)
        sampler.set([keyboard(52)])  // jitter, not a charge
        monitor.tick()
        #expect(monitor.bluetoothTracker.records[address]?.chargedAt == nil)

        clock.advance(by: 3600)
        sampler.set([keyboard(80)])
        monitor.tick()
        #expect(monitor.bluetoothTracker.records[address]?.chargedAt == clock.now)
        #expect(monitor.bluetoothTracker.records[address]?.drain?.from.main == 80)
        #expect(monitor.bluetoothTracker.records[address]?.drain?.since == clock.now)

        clock.advance(by: 3600)
        sampler.set([device("Magic Keyboard", address, type: "Keyboard", level: 79, charging: true)])
        monitor.tick()
        #expect(monitor.bluetoothTracker.records[address]?.chargedAt == clock.now)
    }

    @Test func unpairedDevicesAreForgottenButNotWhileBluetoothIsOff() throws {
        let (monitor, sampler) = try makeMonitor()
        sampler.set([keyboard(64), trackpad(50)])
        monitor.tick()
        clock.advance(by: 30)
        sampler.set([], poweredOn: false)
        monitor.tick()
        #expect(monitor.bluetoothTracker.records.count == 2)
        clock.advance(by: 30)
        sampler.set([keyboard(64)])
        monitor.tick()
        #expect(Array(monitor.bluetoothTracker.records.keys) == [keyboard(nil).address])
    }

    // MARK: Low battery notifications

    @Test func aLowDeviceNotifiesOncePerEpisodeAndReArmsOnceCharged() throws {
        let (monitor, sampler) = try makeMonitor()
        func read(_ level: Int) {
            clock.advance(by: 300)
            sampler.set([trackpad(level), keyboard(64)])
            monitor.tick()
            monitor.tick()  // the same reading again, between reads
        }
        read(30)
        read(20)
        #expect(delivered.isEmpty)
        read(19)
        #expect(delivered.count == 1)
        read(14)
        read(21)  // jitter around the threshold isn't a charge
        read(18)
        #expect(delivered.count == 1)
        read(25)
        read(17)
        #expect(delivered.count == 2)
        #expect(actions.recorded.filter { $0 == .requestNotificationAuthorization }.count == 1)

        let alert = try #require(delivered.last)
        #expect(alert.id == "bluetoothBattery:AA:BB:CC:00:00:03")
        #expect(alert.title == "Magic Trackpad battery is low")
        #expect(alert.chip == "17%")
        #expect(alert.rule == nil && alert.quitTitle == nil && alert.appID == nil)
        #expect(alert.target == .tab(.bluetooth))
    }

    @Test func earbudsAlertOnTheLowerEarbudButNotTheCase() throws {
        let (monitor, sampler) = try makeMonitor()
        sampler.set([airPods(left: 60, right: 55, case: 5)])
        monitor.tick()
        #expect(delivered.isEmpty)
        clock.advance(by: 300)
        sampler.set([airPods(left: 40, right: 18, case: 5)])
        monitor.tick()
        let alert = try #require(delivered.first)
        #expect(alert.chip == "18%")
        #expect(alert.body == "Left 40%, Right 18%. Charge it soon, before it turns off.")
    }

    @Test func anEarbudDroppingOutIsNeitherAChargeNorTheEndOfAnEpisode() throws {
        let (monitor, sampler) = try makeMonitor()
        // Right is low; then it goes into the case and stops reporting, so the lowest level jumps to left's.
        for (left, right) in [(60, 15), (60, nil), (59, 14)] as [(Int, Int?)] {
            clock.advance(by: 300)
            sampler.set([airPods(left: left, right: right, case: 50)])
            monitor.tick()
        }
        #expect(delivered.count == 1)
        #expect(monitor.bluetoothTracker.records[airPodsAddress]?.chargedAt == nil)

        // Charged in the case: right back at 100% ends the episode and counts as a charge.
        clock.advance(by: 300)
        sampler.set([airPods(left: 59, right: 100, case: 40)])
        monitor.tick()
        #expect(monitor.bluetoothTracker.records[airPodsAddress]?.chargedAt == clock.now)
        clock.advance(by: 300)
        sampler.set([airPods(left: 59, right: 12, case: 40)])
        monitor.tick()
        #expect(delivered.count == 2)
    }

    @Test func disconnectingWhileLowDoesNotStartANewEpisode() throws {
        let (monitor, sampler) = try makeMonitor()
        for (level, connected) in [(15, true), (15, false), (12, true)] {
            clock.advance(by: 300)
            sampler.set([trackpad(level).with(connected: connected)])
            monitor.tick()
        }
        #expect(delivered.count == 1)
    }

    @Test func theToggleTurnsTheRuleOffAndOnAndAsksForPermissionOnFirstUse() throws {
        let (monitor, sampler) = try makeMonitor()
        #expect(monitor.bluetoothDetail.lowBatteryAlerts)
        monitor.setBluetoothLowBatteryAlerts(false)
        #expect(!monitor.bluetoothDetail.lowBatteryAlerts)
        sampler.set([trackpad(10)])
        monitor.tick()
        #expect(delivered.isEmpty)
        #expect(actions.recorded.isEmpty)

        monitor.setBluetoothLowBatteryAlerts(true)
        #expect(actions.recorded == [.requestNotificationAuthorization])
        clock.advance(by: 300)
        sampler.set([trackpad(9)])
        monitor.tick()
        #expect(delivered.count == 1)
    }

    @Test func tabNotificationsRoundTripThroughTheirPayload() {
        let alert = Alert.bluetoothLowBattery(trackpad(14), level: 14)
        #expect(AlertNotification.target(from: AlertNotification.userInfo(for: alert)) == .tab(.bluetooth))
        #expect(AlertNotification.target(from: ["tab": "nonsense"]) == nil)
    }

    // MARK: Demand and actions

    @Test func bluetoothIsReadLiveOnTheTabInTheBackgroundForTheRuleOtherwiseNever() throws {
        let (monitor, _) = try makeMonitor()
        #expect(monitor.bluetoothDemand(isTabShowing: true) == .live)
        #expect(monitor.bluetoothDemand(isTabShowing: false) == .background)
        monitor.setBluetoothLowBatteryAlerts(false)
        #expect(monitor.bluetoothDemand(isTabShowing: false) == .none)
        #expect(monitor.bluetoothDemand(isTabShowing: true) == .live)
        #expect(BluetoothDemand.none.interval == nil)
        #expect(BluetoothDemand.background.interval == 300)
        #expect(BluetoothDemand.live.interval == 30)
    }

    @Test func openBluetoothSettingsOpensItsSettingsPane() throws {
        let (monitor, _) = try makeMonitor()
        monitor.openBluetoothSettings()
        #expect(actions.recorded == [.openURL(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)])
    }
}

private extension BluetoothDevice {
    func with(connected: Bool) -> BluetoothDevice {
        var copy = self
        copy.isConnected = connected
        return copy
    }
}
