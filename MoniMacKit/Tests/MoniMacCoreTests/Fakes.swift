import Foundation
import MoniMacCore

/// A controllable "now" for tests. Snapshots are stamped with it; tests move it forward.
final class TestClock {
    private(set) var now: Date

    init(start: Date = Date(timeIntervalSince1970: 1_790_000_000)) {
        now = start
    }

    func advance(by seconds: TimeInterval) {
        now += seconds
    }
}

/// Fake SystemSampler: returns scripted snapshots in order, then repeats the last one.
/// Each returned snapshot is stamped with the clock's current time.
final class ScriptedSampler: SystemSampler {
    private let clock: TestClock
    private var script: [Snapshot]
    private(set) var sampleCount = 0

    init(clock: TestClock, script: [Snapshot]) {
        precondition(!script.isEmpty, "Script at least one snapshot")
        self.clock = clock
        self.script = script
    }

    /// Convenience: script CPU readings only.
    convenience init(clock: TestClock, cpu: [Reading<CPUUsage>]) {
        self.init(clock: clock, script: cpu.map { Snapshot(timestamp: clock.now, cpu: $0) })
    }

    func sample() -> Snapshot {
        var snapshot = script[min(sampleCount, script.count - 1)]
        snapshot.timestamp = clock.now
        sampleCount += 1
        return snapshot
    }
}

/// Fake SystemActions: records requested actions instead of performing them.
@MainActor
final class RecordingActions: SystemActions {
    enum Action: Equatable {
        case quitApp(pid: Int32, reopenWindows: Bool)
        case forceQuitApp(pid: Int32)
        case openActivityMonitor
        case stopProcess(pid: Int32, startedAt: Date)
        case stopContainer(id: String)
        case openURL(URL)
        case revealInFinder(path: String)
        case setLaunchAtLogin(Bool)
        case requestNotificationAuthorization
        case deliver(Alert)
        case setOutputDevice(uid: String)
        case setSystemVolume(Double)
        case setSoundMix(SoundMix)
        case retrySoundAccess
    }

    private(set) var recorded: [Action] = []

    func quitApp(pid: Int32, reopenWindows: Bool) { recorded.append(.quitApp(pid: pid, reopenWindows: reopenWindows)) }
    func forceQuitApp(pid: Int32) { recorded.append(.forceQuitApp(pid: pid)) }
    func openActivityMonitor() { recorded.append(.openActivityMonitor) }
    func stopProcess(pid: Int32, startedAt: Date) { recorded.append(.stopProcess(pid: pid, startedAt: startedAt)) }
    func stopContainer(id: String) { recorded.append(.stopContainer(id: id)) }
    func openURL(_ url: URL) { recorded.append(.openURL(url)) }
    func revealInFinder(path: String) { recorded.append(.revealInFinder(path: path)) }
    /// Starts off; follows what was last set, or waits for approval when `loginNeedsApproval`.
    var launchAtLogin = LaunchAtLogin.off
    var loginNeedsApproval = false
    func setLaunchAtLogin(_ enabled: Bool) {
        recorded.append(.setLaunchAtLogin(enabled))
        launchAtLogin = enabled ? (loginNeedsApproval ? .needsApproval : .on) : .off
    }
    func requestNotificationAuthorization() { recorded.append(.requestNotificationAuthorization) }
    func deliver(_ alert: Alert) { recorded.append(.deliver(alert)) }
    func setOutputDevice(uid: String) { recorded.append(.setOutputDevice(uid: uid)) }
    func setSystemVolume(_ volume: Double) { recorded.append(.setSystemVolume(volume)) }
    func setSoundMix(_ mix: SoundMix) { recorded.append(.setSoundMix(mix)) }
    func retrySoundAccess() { recorded.append(.retrySoundAccess) }

    /// The sound mixes applied so far.
    var soundMixes: [SoundMix] {
        recorded.compactMap { if case .setSoundMix(let mix) = $0 { mix } else { nil } }
    }

    /// The alerts delivered so far.
    var delivered: [Alert] {
        recorded.compactMap { if case .deliver(let alert) = $0 { alert } else { nil } }
    }
}

extension Reading<CPUUsage> {
    /// CPU busy at `user` + `system`, the rest idle.
    static func cpu(user: Double, system: Double) -> Self {
        .value(CPUUsage(user: user, system: system, idle: 1 - user - system))
    }
}
