import Foundation

/// What SystemSampler reads for network on each tick.
public struct NetworkReading: Equatable, Sendable {
    /// The interface carrying the default route, or nil when the Mac is offline.
    public var interface: NetworkInterface?
    /// Bytes per second over the last sampling interval, summed over the Mac's physical interfaces.
    public var downloadPerSecond: Double
    public var uploadPerSecond: Double
    /// Bytes moved since the previous reading. Recorded as amounts so history can total them.
    public var received: Double
    public var sent: Double

    public init(
        interface: NetworkInterface?, downloadPerSecond: Double, uploadPerSecond: Double, received: Double, sent: Double
    ) {
        self.interface = interface
        self.downloadPerSecond = downloadPerSecond
        self.uploadPerSecond = uploadPerSecond
        self.received = received
        self.sent = sent
    }
}

/// The active network interface.
public struct NetworkInterface: Equatable, Sendable {
    /// What the user calls the connection, e.g. "Wi-Fi 6E", "Ethernet", "iPhone USB".
    public var name: String
    /// The Wi-Fi network name. Nil when not on Wi-Fi, or when Location permission isn't granted.
    public var networkName: String?
    /// The negotiated link rate in bits per second, if known.
    public var linkRate: Double?

    public init(name: String, networkName: String? = nil, linkRate: Double? = nil) {
        self.name = name
        self.networkName = networkName
        self.linkRate = linkRate
    }
}

extension SeriesKey {
    /// Download rate, bytes per second.
    public static let networkDown = SeriesKey(rawValue: "network.down")
    /// Upload rate, bytes per second.
    public static let networkUp = SeriesKey(rawValue: "network.up")
    /// Bytes received since the previous sample, for totals.
    public static let networkDownBytes = SeriesKey(rawValue: "network.down.bytes")
    /// Bytes sent since the previous sample, for totals.
    public static let networkUpBytes = SeriesKey(rawValue: "network.up.bytes")
}

extension Snapshot {
    /// Values MetricsHistory records for network.
    var networkSeries: [SeriesSample] {
        guard let network = network.value else { return [] }
        let busiest = AppGrouping.busiestApp(in: processes.value ?? [], by: \.resources.network)
        return [
            SeriesSample(.networkDown, network.downloadPerSecond, contributor: busiest),
            SeriesSample(.networkUp, network.uploadPerSecond),
            SeriesSample(.networkDownBytes, network.received),
            SeriesSample(.networkUpBytes, network.sent),
        ]
    }
}

/// How network speeds are shown.
public enum NetworkUnits: String, CaseIterable, Sendable {
    /// Bytes per second, e.g. `2.4 MB/s`.
    case bytes
    /// Bits per second, as ISPs advertise, e.g. `19 Mbps`.
    case bits
}

extension Preferences {
    public var networkUnits: NetworkUnits {
        get { defaults.string(forKey: "network.units").flatMap(NetworkUnits.init(rawValue:)) ?? .bytes }
        set { defaults.set(newValue.rawValue, forKey: "network.units") }
    }
}

/// The network menu bar item: combined download and upload throughput.
enum NetworkMenuBar: MenuBarMetric {
    /// The widest text the item can show; the item is sized for it.
    static func widestText(preferences: Preferences) -> String {
        switch preferences.networkUnits {
        case .bytes: "999 MB/s"
        case .bits: "999 Mbps"
        }
    }

    static func text(_ snapshot: Snapshot?, preferences: Preferences) -> String {
        guard let network = snapshot?.network.value else { return Format.placeholder }
        return NetworkFormat.rate(network.downloadPerSecond + network.uploadPerSecond, units: preferences.networkUnits)
            .text
    }

    /// Combined throughput over the last minute, scaled so the busiest bar is full height.
    @MainActor
    static func bars(history: MetricsHistory, endingAt now: Date?) -> [Double?] {
        guard let now else { return Sparkline.empty }
        return NetworkFigures.throughputBars(
            history: history, over: .oneMinute, endingAt: now, count: Sparkline.barCount
        ).map { $0.map { $0.down + $0.up } }
    }
}

extension Monitor {
    /// The main window toolbar subtitle for the Network tab, e.g. "Wi-Fi 6E · Studio-5G · 1.2 Gb/s link".
    public var networkSubtitle: String? {
        latest.map { NetworkFormat.interfaceLine($0.network) }
    }

    /// The popover's Network tab for the given chart range.
    public func networkPanel(range: TimeRange) -> NetworkPanel {
        NetworkPanel.make(
            snapshot: latest, apps: apps, history: history, range: range, units: preferences.networkUnits,
            sessionStart: startedAt
        )
    }

    /// The main window's Network tab.
    public func networkDetail() -> NetworkDetail {
        NetworkDetail.make(
            snapshot: latest, apps: apps, history: history, units: preferences.networkUnits, sessionStart: startedAt
        )
    }
}
