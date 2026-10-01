import Foundation

/// What the sampler reads for Projects: the user's processes started from a folder (not "/"), and
/// Docker containers. Read in the background every few seconds and repeated on the ticks between,
/// so `sampledAt` says which read this is.
///
/// It carries raw inputs (cumulative CPU time, the connections open right now), not conclusions:
/// ProjectCatalog decides which processes are servers and ProjectActivity decides which are idle.
public struct DevServerReading: Equatable, Sendable {
    /// When the background read ran.
    public var sampledAt: Date
    /// Processes started from a folder, whether or not they listen on a port. Only those that listen
    /// or watch have a project; the rest link parents to children (e.g. `npm run` → `sh -c` → `vite`).
    public var processes: [DevProcess]
    public var docker: DockerStatus

    public init(sampledAt: Date, processes: [DevProcess], docker: DockerStatus = .notInstalled) {
        self.sampledAt = sampledAt
        self.processes = processes
        self.docker = docker
    }
}

/// The folder a server belongs to: the nearest enclosing git repository or package manifest.
public struct ProjectRoot: Hashable, Sendable {
    /// Absolute path.
    public var path: String
    /// The checked-out branch, nil when it isn't a git repository or HEAD is detached.
    public var branch: String?

    public init(path: String, branch: String? = nil) {
        self.path = path
        self.branch = branch
    }
}

/// One of the user's processes, with a working directory other than "/".
public struct DevProcess: Equatable, Sendable {
    public var pid: Int32
    public var parentPID: Int32
    /// With the pid, this identifies one process instance (pids are reused).
    public var startedAt: Date
    /// The kernel's short name, e.g. "node".
    public var name: String
    /// argv, e.g. ["node", "/…/node_modules/.bin/vite"]. Empty when unreadable.
    public var arguments: [String]
    /// The project its working directory is in. Only looked up for processes that listen on a port or
    /// watch files (looking can raise a privacy prompt); nil for others and outside any project.
    public var project: ProjectRoot?
    /// TCP ports it listens on, ascending.
    public var listeningPorts: [UInt16]
    /// Inbound connections open now on those ports, as "localPort remoteAddress:remotePort".
    /// A connection missing from the previous read is a new one.
    public var connections: Set<String>
    /// CPU time used since the process started, in seconds.
    public var cpuTime: TimeInterval
    /// Physical footprint in bytes, nil when unreadable.
    public var memory: UInt64?

    public init(
        pid: Int32, parentPID: Int32 = 1, startedAt: Date, name: String, arguments: [String], project: ProjectRoot?,
        listeningPorts: [UInt16] = [], connections: Set<String> = [], cpuTime: TimeInterval = 0, memory: UInt64? = nil
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.startedAt = startedAt
        self.name = name
        self.arguments = arguments
        self.project = project
        self.listeningPorts = listeningPorts
        self.connections = connections
        self.cpuTime = cpuTime
        self.memory = memory
    }
}

/// Docker, which MoniMac only reads when its socket exists.
public enum DockerStatus: Equatable, Sendable {
    /// No Docker socket: nothing to show and nothing to explain.
    case notInstalled
    /// The socket exists but nothing answers, e.g. Docker Desktop is quit. Not an error.
    case notRunning
    case running([DockerContainer])
    case failed(String)

    public var containers: [DockerContainer] {
        if case .running(let containers) = self { containers } else { [] }
    }
}

/// A running container.
public struct DockerContainer: Equatable, Sendable {
    public var id: String
    /// e.g. "api-gateway-postgres-1".
    public var name: String
    /// e.g. "postgres:16".
    public var image: String
    public var startedAt: Date?
    /// Ports published on the Mac, ascending.
    public var ports: [UInt16]
    /// The Compose project's folder, when the container was started by Docker Compose.
    public var project: ProjectRoot?
    /// CPU time used since the container started, in seconds.
    public var cpuTime: TimeInterval?
    public var memory: UInt64?
    /// Inbound connections open now on its published ports (held by Docker's host-side proxy).
    public var connections: Set<String>

    public init(
        id: String, name: String, image: String, startedAt: Date? = nil, ports: [UInt16] = [],
        project: ProjectRoot? = nil, cpuTime: TimeInterval? = nil, memory: UInt64? = nil, connections: Set<String> = []
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.startedAt = startedAt
        self.ports = ports
        self.project = project
        self.cpuTime = cpuTime
        self.memory = memory
        self.connections = connections
    }
}
