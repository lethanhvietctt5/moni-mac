import Foundation

// Bluetooth (ticket 15). Bluetooth has no menu bar item and no popover tab. The window tab renders
// `BluetoothDetail` (BluetoothDetail.swift); per-device memory across readings and relaunches lives in
// BluetoothTracker.swift, and the low-battery rule in BluetoothAlerts.swift.
//
// No history series: levels change over hours and are keyed per device, so recording them every tick
// would add writes for nothing a chart shows. What the tab needs from the past (last seen, last charged,
// the drain since then) is a few figures per device, kept by `BluetoothTracker`.

/// What SystemSampler read about Bluetooth devices. The sources are slow, so they're read in the
/// background (see `BluetoothDemand`); the same reading repeats on the ticks in between.
public struct BluetoothReading: Equatable, Sendable {
    /// Paired devices, connected or not, in the order macOS listed them.
    public var devices: [BluetoothDevice]
    /// Whether the Mac's Bluetooth is on. While it's off, nothing is connected.
    public var isPoweredOn: Bool
    /// When the sources were read.
    public var readAt: Date

    public init(devices: [BluetoothDevice], isPoweredOn: Bool = true, readAt: Date) {
        self.devices = devices
        self.isPoweredOn = isPoweredOn
        self.readAt = readAt
    }

    public var connected: [BluetoothDevice] { devices.filter(\.isConnected) }
}

/// One paired device, as macOS reports it.
public struct BluetoothDevice: Equatable, Sendable, Identifiable {
    /// The Bluetooth address, "AA:BB:CC:DD:EE:FF".
    public var address: String
    public var name: String
    /// macOS's word for the device, e.g. "Headphones", "Keyboard", "Magic Trackpad". Nil when not reported.
    public var minorType: String?
    /// The Bluetooth SIG vendor id, e.g. 0x004C for Apple.
    public var vendorID: Int?
    public var isConnected: Bool
    /// e.g. "7A305". Nil when the device doesn't report one.
    public var firmware: String?
    /// While connected, the current levels. While disconnected, macOS still reports AirPods' last levels;
    /// other devices report none.
    public var battery: BluetoothBattery
    /// Whether the device says it's charging; nil when it doesn't say.
    public var isCharging: Bool?

    public init(
        address: String, name: String, minorType: String? = nil, vendorID: Int? = nil, isConnected: Bool,
        firmware: String? = nil, battery: BluetoothBattery = BluetoothBattery(), isCharging: Bool? = nil
    ) {
        self.address = address
        self.name = name
        self.minorType = minorType
        self.vendorID = vendorID
        self.isConnected = isConnected
        self.firmware = firmware
        self.battery = battery
        self.isCharging = isCharging
    }

    public var id: String { address }

    public var kind: BluetoothDeviceKind {
        BluetoothDeviceKind(minorType: minorType, hasEarbuds: battery.hasEarbuds)
    }
}

/// Battery levels in whole percent, 0...100. A single-battery device reports `main`; AirPods-class
/// devices report `left`, `right`, and `case`. Missing levels are nil, never zero.
public struct BluetoothBattery: Equatable, Sendable, Codable {
    public var main: Int?
    public var left: Int?
    public var right: Int?
    public var `case`: Int?

    public init(main: Int? = nil, left: Int? = nil, right: Int? = nil, case: Int? = nil) {
        self.main = main
        self.left = left
        self.right = right
        self.case = `case`
    }

    public var hasEarbuds: Bool { left != nil || right != nil }
    public var isEmpty: Bool { main == nil && left == nil && right == nil && self.case == nil }

    /// The level that runs out first while in use: the lowest of the main battery and the earbuds.
    /// The case is left out: it isn't worn, and earbuds in the case are charging.
    public var lowest: Int? {
        [main, left, right].compactMap { $0 }.min()
    }
}

/// What sort of device it is, for its icon and type label.
public enum BluetoothDeviceKind: Equatable, Sendable {
    /// Headphones with separate left and right earbuds (and usually a case), e.g. AirPods.
    case earbuds
    case headphones
    case keyboard
    case mouse
    case trackpad
    case gameController
    case speaker
    case phone
    /// Anything else, with macOS's own word for it when it gave one.
    case other(String?)

    /// From macOS's minor type. A device that reports separate earbud levels is earbuds whatever its type.
    /// Only the minor type decides: names are the user's and aren't guessed from.
    init(minorType: String?, hasEarbuds: Bool) {
        if hasEarbuds {
            self = .earbuds
            return
        }
        let type = (minorType ?? "").lowercased()
        func has(_ words: String...) -> Bool { words.contains { type.contains($0) } }
        self = if has("headphone", "headset", "earbud") {
            .headphones
        } else if has("trackpad") {
            .trackpad
        } else if has("keyboard") {
            .keyboard
        } else if has("mouse") {
            .mouse
        } else if has("gamepad", "game controller", "joystick") {
            .gameController
        } else if has("speaker") {
            .speaker
        } else if has("phone", "cellular") {
            .phone
        } else {
            .other(minorType.flatMap { $0.isEmpty ? nil : $0 })
        }
    }

    /// e.g. "Keyboard", "Game Controller", or macOS's word for anything else.
    public var title: String {
        switch self {
        case .earbuds, .headphones: "Headphones"
        case .keyboard: "Keyboard"
        case .mouse: "Mouse"
        case .trackpad: "Trackpad"
        case .gameController: "Game Controller"
        case .speaker: "Speaker"
        case .phone: "Phone"
        case .other(let type): type ?? "Device"
        }
    }

    /// Headphones of either sort: the kind the featured card is for.
    public var isHeadphones: Bool { self == .earbuds || self == .headphones }
}

/// How often the Bluetooth sources should be read, decided by what needs them.
public enum BluetoothDemand: Equatable, Sendable {
    /// Nothing needs them: the Bluetooth tab isn't showing and low-battery notifications are off.
    case none
    /// Only the low-battery rule needs them.
    case background
    /// The Bluetooth tab is showing.
    case live

    /// The least time between reads; nil means don't read.
    public var interval: TimeInterval? {
        switch self {
        case .none: nil
        case .background: 300
        case .live: 30
        }
    }
}

extension Preferences {
    /// "Low battery notifications" on the Bluetooth tab. On by default, as the design draws it.
    public var bluetoothLowBatteryAlerts: Bool {
        get { defaults.object(forKey: "bluetooth.lowBatteryAlerts") as? Bool ?? true }
        set { set(newValue, forKey: "bluetooth.lowBatteryAlerts") }
    }
}

extension Monitor {
    /// The main window toolbar subtitle for the Bluetooth tab, e.g. "4 devices connected".
    public var bluetoothSubtitle: String? {
        latest.map { BluetoothDetail.subtitle(for: $0.bluetooth) }
    }

    /// How often the sampler should read Bluetooth: live while the tab is showing, in the background
    /// while low-battery notifications are on, otherwise not at all.
    public func bluetoothDemand(isTabShowing: Bool) -> BluetoothDemand {
        if isTabShowing { return .live }
        return preferences.bluetoothLowBatteryAlerts ? .background : .none
    }

    /// The Bluetooth tab.
    public var bluetoothDetail: BluetoothDetail {
        BluetoothDetail.make(
            reading: latest?.bluetooth ?? .unavailable(.warmingUp), records: bluetoothTracker.records,
            now: latest?.timestamp ?? Date(), lowBatteryAlerts: preferences.bluetoothLowBatteryAlerts,
            audio: latest?.sound.value
        )
    }

    /// Takes in a new reading: remembers each device and runs the low-battery rule. A reading repeats on
    /// the ticks between background reads; it's processed once.
    func observeBluetooth(_ snapshot: Snapshot) {
        guard let reading = snapshot.bluetooth.value, bluetoothTracker.observe(reading) else { return }
        evaluateBluetoothAlerts(reading)
    }

    // MARK: Intents

    /// Turning notifications on is their first use, so it asks for permission (once per session).
    public func setBluetoothLowBatteryAlerts(_ enabled: Bool) {
        preferences.bluetoothLowBatteryAlerts = enabled
        if enabled { requestNotificationPermission() } else { alerts.bluetooth.reset() }
    }

    /// Opens System Settings › Bluetooth, where devices are connected and paired. MoniMac never does that itself.
    public func openBluetoothSettings() {
        actions.openURL(BluetoothDetail.settingsURL)
    }
}
