import Foundation

/// What runs a server, for its icon.
public enum ServerRuntime: Equatable, Sendable {
    case node, python, ruby, docker, other
}

/// A server's detected type, e.g. Next.js on Node.
public struct ServerKind: Equatable, Sendable {
    /// e.g. "Next.js", "Watcher", "Docker".
    public var name: String
    public var runtime: ServerRuntime

    public init(_ name: String, _ runtime: ServerRuntime) {
        self.name = name
        self.runtime = runtime
    }
}

/// A dev server: a process listening on a port, a watcher (no port), or a container.
public struct DevServer: Equatable, Sendable, Identifiable {
    /// How to stop it.
    public enum Target: Equatable, Sendable {
        case process(pid: Int32, startedAt: Date)
        case container(id: String)
    }

    /// Stable for one process or container instance, so activity survives relaunches.
    public var id: String
    public var target: Target
    /// The project root's path, or `ProjectCatalog.containersProjectID` for containers outside Compose.
    public var projectID: String
    public var project: ProjectRoot?
    /// e.g. "next dev", "postgres:16".
    public var command: String
    public var kind: ServerKind
    public var ports: [UInt16]
    public var startedAt: Date?
    public var memory: UInt64?
    /// Cumulative CPU seconds, nil when unreadable.
    public var cpuTime: TimeInterval?
    /// Inbound connections open now; see `DevProcess.connections`.
    public var connections: Set<String>

    /// Watchers have no port, so only their CPU says whether they're busy.
    public var isWatcher: Bool { ports.isEmpty }
}

/// Builds dev servers from the sampler's reading: which processes are servers, what kind, and
/// which project they belong to. Pure; activity over time is ProjectActivity's job.
public enum ProjectCatalog {
    /// Groups containers that weren't started by Docker Compose.
    public static let containersProjectID = "docker"

    /// Servers in the reading: listening processes, watchers, and containers.
    ///
    /// A process qualifies by listening on a TCP port or by a watch-style command line. Wrappers
    /// such as `npm run watch` → `sh -c …` → `tailwindcss --watch` all look like watchers, so a
    /// watcher is dropped when one of its descendants in the same project also qualifies.
    public static func servers(in reading: DevServerReading) -> [DevServer] {
        let candidates = reading.processes.filter {
            $0.project != nil && (!$0.listeningPorts.isEmpty || isWatcher(arguments: $0.arguments))
        }
        let byPID = Dictionary(reading.processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var hasQualifyingDescendant = Set<Int32>()
        for process in candidates {
            var parent = process.parentPID
            var visited = Set<Int32>()
            while parent > 1, visited.insert(parent).inserted, let ancestor = byPID[parent] {
                if ancestor.project == process.project { hasQualifyingDescendant.insert(parent) }
                parent = ancestor.parentPID
            }
        }
        let processes = candidates
            .filter { !$0.listeningPorts.isEmpty || !hasQualifyingDescendant.contains($0.pid) }
            .compactMap { process -> DevServer? in
                guard let project = process.project else { return nil }
                return DevServer(
                    id: "\(process.pid)-\(Int(process.startedAt.timeIntervalSince1970))",
                    target: .process(pid: process.pid, startedAt: process.startedAt),
                    projectID: project.path, project: project,
                    command: command(arguments: process.arguments, name: process.name),
                    kind: kind(arguments: process.arguments, name: process.name, ports: process.listeningPorts),
                    ports: process.listeningPorts, startedAt: process.startedAt, memory: process.memory,
                    cpuTime: process.cpuTime, connections: process.connections
                )
            }
        let containers = reading.docker.containers.map { container in
            DevServer(
                id: "docker-\(container.id)-\(Int(container.startedAt?.timeIntervalSince1970 ?? 0))",
                target: .container(id: container.id),
                projectID: container.project?.path ?? containersProjectID, project: container.project,
                command: container.image, kind: ServerKind("Docker", .docker), ports: container.ports,
                startedAt: container.startedAt, memory: container.memory, cpuTime: container.cpuTime,
                connections: container.connections
            )
        }
        return processes + containers
    }

    // MARK: Command line

    private static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish"]

    private static func isInterpreter(_ program: String) -> Bool {
        ["node", "nodejs", "bun", "deno", "ruby", "php", "perl"].contains(program)
            || program.hasPrefix("python") || program.hasPrefix("pypy")
    }

    /// The last path component without a script extension: "/…/.bin/vite" → "vite", "manage.py" → "manage".
    static func programName(_ argument: String) -> String {
        var name = (argument as NSString).lastPathComponent
        for suffix in [".js", ".mjs", ".cjs", ".ts", ".py", ".rb"] where name.hasSuffix(suffix) && name.count > suffix.count {
            name.removeLast(suffix.count)
        }
        return name
    }

    /// The meaningful part of the command line, as you'd type it: `node …/.bin/next dev` → "next dev",
    /// `python3 -m http.server 8000` → "http.server 8000", `sh -c "vite --port 5173"` → "vite --port 5173".
    public static func command(arguments: [String], name: String) -> String {
        var arguments = arguments.isEmpty ? [name] : arguments
        // Framework Python runs as …/Python.app/Contents/MacOS/Python.
        let program = programName(arguments[0]).lowercased()
        if shells.contains(program), arguments.count >= 3, arguments[1] == "-c" {
            return arguments[2].trimmingCharacters(in: .whitespaces)
        }
        if isInterpreter(program) {
            var rest = arguments.dropFirst()
            // Skip the interpreter's own options; `-m module` names the program.
            while let first = rest.first, first.hasPrefix("-") {
                rest = rest.dropFirst()
                if first == "-m" { break }
            }
            if !rest.isEmpty { arguments = Array(rest) }
        }
        // Paths read better as their file name, e.g. "json-server db.json".
        let shown = [(arguments[0] as NSString).lastPathComponent] + arguments.dropFirst().map { argument in
            argument.hasPrefix("/") ? (argument as NSString).lastPathComponent : argument
        }
        return shown.joined(separator: " ")
    }

    /// Lowercased words of the command line, with paths reduced to program names.
    private static func tokens(_ arguments: [String], name: String) -> [String] {
        (arguments.isEmpty ? [name] : arguments)
            .flatMap { $0.split(separator: " ").map(String.init) }
            .map { programName($0).lowercased() }
    }

    private static let watchPrograms: Set<String> = [
        "nodemon", "watchexec", "chokidar", "entr", "air", "reflex", "onchange", "tsc-watch", "cargo-watch",
    ]
    /// Tools whose `-w` means watch rather than, say, workers.
    private static let shortWatchFlagPrograms: Set<String> = [
        "tsc", "sass", "webpack", "rollup", "esbuild", "babel", "tailwindcss", "postcss", "less", "coffee",
    ]

    /// Whether the command line asks a tool to watch files, e.g. `tailwindcss --watch` or `nodemon`.
    public static func isWatcher(arguments: [String]) -> Bool {
        let words = tokens(arguments, name: "")
        if words.contains(where: { watchPrograms.contains($0) }) { return true }
        if words.contains(where: { $0 == "watch" || $0.hasPrefix("--watch") }) { return true }
        return words.contains("-w") && words.contains(where: { shortWatchFlagPrograms.contains($0) })
    }

    // MARK: Type

    /// The server's type from its command line, then its port, then what runs it.
    public static func kind(arguments: [String], name: String, ports: [UInt16]) -> ServerKind {
        let words = tokens(arguments, name: name)
        let has = { (word: String) in words.contains(word) }
        let runtime = runtime(words)
        if words.contains(where: { $0 == "next" || $0.hasPrefix("next-server") }) { return ServerKind("Next.js", .node) }
        if has("storybook") || has("start-storybook") { return ServerKind("Storybook", .node) }
        if has("vite") { return ServerKind("Vite", .node) }
        if has("nuxt") || has("nuxi") { return ServerKind("Nuxt", .node) }
        if has("astro") { return ServerKind("Astro", .node) }
        if has("webpack") || has("webpack-dev-server") { return ServerKind("Webpack", .node) }
        if has("json-server") || has("mockoon-cli") || has("wiremock") || has("mockserver") || has("mock-server")
            || (has("prism") && has("mock")) {
            return ServerKind("Mock API", runtime == .other ? .node : runtime)
        }
        if has("uvicorn") || has("fastapi") || has("hypercorn") { return ServerKind("FastAPI", .python) }
        if has("manage") && has("runserver") { return ServerKind("Django", .python) }
        if has("flask") { return ServerKind("Flask", .python) }
        if has("rails") || has("puma") { return ServerKind("Rails", .ruby) }
        if has("http.server") || has("http-server") || has("serve") { return ServerKind("Static Server", runtime) }
        if ports.isEmpty { return ServerKind("Watcher", runtime) }
        // Well-known default ports, for wrappers whose command line doesn't name the tool.
        if ports.contains(6006) { return ServerKind("Storybook", .node) }
        if ports.contains(5173) { return ServerKind("Vite", .node) }
        return switch runtime {
        case .node: ServerKind("Node.js", .node)
        case .python: ServerKind("Python", .python)
        case .ruby: ServerKind("Ruby", .ruby)
        case .docker, .other: ServerKind("Server", .other)
        }
    }

    private static func runtime(_ words: [String]) -> ServerRuntime {
        guard let program = words.first else { return .other }
        if ["node", "nodejs", "bun", "deno", "npm", "npx", "pnpm", "yarn"].contains(program) { return .node }
        if program.hasPrefix("python") || ["uvicorn", "gunicorn", "flask", "pypy"].contains(program) { return .python }
        if ["ruby", "rails", "puma", "bundle"].contains(program) { return .ruby }
        return .other
    }
}
