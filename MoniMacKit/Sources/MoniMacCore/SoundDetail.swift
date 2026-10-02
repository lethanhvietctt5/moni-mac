import Foundation

/// The Sound tab: the output device and system volume, the Per-App Volume list, and the ducking and
/// mute-new-apps switches.
public struct SoundDetail: Equatable, Sendable {
    public struct Output: Equatable, Sendable {
        /// e.g. "MacBook Pro Speakers".
        public var name: String
        public var kind: SoundDevice.Kind
        /// e.g. "Output · 48 kHz · System volume".
        public var detail: String
        /// 0...1, or nil when the device has no software volume (no slider then).
        public var volume: Double?
        /// e.g. "68%".
        public var volumeText: String
    }

    /// An entry of the output device switcher.
    public struct DeviceChoice: Equatable, Sendable, Identifiable {
        public var uid: String
        public var name: String
        public var isCurrent: Bool
        public var id: String { uid }
    }

    /// A row of the Per-App Volume list.
    public struct Row: Equatable, Sendable, Identifiable {
        /// The bundle id.
        public var id: String
        public var name: String
        /// The app bundle, for its icon.
        public var path: String?
        public var state: SoundAppState
        /// "Playing", "Silent", or "Muted".
        public var stateText: String
        /// The user's volume for the app, 0...1, whether or not it's muted.
        public var volume: Double
        /// e.g. "82%", or "—" while muted.
        public var volumeText: String
        public var isMuted: Bool
        /// Lowered for a call right now.
        public var isDucked: Bool
        /// e.g. "Lowered 50% during the call".
        public var help: String?
    }

    /// What the Per-App Volume list says about the audio capture permission.
    public enum Notice: Equatable, Sendable {
        /// Before the first use: what will happen and why macOS will ask.
        case explain(String)
        /// A tap is starting; macOS may be asking.
        case checking(String)
        /// A tap couldn't start.
        case problem(String)
        /// Taps hear only silence: the controls are off until MoniMac is reopened or the user tries again.
        case notWorking(title: String, text: String)
    }

    /// e.g. "3 apps playing · 2 silent · 1 muted".
    public var summary: String
    public var output: Output?
    public var devices: [DeviceChoice]
    public var rows: [Row]
    /// Why there are no rows (or no output) to show; nil when the list shows normally.
    public var message: String?
    public var notice: Notice?
    /// The per-app sliders and mute buttons can be used.
    public var controlsEnabled: Bool
    /// "Reset All to 100%" has something to reset.
    public var canReset: Bool
    public var duck: Bool
    public var muteNewApps: Bool
    /// Other apps are lowered for a call right now.
    public var isDucking: Bool

    /// While per-app volume isn't working, the switches can be turned off but not on.
    public var duckEnabled: Bool { controlsEnabled || duck }
    public var muteNewEnabled: Bool { controlsEnabled || muteNewApps }

    public static let duckTitle = "Duck background apps"
    public static let duckDescription = "Lower other apps by \(SoundDucking.reductionText) while a call is active"
    public static let muteNewTitle = "Mute new apps by default"
    public static let muteNewDescription = "Apps that start playing for the first time stay muted"
    public static let appsTitle = "Per-App Volume"
    public static let resetTitle = "Reset All to 100%"
    /// System Settings › Privacy & Security › Screen & System Audio Recording, where the audio capture
    /// permission is granted.
    public static let privacySettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    static let explanation = """
        MoniMac changes an app's volume by routing its audio through MoniMac. The first time, macOS asks to \
        let MoniMac record system audio; nothing is recorded or saved.
        """
    static let checkingText = "If macOS asks to let MoniMac record system audio, choose Allow."
    static let notWorkingTitle = "Per-app volume needs System Audio Recording access"
    static let notWorkingText = """
        MoniMac heard only silence from the apps it adjusts, so it stopped adjusting them and they play as \
        usual. Allow MoniMac in System Settings › Privacy & Security › Screen & System Audio Recording, \
        then reopen MoniMac.
        """

    static func make(reading: Reading<SoundReading>, settings: [String: SoundAppSetting], ducking: SoundDucking,
                     duck: Bool, muteNewApps: Bool, perAppUsed: Bool) -> SoundDetail {
        guard let sound = reading.value else {
            let message = switch reading {
            case .unavailable(.failed(let reason)): "Audio couldn't be read: \(reason)"
            default: "Reading audio…"
            }
            return SoundDetail(
                summary: "", output: nil, devices: [], rows: [], message: message, notice: nil,
                controlsEnabled: false, canReset: !settings.isEmpty, duck: duck, muteNewApps: muteNewApps,
                isDucking: false
            )
        }
        let apps = SoundApps.group(sound.processes)
        let ducked = ducking.duckedApps(among: apps)
        let rows = apps.map { app in
            row(app, setting: settings[app.id], tap: sound.taps[app.id], isDucked: ducked.contains(app.id))
        }
        var summary = SoundApps.summary(rows.map(\.state))
        if ducking.isActive { summary += " · Others lowered for a call" }
        return SoundDetail(
            summary: summary,
            output: sound.output.map(output),
            devices: sound.devices.map { DeviceChoice(uid: $0.uid, name: $0.name, isCurrent: $0.uid == sound.output?.uid) },
            rows: rows,
            message: sound.output == nil ? "No output device" : (rows.isEmpty ? "No apps are using audio" : nil),
            notice: sound.tapProblem.map(Notice.problem) ?? notice(sound.access, perAppUsed: perAppUsed),
            controlsEnabled: sound.access != .notWorking,
            canReset: !settings.isEmpty,
            duck: duck,
            muteNewApps: muteNewApps,
            isDucking: ducking.isActive
        )
    }

    private static func row(_ app: SoundApp, setting: SoundAppSetting?, tap: SoundTap?, isDucked: Bool) -> Row {
        let state = SoundApps.state(of: app, setting: setting, tap: tap)
        let volume = min(max(setting?.volume ?? 1, 0), 1)
        let muted = setting?.muted == true
        let stateText = switch state {
        case .playing: "Playing"
        case .silent: "Silent"
        case .muted: "Muted"
        }
        return Row(
            id: app.id, name: app.name, path: app.path, state: state, stateText: stateText,
            volume: volume, volumeText: muted ? "—" : Format.percent(volume), isMuted: muted,
            isDucked: isDucked && !muted, help: isDucked && !muted ? "Lowered \(SoundDucking.reductionText) during the call" : nil
        )
    }

    private static func output(_ device: SoundDevice) -> Output {
        let rate = device.sampleRate.map(sampleRate)
        let volume = device.volume.map { min(max($0, 0), 1) }
        let detail = ["Output", rate, volume == nil ? "Volume set on the device" : "System volume"]
            .compactMap { $0 }.joined(separator: " · ")
        return Output(name: device.name, kind: device.kind, detail: detail, volume: volume,
                      volumeText: volume.map(Format.percent) ?? "—")
    }

    /// 48000 → "48 kHz", 44100 → "44.1 kHz".
    static func sampleRate(_ hertz: Double) -> String {
        let kilohertz = (hertz / 100).rounded() / 10
        let text = kilohertz == kilohertz.rounded() ? String(Int(kilohertz)) : String(format: "%.1f", kilohertz)
        return "\(text) kHz"
    }

    private static func notice(_ access: SoundAccess, perAppUsed: Bool) -> Notice? {
        switch access {
        case .notWorking: .notWorking(title: notWorkingTitle, text: notWorkingText)
        case .checking: .checking(checkingText)
        case .unused, .working: perAppUsed ? nil : .explain(explanation)
        }
    }
}
