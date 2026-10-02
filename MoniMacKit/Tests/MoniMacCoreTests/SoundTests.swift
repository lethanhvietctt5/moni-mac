import Foundation
import Testing
@testable import MoniMacCore

/// A sampler whose Sound reading the test sets.
@MainActor
private final class SoundSampler: SystemSampler {
    let clock: TestClock
    var reading: Reading<SoundReading> = .unavailable(.unsupported)

    init(clock: TestClock) {
        self.clock = clock
    }

    func set(_ processes: [SoundProcess], output: SoundDevice? = speakers, devices: [SoundDevice] = [speakers, headphones],
             taps: [String: SoundTap] = [:], access: SoundAccess = .unused) {
        reading = .value(SoundReading(output: output, devices: devices, processes: processes, taps: taps, access: access))
    }

    func sample() -> Snapshot {
        Snapshot(timestamp: clock.now, cpu: .cpu(user: 0.1, system: 0.1), sound: reading)
    }
}

private let speakers = SoundDevice(uid: "BuiltInSpeakerDevice", name: "MacBook Pro Speakers", kind: .builtIn,
                                   sampleRate: 48000, volume: 0.68)
private let headphones = SoundDevice(uid: "AA-BB-CC:output", name: "AirPods Pro", kind: .bluetooth,
                                     sampleRate: 44100, volume: 0.5)

private func app(_ name: String, _ id: String, pid: Int32, playing: Bool = false, recording: Bool = false) -> SoundProcess {
    SoundProcess(pid: pid, appID: id, appName: name, appPath: "/Applications/\(name).app", isRunningOutput: playing,
                 isRunningInput: recording)
}

private let spotify = "com.spotify.client"
private let chrome = "com.google.Chrome"
private let zoom = "us.zoom.xos"
private let music = "com.apple.Music"
private let slack = "com.tinyspeck.slackmacgap"
private let safari = "com.apple.Safari"

@MainActor
struct SoundTests {
    let clock = TestClock()
    let defaults = UserDefaults(suiteName: "monimac-tests-\(UUID().uuidString)")!
    let actions = RecordingActions()

    private func makeMonitor() throws -> (Monitor, SoundSampler) {
        let sampler = SoundSampler(clock: clock)
        let monitor = Monitor(sampler: sampler, history: try MetricsHistory(.inMemory),
                              preferences: Preferences(defaults: defaults), actions: actions)
        return (monitor, sampler)
    }

    /// The design's list: three playing, two silent, one muted.
    private func designApps() -> [SoundProcess] {
        [
            app("Spotify", spotify, pid: 10, playing: true),
            app("Google Chrome", chrome, pid: 11, playing: true),
            app("Zoom", zoom, pid: 12, playing: true),
            app("Music", music, pid: 13),
            app("Slack", slack, pid: 14, playing: true),
            app("Safari", safari, pid: 15),
        ]
    }

    // MARK: Activity

    @Test func summarizesPlayingSilentAndMutedApps() throws {
        let (monitor, sampler) = try makeMonitor()
        monitor.toggleSoundAppMute(slack)
        sampler.set(designApps())
        monitor.tick()

        #expect(monitor.soundSubtitle == "3 apps playing · 2 silent · 1 muted")
        let rows = monitor.soundDetail.rows
        #expect(rows.map(\.name) == ["Google Chrome", "Music", "Safari", "Slack", "Spotify", "Zoom"])
        #expect(rows.first { $0.id == slack }?.stateText == "Muted")
        #expect(rows.first { $0.id == slack }?.volumeText == "—")
        #expect(rows.first { $0.id == music }?.stateText == "Silent")
        #expect(rows.first { $0.id == spotify }?.stateText == "Playing")
    }

    @Test func summarizesNothingPlayingAndNoApps() {
        #expect(SoundApps.summary([]) == "No apps using audio")
        #expect(SoundApps.summary([.silent, .silent]) == "Nothing playing · 2 silent")
        #expect(SoundApps.summary([.playing]) == "1 app playing")
    }

    @Test func rollsHelperProcessesUpIntoTheirApp() {
        let apps = SoundApps.group([
            app("Safari", safari, pid: 20),
            app("Safari", safari, pid: 21, playing: true),
            app("Safari", safari, pid: 22, recording: true),
        ])
        #expect(apps.count == 1)
        #expect(apps[0].isRunningOutput)
        #expect(apps[0].isInCall)
    }

    @Test func aTappedAppPlayingSilenceIsSilent() {
        let playing = SoundApp(id: chrome, name: "Chrome", path: nil, isRunningOutput: true, isRunningInput: false)
        #expect(SoundApps.state(of: playing, setting: nil, tap: SoundTap(level: -90)) == .silent)
        #expect(SoundApps.state(of: playing, setting: nil, tap: SoundTap(level: -20)) == .playing)
        #expect(SoundApps.state(of: playing, setting: nil, tap: SoundTap(level: nil)) == .playing)
        #expect(SoundApps.state(of: playing, setting: SoundAppSetting(volume: 0.5, muted: true), tap: nil) == .muted)
    }

    // MARK: Output

    @Test func showsTheOutputDeviceWithSampleRateAndVolume() throws {
        let (monitor, sampler) = try makeMonitor()
        sampler.set([])
        monitor.tick()

        let detail = monitor.soundDetail
        #expect(detail.output?.name == "MacBook Pro Speakers")
        #expect(detail.output?.detail == "Output · 48 kHz · System volume")
        #expect(detail.output?.volumeText == "68%")
        #expect(detail.devices.map(\.name) == ["MacBook Pro Speakers", "AirPods Pro"])
        #expect(detail.devices.map(\.isCurrent) == [true, false])
        #expect(detail.message == "No apps are using audio")
        #expect(SoundDetail.sampleRate(44100) == "44.1 kHz")
        #expect(SoundDetail.sampleRate(96000) == "96 kHz")
    }

    @Test func aDeviceWithoutSoftwareVolumeHasNoSlider() throws {
        let (monitor, sampler) = try makeMonitor()
        let display = SoundDevice(uid: "display", name: "LG IPS QHD", kind: .display, sampleRate: 48000, volume: nil)
        sampler.set([], output: display, devices: [display])
        monitor.tick()

        #expect(monitor.soundDetail.output?.volume == nil)
        #expect(monitor.soundDetail.output?.detail == "Output · 48 kHz · Volume set on the device")
    }

    @Test func switchingOutputAndSettingVolumeGoThroughSystemActions() throws {
        let (monitor, _) = try makeMonitor()
        monitor.setOutputDevice(uid: headphones.uid)
        monitor.setSystemVolume(0.4)
        monitor.setSystemVolume(1.3)

        #expect(actions.recorded == [.setOutputDevice(uid: "AA-BB-CC:output"), .setSystemVolume(0.4), .setSystemVolume(1)])
    }

    // MARK: Per-app volume

    @Test func nothingAdjustedSendsNoMixAndReadsNoAudio() throws {
        let (monitor, sampler) = try makeMonitor()
        sampler.set(designApps())
        monitor.tick()
        monitor.tick()

        #expect(actions.soundMixes.isEmpty)
        #expect(monitor.soundDemand(isTabShowing: false) == .none)
        #expect(monitor.soundDemand(isTabShowing: true) == .active)
    }

    @Test func aSliderOrMuteSetsThatAppsGain() throws {
        let (monitor, sampler) = try makeMonitor()
        sampler.set(designApps())
        monitor.tick()

        monitor.setSoundAppVolume(0.82, for: spotify)
        monitor.toggleSoundAppMute(slack)

        #expect(actions.soundMixes == [
            SoundMix(gains: [.app(spotify): 0.82]),
            SoundMix(gains: [.app(spotify): 0.82, .app(slack): 0]),
        ])
        let rows = monitor.soundDetail.rows
        #expect(rows.first { $0.id == spotify }?.volumeText == "82%")
        #expect(rows.first { $0.id == slack }?.isMuted == true)

        // Moving a muted app's slider unmutes it.
        monitor.setSoundAppVolume(0.4, for: slack)
        #expect(actions.soundMixes.last == SoundMix(gains: [.app(spotify): 0.82, .app(slack): 0.4]))
    }

    @Test func onlyPlayingAppsBelowFullVolumeNeedATap() {
        let mix = SoundMix(gains: [.app(spotify): 0.5, .app(slack): 0])
        #expect(mix.needsTap(appID: spotify, isRunningOutput: true))
        #expect(!mix.needsTap(appID: spotify, isRunningOutput: false))
        #expect(mix.needsTap(appID: slack, isRunningOutput: true))
        #expect(!mix.needsTap(appID: chrome, isRunningOutput: true))
        #expect(SoundMix().isEmpty)
        #expect(!mix.isEmpty)
    }

    @Test func settingsPersistByBundleIDAcrossRelaunches() throws {
        let (monitor, sampler) = try makeMonitor()
        sampler.set(designApps())
        monitor.tick()
        monitor.setSoundAppVolume(0.54, for: chrome)
        monitor.toggleSoundAppMute(slack)

        let relaunched = RecordingActions()
        let again = Monitor(sampler: SoundSampler(clock: clock), history: try MetricsHistory(.inMemory),
                            preferences: Preferences(defaults: defaults), actions: relaunched)

        // The adjusted apps get their gains at launch, before any reading.
        #expect(relaunched.soundMixes == [SoundMix(gains: [.app(chrome): 0.54, .app(slack): 0])])
        #expect(again.soundDetail.canReset)
    }

    @Test func backAtFullVolumeAnAppHasNoSettingAndNoTap() throws {
        let (monitor, _) = try makeMonitor()
        monitor.setSoundAppVolume(0.5, for: spotify)
        monitor.setSoundAppVolume(1, for: spotify)

        #expect(actions.soundMixes.last == SoundMix())
        #expect(defaults.object(forKey: "sound.apps") == nil)
    }

    @Test func resetAllPutsEveryAppBackAtFullVolume() throws {
        let (monitor, sampler) = try makeMonitor()
        sampler.set(designApps())
        monitor.tick()
        monitor.setSoundAppVolume(0.3, for: spotify)
        monitor.toggleSoundAppMute(slack)
        #expect(monitor.soundDetail.canReset)

        monitor.resetSoundApps()

        #expect(actions.soundMixes.last == SoundMix())
        #expect(!monitor.soundDetail.canReset)
        #expect(monitor.soundDetail.rows.allSatisfy { $0.volume == 1 && !$0.isMuted })
    }

    // MARK: Ducking

    @Test func duckingLowersOtherAppsDuringACallAndRestoresThemAfter() throws {
        let (monitor, sampler) = try makeMonitor()
        monitor.setSoundAppVolume(0.8, for: spotify)
        monitor.setSoundDuckDuringCalls(true)
        #expect(monitor.soundDemand(isTabShowing: false) == .active)
        let quiet = [app("Spotify", spotify, pid: 10, playing: true), app("Zoom", zoom, pid: 12),
                     app("Music", music, pid: 13, playing: true)]
        let call = [app("Spotify", spotify, pid: 10, playing: true), app("Zoom", zoom, pid: 12, playing: true, recording: true),
                    app("Music", music, pid: 13, playing: true)]

        sampler.set(quiet)
        monitor.tick()
        #expect(actions.soundMixes.last == SoundMix(gains: [.app(spotify): 0.8]))

        // The call must last 2 s before others are lowered.
        sampler.set(call)
        monitor.tick()
        clock.advance(by: 1)
        monitor.tick()
        #expect(actions.soundMixes.last == SoundMix(gains: [.app(spotify): 0.8]))
        clock.advance(by: 1)
        monitor.tick()
        #expect(actions.soundMixes.last == SoundMix(gains: [.app(spotify): 0.4, .app(music): 0.5]))
        #expect(monitor.soundDetail.isDucking)
        #expect(monitor.soundDetail.rows.first { $0.id == music }?.isDucked == true)
        #expect(monitor.soundDetail.rows.first { $0.id == zoom }?.isDucked == false)
        #expect(monitor.soundSubtitle?.hasSuffix("Others lowered for a call") == true)

        // It ends 2 s after the call does, and levels come back.
        sampler.set(quiet)
        clock.advance(by: 2)
        monitor.tick()
        #expect(monitor.soundDetail.isDucking)
        clock.advance(by: 2)
        monitor.tick()
        #expect(!monitor.soundDetail.isDucking)
        #expect(actions.soundMixes.last == SoundMix(gains: [.app(spotify): 0.8]))
    }

    @Test func recordingWithoutPlayingIsNotACall() throws {
        let (monitor, sampler) = try makeMonitor()
        monitor.setSoundDuckDuringCalls(true)
        sampler.set([app("Voice Memos", "com.apple.VoiceMemos", pid: 30, recording: true),
                     app("Music", music, pid: 13, playing: true)])
        monitor.tick()
        clock.advance(by: 5)
        monitor.tick()

        #expect(!monitor.soundDetail.isDucking)
        #expect(actions.soundMixes.isEmpty)
    }

    @Test func turningDuckingOffRestoresAtOnce() throws {
        let (monitor, sampler) = try makeMonitor()
        monitor.setSoundDuckDuringCalls(true)
        sampler.set([app("Zoom", zoom, pid: 12, playing: true, recording: true), app("Music", music, pid: 13, playing: true)])
        monitor.tick()
        clock.advance(by: 2)
        monitor.tick()
        #expect(actions.soundMixes.last == SoundMix(gains: [.app(music): 0.5]))

        monitor.setSoundDuckDuringCalls(false)
        #expect(actions.soundMixes.last == SoundMix())
    }

    // MARK: Mute new apps

    @Test func newAppsThatStartPlayingStayMuted() throws {
        let (monitor, sampler) = try makeMonitor()
        sampler.set([app("Spotify", spotify, pid: 10, playing: true), app("Slack", slack, pid: 14)])
        monitor.tick()

        monitor.setSoundMuteNewApps(true)
        // Apps using audio when it's turned on are left alone, even ones not playing yet.
        #expect(actions.soundMixes.last == SoundMix(newAppGain: 0, knownApps: [spotify, slack]))

        sampler.set([app("Spotify", spotify, pid: 10, playing: true), app("Slack", slack, pid: 14, playing: true),
                     app("Music", music, pid: 13, playing: true)])
        monitor.tick()

        #expect(actions.soundMixes.last == SoundMix(gains: [.app(music): 0], newAppGain: 0,
                                                    knownApps: [spotify, slack, music]))
        #expect(monitor.soundDetail.rows.first { $0.id == music }?.state == .muted)
        #expect(monitor.soundDetail.rows.first { $0.id == slack }?.state == .playing)

        // Unmuting it sticks: it's no longer new.
        monitor.toggleSoundAppMute(music)
        monitor.tick()
        #expect(monitor.soundDetail.rows.first { $0.id == music }?.state == .playing)
    }

    @Test func appsSeenPlayingBeforeAreNotNew() throws {
        let (monitor, sampler) = try makeMonitor()
        sampler.set([app("Music", music, pid: 13, playing: true)])
        monitor.tick()
        sampler.set([])
        monitor.tick()

        monitor.setSoundMuteNewApps(true)
        sampler.set([app("Music", music, pid: 13, playing: true)])
        monitor.tick()

        #expect(monitor.soundDetail.rows.first?.state == .playing)
        #expect(SoundMix(newAppGain: 0, knownApps: [music]).gain(forApp: music) == 1)
        #expect(SoundMix(newAppGain: 0, knownApps: [music]).gain(forApp: spotify) == 0)
    }

    // MARK: Permission

    @Test func explainsThePermissionUntilFirstUse() throws {
        let (monitor, sampler) = try makeMonitor()
        sampler.set(designApps())
        monitor.tick()
        guard case .explain(let text) = monitor.soundDetail.notice else {
            Issue.record("Expected the explanation")
            return
        }
        #expect(text.contains("nothing is recorded or saved"))
        #expect(monitor.soundDetail.controlsEnabled)

        monitor.setSoundAppVolume(0.5, for: spotify)
        #expect(monitor.soundDetail.notice == nil)
    }

    @Test func silentTapsTurnTheControlsOffAndSaySo() throws {
        let (monitor, sampler) = try makeMonitor()
        monitor.setSoundAppVolume(0.5, for: spotify)
        sampler.set(designApps(), access: .checking)
        monitor.tick()
        guard case .checking = monitor.soundDetail.notice else {
            Issue.record("Expected the checking notice")
            return
        }

        sampler.set(designApps(), access: .notWorking)
        monitor.tick()
        guard case .notWorking(let title, _) = monitor.soundDetail.notice else {
            Issue.record("Expected the not-working notice")
            return
        }
        #expect(title == "Per-app volume needs System Audio Recording access")
        #expect(!monitor.soundDetail.controlsEnabled)
        #expect(!monitor.soundDetail.duckEnabled && !monitor.soundDetail.muteNewEnabled)
        monitor.setSoundMuteNewApps(true)
        #expect(monitor.soundDetail.muteNewEnabled)

        monitor.openSoundPrivacySettings()
        monitor.retrySoundAccess()
        #expect(actions.recorded.suffix(2) == [.openURL(SoundDetail.privacySettingsURL), .retrySoundAccess])
    }

    @Test func saysWhenATapCouldNotStart() throws {
        let (monitor, sampler) = try makeMonitor()
        monitor.setSoundAppVolume(0.5, for: spotify)
        sampler.reading = .value(SoundReading(output: speakers, processes: designApps(), access: .unused,
                                              tapProblem: "Per-app volume can't run on this output device"))
        monitor.tick()
        #expect(monitor.soundDetail.notice == .problem("Per-app volume can't run on this output device"))
    }

    // MARK: Bluetooth

    @Test func bluetoothHeadphonesSayWhichAppsPlayToThem() {
        let airPods = BluetoothDevice(address: "AA:BB:CC:DD:EE:FF", name: "Maya's AirPods Pro", minorType: "Headphones",
                                      isConnected: true)
        let output = SoundDevice(uid: "AA-BB-CC-DD-EE-FF:output", name: "Maya's AirPods Pro", kind: .bluetooth)
        func source(_ processes: [SoundProcess], output: SoundDevice? = output) -> String {
            BluetoothDetail.source(for: airPods, audio: SoundReading(output: output, processes: processes)).text
        }

        #expect(source([app("Spotify", spotify, pid: 10, playing: true), app("Slack", slack, pid: 14)])
            == "Playing from Spotify")
        #expect(source([app("Spotify", spotify, pid: 10, playing: true), app("Zoom", zoom, pid: 12, playing: true),
                        app("Music", music, pid: 13, playing: true)]) == "Playing from Music and 2 more")
        #expect(source([app("Slack", slack, pid: 14)]) == "Nothing playing")
        #expect(source([], output: speakers) == "Not the current output")
        #expect(!BluetoothDetail.source(for: airPods, audio: nil).isKnown)
    }

    @Test func showsWhyNothingIsListedBeforeTheFirstReading() throws {
        let (monitor, _) = try makeMonitor()
        monitor.tick()
        #expect(monitor.soundDetail.message == "Reading audio…")
        #expect(monitor.soundSubtitle == nil)
    }
}
