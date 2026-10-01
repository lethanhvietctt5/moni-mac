/// Processes rolled up into the app they belong to.
public struct AppUsage: Equatable, Sendable, Identifiable {
    /// The app bundle path, or the executable path (or name) for processes outside any bundle.
    public var id: String
    public var name: String
    /// The `.app` bundle, when the group is an app.
    public var bundlePath: String?
    public var processCount: Int
    /// Summed CPU in cores.
    public var cpu: Double
    /// The process to ask to quit. Nil unless the group is a running regular app.
    public var quitPID: Int32?
    /// Sums over the group's processes; nil when no process reported the value.
    public var memory: UInt64?
    public var gpu: Double?
    public var network: Double?
    public var diskReadPerSecond: Double?
    public var diskWritePerSecond: Double?
    public var power: Double?

    public var canQuit: Bool { quitPID != nil }
}

/// Rolls helper processes up into the app responsible for them.
public enum AppGrouping {
    /// Groups processes into apps, busiest first.
    ///
    /// A process belongs to the app bundle of its responsible process when macOS reports one,
    /// otherwise to the outermost `.app` bundle in its own path (so Chrome's nested helper apps
    /// count toward Chrome). Processes outside any bundle are grouped by executable.
    public static func apps(from processes: [ProcessSample]) -> [AppUsage] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var groups: [String: AppUsage] = [:]
        var order: [String] = []

        for process in processes {
            let responsible = process.responsiblePID.flatMap { byPID[$0] }
            let bundle = responsible.flatMap { outermostAppBundle(in: $0.path) } ?? outermostAppBundle(in: process.path)
            let id = bundle ?? process.path ?? process.name
            let name = bundle.map(appName(forBundle:)) ?? process.path.map(lastComponent) ?? process.name

            if groups[id] == nil {
                groups[id] = AppUsage(id: id, name: name, bundlePath: bundle, processCount: 0, cpu: 0)
                order.append(id)
            }
            groups[id]!.processCount += 1
            groups[id]!.cpu += process.cpu
            groups[id]!.add(process)
            if process.isRegularApp, let bundle, outermostAppBundle(in: process.path) == bundle {
                groups[id]!.quitPID = process.pid
            }
        }
        // Stable for equal CPU: first seen first.
        return order.enumerated()
            .map { (index: $0.offset, app: groups[$0.element]!) }
            .sorted { $0.app.cpu != $1.app.cpu ? $0.app.cpu > $1.app.cpu : $0.index < $1.index }
            .map(\.app)
    }

    /// `/Applications/Google Chrome.app/Contents/.../Helper.app/Contents/MacOS/Helper` → `/Applications/Google Chrome.app`.
    static func outermostAppBundle(in path: String?) -> String? {
        guard let path, let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    private static func appName(forBundle bundle: String) -> String {
        String(lastComponent(bundle).dropLast(".app".count))
    }

    private static func lastComponent(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

private extension AppUsage {
    mutating func add(_ process: ProcessSample) {
        func sum<T: AdditiveArithmetic>(_ total: T?, _ value: T?) -> T? {
            guard let value else { return total }
            return (total ?? .zero) + value
        }
        memory = sum(memory, process.memory)
        gpu = sum(gpu, process.gpu)
        network = sum(network, process.network)
        diskReadPerSecond = sum(diskReadPerSecond, process.diskReadPerSecond)
        diskWritePerSecond = sum(diskWritePerSecond, process.diskWritePerSecond)
        power = sum(power, process.power)
    }
}
