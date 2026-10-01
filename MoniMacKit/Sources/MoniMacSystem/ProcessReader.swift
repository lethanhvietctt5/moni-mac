import AppKit
import Darwin
import Foundation
import MoniMacCore

/// Per-process CPU for every process MoniMac can see.
///
/// Without a privileged helper, the proc_* APIs only work for the current user's processes. Those
/// are read directly every tick. Other users' processes (WindowServer, root daemons) are read by
/// `OtherUsersProcessReader` via the setuid `ps`, which is too costly to run every tick.
@MainActor
final class ProcessReader {
    private struct Identity: Equatable {
        /// Process start time (Mach absolute time); with the pid it identifies one process instance.
        var start: UInt64
        var name: String
        var path: String?
        var responsiblePID: Int32?
    }

    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(info.denom))
    }()
    private let others = OtherUsersProcessReader()
    private var identities: [Int32: Identity] = [:]
    /// Cumulative counters per pid at the previous pass, with the process start time they belong to.
    private struct Counters {
        var start: UInt64
        var cpuNanoseconds: UInt64
        var diskRead: UInt64
        var diskWritten: UInt64
        var energyNanojoules: UInt64
    }
    private var previous: [Int32: Counters] = [:]
    private var previousWall: UInt64?
    private var pidBuffer = [pid_t](repeating: 0, count: 4096)
    private let regularApps = RegularApps()
    /// Minimum time between process passes. A pass costs ~5 ms of syscalls, so between passes
    /// the previous rates are reused.
    private let interval: UInt64
    private var lastResult: Reading<[ProcessSample]> = .unavailable(.warmingUp)

    init(interval: TimeInterval = 4) {
        self.interval = UInt64(interval * 1_000_000_000)
    }

    func sample() -> Reading<[ProcessSample]> {
        others.refreshIfDue()
        let wall = DispatchTime.now().uptimeNanoseconds
        if let previousWall, wall - previousWall < interval, lastResult.value != nil {
            return lastResult
        }
        let elapsed = previousWall.map { Double(wall - $0) }

        var samples: [ProcessSample] = []
        var current: [Int32: Counters] = [:]
        for pid in listPIDs() {
            // rusage fails for other users' processes, which OtherUsersProcessReader covers.
            guard let usage = rusage(pid) else { continue }
            let counters = Counters(
                start: usage.ri_proc_start_abstime,
                cpuNanoseconds: (usage.ri_user_time + usage.ri_system_time) * timebase.numer / timebase.denom,
                diskRead: usage.ri_diskio_bytesread,
                diskWritten: usage.ri_diskio_byteswritten,
                energyNanojoules: usage.ri_energy_nj
            )
            current[pid] = counters

            let identity = identity(of: pid, start: counters.start)
            var sample = ProcessSample(
                pid: pid, responsiblePID: identity.responsiblePID, name: identity.name, path: identity.path,
                cpu: 0, isRegularApp: regularApps.contains(pid), memory: usage.ri_phys_footprint
            )
            if let elapsed, let previous = previous[pid], previous.start == counters.start {
                let seconds = elapsed / 1_000_000_000
                func rate(_ now: UInt64, _ before: UInt64) -> Double { now >= before ? Double(now - before) / seconds : 0 }
                sample.cpu = rate(counters.cpuNanoseconds, previous.cpuNanoseconds) / 1_000_000_000
                sample.diskReadPerSecond = rate(counters.diskRead, previous.diskRead)
                sample.diskWritePerSecond = rate(counters.diskWritten, previous.diskWritten)
                // Nanojoules per second → watts.
                sample.power = rate(counters.energyNanojoules, previous.energyNanojoules) / 1_000_000_000
            }
            samples.append(sample)
        }

        if identities.count > current.count * 2 {
            identities = identities.filter { current[$0.key] != nil }
        }
        previous = current
        defer { previousWall = wall }
        guard elapsed != nil else { return .unavailable(.warmingUp) }
        lastResult = .value(samples + others.latest())
        return lastResult
    }

    private func listPIDs() -> ArraySlice<pid_t> {
        while true {
            let bytes = proc_listallpids(&pidBuffer, Int32(pidBuffer.count * MemoryLayout<pid_t>.size))
            let count = Int(bytes)
            if count < pidBuffer.count { return pidBuffer.prefix(max(count, 0)) }
            pidBuffer = [pid_t](repeating: 0, count: pidBuffer.count * 2)
        }
    }

    /// rusage reports CPU time in Mach absolute time units, not nanoseconds.
    private func rusage(_ pid: pid_t) -> rusage_info_v6? {
        var usage = rusage_info_v6()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
        }
        return result == 0 ? usage : nil
    }

    /// Path, name, and responsible pid change only when the process does, so they're cached per instance.
    private func identity(of pid: pid_t, start: UInt64) -> Identity {
        if let cached = identities[pid], cached.start == start { return cached }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let path = proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(nullTerminated: buffer) : nil
        let name = path.map { ($0 as NSString).lastPathComponent } ?? "pid \(pid)"
        let identity = Identity(start: start, name: name, path: path, responsiblePID: Responsibility.pid(for: pid))
        identities[pid] = identity
        return identity
    }
}

/// Pids of running apps with a Dock presence. Each `activationPolicy` read is a LaunchServices
/// round trip, so the set is read once and then maintained from workspace notifications.
@MainActor
private final class RegularApps {
    private var pids: Set<pid_t>
    private var observers: [NSObjectProtocol] = []

    init() {
        let workspace = NSWorkspace.shared
        pids = Set(workspace.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier))
        let center = workspace.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { _ = self?.pids.insert(pid) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { _ = self?.pids.remove(pid) }
        })
    }

    func contains(_ pid: pid_t) -> Bool { pids.contains(pid) }
}

/// macOS's "responsible process" lookup (how Activity Monitor attributes helpers to apps).
/// It's a private libsystem symbol, so it's resolved at runtime and may be missing.
enum Responsibility {
    private typealias Lookup = @convention(c) (pid_t) -> pid_t

    private static let lookup: Lookup? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: Lookup.self)
    }()

    static func pid(for pid: pid_t) -> Int32? {
        guard let lookup else { return nil }
        let responsible = lookup(pid)
        return responsible > 0 ? responsible : nil
    }
}
