import Foundation

/// Everything the main window's Disk tab shows.
public struct DiskDetail: Equatable, Sendable {
    /// The ranges the window chart offers.
    public static let ranges = CPUDetail.ranges
    public static let historyBarCount = 24
    public static let topAppCount = 7

    public struct Stat: Equatable, Sendable {
        public var label: String
        public var value: String
        public var detail: String
        /// Longer text for a tooltip, e.g. when and who caused a peak.
        public var help: String?
    }

    /// One chart column: read under write, as shares of the chart's scale, 0...1.
    public struct Bar: Equatable, Sendable {
        public var read: Double
        public var write: Double
    }

    public struct AppRow: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var bundlePath: String?
        /// e.g. "14 GB".
        public var value: String
        /// Bar length relative to the top writer, 0...1.
        public var share: Double
    }

    /// Toolbar subtitle, e.g. "Macintosh HD · APFS · 1 TB SSD".
    public var subtitle: String
    /// e.g. "312".
    public var free: String
    /// e.g. "GB free of 994 GB".
    public var freeCaption: String
    /// Used share of the capacity, for the usage bar; nil until read.
    public var usedShare: Double?
    public var read: Stat
    public var write: Stat
    /// "Written Today", with SSD health as its detail.
    public var writtenToday: Stat
    /// Present once the background scan has finished.
    public var storage: StorageBreakdown?
    /// Why `storage` is missing, e.g. "Scanning storage…".
    public var storageStatus: String?
    public var range: TimeRange
    /// `historyBarCount` bars over `range`, oldest first; nil where there's no data.
    public var history: [Bar?]
    /// Top, middle, and bottom of the chart's scale, e.g. ["2 GB/s", "1 GB/s", "0"].
    public var yAxis: [String]
    /// Evenly spaced from the start of the range; the last is "Now".
    public var xAxis: [String]
    /// Bytes each app wrote since local midnight, most first.
    public var writesToday: [AppRow]
}

extension DiskDetail {
    @MainActor
    static func make(
        snapshot: Snapshot?, history: MetricsHistory, range: TimeRange, calendar: Calendar = .current
    ) -> DiskDetail {
        let disk = snapshot?.disk.value
        let now = snapshot?.timestamp
        let today = DiskToday(disk: disk, history: history, now: now, calendar: calendar, topAppCount: topAppCount)
        let chart = DiskChart(history: history, range: range, endingAt: now, count: historyBarCount)
        let storage = disk.map(StorageBreakdown.make)

        return DiskDetail(
            subtitle: disk.map { subtitle(for: $0.volume) } ?? Format.placeholder,
            free: disk.map { DiskFormat.parts(Double($0.volume.free)).number } ?? Format.placeholder,
            freeCaption: disk.map { "\(DiskFormat.parts(Double($0.volume.free)).unit) \(freeCaption(for: $0.volume))" }
                ?? "free",
            usedShare: disk.map(\.volume).map(usedShare),
            read: today.read,
            write: today.write,
            writtenToday: today.written,
            storage: storage?.value,
            storageStatus: DiskToday.storageStatus(storage ?? .unavailable(.warmingUp)),
            range: range,
            history: chart.bars,
            yAxis: chart.yAxis,
            xAxis: CPUDetail.xAxis(range: range, endingAt: now, timeZone: calendar.timeZone),
            writesToday: today.writers
        )
    }

    /// e.g. "Macintosh HD · APFS · 1 TB SSD".
    public static func subtitle(for volume: DiskVolume) -> String {
        let size = DiskFormat.driveSize(volume.driveSize ?? volume.capacity)
        return "\(volume.name) · \(volume.format) · \(size)\(volume.isSolidState ? " SSD" : "")"
    }

    /// e.g. "free of 994 GB".
    static func freeCaption(for volume: DiskVolume) -> String {
        "free of \(DiskFormat.bytes(volume.capacity))"
    }

    static func usedShare(_ volume: DiskVolume) -> Double {
        volume.capacity > 0 ? Double(volume.capacity - min(volume.free, volume.capacity)) / Double(volume.capacity) : 0
    }
}

/// Today's figures, shared by the popover and the window. "Today" starts at local midnight.
@MainActor
struct DiskToday {
    let read: DiskDetail.Stat
    let write: DiskDetail.Stat
    let written: DiskDetail.Stat
    /// The apps that wrote the most since midnight, including ones that have since quit.
    let writers: [DiskDetail.AppRow]

    init(disk: DiskReading?, history: MetricsHistory, now: Date?, calendar: Calendar, topAppCount: Int) {
        let midnight = now.map(calendar.startOfDay)
        let io = disk?.io.value
        /// A rate with today's peak, e.g. "48 MB/s" and "Peak 1.9 GB/s today".
        func rate(_ label: String, _ series: SeriesKey, _ value: (DiskIO) -> Double) -> DiskDetail.Stat {
            let current = io.map { DiskFormat.rate(value($0)) } ?? Format.placeholder
            guard let now, let midnight, let peak = try? history.peak(series, from: midnight, to: now) else {
                return DiskDetail.Stat(label: label, value: current, detail: "No data today")
            }
            let time = Format.time(peak.time, within: .twentyFourHours, timeZone: calendar.timeZone)
            return DiskDetail.Stat(label: label, value: current, detail: "Peak \(DiskFormat.rate(peak.value)) today",
                                   help: "Peak at \(time)" + (peak.contributor.map { " · \($0)" } ?? ""))
        }
        read = rate("Read", .diskRead, \.readPerSecond)
        write = rate("Write", .diskWrite, \.writePerSecond)
        let total = now.flatMap { now in midnight.flatMap { try? history.sum(.diskWritten, from: $0, to: now) } }
        let health = Self.health(disk?.health ?? .unavailable(.warmingUp))
        written = DiskDetail.Stat(label: "Written Today", value: total.map(DiskFormat.bytes) ?? Format.placeholder,
                                  detail: health, help: health)
        if let now, let midnight,
           let sums = try? history.sums(prefix: SeriesKey.diskWrittenByAppPrefix, from: midnight, to: now) {
            writers = Self.topWriters(sums, count: topAppCount)
        } else {
            writers = []
        }
    }

    /// Per-app sums keyed "disk.written.app:<app id>" as rows, most first.
    private static func topWriters(_ sums: [SeriesKey: Double], count: Int) -> [DiskDetail.AppRow] {
        let prefixLength = SeriesKey.diskWrittenByAppPrefix.count
        let apps: [(id: String, bytes: Double)] = sums.compactMap { key, bytes in
            bytes > 0 ? (String(key.rawValue.dropFirst(prefixLength)), bytes) : nil
        }
        let top = apps.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.id < $1.id }.prefix(count)
        let most = top.first?.bytes ?? 1
        return top.map { app in
            let bundle = app.id.hasSuffix(".app") ? app.id : nil
            let name = (app.id as NSString).lastPathComponent
            return DiskDetail.AppRow(
                id: app.id, name: bundle != nil ? String(name.dropLast(".app".count)) : name, bundlePath: bundle,
                value: DiskFormat.bytes(app.bytes), share: app.bytes / most
            )
        }
    }

    /// e.g. "SSD health 98% · 54 TB lifetime", or why it can't be read.
    static func health(_ health: Reading<SSDHealth>) -> String {
        switch health {
        case .value(let health):
            "SSD health \(Format.percent(health.remaining)) · \(DiskFormat.bytes(health.lifetimeBytesWritten)) lifetime"
        case .unavailable(.warmingUp): "SSD health \(Format.placeholder)"
        case .unavailable(.unsupported): "SSD health unavailable: the drive doesn't report it"
        case .unavailable(.failed(let reason)): "SSD health unavailable: \(reason)"
        }
    }

    static func storageStatus(_ storage: Reading<StorageBreakdown>) -> String? {
        switch storage {
        case .value: nil
        case .unavailable(.warmingUp): "Scanning storage…"
        case .unavailable(.unsupported): "Storage breakdown isn't available for this volume."
        case .unavailable(.failed(let reason)): "Storage breakdown unavailable: \(reason)"
        }
    }
}

/// Read and write history as stacked bars on a rounded scale.
@MainActor
struct DiskChart {
    let bars: [DiskDetail.Bar?]
    let yAxis: [String]

    init(history: MetricsHistory, range: TimeRange, endingAt now: Date?, count: Int) {
        guard let now else {
            bars = Array(repeating: nil, count: count)
            yAxis = Self.axis(scale: Self.scale(for: 0))
            return
        }
        func resampled(_ series: SeriesKey) -> [Double?] {
            let points = (try? history.summary(series, over: range, endingAt: now).points) ?? []
            return Resample.bars(points, endingAt: now, window: range.duration, count: count)
        }
        let pairs = zip(resampled(.diskRead), resampled(.diskWrite)).map { read, write -> (Double, Double)? in
            guard let read, let write else { return nil }
            return (read, write)
        }
        let scale = Self.scale(for: pairs.compactMap { $0.map { $0.0 + $0.1 } }.max() ?? 0)
        bars = pairs.map { $0.map { DiskDetail.Bar(read: $0.0 / scale, write: $0.1 / scale) } }
        yAxis = Self.axis(scale: scale)
    }

    /// The smallest 1, 2, or 5 × 10ⁿ bytes/s at or above the busiest bar, at least 1 MB/s.
    static func scale(for peak: Double) -> Double {
        var scale = 1_000_000.0
        let steps = [2.0, 2.5, 2]  // 1 → 2 → 5 → 10 …
        var index = 0
        while scale < peak {
            scale *= steps[index % steps.count]
            index += 1
        }
        return scale
    }

    private static func axis(scale: Double) -> [String] {
        [DiskFormat.rate(scale), DiskFormat.rate(scale / 2), "0"]
    }
}
