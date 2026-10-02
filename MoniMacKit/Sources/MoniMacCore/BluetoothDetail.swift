import Foundation

/// The Bluetooth tab: a featured card for headphones, the other paired devices, and the low-battery switch.
public struct BluetoothDetail: Equatable, Sendable {
    /// How a level is drawn.
    public enum Tone: Equatable, Sendable {
        case normal
        /// Under half: the design draws a ring amber. Rings only; bars go straight from normal to low.
        case warning
        /// Under 20%, in red.
        case low
        /// A disconnected device's last known level, greyed.
        case inactive
    }

    /// One fact about the featured device. One the Mac can't provide reads as unknown, and `help` says why.
    public struct Fact: Equatable, Sendable, Identifiable {
        /// e.g. "Firmware 7A305", "Noise control unknown".
        public var text: String
        public var isKnown: Bool
        public var help: String?
        public var id: String { text }
    }

    /// A battery ring on the featured card.
    public struct Ring: Equatable, Sendable, Identifiable {
        /// "Left", "Right", "Case", or "Battery".
        public var label: String
        /// 0...1, or nil when not reported (the ring is an empty track).
        public var level: Double?
        /// e.g. "82%", or "—".
        public var text: String
        public var tone: Tone
        public var id: String { label }
    }

    public struct Featured: Equatable, Sendable {
        public var address: String
        public var name: String
        public var kind: BluetoothDeviceKind
        public var isConnected: Bool
        /// e.g. "Connected", "Not connected · Last seen yesterday, 22:42".
        public var status: String
        /// What it's playing from, shown after the status while connected.
        public var source: Fact?
        /// Noise control, firmware, listening time left.
        public var facts: [Fact]
        public var rings: [Ring]
    }

    /// A row of Other Devices.
    public struct Row: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var kind: BluetoothDeviceKind
        /// e.g. "Keyboard · Connected".
        public var status: String
        public var isConnected: Bool
        /// 0...1, or nil when the device reports no level.
        public var level: Double?
        /// e.g. "64%", or "—".
        public var levelText: String
        /// Why there's no level, when there isn't one.
        public var levelHelp: String?
        public var tone: Tone
        /// e.g. "Charged 6 days ago", "Low — charge soon", "Est. 58 days left", "Last seen yesterday, 22:42".
        public var hint: String?
        /// The hint warns of a low battery and reads in red.
        public var isHintLow: Bool
    }

    public var featured: Featured?
    public var rows: [Row]
    /// Why there are no devices to show, or that Bluetooth is off; nil when devices show normally.
    public var message: String?
    public var lowBatteryAlerts: Bool

    public static let lowBatteryTitle = "Low battery notifications"
    public static let lowBatteryDescription =
        "Notify me when any connected device drops below \(BluetoothLowBatteryRule.threshold)%"
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!

    static let sourceHelp = "macOS doesn't tell MoniMac which app is playing to a Bluetooth device."
    static let noiseControlHelp = "macOS doesn't share the noise-control mode with other apps."
    static let firmwareHelp = "The device didn't report a firmware version."
    static let listeningHelp = """
        Estimated from how fast the battery drains while connected, once it has dropped \
        \(BluetoothTracker.minimumDrop)% over at least 10 minutes.
        """
    static let noLevelHelp = "This device doesn't report its battery level to the Mac."
    /// Listening time is estimated after this long, peripheral days left after a day.
    static let listeningMinimumTime: TimeInterval = 600
    static let daysLeftMinimumTime: TimeInterval = 86400

    /// e.g. "4 devices connected", "Bluetooth is off".
    public static func subtitle(for reading: Reading<BluetoothReading>) -> String {
        switch reading {
        case .unavailable(.warmingUp): return "Looking for devices…"
        case .unavailable(.unsupported): return "No Bluetooth"
        case .unavailable(.failed): return "Devices unavailable"
        case .value(let reading):
            guard reading.isPoweredOn else { return "Bluetooth is off" }
            let count = reading.connected.count
            return switch count {
            case 0: "No devices connected"
            case 1: "1 device connected"
            default: "\(count) devices connected"
            }
        }
    }

    static func make(
        reading: Reading<BluetoothReading>, records: [String: BluetoothDeviceRecord], now: Date,
        lowBatteryAlerts: Bool, calendar: Calendar = .current
    ) -> BluetoothDetail {
        var detail = BluetoothDetail(featured: nil, rows: [], message: nil, lowBatteryAlerts: lowBatteryAlerts)
        guard let reading = reading.value else {
            detail.message = switch reading {
            case .unavailable(.unsupported): "This Mac has no Bluetooth."
            case .unavailable(.failed(let reason)): "Bluetooth devices can't be read: \(reason)."
            default: "Looking for Bluetooth devices…"
            }
            return detail
        }
        if !reading.isPoweredOn {
            detail.message = "Bluetooth is off. Turn it on in Bluetooth Settings to see your devices."
        } else if reading.devices.isEmpty {
            detail.message = "No Bluetooth devices are paired with this Mac."
        }
        let clock = Clock(now: now, calendar: calendar)
        let devices = reading.devices.map { Known(device: $0, record: records[$0.address]) }
        let featured = devices.filter(\.kind.isHeadphones).min(by: Known.featuredFirst)
        detail.featured = featured.map { featuredCard($0, clock: clock) }
        detail.rows = devices.filter { $0.device.address != featured?.device.address }
            .sorted(by: Known.listedFirst)
            .map { row($0, clock: clock) }
        return detail
    }

    // MARK: Featured card

    private static func featuredCard(_ known: Known, clock: Clock) -> Featured {
        let device = known.device
        let battery = known.battery
        var facts = [
            Fact(text: "Noise control unknown", isKnown: false, help: noiseControlHelp),
            device.firmware.map { Fact(text: "Firmware \($0)", isKnown: true) }
                ?? Fact(text: "Firmware unknown", isKnown: false, help: firmwareHelp),
        ]
        if device.isConnected, let level = battery.lowest {
            let left = known.record?.timeLeft(at: level, now: clock.now, minimumTime: listeningMinimumTime)
            facts.append(left.map {
                // Rounded to 10 minutes: it's an estimate.
                let minutes = Int(($0 / 600).rounded()) * 10
                return Fact(text: "Approx. \(BatteryDetail.duration(minutes: minutes)) listening left", isKnown: true,
                            help: listeningHelp)
            } ?? Fact(text: "Listening time left: estimating…", isKnown: false, help: listeningHelp))
        }
        let parts: [(String, Int?)] = known.kind == .earbuds
            ? [("Left", battery.left), ("Right", battery.right), ("Case", battery.case)]
            : [("Battery", battery.main)]
        return Featured(
            address: device.address, name: device.name, kind: known.kind, isConnected: device.isConnected,
            status: connectionStatus(known, clock: clock),
            source: device.isConnected ? Fact(text: "Audio source unknown", isKnown: false, help: sourceHelp) : nil,
            facts: facts,
            rings: parts.map { label, value in
                Ring(label: label, level: value.map { Double($0) / 100 }, text: value.map { "\($0)%" } ?? Format.placeholder,
                     tone: tone(value, isConnected: device.isConnected, warnsBelowHalf: true))
            }
        )
    }

    private static func connectionStatus(_ known: Known, clock: Clock) -> String {
        if known.device.isConnected { return "Connected" }
        guard let seen = known.record?.lastSeen else { return "Not connected" }
        return "Not connected · Last seen \(clock.moment(seen))"
    }

    // MARK: Other Devices

    private static func row(_ known: Known, clock: Clock) -> Row {
        let device = known.device
        let level = known.battery.lowest
        let tone = tone(level, isConnected: device.isConnected, warnsBelowHalf: false)
        let hint = hint(known, level: level, clock: clock)
        return Row(
            id: device.address, name: device.name, kind: known.kind,
            status: "\(known.kind.title) · \(device.isConnected ? "Connected" : "Not connected")",
            isConnected: device.isConnected,
            level: level.map { Double($0) / 100 },
            levelText: level.map { "\($0)%" } ?? Format.placeholder,
            levelHelp: level == nil && device.isConnected ? noLevelHelp : nil,
            tone: tone, hint: hint, isHintLow: tone == .low
        )
    }

    /// Low beats charging beats an estimate beats when it was last charged; a disconnected device says
    /// when it was last seen.
    private static func hint(_ known: Known, level: Int?, clock: Clock) -> String? {
        let device = known.device
        guard device.isConnected else {
            return known.record?.lastSeen.map { "Last seen \(clock.moment($0))" }
        }
        if let level, level < BluetoothLowBatteryRule.threshold { return "Low — charge soon" }
        if device.isCharging == true { return "Charging" }
        if let level, let left = known.record?.timeLeft(at: level, now: clock.now, minimumTime: daysLeftMinimumTime) {
            let days = Int((left / 86400).rounded(.down))
            return switch days {
            case 0: "Est. under a day left"
            case 1: "Est. 1 day left"
            default: "Est. \(days) days left"
            }
        }
        guard let charged = known.record?.chargedAt else { return nil }
        return switch clock.daysAgo(charged) {
        case ...0: "Charged today"
        case 1: "Charged yesterday"
        case let days: "Charged \(days) days ago"
        }
    }

    private static func tone(_ level: Int?, isConnected: Bool, warnsBelowHalf: Bool) -> Tone {
        guard isConnected else { return .inactive }
        guard let level else { return .normal }
        if level < BluetoothLowBatteryRule.threshold { return .low }
        return warnsBelowHalf && level < 50 ? .warning : .normal
    }
}

/// A device with what MoniMac remembers about it.
private struct Known {
    var device: BluetoothDevice
    var record: BluetoothDeviceRecord?

    /// Its levels now while connected; its last known ones while not.
    var battery: BluetoothBattery {
        if device.isConnected { return device.battery }
        if let remembered = record?.battery, !remembered.isEmpty { return remembered }
        return device.battery
    }

    /// Earbuds by their remembered levels too: disconnected AirPods don't always report them.
    var kind: BluetoothDeviceKind {
        BluetoothDeviceKind(minorType: device.minorType,
                            hasEarbuds: device.battery.hasEarbuds || record?.battery.hasEarbuds == true)
    }

    /// The featured card prefers connected headphones, earbuds over other headphones, then the most
    /// recently seen, then the name.
    static func featuredFirst(_ a: Known, _ b: Known) -> Bool {
        if a.device.isConnected != b.device.isConnected { return a.device.isConnected }
        if (a.kind == .earbuds) != (b.kind == .earbuds) { return a.kind == .earbuds }
        return seenFirst(a, b)
    }

    /// Connected devices by name, then disconnected ones most recently seen first.
    static func listedFirst(_ a: Known, _ b: Known) -> Bool {
        if a.device.isConnected != b.device.isConnected { return a.device.isConnected }
        if a.device.isConnected { return byName(a, b) }
        return seenFirst(a, b)
    }

    private static func seenFirst(_ a: Known, _ b: Known) -> Bool {
        switch (a.record?.lastSeen, b.record?.lastSeen) {
        case let (x?, y?) where x != y: x > y
        case (_?, nil): true
        case (nil, _?): false
        default: byName(a, b)
        }
    }

    private static func byName(_ a: Known, _ b: Known) -> Bool {
        let order = a.device.name.localizedStandardCompare(b.device.name)
        return order == .orderedSame ? a.device.address < b.device.address : order == .orderedAscending
    }
}

/// Relative times in the user's calendar, with 24-hour clock times.
private struct Clock {
    var now: Date
    var calendar: Calendar

    /// Calendar days from `date` to now: 0 today, 1 yesterday.
    func daysAgo(_ date: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
    }

    /// e.g. "today, 09:15", "yesterday, 22:42", "Tue 22:42" within a week, else "24 Sep".
    func moment(_ date: Date) -> String {
        let days = daysAgo(date)
        switch days {
        case ...0: return "today, \(format(date, "HH:mm"))"
        case 1: return "yesterday, \(format(date, "HH:mm"))"
        case 2..<7: return format(date, "EEE HH:mm")
        default: return format(date, "d MMM")
        }
    }

    private func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
