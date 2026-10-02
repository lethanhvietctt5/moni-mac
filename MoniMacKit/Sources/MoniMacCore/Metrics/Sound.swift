import Foundation

// Sound (ticket 17). Sound has no menu bar item, no popover tab, and no history series. The window tab
// renders `SoundDetail` (SoundDetail.swift). Apps are grouped and judged in SoundApps.swift; the desired
// per-app gains (volume, mute, ducking, mute-new-apps) are decided in SoundPolicy.swift and handed to
// `SystemActions.setSoundMix`, whose real implementation runs Core Audio process taps (MoniMacSystem).
//
// Nothing about audio is read unless something needs it (`SoundDemand`), and no tap runs unless an
// app's gain isn't 100%: each tap costs `coreaudiod` about 3% CPU (docs/spikes/16-per-app-audio.md).

/// What SystemSampler read about audio output. Kept current by Core Audio listeners while something
/// needs it; the same reading repeats until something changes.
public struct SoundReading: Equatable, Sendable {
    /// The default output device, or nil when there is none.
    public var output: SoundDevice?
    /// Every device that can play sound, in the order Core Audio lists them. MoniMac's own devices are left out.
    public var devices: [SoundDevice]
    /// Audio clients that belong to an app the user would recognize, one per Core Audio process object.
    /// MoniMac itself and macOS's background services are left out.
    public var processes: [SoundProcess]
    /// The input level of each app MoniMac currently taps, keyed by `SoundProcess.appID`.
    public var taps: [String: SoundTap]
    /// Whether per-app volume can work: the audio capture permission has no API, so this is judged from
    /// what the taps deliver.
    public var access: SoundAccess
    /// Why the last tap couldn't start (e.g. the output device's microphone couldn't be kept out of it);
    /// nil once one does.
    public var tapProblem: String?

    public init(output: SoundDevice?, devices: [SoundDevice] = [], processes: [SoundProcess] = [],
                taps: [String: SoundTap] = [:], access: SoundAccess = .unused, tapProblem: String? = nil) {
        self.output = output
        self.devices = devices
        self.processes = processes
        self.taps = taps
        self.access = access
        self.tapProblem = tapProblem
    }
}

/// An output device.
public struct SoundDevice: Equatable, Sendable, Identifiable {
    /// Core Audio's persistent UID, e.g. "BuiltInSpeakerDevice".
    public var uid: String
    public var name: String
    public var kind: Kind
    /// Nominal sample rate in Hz, e.g. 48000; nil when not reported.
    public var sampleRate: Double?
    /// The system volume on this device, 0...1; nil when it has no software volume (e.g. some HDMI displays).
    public var volume: Double?

    public enum Kind: Equatable, Sendable {
        case builtIn, bluetooth, usb, display, airPlay, virtual, other
    }

    public init(uid: String, name: String, kind: Kind = .other, sampleRate: Double? = nil, volume: Double? = nil) {
        self.uid = uid
        self.name = name
        self.kind = kind
        self.sampleRate = sampleRate
        self.volume = volume
    }

    public var id: String { uid }
}

/// One Core Audio client process, attributed to the app responsible for it (a browser's audio helper
/// counts toward the browser).
public struct SoundProcess: Equatable, Sendable {
    public var pid: Int32
    /// The app's bundle id, e.g. "com.spotify.client". Per-app settings are keyed by it.
    public var appID: String
    /// e.g. "Spotify".
    public var appName: String
    /// The app's bundle, for its icon.
    public var appPath: String?
    /// Sending audio to an output device right now. Stays on while MoniMac mutes the app.
    public var isRunningOutput: Bool
    /// Recording from an input device right now.
    public var isRunningInput: Bool

    public init(pid: Int32, appID: String, appName: String, appPath: String? = nil, isRunningOutput: Bool,
                isRunningInput: Bool = false) {
        self.pid = pid
        self.appID = appID
        self.appName = appName
        self.appPath = appPath
        self.isRunningOutput = isRunningOutput
        self.isRunningInput = isRunningInput
    }
}

/// What a running tap hears from its app, before MoniMac's gain.
public struct SoundTap: Equatable, Sendable {
    /// Recent peak of the app's own output, in dBFS; nil until the tap delivers audio.
    public var level: Double?

    public init(level: Double?) {
        self.level = level
    }
}

/// Whether per-app volume works. macOS has no API to read or request the audio capture permission:
/// the first tap asks, and a denied tap delivers silence rather than an error.
public enum SoundAccess: Equatable, Sendable {
    /// No tap has run this session.
    case unused
    /// A tap is running but hasn't delivered sound yet (the permission prompt may be up).
    case checking
    /// A tap has delivered sound, so the permission was granted.
    case working
    /// Taps delivered only silence while their apps were playing: the permission was denied, or taps
    /// don't work here. Every tap was stopped so apps are heard as usual.
    case notWorking
}

/// Who an app's gain applies to in a `SoundMix`.
public enum SoundTarget: Hashable, Sendable {
    /// Every audio process of the app with this bundle id. The only target Monitor uses.
    case app(String)
    /// One process, for the `--sound-selftest` development flag, which adjusts only tones it started.
    case process(Int32)
}

/// The per-app gains MoniMac wants applied: what `SystemActions.setSoundMix` puts into effect.
/// A target missing from `gains` plays at 100% and gets no tap.
public struct SoundMix: Equatable, Sendable {
    /// Gain 0...1 per target; only targets below 1. 0 is muted.
    public var gains: [SoundTarget: Double]
    /// The gain for an app that starts playing and is neither in `gains` nor in `knownApps`: 0 while
    /// "Mute new apps by default" is on, otherwise 1. Applied as soon as the app starts playing, before
    /// Monitor's next tick records it as muted.
    public var newAppGain: Double
    /// Apps that aren't new (bundle ids). Empty while new apps aren't muted.
    public var knownApps: Set<String>

    public init(gains: [SoundTarget: Double] = [:], newAppGain: Double = 1, knownApps: Set<String> = []) {
        self.gains = gains
        self.newAppGain = newAppGain
        self.knownApps = knownApps
    }

    /// Nothing to change: no tap needs to run, and nothing needs watching for.
    public var isEmpty: Bool { gains.isEmpty && newAppGain >= 1 }

    /// The gain for an app that is playing.
    public func gain(forApp appID: String) -> Double {
        if let gain = gains[.app(appID)] { return gain }
        return knownApps.contains(appID) ? 1 : newAppGain
    }
}

/// Whether audio needs reading, decided by what uses it.
public enum SoundDemand: Equatable, Sendable {
    /// Nothing: the Sound tab isn't showing and neither ducking nor mute-new-apps is on.
    case none
    /// Keep the reading current (by listeners, not polling).
    case active
}

// MARK: Settings

/// One app's volume setting, persisted by bundle id.
public struct SoundAppSetting: Equatable, Sendable, Codable {
    /// 0...1.
    public var volume: Double
    public var muted: Bool

    public init(volume: Double = 1, muted: Bool = false) {
        self.volume = volume
        self.muted = muted
    }

    /// At 100% and not muted: the same as having no setting.
    public var isDefault: Bool { volume >= 1 && !muted }
}

extension Preferences {
    /// Per-app volume and mute, keyed by bundle id. Only apps that differ from 100% are kept.
    public var soundAppSettings: [String: SoundAppSetting] {
        guard let data = defaults.data(forKey: "sound.apps") else { return [:] }
        return (try? JSONDecoder().decode([String: SoundAppSetting].self, from: data)) ?? [:]
    }

    func setSoundAppSettings(_ settings: [String: SoundAppSetting]) {
        let kept = settings.filter { !$0.value.isDefault }
        set(kept.isEmpty ? nil : try? JSONEncoder().encode(kept), forKey: "sound.apps")
    }

    /// "Duck background apps": lower other apps by 50% while a call is active. Off by default.
    public var soundDuckDuringCalls: Bool {
        get { defaults.bool(forKey: "sound.duck") }
        set { set(newValue ? true : nil, forKey: "sound.duck") }
    }

    /// "Mute new apps by default": apps that start playing for the first time stay muted. Off by default.
    public var soundMuteNewApps: Bool {
        get { defaults.bool(forKey: "sound.muteNewApps") }
        set { set(newValue ? true : nil, forKey: "sound.muteNewApps") }
    }

    /// Whether the user has used a per-app control, after which the explanation of the permission prompt
    /// is no longer shown.
    public var soundPerAppUsed: Bool {
        get { defaults.bool(forKey: "sound.perAppUsed") }
        set { set(newValue ? true : nil, forKey: "sound.perAppUsed") }
    }

    /// Apps seen playing (bundle ids), so "Mute new apps" knows which are new. Bookkeeping: written
    /// without re-rendering surfaces.
    var soundSeenApps: Set<String> {
        get { Set(defaults.stringArray(forKey: "sound.seenApps") ?? []) }
        set { defaults.set(newValue.sorted(), forKey: "sound.seenApps") }
    }
}

extension Monitor {
    /// The main window toolbar subtitle for the Sound tab, e.g. "3 apps playing · 2 silent · 1 muted".
    public var soundSubtitle: String? {
        let summary = soundDetail.summary
        return summary.isEmpty ? nil : summary
    }

    /// Whether the sampler should read audio: while the tab shows, and while ducking or mute-new-apps
    /// needs to see apps start. Adjusted apps alone need no reading: the taps follow their apps themselves.
    public func soundDemand(isTabShowing: Bool) -> SoundDemand {
        isTabShowing || preferences.soundDuckDuringCalls || preferences.soundMuteNewApps ? .active : .none
    }

    /// The Sound tab.
    public var soundDetail: SoundDetail {
        SoundDetail.make(
            reading: latest?.sound ?? .unavailable(.warmingUp), settings: preferences.soundAppSettings,
            ducking: soundPolicy.ducking, duck: preferences.soundDuckDuringCalls,
            muteNewApps: preferences.soundMuteNewApps, perAppUsed: preferences.soundPerAppUsed
        )
    }

    /// Takes in a new reading, then applies the resulting gains.
    func observeSound(_ snapshot: Snapshot) {
        soundPolicy.observe(snapshot.sound.value, at: snapshot.timestamp)
        applySoundMix()
    }

    /// Hands the gains to SystemActions when they changed. Nothing is sent while there's nothing to
    /// change, so with no app adjusted nothing audio-related runs.
    func applySoundMix() {
        let mix = soundPolicy.mix
        guard mix != (soundPolicy.sentMix ?? SoundMix()) else { return }
        soundPolicy.sentMix = mix
        actions.setSoundMix(mix)
    }

    // MARK: Intents

    /// Sets an app's volume (0...1). Moving the slider unmutes the app. The first per-app change is the
    /// first use of the audio capture permission: macOS asks when the app's tap starts.
    public func setSoundAppVolume(_ volume: Double, for appID: String) {
        updateSoundSetting(appID) { setting in
            setting.volume = min(max(volume, 0), 1)
            setting.muted = false
        }
    }

    public func toggleSoundAppMute(_ appID: String) {
        updateSoundSetting(appID) { $0.muted.toggle() }
    }

    /// "Reset All to 100%": every app back to full volume and unmuted, so no tap runs.
    public func resetSoundApps() {
        preferences.setSoundAppSettings([:])
        applySoundMix()
    }

    public func setSoundDuckDuringCalls(_ enabled: Bool) {
        if enabled { preferences.soundPerAppUsed = true }
        preferences.soundDuckDuringCalls = enabled
        if !enabled { soundPolicy.observe(nil, at: latest?.timestamp ?? Date()) }
        applySoundMix()
    }

    /// Turning it on leaves alone every app using audio now; only apps that start playing later are muted.
    public func setSoundMuteNewApps(_ enabled: Bool) {
        if enabled {
            preferences.soundPerAppUsed = true
            soundPolicy.markCurrentAppsSeen()
        }
        preferences.soundMuteNewApps = enabled
        applySoundMix()
    }

    public func setOutputDevice(uid: String) {
        actions.setOutputDevice(uid: uid)
    }

    public func setSystemVolume(_ volume: Double) {
        actions.setSystemVolume(min(max(volume, 0), 1))
    }

    /// Opens Privacy & Security › Screen & System Audio Recording.
    public func openSoundPrivacySettings() {
        actions.openURL(SoundDetail.privacySettingsURL)
    }

    /// After per-app volume was found not to work: try the taps again.
    public func retrySoundAccess() {
        actions.retrySoundAccess()
    }

    private func updateSoundSetting(_ appID: String, _ change: (inout SoundAppSetting) -> Void) {
        preferences.soundPerAppUsed = true
        var settings = preferences.soundAppSettings
        var setting = settings[appID] ?? SoundAppSetting()
        change(&setting)
        settings[appID] = setting
        preferences.setSoundAppSettings(settings)
        applySoundMix()
    }
}
