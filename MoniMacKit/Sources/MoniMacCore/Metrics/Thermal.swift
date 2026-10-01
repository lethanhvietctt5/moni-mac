import Foundation

/// What SystemSampler reads for thermal on each tick: the OS thermal state, named temperature
/// sensors, and fans. MoniMac only reads these; it never controls fans.
public struct ThermalReading: Equatable, Sendable {
    /// Nil when macOS reports a state this version of MoniMac doesn't know.
    public var state: ThermalState?
    /// Every temperature sensor the Mac reported, under the name the hardware uses.
    public var sensors: Reading<[ThermalSensor]>
    /// `.unavailable(.unsupported)` on a fanless Mac.
    public var fans: Reading<[Fan]>

    public init(state: ThermalState?, sensors: Reading<[ThermalSensor]>, fans: Reading<[Fan]>) {
        self.state = state
        self.sensors = sensors
        self.fans = fans
    }
}

/// How hard macOS is working to cool the Mac (`ProcessInfo.ThermalState`).
public enum ThermalState: String, CaseIterable, Sendable {
    case nominal, fair, serious, critical

    public var title: String { rawValue.capitalized }
}

/// One temperature reading.
public struct ThermalSensor: Equatable, Sendable {
    /// What the hardware calls it: an SMC key (e.g. "Tp01") or an IOHID product (e.g. "NAND CH0 temp").
    public var name: String
    public var celsius: Double

    public init(name: String, celsius: Double) {
        self.name = name
        self.celsius = celsius
    }
}

/// One fan's speed and the range macOS drives it within.
public struct Fan: Equatable, Sendable {
    /// The name the SMC gives the fan, if it gives one.
    public var name: String?
    public var rpm: Double
    public var minimumRPM: Double
    public var maximumRPM: Double

    public init(name: String? = nil, rpm: Double, minimumRPM: Double, maximumRPM: Double) {
        self.name = name
        self.rpm = rpm
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
    }
}

extension SeriesKey {
    /// Average CPU core temperature, °C. Its contributor is the busiest app by CPU.
    public static let thermalCPU = SeriesKey(rawValue: "thermal.cpu")
    public static let thermalGPU = SeriesKey(rawValue: "thermal.gpu")
    public static let thermalSSD = SeriesKey(rawValue: "thermal.ssd")
    public static let thermalBattery = SeriesKey(rawValue: "thermal.battery")
}

/// The parts with a card in the Temperature & Fans tab, each with a history series.
public enum ThermalCard: CaseIterable, Sendable {
    case cpu, gpu, ssd, battery

    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .ssd: "SSD"
        case .battery: "Battery"
        }
    }

    var series: SeriesKey {
        switch self {
        case .cpu: .thermalCPU
        case .gpu: .thermalGPU
        case .ssd: .thermalSSD
        case .battery: .thermalBattery
        }
    }

    /// This part's temperature, °C, or nil when the Mac doesn't report it.
    func celsius(in groups: ThermalGroups) -> Double? {
        switch self {
        case .cpu: groups.cpu
        case .gpu: groups.average(.gpu)
        case .ssd: groups.average(.ssd)
        case .battery: groups.average(.battery)
        }
    }
}

/// The span gauges, chart bars, and the menu bar sparkline share: room temperature to throttling.
enum TemperatureScale {
    static let range: ClosedRange<Double> = 20...100

    /// A temperature as 0...1 of `range`.
    static func position(_ celsius: Double) -> Double {
        min(max((celsius - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }
}

extension Snapshot {
    /// Sensors grouped for this Mac's chip, or nil when no sensors were read.
    var thermalGroups: ThermalGroups? {
        thermal.value?.sensors.value.map { ThermalGroups($0, chip: system.chipName) }
    }

    /// Values MetricsHistory records for thermal: the card temperatures, in °C.
    var thermalSeries: [SeriesSample] {
        guard let groups = thermalGroups else { return [] }
        return ThermalCard.allCases.compactMap { card in
            card.celsius(in: groups).map { celsius in
                let busiest = card == .cpu ? AppGrouping.busiestApp(in: processes.value ?? [], by: \.cpu) : nil
                return SeriesSample(card.series, celsius, contributor: busiest)
            }
        }
    }

    /// The menu bar's temperature: the CPU, or the hottest known sensor when the CPU isn't reported.
    var headlineTemperature: Double? {
        thermalGroups.flatMap { $0.cpu ?? $0.hottest }
    }
}

/// Celsius or Fahrenheit, applied on every surface.
public enum TemperatureUnit: String, CaseIterable, Sendable {
    case celsius, fahrenheit

    /// "°C" or "°F".
    public var symbol: String { self == .celsius ? "°C" : "°F" }

    /// A Celsius temperature in this unit, rounded to a whole degree.
    public func degrees(_ celsius: Double) -> Int {
        let value = self == .celsius ? celsius : celsius * 9 / 5 + 32
        return Int(value.rounded())
    }

    /// Compact, e.g. "58°C"; for the menu bar.
    public func compact(_ celsius: Double) -> String { "\(degrees(celsius))\(symbol)" }

    /// Spaced, e.g. "58 °C"; for lists and captions.
    public func format(_ celsius: Double) -> String { "\(degrees(celsius)) \(symbol)" }
}

extension Preferences {
    /// °C or °F. Settings (ticket 13) offers the choice.
    public var temperatureUnit: TemperatureUnit {
        get { defaults.string(forKey: "temperature.unit").flatMap(TemperatureUnit.init(rawValue:)) ?? .celsius }
        set { defaults.set(newValue.rawValue, forKey: "temperature.unit") }
    }
}

/// The temperature menu bar item.
enum TemperatureMenuBar: MenuBarMetric {
    /// The widest text the item can show; the item is sized for it.
    static func widestText(preferences: Preferences) -> String {
        preferences.temperatureUnit.compact(100)
    }

    static func text(_ snapshot: Snapshot?, preferences: Preferences) -> String {
        guard let celsius = snapshot?.headlineTemperature else { return Format.placeholder }
        return preferences.temperatureUnit.compact(celsius)
    }

    /// Sparkline bars over the last minute, 0...1 of `TemperatureScale`, `Sparkline.barCount` long.
    @MainActor
    static func bars(history: MetricsHistory, endingAt now: Date?) -> [Double?] {
        guard let now else { return Sparkline.empty }
        let points = (try? history.summary(.thermalCPU, over: .oneMinute, endingAt: now).points) ?? []
        return Sparkline.bars(points, endingAt: now).map { $0.map(TemperatureScale.position) }
    }
}

extension Monitor {
    /// The main window toolbar subtitle for the Temperature & Fans tab, e.g. "Thermal state: Nominal · 1 fan".
    public var temperatureSubtitle: String? {
        latest?.thermal.value.map(TemperatureDetail.subtitle)
    }

    /// The main window's Temperature & Fans tab for the given chart range.
    public func temperatureDetail(range: TimeRange) -> TemperatureDetail {
        TemperatureDetail.make(snapshot: latest, history: history, range: range, unit: preferences.temperatureUnit)
    }
}
