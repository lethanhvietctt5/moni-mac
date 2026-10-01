import Foundation
import Observation

/// Tracks when each dev server was last active, across readings and relaunches.
///
/// **Idle** means no new inbound connections on any of the server's ports *and* CPU under
/// `cpuFloor` since the previous reading; watchers have no port, so CPU alone decides. A server is
/// last active at the most recent reading where either was true. A server MoniMac sees for the first
/// time counts as active then: how long it sat unused before is unknown, and guessing would raise
/// false alarms on a fresh install.
///
/// Last-active times and ignored banners persist in Preferences, so "Idle 4 days" survives relaunch.
@MainActor
@Observable
public final class ProjectActivity {
    /// CPU, in cores, at or above which a server counts as busy: 3% of one core.
    nonisolated public static let cpuFloor = 0.03
    /// A server shows as idle once it has been inactive this long.
    nonisolated public static let idleAfter: TimeInterval = 5 * 60
    /// Servers idle this long are highlighted and raise the banner.
    nonisolated public static let forgottenAfter: TimeInterval = 2 * 86400
    /// A stop that hasn't taken effect after this long stops showing as "Stopping…".
    nonisolated static let stopTimeout: TimeInterval = 30
    /// Last-active times are saved when one moves by at least this much, not on every reading.
    nonisolated static let persistInterval: TimeInterval = 60

    /// Servers in the latest reading; nil before the first one.
    public private(set) var servers: [DevServer]?
    public private(set) var docker: DockerStatus = .notInstalled
    /// The user's home folder, from the reading.
    public private(set) var home = ""
    public private(set) var lastActive: [DevServer.ID: Date]
    /// Projects whose idle banner was dismissed, until they're active again.
    public private(set) var ignoredProjects: Set<String>
    /// Servers asked to stop, with when, so rows can show it until the next reading drops them.
    public private(set) var stopRequests: [DevServer.ID: Date] = [:]

    private struct Baseline {
        var cpuTime: TimeInterval?
        var connections: Set<String>
        var at: Date
    }

    @ObservationIgnored private var baselines: [DevServer.ID: Baseline] = [:]
    @ObservationIgnored private var lastSampledAt: Date?
    @ObservationIgnored private var persisted: [DevServer.ID: Date]
    @ObservationIgnored private let preferences: Preferences

    public init(preferences: Preferences) {
        self.preferences = preferences
        let saved = preferences.projectsLastActive
        lastActive = saved
        persisted = saved
        ignoredProjects = preferences.projectsIgnored
    }

    /// Takes in a reading. The same reading repeats on ticks between background reads; it's
    /// processed once.
    public func observe(_ reading: Reading<DevServerReading>, now: Date) {
        expireStopRequests(now: now)
        guard let reading = reading.value, reading.sampledAt != lastSampledAt else { return }
        lastSampledAt = reading.sampledAt
        var servers = ProjectCatalog.servers(in: reading)
        // A failed Docker read says nothing about the containers: keep the last ones, so their idle
        // times and Ignore aren't lost to one bad read.
        if case .failed = reading.docker {
            servers += (self.servers ?? []).filter { if case .container = $0.target { true } else { false } }
        }
        let time = reading.sampledAt
        var nextActive: [DevServer.ID: Date] = [:]
        var nextBaselines: [DevServer.ID: Baseline] = [:]
        var ignored = ignoredProjects
        for server in servers {
            var active = false
            if let known = lastActive[server.id] {
                nextActive[server.id] = known
            } else {
                nextActive[server.id] = time
                active = true
            }
            if let before = baselines[server.id], time > before.at {
                let newConnection = !server.connections.subtracting(before.connections).isEmpty
                var busy = false
                if let now = server.cpuTime, let then = before.cpuTime {
                    busy = (now - then) / time.timeIntervalSince(before.at) >= Self.cpuFloor
                }
                if busy || (!server.isWatcher && newConnection) {
                    nextActive[server.id] = time
                    active = true
                }
            }
            if active { ignored.remove(server.projectID) }
            nextBaselines[server.id] = Baseline(cpuTime: server.cpuTime, connections: server.connections, at: time)
        }
        // Forget projects that are gone: if they come back, their servers are new, and so active.
        ignored.formIntersection(servers.map(\.projectID))

        self.servers = servers
        docker = reading.docker
        home = reading.home
        baselines = nextBaselines
        lastActive = nextActive
        stopRequests = stopRequests.filter { nextActive[$0.key] != nil }
        if ignored != ignoredProjects {
            ignoredProjects = ignored
            preferences.projectsIgnored = ignored
        }
        persistIfMoved()
    }

    /// Hides the banner for these projects until one of their servers is active again.
    public func ignore(projects: some Sequence<String>) {
        ignoredProjects.formUnion(projects)
        preferences.projectsIgnored = ignoredProjects
    }

    func noteStopRequested(_ ids: some Sequence<DevServer.ID>, at time: Date) {
        for id in ids { stopRequests[id] = time }
    }

    private func expireStopRequests(now: Date) {
        let live = stopRequests.filter { now.timeIntervalSince($0.value) < Self.stopTimeout }
        if live.count != stopRequests.count { stopRequests = live }
    }

    private func persistIfMoved() {
        let moved = Set(lastActive.keys) != Set(persisted.keys) || lastActive.contains { id, time in
            persisted[id].map { abs(time.timeIntervalSince($0)) >= Self.persistInterval } ?? true
        }
        guard moved else { return }
        preferences.projectsLastActive = lastActive
        persisted = lastActive
    }
}

extension Preferences {
    /// When each dev server was last active, keyed by `DevServer.id`.
    var projectsLastActive: [String: Date] {
        get {
            (defaults.dictionary(forKey: "projects.lastActive") as? [String: Double] ?? [:])
                .mapValues { Date(timeIntervalSince1970: $0) }
        }
        set { defaults.set(newValue.mapValues(\.timeIntervalSince1970), forKey: "projects.lastActive") }
    }

    /// Project roots whose idle-servers banner was dismissed with Ignore.
    var projectsIgnored: Set<String> {
        get { Set(defaults.stringArray(forKey: "projects.ignored") ?? []) }
        set { defaults.set(newValue.sorted(), forKey: "projects.ignored") }
    }
}
