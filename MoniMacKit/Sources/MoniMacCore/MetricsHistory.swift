import Foundation

/// A named numeric series recorded from snapshots.
public struct SeriesKey: Hashable, Sendable, RawRepresentable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Total CPU in use, 0...1.
    public static let cpuTotal = SeriesKey(rawValue: "cpu.total")
    public static let cpuUser = SeriesKey(rawValue: "cpu.user")
    public static let cpuSystem = SeriesKey(rawValue: "cpu.system")
}

/// The time ranges charts can show.
public enum TimeRange: CaseIterable, Sendable {
    case oneMinute, fiveMinutes, oneHour, twelveHours, twentyFourHours, sevenDays, thirtyDays

    public var duration: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .fiveMinutes: 5 * 60
        case .oneHour: 3600
        case .twelveHours: 12 * 3600
        case .twentyFourHours: 24 * 3600
        case .sevenDays: 7 * 86400
        case .thirtyDays: 30 * 86400
        }
    }
}

public struct SeriesPoint: Equatable, Sendable {
    public var time: Date
    public var value: Double

    public init(time: Date, value: Double) {
        self.time = time
        self.value = value
    }
}

/// One series over one time range.
public struct SeriesSummary: Equatable, Sendable {
    /// Oldest first. Raw samples for short ranges, bucket averages for long ones.
    public var points: [SeriesPoint]
    public var average: Double?
    /// The highest single sample in the range and when it happened.
    public var peak: SeriesPoint?
}

/// Stores snapshots locally and answers range queries.
///
/// Every sample is written raw and also folded into one-minute and 15-minute buckets at write time.
/// Finer tiers are pruned once coarser ones cover them, so older data survives only downsampled:
/// raw for about an hour, one-minute buckets for a day, 15-minute buckets for the retention period.
@MainActor
public final class MetricsHistory {
    public enum Location: Equatable {
        case inMemory
        case file(URL)
    }

    /// How long 15-minute buckets are kept. Changing it prunes immediately.
    public var retention: TimeInterval {
        didSet { try? prune(now: lastRecorded ?? Date()) }
    }

    private let database: Database
    private var lastRecorded: Date?
    private var lastPruned: Date?

    public init(_ location: Location, retention: TimeInterval = TimeRange.thirtyDays.duration) throws {
        self.retention = retention
        switch location {
        case .inMemory: database = try Database(.inMemory)
        case .file(let url): database = try Database(.file(url))
        }
        try database.execute("""
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            CREATE TABLE IF NOT EXISTS raw (series TEXT NOT NULL, t REAL NOT NULL, v REAL NOT NULL);
            CREATE INDEX IF NOT EXISTS raw_series_t ON raw (series, t);
            CREATE TABLE IF NOT EXISTS buckets (
                tier INTEGER NOT NULL, series TEXT NOT NULL, start REAL NOT NULL,
                sum REAL NOT NULL, count INTEGER NOT NULL, max REAL NOT NULL, max_t REAL NOT NULL,
                PRIMARY KEY (tier, series, start)
            ) WITHOUT ROWID;
            """)
    }

    /// Records every available value in the snapshot. Unavailable values leave a gap.
    public func record(_ snapshot: Snapshot) throws {
        let values = Self.values(in: snapshot)
        let t = snapshot.timestamp.timeIntervalSinceReferenceDate
        try database.transaction {
            for (series, value) in values {
                try database.run("INSERT INTO raw (series, t, v) VALUES (?, ?, ?)",
                                 .text(series.rawValue), .double(t), .double(value))
                for tier in Tier.bucketed {
                    try database.run("""
                        INSERT INTO buckets VALUES (?, ?, ?, ?, 1, ?, ?)
                        ON CONFLICT (tier, series, start) DO UPDATE SET
                            sum = sum + excluded.sum,
                            count = count + 1,
                            max_t = CASE WHEN excluded.max > max THEN excluded.max_t ELSE max_t END,
                            max = MAX(max, excluded.max)
                        """,
                        .int(tier.rawValue), .text(series.rawValue), .double(tier.bucketStart(t)),
                        .double(value), .double(value), .double(t))
                }
            }
        }
        lastRecorded = snapshot.timestamp
        if lastPruned.map({ snapshot.timestamp.timeIntervalSince($0) >= 60 }) ?? true {
            try prune(now: snapshot.timestamp)
        }
    }

    /// The series over `range`, ending at `now`.
    public func summary(_ series: SeriesKey, over range: TimeRange, endingAt now: Date) throws -> SeriesSummary {
        let to = now.timeIntervalSinceReferenceDate
        let from = to - range.duration
        let tier = Tier.serving(range)
        let key = Database.Value.text(series.rawValue)

        if tier == .raw {
            let points = try database.query(
                "SELECT t, v FROM raw WHERE series = ? AND t > ? AND t <= ? ORDER BY t", key, .double(from), .double(to)
            ) { SeriesPoint(time: Date(timeIntervalSinceReferenceDate: $0.double(0)), value: $0.double(1)) }
            let average = points.isEmpty ? nil : points.map(\.value).reduce(0, +) / Double(points.count)
            let peak = points.max { $0.value < $1.value }
            return SeriesSummary(points: points, average: average, peak: peak)
        }

        let rows = try database.query("""
            SELECT start, sum, count, max, max_t FROM buckets
            WHERE tier = ? AND series = ? AND start > ? AND start <= ? ORDER BY start
            """, .int(tier.rawValue), key, .double(from - tier.size), .double(to)
        ) { (start: $0.double(0), sum: $0.double(1), count: $0.double(2), max: $0.double(3), maxT: $0.double(4)) }
        let points = rows.map {
            SeriesPoint(time: Date(timeIntervalSinceReferenceDate: $0.start), value: $0.sum / $0.count)
        }
        let total = rows.reduce(0) { $0 + $1.count }
        let average = total == 0 ? nil : rows.reduce(0) { $0 + $1.sum } / total
        let peak = rows.max { $0.max < $1.max }.map {
            SeriesPoint(time: Date(timeIntervalSinceReferenceDate: $0.maxT), value: $0.max)
        }
        return SeriesSummary(points: points, average: average, peak: peak)
    }

    private func prune(now: Date) throws {
        let t = now.timeIntervalSinceReferenceDate
        try database.transaction {
            try database.run("DELETE FROM raw WHERE t < ?", .double(t - Tier.raw.keep(retention: retention)))
            for tier in Tier.bucketed {
                try database.run("DELETE FROM buckets WHERE tier = ? AND start < ?",
                                 .int(tier.rawValue), .double(t - tier.keep(retention: retention)))
            }
        }
        lastPruned = now
    }

    private static func values(in snapshot: Snapshot) -> [(SeriesKey, Double)] {
        snapshot.cpuSeries + snapshot.memorySeries + snapshot.gpuSeries + snapshot.networkSeries
            + snapshot.diskSeries + snapshot.batterySeries + snapshot.thermalSeries
    }
}

private enum Tier: Int {
    case raw = 0
    case minute = 1
    case quarterHour = 2

    static let bucketed: [Tier] = [.minute, .quarterHour]

    /// Bucket width in seconds.
    var size: TimeInterval {
        switch self {
        case .raw: 0
        case .minute: 60
        case .quarterHour: 900
        }
    }

    func bucketStart(_ t: TimeInterval) -> TimeInterval {
        (t / size).rounded(.down) * size
    }

    /// How long this tier is kept. Each tier outlives the ranges it serves by a small margin.
    func keep(retention: TimeInterval) -> TimeInterval {
        switch self {
        case .raw: TimeRange.oneHour.duration + 5 * 60
        case .minute: TimeRange.twentyFourHours.duration + 3600
        case .quarterHour: retention
        }
    }

    /// The finest tier that still covers the range.
    static func serving(_ range: TimeRange) -> Tier {
        switch range.duration {
        case ...TimeRange.oneHour.duration: .raw
        case ...TimeRange.twentyFourHours.duration: .minute
        default: .quarterHour
        }
    }
}
