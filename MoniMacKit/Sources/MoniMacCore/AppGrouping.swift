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
    /// Summed over the group's processes.
    public var resources = ResourceUse()
    /// What sort of software the group is. See `AppKind`.
    public var kind = AppKind.agent

    public var canQuit: Bool { quitPID != nil }
}

/// What sort of software an app group is. Every group has a kind; the Overview Processes tile
/// counts only groups with an `.app` bundle, leaving bare daemons to its process count.
public enum AppKind: CaseIterable, Sendable {
    /// A regular app: at least one of its processes has a Dock presence (Safari, Xcode, Finder).
    case app
    /// The user's own background software: menu bar apps, launch agents, and helpers outside any
    /// regular app, e.g. a menu bar utility in /Applications or a tool in ~/Library or /opt/homebrew.
    case agent
    /// The operating system: groups whose processes all belong to other users (root daemons,
    /// WindowServer, kernel_task), and the user's own processes that ship with macOS, i.e. whose
    /// bundle or executable lives under /System, /usr (but not /usr/local), /bin, /sbin, or /Library/Apple.
    case system
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
        var hasRegularApp: Set<String> = []
        var hasOwnProcess: Set<String> = []

        for process in processes {
            let (id, name, bundle) = owner(of: process, byPID: byPID)

            if groups[id] == nil {
                groups[id] = AppUsage(id: id, name: name, bundlePath: bundle, processCount: 0, cpu: 0)
                order.append(id)
            }
            groups[id]!.processCount += 1
            groups[id]!.cpu += process.cpu
            groups[id]!.resources = groups[id]!.resources + process.resources
            if process.isRegularApp, let bundle, outermostAppBundle(in: process.path) == bundle {
                groups[id]!.quitPID = process.pid
            }
            if process.isRegularApp { hasRegularApp.insert(id) }
            if !process.isOtherUser { hasOwnProcess.insert(id) }
        }
        for id in order {
            groups[id]!.kind = if hasRegularApp.contains(id) {
                .app
            } else if !hasOwnProcess.contains(id) || isSystemLocation(groups[id]!.bundlePath ?? id) {
                .system
            } else {
                .agent
            }
        }
        // Stable for equal CPU: first seen first.
        return order.enumerated()
            .map { (index: $0.offset, app: groups[$0.element]!) }
            .sorted { $0.app.cpu != $1.app.cpu ? $0.app.cpu > $1.app.cpu : $0.index < $1.index }
            .map(\.app)
    }

    /// The app a process belongs to: its id, display name, and bundle (if any).
    static func owner(of process: ProcessSample, byPID: [Int32: ProcessSample]) -> (id: String, name: String, bundle: String?) {
        let responsible = process.responsiblePID.flatMap { byPID[$0] }
        let bundle = responsible.flatMap { outermostAppBundle(in: $0.path) } ?? outermostAppBundle(in: process.path)
        let id = bundle ?? process.path ?? process.name
        let name = bundle.map(appName(forBundle:)) ?? process.path.map(lastComponent) ?? process.name
        return (id, name, bundle)
    }

    /// The name of the app owning the busiest process by `measure`, without grouping every process.
    /// Cheap enough to run every tick, e.g. to record who caused a peak.
    public static func busiestApp(in processes: [ProcessSample], by measure: (ProcessSample) -> Double?) -> String? {
        guard let busiest = processes.max(by: { (measure($0) ?? 0) < (measure($1) ?? 0) }),
              (measure(busiest) ?? 0) > 0 else { return nil }
        let responsible = busiest.responsiblePID.flatMap { pid in processes.first { $0.pid == pid } }
        return owner(of: busiest, byPID: responsible.map { [$0.pid: $0] } ?? [:]).name
    }

    /// Where macOS keeps its own software. Groups without a readable path have their name as id, which
    /// never starts with "/", so an own-user process with an unreadable path counts as an agent.
    /// /usr/local is where users install their own tools, so it isn't macOS.
    static func isSystemLocation(_ path: String) -> Bool {
        guard !path.hasPrefix("/usr/local/") else { return false }
        return ["/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/"].contains { path.hasPrefix($0) }
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

