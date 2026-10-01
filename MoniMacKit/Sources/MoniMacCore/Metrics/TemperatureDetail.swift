import Foundation

/// Everything the main window's Temperature & Fans tab shows. Read-only: there is no fan control.
public struct TemperatureDetail: Equatable, Sendable {
    /// The ranges the chart offers.
    public static let ranges = CPUDetail.ranges
    public static let historyBarCount = 36

    /// A CPU, GPU, SSD, or Battery card.
    public struct Card: Equatable, Sendable {
        public var kind: ThermalCard
        public var title: String
        /// The number alone, e.g. "62", or a placeholder.
        public var value: String
        /// "°C" or "°F".
        public var unit: String
        /// Marker position on the 20–100 °C gauge, 0...1; nil when unavailable.
        public var gauge: Double?
        /// e.g. "Peak 81° today".
        public var caption: String
    }

    /// How hot a chart bar is, for its color.
    public enum Level: Equatable, Sendable {
        /// Under 60 °C.
        case cool
        /// 60–80 °C.
        case warm
        /// 80 °C and over.
        case hot

        static func of(_ celsius: Double) -> Level {
            celsius < 60 ? .cool : celsius < 80 ? .warm : .hot
        }
    }

    public struct Bar: Equatable, Sendable {
        /// 0...1 of the 20–100 °C scale.
        public var height: Double
        public var level: Level
    }

    /// What the read-only Fans card shows.
    public enum Fans: Equatable, Sendable {
        case speeds([FanRow])
        /// The Mac has fans but they couldn't be read; says why.
        case unreadable(String)
    }

    public struct FanRow: Equatable, Sendable, Identifiable {
        public var id: Int
        /// e.g. "Fan", "Fan 2", or the name the SMC reports.
        public var name: String
        /// e.g. "3,200".
        public var rpm: String
        /// Share of the fan's maximum speed, e.g. "48%".
        public var percent: String
        /// The same share, 0...1, for the speed bar.
        public var share: Double
        /// e.g. "1,200 RPM".
        public var minimum: String
        public var maximum: String
    }

    public struct SensorRow: Equatable, Sendable {
        public var name: String
        /// e.g. "66 °C".
        public var value: String
    }

    /// Toolbar subtitle, e.g. "Thermal state: Nominal · 1 fan".
    public var subtitle: String?
    public var cards: [Card]
    public var range: TimeRange
    /// e.g. "Avg 58 °C · Peak 81 °C at 14:14 while Xcode was busiest", or nil with no history.
    public var chartSummary: String?
    /// CPU temperature as `historyBarCount` bars over `range`, oldest first; nil where there's no data.
    public var history: [Bar?]
    /// Evenly spaced from the start of the range; the last is "Now".
    public var xAxis: [String]
    /// Nil hides the Fans card: the Mac has no fans.
    public var fans: Fans?
    /// One row per sensor group the Mac reports, averaged.
    public var sensors: [SensorRow]
    /// e.g. "Plus 132 sensors without a known location", or nil when every sensor is named.
    public var unnamedSensors: String?
}

extension TemperatureDetail {
    @MainActor
    static func make(
        snapshot: Snapshot?, history: MetricsHistory, range: TimeRange, unit: TemperatureUnit,
        calendar: Calendar = .current
    ) -> TemperatureDetail {
        let thermal = snapshot?.thermal.value
        let groups = snapshot?.thermalGroups ?? ThermalGroups([], chip: "")
        let now = snapshot?.timestamp

        return TemperatureDetail(
            subtitle: thermal.map(subtitle),
            cards: ThermalCard.allCases.map { kind in
                let celsius = kind.celsius(in: groups)
                let peak = now.flatMap { todaysPeak(kind.series, history: history, now: $0, calendar: calendar) }
                return Card(
                    kind: kind,
                    title: kind.title,
                    value: celsius.map { "\(unit.degrees($0))" } ?? Format.placeholder,
                    unit: unit.symbol,
                    gauge: celsius.map(TemperatureScale.position),
                    caption: celsius == nil ? "Not reported" : peak.map { "Peak \(unit.degrees($0))° today" } ?? "—"
                )
            },
            range: range,
            chartSummary: now.flatMap { chartSummary(history: history, range: range, now: $0, unit: unit, timeZone: calendar.timeZone) },
            history: historyBars(history, range: range, endingAt: now),
            xAxis: CPUDetail.xAxis(range: range, endingAt: now, timeZone: calendar.timeZone),
            fans: thermal.flatMap { fans($0.fans) },
            sensors: ThermalSensorGroup.allCases.compactMap { group in
                groups.average(group).map { SensorRow(name: group.title, value: unit.format($0)) }
            },
            unnamedSensors: groups.unnamedCount == 0 ? nil
                : "Plus \(groups.unnamedCount) \(groups.unnamedCount == 1 ? "sensor" : "sensors") without a known location"
        )
    }

    /// e.g. "Thermal state: Nominal · 1 fan". Fan count is left out when there are no fans.
    public static func subtitle(for thermal: ThermalReading) -> String {
        let state = "Thermal state: \(thermal.state?.title ?? "Unknown")"
        guard let count = thermal.fans.value?.count, count > 0 else { return state }
        return "\(state) · \(count) \(count == 1 ? "fan" : "fans")"
    }

    /// The highest value since local midnight. The 24-hour peak is exact when it falls today;
    /// otherwise today's peak is the highest one-minute average since midnight.
    @MainActor
    static func todaysPeak(_ series: SeriesKey, history: MetricsHistory, now: Date, calendar: Calendar) -> Double? {
        guard let summary = try? history.summary(series, over: .twentyFourHours, endingAt: now) else { return nil }
        let midnight = calendar.startOfDay(for: now)
        if let peak = summary.peak, peak.time >= midnight { return peak.value }
        return summary.points.filter { $0.time >= midnight }.map(\.value).max()
    }

    @MainActor
    private static func chartSummary(
        history: MetricsHistory, range: TimeRange, now: Date, unit: TemperatureUnit, timeZone: TimeZone
    ) -> String? {
        guard let summary = try? history.summary(.thermalCPU, over: range, endingAt: now),
              let average = summary.average, let peak = summary.peak else { return nil }
        var text = "Avg \(unit.format(average)) · Peak \(unit.format(peak.value)) at "
            + Format.time(peak.time, within: range, timeZone: timeZone)
        if let app = peak.contributor { text += " while \(app) was busiest" }
        return text
    }

    @MainActor
    private static func historyBars(_ history: MetricsHistory, range: TimeRange, endingAt now: Date?) -> [Bar?] {
        guard let now else { return Array(repeating: nil, count: historyBarCount) }
        let points = (try? history.summary(.thermalCPU, over: range, endingAt: now).points) ?? []
        return Resample.bars(points, endingAt: now, window: range.duration, count: historyBarCount).map { celsius in
            celsius.map { Bar(height: TemperatureScale.position($0), level: .of($0)) }
        }
    }

    /// Nil on a fanless Mac (no fans, or a reading that says so), which hides the card.
    private static func fans(_ reading: Reading<[Fan]>) -> Fans? {
        switch reading {
        case .value([]), .unavailable(.unsupported):
            return nil
        case .unavailable(.warmingUp):
            return .unreadable("Reading fan speeds…")
        case .unavailable(.failed(let reason)):
            return .unreadable("Fan speeds couldn't be read: \(reason).")
        case .value(let fans):
            return .speeds(fans.enumerated().map { index, fan in
                let share = fan.maximumRPM > 0 ? min(max(fan.rpm / fan.maximumRPM, 0), 1) : 0
                return FanRow(
                    id: index,
                    name: fan.name ?? (fans.count == 1 ? "Fan" : "Fan \(index + 1)"),
                    rpm: Format.count(Int(fan.rpm.rounded())),
                    percent: Format.percent(share),
                    share: share,
                    minimum: "\(Format.count(Int(fan.minimumRPM.rounded()))) RPM",
                    maximum: "\(Format.count(Int(fan.maximumRPM.rounded()))) RPM"
                )
            })
        }
    }
}
