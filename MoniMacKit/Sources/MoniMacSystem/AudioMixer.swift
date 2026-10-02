import CoreAudio
import Foundation
import MoniMacCore
import os

private let log = Logger(subsystem: "io.github.lethanhvietctt5.MoniMac", category: "Sound")

/// Puts a `SoundMix` into effect with Core Audio process taps, and keeps the Sound reading current.
///
/// - **Only where it changes something.** An app gets a tap (`AudioTapPipeline`) only while it plays
///   and its gain isn't 100% (`SoundMix.needsTap`); the tap is kept `idleHold` after the app stops, so
///   pauses between tracks don't rebuild it, then destroyed. Each running tap costs `coreaudiod` about 3% CPU.
/// - **Following the app.** The process-list and per-process listeners (`AudioWatcher`) retarget a tap
///   when the app's processes change, and start one as soon as an adjusted or new (muted-by-default) app
///   starts playing, without waiting for the refresh loop.
/// - **Following the output.** When the default output device or its sample rate changes, every tap is
///   rebuilt on the new device after it settles (taps are tied to the device they were built on).
/// - **Watchdog.** A tap that stops getting IO callbacks, or (within a minute of an output change) goes
///   silent while its app plays after it was heard, is rebuilt, at most once a minute.
/// - **Permission.** macOS has no API to read the audio capture permission and a denied tap delivers
///   silence. Until a tap has delivered sound, taps that hear only zeros while their apps play for
///   `accessVerdictDelay` mean "not working": every tap is stopped (so apps are heard as usual) and none
///   is started until `retryAccess()` or a relaunch. A playing app that's really silent (a call nobody
///   speaks in) can trip this; the UI says so and offers to try again.
/// - **Coexistence.** Other tap-based mixers (SoundSource's ARK, FineTune) on the same device may
///   interfere; MoniMac doesn't try to detect or fight them.
///
/// Inert until used: creating it makes no Core Audio call. All work runs on one serial queue.
public final class AudioMixer: @unchecked Sendable {
    static let idleHold: TimeInterval = 10
    static let accessVerdictDelay: TimeInterval = 6
    static let stalledAfter: TimeInterval = 3
    static let silentAfter: TimeInterval = 8
    static let rebuildInterval: TimeInterval = 60
    /// A tap that couldn't be built isn't tried again for this long.
    static let retryAfterFailure: TimeInterval = 30

    /// For `--sound-selftest`: what the taps are doing.
    public struct Status: Sendable, CustomStringConvertible {
        public var access: SoundAccess
        public var taps: [Tap]

        public struct Tap: Sendable {
            public var target: SoundTarget
            public var gain: Double
            public var level: Double?
            public var callbacks: UInt64
        }

        public var description: String {
            let taps = taps.map { tap in
                let level = tap.level.map { String(format: "%.1f dBFS", $0) } ?? "no sound yet"
                return "\(tap.target) gain \(tap.gain) level \(level) callbacks \(tap.callbacks)"
            }
            return (["access \(access)", "taps \(taps.count)"] + taps).joined(separator: "\n")
        }
    }

    private struct Published {
        var access = SoundAccess.unused
        var problem: String?
        var levels: [String: Double?] = [:]
        var status = Status(access: .unused, taps: [])
    }

    private let queue = DispatchQueue(label: "io.github.lethanhvietctt5.MoniMac.audio", qos: .userInitiated)
    private let watcher: AudioWatcher
    private let published = OSAllocatedUnfairLock(initialState: Published())

    // Confined to `queue`.
    private var mix = SoundMix()
    private var testGains: [Int32: Double] = [:]
    private var pipelines: [SoundTarget: AudioTapPipeline] = [:]
    private var lastPlaying: [SoundTarget: Date] = [:]
    private var access = SoundAccess.unused
    private var silentSince: Date?
    private var health: [SoundTarget: Health] = [:]
    private var watchdog: DispatchSourceTimer?
    private var pendingRebuild: DispatchWorkItem?
    private var isShutDown = false
    /// Targets whose tap couldn't be built, and when.
    private var failures: [SoundTarget: Date] = [:]
    /// Why the last tap couldn't be built, for the Sound tab; cleared when one is.
    private var problem: String?
    /// When the output last changed. Taps going silent after a device or rate change is a known Core Audio
    /// problem, so silence is treated as a fault only for `silentAfterChange` after one; otherwise it's a
    /// paused app that keeps its stream open.
    private var outputChangedAt: Date?
    static let silentAfterChange: TimeInterval = 60

    /// What the watchdog last saw of a tap.
    private struct Health {
        var callbacks: UInt64 = 0
        var audible: UInt64 = 0
        var progressAt = Date()
        var audibleAt: Date?
        var rebuiltAt: Date?
    }

    public init() {
        watcher = AudioWatcher(queue: queue)
        watcher.onChange = { [weak self] change in self?.watcherChanged(change) }
    }

    // MARK: API

    /// Applies new gains. Starts watching audio if anything needs a tap now or later, stops otherwise.
    public func apply(_ mix: SoundMix) {
        queue.async { [self] in
            self.mix = mix
            reconcile()
        }
    }

    /// For `--sound-selftest`: gains for single processes, on top of the mix.
    public func setTestGains(_ gains: [Int32: Double]) {
        queue.async { [self] in
            testGains = gains
            reconcile()
        }
    }

    /// Forgets a "not working" verdict and tries the taps again.
    public func retryAccess() {
        queue.async { [self] in
            guard access == .notWorking else { return }
            setAccess(.unused)
            reconcile()
        }
    }

    /// Whether the Sound reading is needed (`SoundDemand`).
    func setReadingNeeded(_ needed: Bool) {
        queue.async { [self] in
            guard !isShutDown else { return }
            watcher.setNeeded(needed, by: .reading)
        }
    }

    /// The Sound reading, from the cache the listeners keep. Never touches Core Audio.
    func reading() -> Reading<SoundReading> {
        let cache = watcher.latest()
        guard cache.isReady else { return .unavailable(.warmingUp) }
        let (access, problem, levels) = published.withLock { ($0.access, $0.problem, $0.levels) }
        let processes = cache.clients.compactMap { client -> SoundProcess? in
            guard let app = client.app else { return nil }
            return SoundProcess(pid: client.pid, appID: app.id, appName: app.name, appPath: app.path,
                                isRunningOutput: client.isRunningOutput, isRunningInput: client.isRunningInput)
        }
        return .value(SoundReading(
            output: cache.output, devices: cache.devices, processes: processes,
            taps: levels.mapValues { SoundTap(level: $0) }, access: access, tapProblem: problem
        ))
    }

    public var status: Status {
        published.withLock { $0.status }
    }

    /// Destroys every tap and stops listening. Called when MoniMac quits; waits at most 2 s, since a tap
    /// build can be blocked behind the permission prompt. Private taps end with the process anyway.
    public func shutdown() {
        let done = DispatchSemaphore(value: 0)
        queue.async { [self] in
            defer { done.signal() }
            isShutDown = true
            pendingRebuild?.cancel()
            stopWatchdog()
            let count = pipelines.count
            for pipeline in pipelines.values { pipeline.destroy() }
            pipelines = [:]
            watcher.setNeeded(false, by: .reading)
            watcher.setNeeded(false, by: .mixer)
            if count > 0 {
                let left = AudioHAL.objects(AudioHAL.system, kAudioHardwarePropertyTapList).count
                log.notice("Destroyed \(count) taps on quit; taps still listed for MoniMac: \(left)")
            }
        }
        if done.wait(timeout: .now() + 2) == .timedOut { log.notice("Quitting without waiting for the audio queue") }
    }

    // MARK: Reconciling

    private func watcherChanged(_ change: AudioWatcher.Change) {
        switch change {
        case .clients: reconcile()
        case .output: scheduleRebuild()
        case .devices:
            // The device the taps play on was unplugged: they're silent until rebuilt.
            if let uid = pipelines.values.first?.output.uid, !watcher.latest().devices.contains(where: { $0.uid == uid }) {
                scheduleRebuild()
            }
        case .volume: break
        }
    }

    /// Makes the taps match the mix and what's playing. On `queue`.
    private func reconcile(now: Date = Date()) {
        guard !isShutDown else { return }
        watcher.setNeeded(!mix.isEmpty || !testGains.isEmpty, by: .mixer)
        let wanted = access == .notWorking ? [:] : wantedTaps(now: now)
        for (target, pipeline) in pipelines where wanted[target] == nil {
            log.notice("Stopping the tap for \(String(describing: target), privacy: .public)")
            pipeline.destroy()
            pipelines[target] = nil
            health[target] = nil
        }
        for (target, want) in wanted {
            if let pipeline = pipelines[target] {
                pipeline.gain = want.gain
                if Set(pipeline.objects) != Set(want.objects), !pipeline.retarget(want.objects) {
                    rebuild(target, objects: want.objects, gain: want.gain)
                }
            } else if failures[target].map({ now.timeIntervalSince($0) >= Self.retryAfterFailure }) ?? true {
                rebuild(target, objects: want.objects, gain: want.gain)
            }
        }
        failures = failures.filter { wanted[$0.key] != nil }
        if pipelines.isEmpty {
            stopWatchdog()
            // No tap is left to judge by: the next one starts the verdict afresh.
            silentSince = nil
            if access == .checking { setAccess(.unused) }
        } else {
            startWatchdog()
        }
        publish()
    }

    /// Each target that should have a tap now, with its gain and processes.
    private func wantedTaps(now: Date) -> [SoundTarget: (gain: Double, objects: [AudioObjectID])] {
        var groups: [SoundTarget: [AudioClient]] = [:]
        for client in watcher.clients.values {
            if let app = client.app { groups[.app(app.id), default: []].append(client) }
            if testGains[client.pid] != nil { groups[.process(client.pid), default: []].append(client) }
        }
        var wanted: [SoundTarget: (gain: Double, objects: [AudioObjectID])] = [:]
        for (target, clients) in groups {
            let gain: Double = switch target {
            case .app(let id): mix.gain(forApp: id)
            case .process(let pid): testGains[pid] ?? 1
            }
            guard gain < 1 else { continue }
            let playing = clients.contains(where: \.isRunningOutput)
            if playing { lastPlaying[target] = now }
            let recentlyPlaying = pipelines[target] != nil
                && lastPlaying[target].map { now.timeIntervalSince($0) < Self.idleHold } == true
            guard playing || recentlyPlaying else { continue }
            wanted[target] = (gain, clients.map(\.object).sorted())
        }
        lastPlaying = lastPlaying.filter { groups[$0.key] != nil }
        return wanted
    }

    /// Builds a tap for `target` on the current output, replacing any old one only once the new one runs.
    private func rebuild(_ target: SoundTarget, objects: [AudioObjectID], gain: Double) {
        guard let output = watcher.output else { return }
        let old = pipelines[target]
        do {
            let pipeline = try AudioTapPipeline(target: target, objects: objects, gain: gain, output: output)
            old?.destroy()
            pipelines[target] = pipeline
            health[target] = Health(rebuiltAt: old == nil ? nil : Date())
            failures[target] = nil
            problem = nil
            if access == .unused { setAccess(.checking) }
        } catch {
            log.error("Couldn't start a tap for \(String(describing: target), privacy: .public): \(String(describing: error), privacy: .public)")
            failures[target] = Date()
            if old == nil { health[target] = nil }
            problem = switch error {
            case AudioTapPipeline.Failure.unexpectedInputs:
                "Per-app volume can't run on this output device: MoniMac couldn't keep its microphone out of the way."
            default: "Per-app volume couldn't start (\(error)). MoniMac will try again."
            }
            publish()
        }
    }

    /// Rebuilds every tap on the new output once it has settled: 2 s, or 5 s for Bluetooth (FineTune's figures).
    private func scheduleRebuild() {
        pendingRebuild?.cancel()
        outputChangedAt = Date()
        guard !pipelines.isEmpty else { return }
        let bluetooth = AudioHAL.isBluetooth(transport: watcher.output?.transport ?? 0)
        let work = DispatchWorkItem { [weak self] in
            guard let self, !isShutDown else { return }
            log.notice("Output changed; rebuilding \(self.pipelines.count) taps")
            for (target, pipeline) in pipelines { rebuild(target, objects: pipeline.objects, gain: pipeline.gain) }
            publish()
        }
        pendingRebuild = work
        queue.asyncAfter(deadline: .now() + (bluetooth ? 5 : 2), execute: work)
    }

    // MARK: Watchdog and permission

    private func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.checkTaps() }
        timer.resume()
        watchdog = timer
    }

    private func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    private func checkTaps(now: Date = Date()) {
        var anyHeard = false
        var allSilentWhilePlaying = !pipelines.isEmpty
        for (target, pipeline) in pipelines {
            var record = health[target] ?? Health()
            let callbacks = pipeline.callbacks
            let audible = pipeline.audibleCallbacks
            if callbacks != record.callbacks { record.progressAt = now }
            if audible != record.audible { record.audibleAt = now }
            (record.callbacks, record.audible) = (callbacks, audible)
            health[target] = record
            if audible > 0 { anyHeard = true }
            let playing = isPlaying(target)
            if !(playing && callbacks > 0 && audible == 0) { allSilentWhilePlaying = false }

            guard access == .working, canRebuild(record, now: now) else { continue }
            let stalled = now.timeIntervalSince(record.progressAt) >= Self.stalledAfter
            let afterChange = outputChangedAt.map { now.timeIntervalSince($0) < Self.silentAfterChange } == true
            let wentSilent = afterChange && playing
                && record.audibleAt.map { now.timeIntervalSince($0) >= Self.silentAfter } == true
            if stalled || wentSilent {
                log.notice("Tap for \(String(describing: target), privacy: .public) \(stalled ? "stalled" : "went silent", privacy: .public); rebuilding")
                rebuild(target, objects: pipeline.objects, gain: pipeline.gain)
            }
        }
        if anyHeard, access != .working {
            silentSince = nil
            setAccess(.working)
        } else if access == .checking {
            silentSince = allSilentWhilePlaying ? (silentSince ?? now) : nil
            if let since = silentSince, now.timeIntervalSince(since) >= Self.accessVerdictDelay {
                log.error("Taps heard only silence while their apps played; per-app volume isn't working (permission denied?)")
                setAccess(.notWorking)
                silentSince = nil
                reconcile(now: now)
                return
            }
        }
        reconcile(now: now)
    }

    private func canRebuild(_ record: Health, now: Date) -> Bool {
        record.rebuiltAt.map { now.timeIntervalSince($0) >= Self.rebuildInterval } ?? true
    }

    private func isPlaying(_ target: SoundTarget) -> Bool {
        watcher.clients.values.contains { client in
            guard client.isRunningOutput else { return false }
            return switch target {
            case .app(let id): client.app?.id == id
            case .process(let pid): client.pid == pid
            }
        }
    }

    private func setAccess(_ access: SoundAccess) {
        guard access != self.access else { return }
        log.notice("Per-app volume: \(String(describing: access), privacy: .public)")
        self.access = access
        publish()
    }

    private func publish() {
        let taps = pipelines.map { target, pipeline in
            Status.Tap(target: target, gain: pipeline.gain, level: pipeline.level, callbacks: pipeline.callbacks)
        }
        var appLevels: [String: Double?] = [:]
        for tap in taps { if case .app(let id) = tap.target { appLevels[id] = tap.level } }
        let (access, problem, levels) = (access, problem, appLevels)
        published.withLock {
            $0.access = access
            $0.problem = problem
            $0.levels = levels
            $0.status = Status(access: access, taps: taps)
        }
    }
}
