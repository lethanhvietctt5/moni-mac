import Foundation

/// "Duck background apps": while a call is active, every other app plays at half its volume.
///
/// A call is an app playing and recording at once (`SoundApp.isInCall`). It must last `startDelay`
/// before ducking starts, so a notification sound during dictation doesn't count, and ducking ends
/// `endDelay` after no app is in a call, so a brief gap doesn't bounce levels. The call's apps are kept
/// while the end delay runs, so they're never ducked themselves.
public struct SoundDucking: Equatable, Sendable {
    static let startDelay: TimeInterval = 2
    static let endDelay: TimeInterval = 2
    /// Other apps' gain during a call: half (−6 dB).
    static let factor = 0.5

    public private(set) var isActive = false
    /// The apps in the call, which aren't ducked.
    public private(set) var callApps: Set<String> = []
    private var callSince: Date?
    private var quietSince: Date?

    public init() {}

    mutating func update(callApps current: Set<String>, enabled: Bool, at now: Date) {
        guard enabled else {
            self = SoundDucking()
            return
        }
        if current.isEmpty {
            callSince = nil
            guard isActive else { return }
            let since = quietSince ?? now
            quietSince = since
            if now.timeIntervalSince(since) >= Self.endDelay {
                isActive = false
                callApps = []
                quietSince = nil
            }
        } else {
            quietSince = nil
            let since = callSince ?? now
            callSince = since
            if !isActive, now.timeIntervalSince(since) >= Self.startDelay { isActive = true }
            if isActive { callApps = current }
        }
    }
}

extension SoundMix {
    /// Whether an app needs a tap now: it's playing and its gain isn't 100%. Apps that are connected to
    /// audio but not playing get none, because each tap costs `coreaudiod` CPU even when it hears nothing.
    public func needsTap(appID: String, isRunningOutput: Bool) -> Bool {
        isRunningOutput && gain(forApp: appID) < 1
    }
}

/// Decides the gain for every app from the user's settings and what audio is doing: per-app volume and
/// mute (by bundle id), ducking during calls, and muting apps that play for the first time.
///
/// "First time" means not seen playing before, while MoniMac was watching audio (the Sound tab was open,
/// or ducking or mute-new-apps was on). Turning "Mute new apps" on counts every app using audio then as seen.
@MainActor
final class SoundPolicy {
    private let preferences: Preferences
    private(set) var ducking = SoundDucking()
    /// The apps in the latest reading.
    private(set) var apps: [SoundApp] = []
    /// The mix last handed to SystemActions; nil until one is.
    var sentMix: SoundMix?

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    /// Takes in a reading (nil when audio isn't being read): remembers apps seen playing, mutes new ones
    /// when asked, and runs ducking.
    func observe(_ reading: SoundReading?, at now: Date) {
        if let reading {
            apps = SoundApps.group(reading.processes)
            recordNewlyPlaying()
        }
        let inCall = Set((reading == nil ? [] : apps).filter(\.isInCall).map(\.id))
        ducking.update(callApps: inCall, enabled: preferences.soundDuckDuringCalls, at: now)
    }

    private func recordNewlyPlaying() {
        var seen = preferences.soundSeenApps
        let newlyPlaying = apps.filter { $0.isRunningOutput && !seen.contains($0.id) }.map(\.id)
        guard !newlyPlaying.isEmpty else { return }
        seen.formUnion(newlyPlaying)
        preferences.soundSeenApps = seen
        guard preferences.soundMuteNewApps else { return }
        var settings = preferences.soundAppSettings
        for id in newlyPlaying where settings[id] == nil { settings[id] = SoundAppSetting(muted: true) }
        preferences.setSoundAppSettings(settings)
    }

    /// Turning "Mute new apps" on leaves alone every app using audio now.
    func markCurrentAppsSeen() {
        preferences.soundSeenApps = preferences.soundSeenApps.union(apps.map(\.id))
    }

    /// The gains to apply now.
    var mix: SoundMix {
        let settings = preferences.soundAppSettings
        let ducked = ducking.isActive ? Set(apps.map(\.id)).subtracting(ducking.callApps) : []
        var gains: [SoundTarget: Double] = [:]
        for id in Set(settings.keys).union(ducked) {
            let setting = settings[id] ?? SoundAppSetting()
            var gain = setting.muted ? 0 : min(max(setting.volume, 0), 1)
            if ducked.contains(id) { gain *= SoundDucking.factor }
            if gain < 1 { gains[.app(id)] = gain }
        }
        guard preferences.soundMuteNewApps else { return SoundMix(gains: gains) }
        return SoundMix(gains: gains, newAppGain: 0, knownApps: preferences.soundSeenApps.union(settings.keys))
    }
}
