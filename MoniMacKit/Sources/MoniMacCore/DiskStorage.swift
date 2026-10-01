import Foundation

/// What fills the startup disk, as six segments that add up to its capacity.
///
/// - **Applications:** /Applications and ~/Applications.
/// - **Developer:** Xcode data and simulators (~/Library/Developer), command line tools and
///   simulator runtimes (/Library/Developer), Homebrew, and toolchains and package caches in the
///   home folder (npm, Cargo, rustup, Gradle, Maven, Go, CocoaPods, Colima).
/// - **Documents:** everything else on the Data volume: your files, photos, mail, and app data.
///   It's what remains after the other categories, so protected folders (Documents, Desktop,
///   Downloads, other apps' containers) are never read and no privacy prompt appears. Docker
///   Desktop's disk image lives in its container, so it counts here.
/// - **macOS:** the System, Preboot, Recovery, VM (swap), and Update volumes.
/// - **Purgeable:** caches and local snapshots macOS frees when space runs low.
/// - **Free:** available now.
public struct StorageBreakdown: Equatable, Sendable {
    public enum Category: String, CaseIterable, Sendable {
        case applications = "Applications"
        case developer = "Developer"
        case documents = "Documents"
        case macOS = "macOS"
        case purgeable = "Purgeable"
        case free = "Free"
    }

    public struct Segment: Equatable, Sendable {
        public var category: Category
        public var bytes: UInt64
        /// Share of the capacity, 0...1.
        public var share: Double
        /// e.g. "182 GB", or "≥ 182 GB" when the scan was capped.
        public var value: String
        /// e.g. "214 apps", "Xcode, Simulators".
        public var hint: String
    }

    /// In `Category.allCases` order.
    public var segments: [Segment]

    /// The used segments the bar draws, left to right; Free fills the rest.
    public var usedSegments: [Segment] {
        segments.filter { $0.category != .free && $0.bytes > 0 }
    }
}

extension StorageBreakdown {
    /// Combines the live free space with the slower space reading and the background scan.
    /// Missing until both have been read; their reason is passed on.
    static func make(_ disk: DiskReading) -> Reading<StorageBreakdown> {
        let space: VolumeSpace, scan: StorageScan
        switch (disk.space, disk.scan) {
        case (.value(let s), .value(let c)): (space, scan) = (s, c)
        case (.unavailable(let reason), _), (_, .unavailable(let reason)): return .unavailable(reason)
        }
        let capacity = disk.volume.capacity
        let free = min(disk.volume.free, capacity)
        let developer = scan.developer.reduce(0) { $0 + $1.bytes }
        let known = [scan.applications, developer, space.system, space.purgeable].reduce(0, +)
        // The remainder; clamped because the inputs were read at different times.
        let documents = capacity - free > known ? capacity - free - known : 0
        let topDeveloper = scan.developer.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }.prefix(2).map(\.name)

        func segment(_ category: Category, _ bytes: UInt64, _ hint: String, scanned: Bool = false) -> Segment {
            let value = DiskFormat.bytes(bytes)
            return Segment(
                category: category, bytes: bytes, share: capacity > 0 ? Double(bytes) / Double(capacity) : 0,
                value: scanned && scan.isPartial ? "≥ \(value)" : value, hint: hint
            )
        }
        return .value(StorageBreakdown(segments: [
            segment(.applications, scan.applications, scan.appCount == 1 ? "1 app" : "\(scan.appCount) apps", scanned: true),
            segment(.developer, developer, topDeveloper.isEmpty ? "None found" : topDeveloper.joined(separator: ", "),
                    scanned: true),
            segment(.documents, documents, "Your files & app data"),
            segment(.macOS, space.system, "System volumes"),
            segment(.purgeable, space.purgeable, "Caches, snapshots"),
            segment(.free, free, "Available now"),
        ]))
    }
}
