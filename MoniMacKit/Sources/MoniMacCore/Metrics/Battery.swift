import Foundation

// Battery (ticket 09). Battery has no menu bar item. The window and popover tabs render
// `BatteryDetail` (BatteryDetail.swift); history math lives in BatteryHistory.swift.

/// What SystemSampler reads for the internal battery on each tick.
/// Figures the Mac doesn't report are nil and shown as a placeholder, never as zero.
public struct BatteryReading: Equatable, Sendable {
    /// How long until the battery is full (while charging) or empty (on battery).
    public enum TimeRemaining: Equatable, Sendable {
        /// macOS is still estimating (it reports -1 for a while after the power source changes).
        case calculating
        case minutes(Int)

        /// The estimate, or nil while calculating.
        public var minutes: Int? {
            if case .minutes(let minutes) = self { minutes } else { nil }
        }
    }

    /// State of charge, 0...1.
    public var charge: Double
    /// Whether a power adapter is connected. True while plugged in even when the battery isn't charging.
    public var isPluggedIn: Bool
    public var isCharging: Bool
    public var isFullyCharged: Bool
    /// Time to full while charging, time to empty on battery; nil when neither applies.
    public var timeRemaining: TimeRemaining?
    /// The connected adapter's rating in watts.
    public var adapterWatts: Double?
    /// Power flowing through the battery in watts: positive while charging, negative while discharging.
    public var batteryPower: Double?
    /// The whole Mac's power use in watts, as estimated by the power controller.
    public var systemPower: Double?
    /// Capacity when new, mAh.
    public var designCapacity: Int?
    /// Capacity now, mAh.
    public var maxCapacity: Int?
    public var cycleCount: Int?
    /// Cycles the battery is rated for, when the battery reports it.
    public var ratedCycles: Int?
    /// Apple's rating for Apple silicon MacBook batteries, assumed when the battery doesn't say.
    public static let appleSiliconRatedCycles = 1000
    /// Battery temperature in °C.
    public var temperature: Double?

    public init(
        charge: Double, isPluggedIn: Bool, isCharging: Bool, isFullyCharged: Bool = false,
        timeRemaining: TimeRemaining? = nil, adapterWatts: Double? = nil, batteryPower: Double? = nil,
        systemPower: Double? = nil, designCapacity: Int? = nil, maxCapacity: Int? = nil, cycleCount: Int? = nil,
        ratedCycles: Int? = nil, temperature: Double? = nil
    ) {
        self.charge = charge
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
        self.isFullyCharged = isFullyCharged
        self.timeRemaining = timeRemaining
        self.adapterWatts = adapterWatts
        self.batteryPower = batteryPower
        self.systemPower = systemPower
        self.designCapacity = designCapacity
        self.maxCapacity = maxCapacity
        self.cycleCount = cycleCount
        self.ratedCycles = ratedCycles
        self.temperature = temperature
    }

    /// Current capacity as a share of design capacity, 0...1.
    public var health: Double? {
        guard let designCapacity, let maxCapacity, designCapacity > 0 else { return nil }
        return Double(maxCapacity) / Double(designCapacity)
    }
}

extension SeriesKey {
    /// State of charge, 0...1.
    public static let batteryCharge = SeriesKey(rawValue: "battery.charge")
    /// 1 while a power adapter is connected, 0 on battery. Bucket averages are the plugged-in share.
    public static let batteryPluggedIn = SeriesKey(rawValue: "battery.pluggedIn")
}

extension Snapshot {
    /// Values MetricsHistory records for battery.
    var batterySeries: [SeriesSample] {
        guard let battery = battery.value else { return [] }
        return [
            SeriesSample(.batteryCharge, battery.charge),
            SeriesSample(.batteryPluggedIn, battery.isPluggedIn ? 1 : 0),
        ]
    }
}

extension Monitor {
    /// The main window toolbar subtitle for the Battery tab, e.g. "Charging · 1 h 12 min until full".
    public var batterySubtitle: String? {
        latest.map { BatteryDetail.subtitle(for: $0.battery) }
    }

    /// Whether this Mac has a battery. Every battery surface is hidden when it doesn't.
    ///
    /// Only a sampler that reports battery as unsupported hides it: a battery whose read failed
    /// still shows, with the reason. Before the first sample nothing is known, so it stays hidden
    /// rather than flashing a tab a desktop Mac doesn't have (the first sample is taken at launch).
    public var hasBattery: Bool {
        guard let latest else { return false }
        return latest.battery != .unavailable(.unsupported)
    }

    /// The Battery tab for the given chart range: `.window` for the main window, `.popover` for the popover.
    public func batteryDetail(range: TimeRange, layout: BatteryDetail.Layout) -> BatteryDetail {
        BatteryDetail.make(snapshot: latest, apps: apps, history: history, range: range, layout: layout,
                           unit: preferences.temperatureUnit)
    }
}
