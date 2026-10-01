import Foundation
import os

/// Per-process network rates, from `nettop`.
///
/// There's no public per-process network API. `nettop` reads the kernel's network statistics for
/// every process with sockets, including other users', and one run costs under 1 ms of CPU. It runs
/// in the background each time the process list refreshes; rates are the byte deltas between two
/// runs, so the latest rates trail by one run.
final class NetworkProcessReader: Sendable {
    private let interval: TimeInterval

    private struct State {
        var running = false
        var lastRun: Date?
        /// Cumulative bytes (in + out) per pid at the previous run.
        var previous: (bytes: [Int32: UInt64], wall: Date)?
        var latest: [Int32: Double]?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// `interval` is a floor between runs, a little under the process list's 4 s cadence.
    init(interval: TimeInterval = 3) {
        self.interval = interval
    }

    /// Whether no `nettop` run is in flight.
    var isIdle: Bool {
        state.withLock { !$0.running }
    }

    /// Bytes per second (in + out) per pid from the two most recent runs, or nil until two have finished.
    func latest() -> [Int32: Double]? {
        state.withLock { $0.latest }
    }

    /// Starts a background `nettop` run unless one is in flight or the last started under `interval` ago.
    func refreshIfDue() {
        let now = Date()
        let due = state.withLock { state in
            guard !state.running, state.lastRun.map({ now.timeIntervalSince($0) >= interval }) ?? true
            else { return false }
            state.running = true
            state.lastRun = now
            return true
        }
        guard due else { return }
        DispatchQueue.global(qos: .utility).async { [self] in
            let bytes = Self.runNettop()
            let wall = Date()
            state.withLock { state in
                defer { state.running = false }
                guard let bytes else { return }
                if let previous = state.previous {
                    let elapsed = wall.timeIntervalSince(previous.wall)
                    if elapsed > 0 {
                        state.latest = Self.rates(from: previous.bytes, to: bytes, seconds: elapsed)
                    }
                }
                state.previous = (bytes, wall)
            }
        }
    }

    /// Per-pid rates between two runs. A process seen once has no rate yet; a counter that went down
    /// (closed sockets dropping out of the total) counts as idle.
    static func rates(from previous: [Int32: UInt64], to current: [Int32: UInt64], seconds: Double) -> [Int32: Double] {
        var rates: [Int32: Double] = [:]
        for (pid, bytes) in current {
            guard let before = previous[pid] else { continue }
            rates[pid] = bytes >= before ? Double(bytes - before) / seconds : 0
        }
        return rates
    }

    private static func runNettop() -> [Int32: UInt64]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        // One sample (-L 1), per process (-P), numeric (-n, -x), only the byte counters, and only
        // traffic leaving the Mac (-t external): loopback (e.g. local dev servers) isn't network use.
        process.arguments = ["-P", "-L", "1", "-n", "-x", "-t", "external", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// Parses `nettop -P -L 1 -x -J bytes_in,bytes_out` CSV: a header, then `name.pid,in,out,` rows.
    /// Names can contain dots and commas, so fields are read from the right.
    static func parse(_ output: String) -> [Int32: UInt64] {
        var result: [Int32: UInt64] = [:]
        for line in output.split(separator: "\n") {
            var fields = line.split(separator: ",", omittingEmptySubsequences: false)
            if fields.last?.isEmpty == true { fields.removeLast() }
            guard fields.count >= 3,
                  let sent = UInt64(fields[fields.count - 1]), let received = UInt64(fields[fields.count - 2])
            else { continue }
            let label = fields[..<(fields.count - 2)].joined(separator: ",")
            guard let dot = label.lastIndex(of: "."), let pid = Int32(label[label.index(after: dot)...]) else { continue }
            result[pid, default: 0] += received + sent
        }
        return result
    }
}
