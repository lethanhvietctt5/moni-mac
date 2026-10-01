import Foundation

/// Everything the main window's Projects tab shows.
public struct ProjectDetail: Equatable, Sendable {
    public enum Level: Equatable, Sendable {
        /// Active within `ProjectActivity.idleAfter`.
        case active
        case idle
        /// Idle for `ProjectActivity.forgottenAfter` or more: highlighted, and it raises the banner.
        case forgotten
        /// Asked to stop; waiting for the next reading.
        case stopping
    }

    public struct Server: Equatable, Sendable, Identifiable {
        public var id: DevServer.ID
        /// e.g. "next dev".
        public var command: String
        public var kind: ServerKind
        public var ports: [UInt16]
        /// Tooltip for the port chip, e.g. "Open http://localhost:3000 · also listening on 3001".
        public var portHelp: String?
        /// e.g. "3h 12m".
        public var uptime: String
        /// e.g. "742 MB".
        public var memory: String
        /// e.g. "Active · now", "Idle 26 min", "Idle 4 days".
        public var activity: String
        public var level: Level
    }

    public struct Project: Equatable, Sendable, Identifiable {
        public var id: String
        public var name: String
        /// e.g. "~/Developer/acme-web"; nil for containers outside a project.
        public var path: String?
        /// e.g. "main · 3 servers".
        public var summary: String
        /// Total memory, e.g. "1.3 GB".
        public var memory: String
        /// Every server is forgotten, so the whole project is.
        public var isForgotten: Bool
        public var servers: [Server]
    }

    /// Servers idle for days, with "Stop Idle Servers" and "Ignore".
    public struct Banner: Equatable, Sendable {
        /// e.g. "2 servers have been idle for days".
        public var title: String
        /// e.g. "old-landing has had no requests since Sep 27 and is holding 1.1 GB of memory and ports 5173, 4000."
        public var message: String
        public var projectIDs: [String]
        public var serverIDs: [DevServer.ID]
    }

    /// Toolbar subtitle, e.g. "8 dev servers across 3 projects · 2.9 GB"; nil before the first reading.
    public var subtitle: String?
    public var banner: Banner?
    public var projects: [Project]
    /// Shown with no servers, e.g. "No dev servers running"; nil when there are some.
    public var emptyMessage: String?
    /// e.g. "Docker isn't running." Docker being off isn't an error, just a note.
    public var dockerNote: String?
}

extension ProjectDetail {
    static func make(
        servers: [DevServer]?, docker: DockerStatus, lastActive: [DevServer.ID: Date], ignored: Set<String>,
        stopping: Set<DevServer.ID>, now: Date, home: String, timeZone: TimeZone = .current
    ) -> ProjectDetail {
        guard let servers else {
            return ProjectDetail(subtitle: nil, banner: nil, projects: [], emptyMessage: "Looking for dev servers…")
        }
        func idleFor(_ server: DevServer) -> TimeInterval {
            now.timeIntervalSince(lastActive[server.id] ?? now)
        }
        func level(_ server: DevServer) -> Level {
            if stopping.contains(server.id) { return .stopping }
            let idle = idleFor(server)
            return idle >= ProjectActivity.forgottenAfter ? .forgotten : idle >= ProjectActivity.idleAfter ? .idle : .active
        }

        let groups = Dictionary(grouping: servers, by: \.projectID)
        let projects = groups.map { id, servers in
            let sorted = order(servers, now: now)
            let root = servers.first?.project
            let branch = root?.branch.map { "\($0) · " } ?? ""
            return (
                recent: servers.compactMap { lastActive[$0.id] }.max() ?? .distantPast,
                project: Project(
                    id: id,
                    name: root.map { ($0.path as NSString).lastPathComponent } ?? "Containers",
                    path: root.map { abbreviate($0.path, home: home) },
                    summary: branch + plural(servers.count, "server"),
                    memory: memoryText(servers.compactMap(\.memory)),
                    isForgotten: servers.allSatisfy { level($0) == .forgotten },
                    servers: sorted.map { server in
                        let level = level(server)
                        return Server(
                            id: server.id, command: server.command, kind: server.kind, ports: server.ports,
                            portHelp: portHelp(server.ports),
                            uptime: server.startedAt.map { Format.uptime(now.timeIntervalSince($0)) } ?? Format.placeholder,
                            memory: server.memory.map(Format.memorySize) ?? Format.placeholder,
                            activity: level == .stopping ? "Stopping…" : activity(idleFor: idleFor(server)),
                            level: level
                        )
                    }
                )
            )
        }
        // Most recently active first; containers outside a project last.
        .sorted { lhs, rhs in
            let (left, right) = (lhs.project.path == nil, rhs.project.path == nil)
            if left != right { return right }
            if lhs.recent != rhs.recent { return lhs.recent > rhs.recent }
            return lhs.project.name < rhs.project.name
        }
        .map(\.project)

        let forgotten = servers.filter { level($0) == .forgotten && !ignored.contains($0.projectID) }
        let dockerNote: String? = switch docker {
        case .notRunning: "Docker isn't running."
        case .failed(let reason): "Couldn't read Docker containers: \(reason)"
        case .notInstalled, .running: nil
        }
        return ProjectDetail(
            subtitle: subtitle(servers: servers, projects: groups.count),
            banner: banner(forgotten, projects: projects, lastActive: lastActive, timeZone: timeZone),
            projects: projects,
            emptyMessage: servers.isEmpty ? "No dev servers running" : nil,
            dockerNote: dockerNote
        )
    }

    /// Listening servers before watchers, then containers; oldest first within each.
    private static func order(_ servers: [DevServer], now: Date) -> [DevServer] {
        func rank(_ server: DevServer) -> Int {
            if case .container = server.target { return 2 }
            return server.isWatcher ? 1 : 0
        }
        return servers.sorted { lhs, rhs in
            if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
            return (lhs.startedAt ?? now, lhs.id) < (rhs.startedAt ?? now, rhs.id)
        }
    }

    /// e.g. "8 dev servers across 3 projects · 2.9 GB".
    static func subtitle(servers: [DevServer], projects: Int) -> String {
        guard !servers.isEmpty else { return "No dev servers running" }
        let across = projects == 1 ? "in 1 project" : "across \(projects) projects"
        let memory = servers.compactMap(\.memory)
        return "\(plural(servers.count, "dev server")) \(across)" + (memory.isEmpty ? "" : " · \(memoryText(memory))")
    }

    private static func banner(
        _ forgotten: [DevServer], projects: [Project], lastActive: [DevServer.ID: Date], timeZone: TimeZone
    ) -> Banner? {
        guard !forgotten.isEmpty else { return nil }
        let ids = Set(forgotten.map(\.projectID))
        let names = projects.filter { ids.contains($0.id) }.map(\.name)
        let one = names.count == 1
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d"
        // The latest of their last-active times: none of them has had a request since.
        let since = forgotten.compactMap { lastActive[$0.id] }.max().map(formatter.string(from:))
        var holding: [String] = []
        let memory = forgotten.compactMap(\.memory)
        if !memory.isEmpty { holding.append("\(memoryText(memory)) of memory") }
        let ports = forgotten.flatMap(\.ports)
        if !ports.isEmpty {
            holding.append((ports.count == 1 ? "port " : "ports ") + ports.map(String.init).joined(separator: ", "))
        }
        var message = "\(list(names)) \(one ? "has" : "have") had no requests"
        if let since { message += " since \(since)" }
        if !holding.isEmpty { message += " and \(one ? "is" : "are") holding \(holding.joined(separator: " and "))" }
        return Banner(
            title: "\(plural(forgotten.count, "server")) \(forgotten.count == 1 ? "has" : "have") been idle for days",
            message: message + ".",
            projectIDs: projects.map(\.id).filter(ids.contains),
            serverIDs: forgotten.map(\.id)
        )
    }

    private static func portHelp(_ ports: [UInt16]) -> String? {
        guard let first = ports.first else { return nil }
        let open = "Open \(serverURL(port: first).absoluteString)"
        return ports.count == 1 ? open : open + " · also listening on " + ports.dropFirst().map(String.init).joined(separator: ", ")
    }

    /// Where a server's port is opened.
    static func serverURL(port: UInt16) -> URL {
        URL(string: "http://localhost:\(port)")!
    }

    /// "Active · now", "Active · 2 min", "Idle 26 min", "Idle 3 h", "Idle 4 days".
    static func activity(idleFor idle: TimeInterval) -> String {
        let minutes = Int(max(idle, 0) / 60)
        if idle < ProjectActivity.idleAfter { return minutes == 0 ? "Active · now" : "Active · \(minutes) min" }
        if minutes < 60 { return "Idle \(minutes) min" }
        if minutes < 1440 { return "Idle \(minutes / 60) h" }
        return "Idle \(plural(minutes / 1440, "day"))"
    }

    /// e.g. "1 server", "3 servers".
    private static func plural(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }

    private static func memoryText(_ sizes: [UInt64]) -> String {
        sizes.isEmpty ? Format.placeholder : Format.memorySize(sizes.reduce(0, +))
    }

    /// "a", "a and b", "a, b and c".
    private static func list(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    /// "/Users/me/Developer/x" → "~/Developer/x".
    static func abbreviate(_ path: String, home: String) -> String {
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

extension Monitor {
    /// The main window's Projects tab.
    public var projectDetail: ProjectDetail {
        ProjectDetail.make(
            servers: projectActivity.servers, docker: projectActivity.docker, lastActive: projectActivity.lastActive,
            ignored: projectActivity.ignoredProjects, stopping: Set(projectActivity.stopRequests.keys),
            now: latest?.timestamp ?? Date(), home: projectActivity.home
        )
    }

    /// The main window toolbar subtitle for the Projects tab, e.g. "8 dev servers across 3 projects · 2.9 GB".
    public var projectsSubtitle: String? {
        projectActivity.servers.map { servers in
            ProjectDetail.subtitle(servers: servers, projects: Set(servers.map(\.projectID)).count)
        }
    }

    /// Feeds the latest reading to the activity tracker. Called on every tick.
    func observeProjects(_ snapshot: Snapshot) {
        projectActivity.observe(snapshot.devServers, now: snapshot.timestamp)
    }

    // MARK: Intents

    public func stopServer(id: DevServer.ID) {
        stop(projectActivity.servers?.filter { $0.id == id } ?? [])
    }

    /// Stops every server in the project ("Stop All").
    public func stopProject(id: String) {
        stop(projectActivity.servers?.filter { $0.projectID == id } ?? [])
    }

    /// Stops the servers the banner names.
    public func stopIdleServers() {
        let ids = Set(projectDetail.banner?.serverIDs ?? [])
        stop(projectActivity.servers?.filter { ids.contains($0.id) } ?? [])
    }

    /// Dismisses the banner until one of its projects is active again.
    public func ignoreIdleServers() {
        guard let banner = projectDetail.banner else { return }
        projectActivity.ignore(projects: banner.projectIDs)
    }

    /// Opens the server's port in the browser.
    public func openServer(port: UInt16) {
        actions.openURL(ProjectDetail.serverURL(port: port))
    }

    /// Reveals the project's folder in Finder.
    public func revealProject(id: String) {
        guard let path = projectActivity.servers?.first(where: { $0.projectID == id })?.project?.path else { return }
        actions.revealInFinder(path: path)
    }

    private func stop(_ servers: [DevServer]) {
        let stopping = projectActivity.stopRequests
        let servers = servers.filter { stopping[$0.id] == nil }
        for server in servers {
            switch server.target {
            case .process(let pid, let startedAt): actions.stopProcess(pid: pid, startedAt: startedAt)
            case .container(let id): actions.stopContainer(id: id)
            }
        }
        projectActivity.noteStopRequested(servers.map(\.id), at: latest?.timestamp ?? Date())
    }
}
