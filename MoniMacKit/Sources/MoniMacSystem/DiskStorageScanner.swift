import Foundation
import MoniMacCore

/// Sizes the folders behind the storage breakdown's Applications and Developer categories.
/// See `StorageBreakdown` for what each category covers.
///
/// It only reads folders that never trigger a privacy prompt: not Documents, Desktop, Downloads,
/// or other apps' containers. Sizes are allocated bytes (`totalFileAllocatedSize`), so sparse
/// and compressed files count what they actually take. Mounted volumes inside a folder (e.g.
/// simulator runtimes) and symbolic links aren't followed. Work is capped at `maxEntries`.
struct DiskStorageScanner: Sendable {
    struct Location: Sendable {
        var name: String
        var path: String
        /// Subfolders counted elsewhere, e.g. simulators inside ~/Library/Developer.
        var excluding: [String] = []
    }

    var applications: [String]
    var developer: [Location]
    var maxEntries: Int

    init(home: String = NSHomeDirectory(), maxEntries: Int = 5_000_000) {
        applications = ["/Applications", "\(home)/Applications"]
        developer = [
            Location(name: "Xcode", path: "\(home)/Library/Developer",
                     excluding: ["\(home)/Library/Developer/CoreSimulator"]),
            Location(name: "Simulators", path: "\(home)/Library/Developer/CoreSimulator"),
            Location(name: "Developer tools", path: "/Library/Developer"),
            Location(name: "Homebrew", path: "/opt/homebrew"),
            Location(name: "Homebrew", path: "/usr/local/Homebrew"),
            Location(name: "npm", path: "\(home)/.npm"),
            Location(name: "Cargo", path: "\(home)/.cargo"),
            Location(name: "Rust", path: "\(home)/.rustup"),
            Location(name: "Gradle", path: "\(home)/.gradle"),
            Location(name: "Maven", path: "\(home)/.m2"),
            Location(name: "Go", path: "\(home)/go"),
            Location(name: "CocoaPods", path: "\(home)/.cocoapods"),
            Location(name: "Colima", path: "\(home)/.colima"),
        ]
        self.maxEntries = maxEntries
    }

    /// The scan and how many entries it visited.
    func scan() -> (StorageScan, entries: Int) {
        var budget = maxEntries
        var applicationBytes: UInt64 = 0
        var appCount = 0
        for path in applications {
            let size = Self.size(of: path, budget: &budget)
            applicationBytes += size.bytes
            appCount += size.apps
        }
        var developerBytes: [String: UInt64] = [:]
        var order: [String] = []
        for location in developer {
            let size = Self.size(of: location.path, excluding: Set(location.excluding), budget: &budget)
            if developerBytes[location.name] == nil { order.append(location.name) }
            developerBytes[location.name, default: 0] += size.bytes
        }
        let scan = StorageScan(
            applications: applicationBytes, appCount: appCount,
            developer: order.map { StorageScan.Item(name: $0, bytes: developerBytes[$0]!) },
            isPartial: budget <= 0
        )
        return (scan, maxEntries - max(budget, 0))
    }

    /// Allocated bytes under `path`, and the `.app` bundles in it or one folder down. A missing
    /// folder is empty. Stops when `budget` (entries left to visit) runs out.
    static func size(of path: String, excluding: Set<String> = [], budget: inout Int) -> (bytes: UInt64, apps: Int) {
        // Enumerated paths are canonical (e.g. /private/var/… for /var/…), so compare canonical ones.
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let excluding = Set(excluding.map(canonical))
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey, .isVolumeKey]
        guard budget > 0, let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return (0, 0) }
        var bytes: UInt64 = 0
        var apps = 0
        for case let url as URL in enumerator {
            budget -= 1
            if budget <= 0 { break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true {
                if values.isVolume == true || excluding.contains(url.path) {
                    enumerator.skipDescendants()
                } else if url.pathExtension == "app", enumerator.level <= 2,
                          url.deletingLastPathComponent().pathExtension != "app" {
                    apps += 1
                }
            }
            bytes += UInt64(values.totalFileAllocatedSize ?? 0)
        }
        return (bytes, apps)
    }

    /// The path with symbolic links resolved, as `realpath` gives it (unlike `resolvingSymlinksInPath`,
    /// which drops /private). Unchanged if it doesn't exist.
    private static func canonical(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
