import Darwin
import Foundation
import MoniMacCore
import os

private let log = Logger(subsystem: "io.github.lethanhvietctt5.MoniMac", category: "Projects")

/// Dev servers and containers for Projects, read on a utility-QoS background queue every
/// `interval` (12 s). The refresh loop only picks up the latest result and never waits for it.
///
/// Each read:
/// - checks every pid's owner and start time (`PROC_PIDTBSDINFO`); for the user's own processes
///   it reads, once per process, the working directory and executable path
/// - for processes started from a folder other than "/", the home folder, or ~/Library (and that
///   aren't app bundles): argv once, then each time their TCP sockets; and for those that listen or
///   watch, the project their folder is in, CPU time, and memory
/// - asks Docker for its containers, if Docker's socket exists, and attributes inbound connections
///   held by Docker's host-side proxy to the containers whose published ports they're on
final class DevServerReader: Sendable {
    private struct State {
        var latest: Reading<DevServerReading> = .unavailable(.warmingUp)
        var running = false
        var lastRun: Date?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    /// Only the background read uses it, one read at a time (`running` guards that), so holding the
    /// lock for a whole read never blocks the refresh loop, which only takes `state`.
    private let scanner: OSAllocatedUnfairLock<DevServerScanner>
    private let interval: TimeInterval
    private let started: Date
    private let firstDelay: TimeInterval

    init(scanner: DevServerScanner = DevServerScanner(), interval: TimeInterval = 12, firstDelay: TimeInterval = 3,
         now: Date = Date()) {
        self.scanner = OSAllocatedUnfairLock(uncheckedState: scanner)
        self.interval = interval
        self.firstDelay = firstDelay
        self.started = now
    }

    func latest() -> Reading<DevServerReading> {
        state.withLock { $0.latest }
    }

    /// Starts a background read if the last one is older than `interval` and none is running.
    func refreshIfDue(now: Date = Date()) {
        let due = state.withLock { state in
            guard !state.running, now.timeIntervalSince(started) >= firstDelay,
                  state.lastRun.map({ now.timeIntervalSince($0) >= interval }) ?? true else { return false }
            (state.running, state.lastRun) = (true, now)
            return true
        }
        guard due else { return }
        DispatchQueue.global(qos: .utility).async { [self] in
            let reading = scanner.withLockUnchecked { $0.scan() }
            state.withLock {
                $0.latest = .value(reading)
                $0.running = false
            }
        }
    }

    /// Reads once, synchronously. For smoke tests.
    func readNow() -> DevServerReading {
        scanner.withLockUnchecked { $0.scan() }
    }
}

/// The state a read keeps between runs: per-process facts that never change, and folder lookups.
final class DevServerScanner {
    private struct Identity {
        var start: Date
        var name: String
        var cwd: String?
        var isAppBundle: Bool
        var arguments: [String]?
    }

    private let uid = getuid()
    private let home = NSHomeDirectory()
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(info.denom))
    }()
    private var identities: [Int32: Identity] = [:]
    private var pidBuffer = [pid_t](repeating: 0, count: 4096)
    private let resolver: ProjectRootResolver
    private let docker: DockerReader

    init(resolver: ProjectRootResolver = ProjectRootResolver(), docker: DockerReader = DockerReader()) {
        self.resolver = resolver
        self.docker = docker
    }

    func scan(now: Date = Date()) -> DevServerReading {
        let cpuStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        var live: [Int32: Identity] = [:]
        var processes: [DevProcess] = []
        var dockerProxies: [Int32] = []
        for pid in listPIDs() {
            guard let info = DevProcessInfo.bsdInfo(pid), info.pbi_uid == uid else { continue }
            let start = DevProcessInfo.startTime(info)
            let name = DevProcessInfo.name(info)
            // exec keeps the pid and start time but changes the name (e.g. `env` → `python3`), and with
            // it the arguments and executable.
            var identity = identities[pid].flatMap { $0.start == start && $0.name == name ? $0 : nil } ?? Identity(
                start: start, name: name, cwd: DevProcessInfo.cwd(pid),
                isAppBundle: DevProcessInfo.executablePath(pid).map(Self.isAppBundle) ?? false
            )
            defer { live[pid] = identity }
            if identity.name.hasPrefix("com.docker") { dockerProxies.append(pid) }
            guard !identity.isAppBundle, let cwd = identity.cwd, cwd != "/" else { continue }
            // Agents and helpers started from the home folder or ~/Library are never in a project, but
            // they're kept (with nothing else read) to link parents to children.
            let outside = cwd == home || cwd.hasPrefix(home + "/Library/")
            if !outside, identity.arguments == nil { identity.arguments = DevProcessInfo.arguments(pid) ?? [] }
            let sockets = outside ? DevProcessInfo.Sockets() : DevProcessInfo.sockets(pid)
            let ports = Set(sockets.listening)
            // Only servers and watchers need their project; looking it up touches the folder.
            let qualifies = !outside && (!ports.isEmpty || ProjectCatalog.isWatcher(arguments: identity.arguments ?? []))
            let project = qualifies ? resolver.project(for: cwd, now: now) : nil
            let usage = project == nil ? nil : DevProcessInfo.usage(pid, timebase: timebase)
            processes.append(DevProcess(
                pid: pid, parentPID: Int32(info.pbi_ppid), startedAt: start, name: identity.name,
                arguments: identity.arguments ?? [], project: usage == nil ? nil : project,
                listeningPorts: sockets.listening,
                connections: Self.connections(sockets.established, on: ports),
                cpuTime: usage?.cpuTime ?? 0, memory: usage?.memory
            ))
        }
        identities = live
        var docker = docker.read { [resolver] in resolver.project(for: $0, now: now) }
        if case .running(var containers) = docker, !containers.isEmpty {
            let established = dockerProxies.flatMap { DevProcessInfo.sockets($0).established }
            for index in containers.indices {
                let ports = Set(containers[index].ports)
                containers[index].connections = Self.connections(established, on: ports)
            }
            docker = .running(containers)
        }
        resolver.prune(now: now)
        let cpu = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - cpuStart) / 1_000_000
        log.debug("Dev server read: \(processes.count) processes in projects, \(cpu, format: .fixed(precision: 1)) ms CPU")
        return DevServerReading(sampledAt: now, processes: processes, docker: docker, home: home)
    }

    /// Connections on `ports`, as `DevProcess.connections` identifies them.
    static func connections(_ established: [(port: UInt16, peer: String)], on ports: Set<UInt16>) -> Set<String> {
        Set(established.filter { ports.contains($0.port) }.map { "\($0.port) \($0.peer)" })
    }

    /// An app or its helper, not a dev server (Electron apps under development included). Python
    /// from a framework build runs as Python.app inside Python.framework, and is a dev server's runtime.
    static func isAppBundle(_ executable: String) -> Bool {
        executable.contains(".app/") && !executable.contains(".framework/")
    }

    private func listPIDs() -> ArraySlice<pid_t> {
        while true {
            let count = Int(proc_listallpids(&pidBuffer, Int32(pidBuffer.count * MemoryLayout<pid_t>.size)))
            if count < pidBuffer.count { return pidBuffer.prefix(max(count, 0)) }
            pidBuffer = [pid_t](repeating: 0, count: pidBuffer.count * 2)
        }
    }
}
