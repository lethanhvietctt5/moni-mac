import Foundation

/// Everything the Battery tabs show. The window and the popover build it with different layouts.
public struct BatteryDetail: Equatable, Sendable {
    /// What differs between the window tab and the compact popover tab.
    public struct Layout: Equatable, Sendable {
        /// The ranges the chart offers.
        public var ranges: [TimeRange]
        /// Used when the surface's kept range isn't one of `ranges`.
        public var defaultRange: TimeRange
        public var historyBarCount: Int
        public var energyAppCount: Int

        public static let window = Layout(
            ranges: [.twelveHours, .twentyFourHours, .sevenDays, .thirtyDays], defaultRange: .twentyFourHours,
            historyBarCount: 24, energyAppCount: 7
        )
        /// Charge barely moves within minutes, so the popover offers hours rather than the CPU tab's 1m/5m.
        public static let popover = Layout(
            ranges: [.oneHour, .twelveHours, .twentyFourHours], defaultRange: .twentyFourHours,
            historyBarCount: 30, energyAppCount: 4
        )
    }

    public struct Stat: Equatable, Sendable {
        public enum Kind: Sendable { case power, health, cycles, temperature }

        public var kind: Kind
        public var label: String
        public var value: String
        public var caption: String
        /// Tooltip, e.g. saying a figure is an estimate.
        public var help: String?
    }

    public struct EnergyApp: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var bundlePath: String?
        /// e.g. "4.8 W".
        public var value: String
        /// Bar length relative to the hungriest app, 0...1.
        public var share: Double
        public var canQuit: Bool
    }

    /// Toolbar subtitle, e.g. "Charging · 1 h 12 min until full".
    public var subtitle: String
    /// e.g. "86%".
    public var charge: String
    /// For the battery glyph, 0...1; nil when unavailable.
    public var level: Double?
    public var isCharging: Bool
    /// e.g. "Power Adapter · 96 W" or "On battery".
    public var source: String
    /// e.g. "Full in 1 h 12 min", "3 h 20 min remaining", "Calculating…".
    public var status: String
    /// Power Draw, Health, Cycle Count, Temperature.
    public var stats: [Stat]
    /// The range shown: the requested one, or the layout's default if the layout doesn't offer it.
    public var range: TimeRange
    public var ranges: [TimeRange]
    /// `historyBarCount` bars over `range`, oldest first; nil where there's no data.
    public var history: [BatteryHistory.Bar?]
    /// e.g. "Plugged in 2 times · Avg drain 9.8 %/h on battery".
    public var historyCaption: String
    public var yAxis: [String]
    /// Evenly spaced from the start of the range; the last is "Now".
    public var xAxis: [String]
    /// Apps by estimated power, hungriest first.
    public var energyApps: [EnergyApp]

    /// Tooltip for every power figure.
    public static let estimateHelp = "Estimated from the power controller's readings; not a precise measurement."
    public static let appEstimateHelp = "Estimated from each app's CPU and GPU energy use; not a precise measurement."
}

extension BatteryDetail {
    @MainActor
    static func make(
        snapshot: Snapshot?, apps: [AppUsage], history: MetricsHistory, range requested: TimeRange, layout: Layout,
        unit: TemperatureUnit = .celsius, timeZone: TimeZone = .current
    ) -> BatteryDetail {
        let reading = snapshot?.battery ?? .unavailable(.warmingUp)
        let battery = reading.value
        let range = layout.ranges.contains(requested) ? requested : layout.defaultRange
        let now = snapshot?.timestamp
        let charge = now.map { (try? history.summary(.batteryCharge, over: range, endingAt: $0).points) ?? [] } ?? []
        let pluggedIn = now.map { (try? history.summary(.batteryPluggedIn, over: range, endingAt: $0).points) ?? [] } ?? []

        return BatteryDetail(
            subtitle: subtitle(for: reading),
            charge: battery.map { Format.percent($0.charge) } ?? Format.placeholder,
            level: battery?.charge,
            isCharging: battery?.isCharging ?? false,
            source: battery.map(source) ?? Format.placeholder,
            status: status(for: reading),
            stats: stats(battery, unit: unit),
            range: range,
            ranges: layout.ranges,
            history: now.map {
                BatteryHistory.bars(charge: charge, pluggedIn: pluggedIn, endingAt: $0, window: range.duration,
                                    count: layout.historyBarCount)
            } ?? Array(repeating: nil, count: layout.historyBarCount),
            historyCaption: historyCaption(charge: charge, pluggedIn: pluggedIn, range: range),
            yAxis: ["100%", "50%", "0%"],
            xAxis: CPUDetail.xAxis(range: range, endingAt: now, timeZone: timeZone),
            energyApps: energyApps(apps, count: layout.energyAppCount)
        )
    }

    /// What the battery is doing, with minutes to full or empty when macOS has an estimate.
    private enum State {
        case charging(minutes: Int?)
        case pluggedIn(isFullyCharged: Bool)
        case onBattery(minutes: Int?)

        init(_ battery: BatteryReading) {
            // A missing estimate while charging or on battery means macOS hasn't produced one yet.
            let minutes = battery.timeRemaining?.minutes
            if battery.isCharging {
                self = .charging(minutes: minutes)
            } else if battery.isPluggedIn {
                self = .pluggedIn(isFullyCharged: battery.isFullyCharged)
            } else {
                self = .onBattery(minutes: minutes)
            }
        }
    }

    /// e.g. "Charging · 1 h 12 min until full", "On battery · 3 h 20 min left", "Fully charged".
    static func subtitle(for reading: Reading<BatteryReading>) -> String {
        guard let battery = reading.value else { return status(for: reading) }
        return switch State(battery) {
        case .charging(let minutes): "Charging · " + (minutes.map { "\(duration(minutes: $0)) until full" } ?? calculating)
        case .pluggedIn(let full): full ? "Fully charged" : "On power · Not charging"
        case .onBattery(let minutes): "On battery · " + (minutes.map { "\(duration(minutes: $0)) left" } ?? calculating)
        }
    }

    /// The hero's second line: time to full or empty, or why there's none.
    static func status(for reading: Reading<BatteryReading>) -> String {
        switch reading {
        case .unavailable(.warmingUp): Format.placeholder
        case .unavailable(.unsupported): "This Mac has no battery"
        case .unavailable(.failed(let reason)): "Battery unavailable: \(reason)"
        case .value(let battery):
            switch State(battery) {
            case .charging(let minutes): minutes.map { "Full in \(duration(minutes: $0))" } ?? calculating
            case .pluggedIn(let full): full ? "Fully charged" : "Not charging"
            case .onBattery(let minutes): minutes.map { "\(duration(minutes: $0)) remaining" } ?? calculating
            }
        }
    }

    static let calculating = "Calculating…"

    /// e.g. "Power Adapter · 96 W" or "On battery".
    private static func source(_ battery: BatteryReading) -> String {
        guard battery.isPluggedIn else { return "On battery" }
        return battery.adapterWatts.map { "Power Adapter · \(Int($0.rounded())) W" } ?? "Power Adapter"
    }

    private static func stats(_ battery: BatteryReading?, unit: TemperatureUnit) -> [Stat] {
        let dash = Format.placeholder
        let health = battery?.health
        let temperature = battery?.temperature
        return [
            Stat(kind: .power, label: "Power Draw", value: battery?.batteryPower.map { watts(abs($0)) } ?? dash,
                 caption: powerCaption(battery),
                 help: "Power flowing into or out of the battery, and the whole Mac's use. " + estimateHelp),
            Stat(kind: .health, label: "Health", value: health.map { Format.percent($0) } ?? dash,
                 caption: health.map { health in
                     let condition = health >= 0.8 ? "Normal" : "Service recommended"
                     guard let max = battery?.maxCapacity, let design = battery?.designCapacity else { return condition }
                     return "\(condition) · \(Format.count(max)) of \(Format.count(design)) mAh"
                 } ?? dash,
                 help: "Current full-charge capacity compared with the battery's design capacity."),
            Stat(kind: .cycles, label: "Cycle Count", value: battery?.cycleCount.map(Format.count) ?? dash,
                 caption: battery.map {
                     "of \(Format.count($0.ratedCycles ?? BatteryReading.appleSiliconRatedCycles)) rated cycles"
                 } ?? dash,
                 help: nil),
            Stat(kind: .temperature, label: "Temperature", value: temperature.map(unit.precise) ?? dash,
                 caption: temperature.map(temperatureNote) ?? dash, help: nil),
        ]
    }

    /// Says which way power flows, since Power Draw is shown unsigned: "Charging · system using 21.6 W".
    private static func powerCaption(_ battery: BatteryReading?) -> String {
        let system = battery?.systemPower.map { "system using \(watts($0))" } ?? "system power unavailable"
        let caption = (battery?.batteryPower ?? 0) > 0 ? "Charging · \(system)" : system
        return caption.prefix(1).uppercased() + caption.dropFirst()
    }

    /// Apple rates Mac batteries for 10–35 °C ambient; the pack itself normally sits below 40 °C.
    static func temperatureNote(_ celsius: Double) -> String {
        switch celsius {
        case ..<10: "Below normal range"
        case ...40: "Within normal range"
        default: "Above normal range"
        }
    }

    static func historyCaption(charge: [SeriesPoint], pluggedIn: [SeriesPoint], range: TimeRange) -> String {
        guard !pluggedIn.isEmpty else { return "No history yet" }
        if pluggedIn.allSatisfy({ BatteryHistory.isPluggedIn($0.value) }) { return "On power the whole time" }
        let count = BatteryHistory.plugInCount(pluggedIn)
        let plugged = "Plugged in \(count) \(count == 1 ? "time" : "times")"
        guard let drain = BatteryHistory.averageDrain(
            charge: charge, pluggedIn: pluggedIn, maxGap: BatteryHistory.maxGap(for: range)
        ) else { return plugged }
        return plugged + String(format: " · Avg drain %.1f %%/h on battery", drain * 100)
    }

    private static func energyApps(_ apps: [AppUsage], count: Int) -> [EnergyApp] {
        let ranked = apps.compactMap { app in
            app.resources.power.flatMap { $0 >= significantPower ? (app, $0) : nil }
        }
            .sorted { $0.1 > $1.1 }
            .prefix(count)
        let top = ranked.first?.1 ?? 0
        return ranked.map { app, power in
            EnergyApp(id: app.id, name: app.name, bundlePath: app.bundlePath, value: watts(power),
                      share: top > 0 ? power / top : 0, canQuit: app.canQuit)
        }
    }

    /// Apps below this draw would read "0.0 W", so they aren't listed.
    static let significantPower = 0.05

    /// e.g. "4.8 W".
    static func watts(_ value: Double) -> String {
        String(format: "%.1f W", value)
    }

    /// e.g. "1 h 12 min", "45 min".
    static func duration(minutes: Int) -> String {
        let (hours, mins) = (max(minutes, 0) / 60, max(minutes, 0) % 60)
        if hours == 0 { return mins == 0 ? "< 1 min" : "\(mins) min" }
        return mins == 0 ? "\(hours) h" : "\(hours) h \(mins) min"
    }
}
