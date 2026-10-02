import Foundation

/// An app using audio, its Core Audio processes rolled up.
public struct SoundApp: Equatable, Sendable, Identifiable {
    /// The bundle id.
    public var id: String
    public var name: String
    /// The app bundle, for its icon.
    public var path: String?
    /// Any of its processes is sending audio to an output device.
    public var isRunningOutput: Bool
    /// Any of its processes is recording.
    public var isRunningInput: Bool

    /// Playing and recording at once, as a call does. Both must be the same app's: macOS's own speech
    /// services record on their own, and dictation alone isn't a call.
    public var isInCall: Bool { isRunningOutput && isRunningInput }
}

/// What the Per-App Volume list says about an app.
public enum SoundAppState: Equatable, Sendable {
    case playing
    /// Connected to audio but not playing, or playing nothing audible.
    case silent
    /// Muted by the user, or by "Mute new apps by default".
    case muted
}

enum SoundApps {
    /// A tapped app quieter than this (dBFS) is playing silence, e.g. a paused video that keeps its stream open.
    static let audibleLevel = -60.0

    /// Groups processes into apps, by name (then bundle id), so rows don't jump around while playing.
    static func group(_ processes: [SoundProcess]) -> [SoundApp] {
        var apps: [String: SoundApp] = [:]
        for process in processes {
            var app = apps[process.appID] ?? SoundApp(
                id: process.appID, name: process.appName, path: process.appPath, isRunningOutput: false,
                isRunningInput: false
            )
            app.isRunningOutput = app.isRunningOutput || process.isRunningOutput
            app.isRunningInput = app.isRunningInput || process.isRunningInput
            if app.path == nil { app.path = process.appPath }
            apps[process.appID] = app
        }
        return apps.values.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    /// Muted wins; otherwise an app is playing while it sends output, unless its tap hears only silence.
    static func state(of app: SoundApp, setting: SoundAppSetting?, tap: SoundTap?) -> SoundAppState {
        if setting?.muted == true { return .muted }
        guard app.isRunningOutput else { return .silent }
        if let level = tap?.level, level < audibleLevel { return .silent }
        return .playing
    }

    /// e.g. "3 apps playing · 2 silent · 1 muted", "Nothing playing · 2 silent", "No apps using audio".
    static func summary(_ states: [SoundAppState]) -> String {
        guard !states.isEmpty else { return "No apps using audio" }
        let playing = states.filter { $0 == .playing }.count
        let silent = states.filter { $0 == .silent }.count
        let muted = states.filter { $0 == .muted }.count
        var parts = [playing == 0 ? "Nothing playing" : "\(playing) app\(playing == 1 ? "" : "s") playing"]
        if silent > 0 { parts.append("\(silent) silent") }
        if muted > 0 { parts.append("\(muted) muted") }
        return parts.joined(separator: " · ")
    }
}
