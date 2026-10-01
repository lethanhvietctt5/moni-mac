import Darwin
import Foundation
import MoniMacCore
import os

/// CPU for processes owned by other users (WindowServer, root daemons).
///
/// Only the setuid `/bin/ps` can read them without a privileged helper. Each run costs ~30 ms of
/// CPU, so it runs in the background at most every `interval` (15 s), and rates are averaged over that
/// interval. Between runs, the latest rates are reused.
final class OtherUsersProcessReader: Sendable {
    private let interval: TimeInterval

    private struct State {
        var running = false
        var lastRun: Date?
        var previous: [Int32: (cpuSeconds: Double, wall: Date)] = [:]
        var latest: [ProcessSample] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let uid = getuid()

    init(interval: TimeInterval = 15) {
        self.interval = interval
    }

    /// Whether no `ps` run is in flight.
    var isIdle: Bool {
        state.withLock { !$0.running }
    }

    /// The rates from the most recent completed run.
    func latest() -> [ProcessSample] {
        state.withLock { $0.latest }
    }

    /// Starts a background `ps` run if the last one is older than `interval` and none is running.
    func refreshIfDue() {
        let now = Date()
        let due = state.withLock { state in
            // Rates need two runs; the second follows the first baseline run quickly.
            let wait = state.latest.isEmpty ? min(interval, 3) : interval
            guard !state.running, state.lastRun.map({ now.timeIntervalSince($0) >= wait }) ?? true
            else { return false }
            state.running = true
            state.lastRun = now
            return true
        }
        guard due else { return }
        DispatchQueue.global(qos: .utility).async { [self] in
            let rows = Self.runPS()
            let wall = Date()
            state.withLock { state in
                var next: [Int32: (cpuSeconds: Double, wall: Date)] = [:]
                var samples: [ProcessSample] = []
                for row in rows where row.uid != uid {
                    next[row.pid] = (row.cpuSeconds, wall)
                    guard let previous = state.previous[row.pid], row.cpuSeconds >= previous.cpuSeconds else { continue }
                    let elapsed = wall.timeIntervalSince(previous.wall)
                    guard elapsed > 0 else { continue }
                    samples.append(ProcessSample(
                        pid: row.pid, name: (row.command as NSString).lastPathComponent,
                        path: row.command.hasPrefix("/") ? row.command : nil,
                        cpu: (row.cpuSeconds - previous.cpuSeconds) / elapsed
                    ))
                }
                state.previous = next
                state.latest = samples
                state.running = false
            }
        }
    }

    struct Row: Equatable {
        var pid: Int32
        var uid: uid_t
        var cpuSeconds: Double
        var command: String
    }

    private static func runPS() -> [Row] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,uid=,time=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// Parses `ps -axo pid=,uid=,time=,comm=` output.
    static func parse(_ output: String) -> [Row] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4, let pid = Int32(fields[0]), let uid = uid_t(fields[1]),
                  let seconds = parseCPUTime(fields[2]) else { return nil }
            return Row(pid: pid, uid: uid, cpuSeconds: seconds, command: String(fields[3]))
        }
    }

    /// `ps` CPU time: `[[dd-]hh:]mm:ss.cc`, where minutes may exceed 59 (e.g. `1266:23.49`).
    static func parseCPUTime<S: StringProtocol>(_ text: S) -> Double? {
        var rest = Substring(text)
        var days = 0.0
        if let dash = rest.firstIndex(of: "-") {
            guard let value = Double(rest[..<dash]) else { return nil }
            days = value
            rest = rest[rest.index(after: dash)...]
        }
        let parts = rest.split(separator: ":").reversed().map { Double($0) }
        guard (1...3).contains(parts.count), parts.allSatisfy({ $0 != nil }) else { return nil }
        let multipliers = [1.0, 60, 3600]
        return zip(parts, multipliers).reduce(days * 86400) { $0 + $1.0! * $1.1 }
    }
}
