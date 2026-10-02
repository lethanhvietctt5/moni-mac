# Spike 16: per-app audio with Core Audio process taps

**Decision: GO.** Per-app volume, mute, ducking, and "mute new apps" all work with Core Audio process taps feeding a MoniMac-owned private aggregate device. They work from an ad-hoc-signed, non-notarized, non-sandboxed build. Two checks are still open: the listening checks and the exact prompt text, both **pending user report**. Neither changes the decision.

| Capability | Result | Evidence |
|---|---|---|
| Per-app volume | **Go** | Gain 0.25 lowered app A by exactly −12.0 dB. App B stayed at −30.5 dBFS (±0.0 dB). |
| Mute | **Go** | Gain 0 produced digital silence on MoniMac's path. The tap's `muteBehavior` suppresses the original stream. Listening check pending. |
| Duck during calls | **Go** for the gain; call detection **not exercised** | Gain 0.5 measured −6.0 dB. Detection is a heuristic over `kAudioProcessPropertyIsRunningInput` (below). It wasn't tried with a real call. |
| Mute new apps by default | **Go**, with a short leak window | A muted pipeline was running 25 ms after the new process started output (98 ms after spawn). Whether that blip is audible is pending user report. |
| Self-signed or ad-hoc, non-notarized | **Go** | Observed with an ad-hoc signature, no notarization, no sandbox. |

The prototype was a throwaway app bundle in the session scratchpad and is not merged. It tapped only `afplay` processes it started itself, which played generated sine tones at −30.5 dBFS.

## How it was measured

Machine: MacBook Pro, Apple silicon, macOS 27.0 (26A428), output on MacBook Pro Speakers at 48 kHz with a 512-frame buffer.

- **Test audio:** tone A at 440 Hz (48 kHz WAV), tone B at 660 Hz (44.1 kHz WAV, to exercise resampling), and tone C at 880 Hz. Each played from its own `afplay`.
- **Per-app pipeline:** one tap per app with `CATapDescription(stereoMixdownOfProcesses: [process])`, `isPrivate = true`. A used `muteBehavior = .muted` and B used `.mutedWhenTapped`.
- **Aggregate:** one private aggregate per pipeline, with the output device as main sub-device and clock, and the tap in its tap list (drift compensation on).
- **IOProc:** copies tap input × gain to the output, with a one-buffer linear ramp.
- **Measurement:** Goertzel amplitude at each tone's frequency, over 0.1 s blocks.
- **Meters:**
  - each pipeline's input and output
  - **O1**, an unmuted tap on the prototype's own process. It shows what MoniMac actually sends to the device, measured independently of the IOProc's own meter.
  - **O2**, an unmuted tap on A and B together

### Results (dBFS at each tone's frequency)

| Phase | A out (440) | B out (660) | O1 own output 440 / 660 | O2 raw A+B 440 / 660 |
|---|---|---|---|---|
| P0: no gain taps | — | — | — | −30.5 / −30.5 |
| P1: A = 1.0, B = 1.0 | −30.5 | −30.5 | −30.5 / −30.5 | −30.5 / −30.5 |
| P2: A = 0.25 | **−42.5** | −30.5 | **−42.5** / −30.5 | −30.5 / −30.5 |
| P3: A = 0 (mute) | **−180 (digital silence)** | −30.5 | **−180** / −30.5 | −30.5 / −30.5 |
| P4: B = 0.5 (duck) | −30.5 | **−36.5** | −30.5 / **−36.5** | −30.5 / −30.5 |

- **Isolation:** each tap contains only its own process. Tone B in A's tap read −159 to −180 dBFS, over 125 dB down.
- **Taps read pre-mute audio:** O2 kept reading −30.5 dBFS while the muted taps were active. So a tap can't prove that the hardware stream was muted. That rests on the header contract and the listening check.
  - The header contract (`CATapDescription.h`) for `CATapMuted` is "no audio is sent from the process to the audio hardware".
  - **Listening check:** pending user report on whether the 440 Hz tone went fully silent in P3, with no faint copy.
- **Both mute behaviors work:** `.muted` (A) and `.mutedWhenTapped` (B) behaved the same while MoniMac was reading.
  - Prefer `.mutedWhenTapped`, as FineTune and Mimir do. If MoniMac's reader stops, the app is heard again instead of going silent.

## Latency, quality, CPU

- **Format:** tap A was 48 kHz, 2 channels, Float32 interleaved (`flags 9`). Tap B's source file was 44.1 kHz, but its tap also came in at 48 kHz with an unchanged level, so `afplay`/the HAL resampled it before the tap.
- **Glitches:** none. Every phase ran 281–284 IOProc calls per 3 s (about 48 kHz at 512 frames), with **0 timestamp discontinuities** and **0 processor overloads**, across 7 pipelines and about 50 s.
- **Latency, from HAL properties:** these are estimates, not an acoustic measurement.
  - The aggregate reports input latency 21 + safety offset 36 frames and output latency 60 + safety 48 + stream 690 frames, plus one 512-frame buffer on each side.
  - That is about **39 ms** from the app's buffer to the speaker.
  - Direct playback already pays the output side, so the **added delay is about one IO cycle plus the input safety offset: roughly 12 ms**. FineTune reports "~10–13 ms" on wired outputs.
  - Bluetooth adds much more (FineTune issue #424).
- **CPU:** one 10 s reading with metering off, on a Mac doing other audio work, so treat it as indicative.

  | | Prototype | coreaudiod |
  |---|---|---|
  | Two tones playing, no taps | 0.11% | 10.9% |
  | Same, with 2 tap pipelines | 0.33% (≈ +0.1% per pipeline) | 17.5% (≈ **+3% per pipeline**) |

  - MoniMac's own cost is small. The daemon cost is not: always-on taps for every audio app would cost several percent of a core in `coreaudiod`.
  - Re-measure this in ticket 17 against MoniMac's 1% self-cost budget.
- **Build cost:** creating a tap took 3–5 ms, the aggregate 7–24 ms, and `AudioDeviceStart` 6–16 ms. A full pipeline took about 25–55 ms.

## Permission

- **Info.plist key:** `NSAudioCaptureUsageDescription`, with the prompt's explanation. The prototype had it; running without it was not tested.
  - Put the key in `App/Info.plist` (or `project.yml`'s info properties), not as an `INFOPLIST_KEY_…` build setting, which Xcode reportedly drops for this key.
- **Prompt:** a system-audio-recording consent prompt naming the app.
  - Exact wording and buttons: **pending user report**. Third-party sources quote `"<App>" would like access to record your system audio`.
  - The grant appears in System Settings › Privacy & Security › Screen & System Audio Recording.
- **When it appears:**
  - Creating the tap (4 ms) and the aggregate (7 ms) returned at once with `noErr`.
  - The next IO setup on the aggregate holding the tap took **3.7 s** while the prompt was up. That setup is the input-stream query, listener registration, and `AudioDeviceCreateIOProcIDWithBlock`. With permission granted, the same steps take about 2 ms.
  - Apple's sample says the prompt appears "the first time you start recording from an aggregate device that contains a tap".
  - Either way, the first IO setup on a tap aggregate can block for as long as the prompt is up. Do it off the main thread.
- **Detecting the state:**
  - There is no public API to read or request this permission (AudioCap README; Apple DTS).
  - The private `TCCAccessPreflight("kTCCServiceAudioCapture")` worked at launch: `unknown(2)`, then `authorized(0)` in a fresh process.
  - **Inside the process that showed the prompt, it kept returning `unknown(2)` for 90 s**, while the tap was already delivering full-level audio (−30.5 dBFS).
  - **Recommendation:** MoniMac should not use the private SPI. Treat "the user turned on per-app volume" as the request. Then judge the result from the audio itself: a tap that delivers only zeros for a few seconds while `kAudioProcessPropertyIsRunningOutput == 1` means "not allowed".
- **Denied:** not observed, because the user allowed. Research says tap and aggregate creation and `AudioDeviceStart` all return `noErr` and the tap delivers zeros (AudioCap; Apple DTS; dev.to "2000 buffers of nothing").
  - So MoniMac must never mute or rebuild silently on a denied tap. With `.muted` and a denied grant, the app could go silent; this is unverified.
  - Show "Per-app volume needs System Audio Recording access" with a button to the Privacy pane, and keep per-app controls disabled.
- **Ad-hoc signing:**
  - The grant worked and persisted across launches of the same ad-hoc build: the second run started `authorized(0)`.
  - Rebuilding changes the cdhash, and TCC then treats it as a new app (Apple DTS). This wasn't tested here, to keep the grant.
  - Releases signed with the stable self-signed certificate should keep the grant across updates, because TCC keys on the designated requirement. That is inferred from TN3127, not observed.
- **Privacy indicator:** while any tap is running, macOS shows the purple "system audio is being recorded" dot in the menu bar (Apple Mac User Guide). Whether it showed during the spike is pending user report. This supports running taps only when they're needed (below).
- **UX for story 143 (ask on first use):**
  - Sound tab: show the activity list without sliders, plus "Turn on per-app volume…" with one plain sentence: *"MoniMac changes an app's volume by routing its audio through MoniMac. macOS will ask to let MoniMac record system audio; nothing is recorded or saved."*
  - The first slider move or mute, or turning on Duck or "Mute new apps", triggers the prompt.
  - Never at launch.

## Process lifecycle

- **Appearing:** a new `afplay`'s HAL process object appeared 15–37 ms after spawn. `IsRunningOutput` became 1 at 41–73 ms. The `kAudioHardwarePropertyProcessObjectList` listener fired for each change.
- **Quit:**
  - The process object vanished. The listener fired before `waitUntilExit` returned.
  - **The tap stayed alive and listed.** Its IOProc kept running at full rate, delivering digital silence with no error.
  - MoniMac must tear the tap down itself or retarget it, driven by the process-list listener.
- **Relaunch:**
  - The new process got a **new process object**. The old tap did not follow it, so the relaunched app played **unmanaged at full volume** until it was handled.
  - **Rebuild** (new tap + aggregate + start): 54 ms.
  - **Retarget:** set `kAudioTapPropertyDescription` on the existing tap. `AudioObjectIsPropertySettable` reported true, the set returned `noErr` in 11.5 ms, and gain applied at once (−42.5 dBFS at 0.25). Prefer retargeting; it avoids rebuilding the aggregate.
  - **macOS 26+:** `CATapDescription.bundleIDs` and `isProcessRestoreEnabled` ("restore them to the tap when they start up again") could make this automatic. Not tested, because `afplay` has no bundle ID. MoniMac's floor is 14.2, so the listener path is needed anyway.
- **Mute new apps:**
  - C was spawned, its object appeared at 34 ms, output started at 72 ms, and a muted gain-0 pipeline was running **25 ms later**. That is 98 ms from spawn, with polling at 1 ms.
  - The tapped stream was −30.5 dBFS in and digital silence out.
  - A brief leak at the start is possible; whether it was audible is **pending user report**.
  - Apps that connect to the HAL (object appears) before they play could be tapped when the object appears, instead of when output starts, which would close the window. How often real apps do this wasn't checked.
- **State while muted:** `IsRunningOutput` stays 1 while the tap mutes the app. Playing/Silent can't come from `IsRunningOutput` alone (below).

## Output device switching

**Not exercised.** The lead asked not to run the manual switch test. This section is from the API and the research.

- Each aggregate names its main sub-device by UID, so it stays on that device.
  - After the user switches output, tapped apps keep playing on the **old** device through MoniMac's aggregates until MoniMac rebuilds them.
  - If the old device disappears (unplugged, Bluetooth gone), they fall silent until the rebuild.
- **Handle `kAudioHardwarePropertyDefaultOutputDevice`:** listen for it and rebuild every pipeline on the new device.
  - FineTune builds the new tap and aggregate first, crossfades over about 200 ms, and waits 2 s for wired and 5 s for Bluetooth devices to settle.
  - Mimir saves state, removes all taps, and recreates them.
  - Also rebuild on sample-rate changes (Bluetooth A2DP ↔ hands-free); FineTune found recreation "the only reliable way".
- **Devices with a microphone** (AirPods, headsets, displays with a mic) add input streams to the aggregate next to the tap.
  - The prototype refused to start IO in that case.
  - MoniMac must pick out the tap's stream explicitly, never "the last input buffer". It must make sure no microphone data is routed or read, because reading it could also raise a Microphone prompt.
- **Bluetooth:** turn drift compensation off on Bluetooth and virtual devices (FineTune: "to avoid rhythmic crackle").
- **Silent taps after a change:** a forum report (macOS 26.5 beta) has taps going silent after a device or rate change until fully rebuilt. Add a watchdog: if a pipeline whose app has `IsRunningOutput == 1` delivers no callbacks or only zeros for several seconds, rebuild it.

## Call detection (for ducking)

- **What can be read:** `kAudioProcessPropertyIsRunningInput` and `kAudioProcessPropertyIsRunningOutput` are readable per HAL process object.
  - The prototype read them for all 39–43 objects; up to 2 were running input during the run.
  - This read happened with the grant in place. That it needs no permission is likely (the unauthorized dry run enumerated every object) but wasn't proven with an active input.
- **Heuristic:** a call is active while any app other than MoniMac has input **and** output running (full duplex) for more than about 2 s.
  - Optionally restrict this to known call apps (FaceTime, Zoom, Teams, Slack, Discord, Webex, and browsers for Meet). Without that, dictation or recording apps also count.
- **Restore:** un-duck about 2 s after the condition ends.
- **Known HAL bugs:** `kAudioProcessPropertyDevices` on the input scope and `kAudioDevicePropertyDeviceIsRunningSomewhere` for Bluetooth mics are buggy (Apple forums), so don't use them.
- **Status:** not exercised with a real call. The prototype never touched the user's apps.

## Design for MoniMac

**Run taps only where they change something.** Keep a pipeline only for an app whose effective gain isn't 1.0: user volume < 100%, muted, ducked, or muted-by-default.

- Apps at 100% get no tap, which means no added latency, no `coreaudiod` cost, and no purple dot.
- This differs from FineTune, which taps every audio app.

**One pipeline per app**, as measured:

- The tap lists **all** of the app's HAL process objects, grouped by `AppGrouping`'s responsible app. Browsers play from helpers such as `com.apple.WebKit.GPU`.
- Use `.mutedWhenTapped` and a private tap and aggregate, so both disappear if MoniMac crashes.
- An alternative, untested, is one aggregate holding several taps with per-tap gain in one IOProc. It may cost `coreaudiod` less, and ticket 17 could measure it.
- **Untested idea for mute:** a `.muted` tap with no aggregate reading it might mute an app at near-zero cost. Ticket 17 can check it cheaply.

**SystemSampler (reads, no permission needed). An `AudioReader` adds `Snapshot.audio`:**

- **Output device:** name, UID, sample rate, system volume, and the device list.
- **`audioProcesses`:** from `kAudioHardwarePropertyProcessObjectList`. For each object:
  - pid
  - bundle ID
  - `isRunningOutput`
  - `isRunningInput`
- **`level`:** only for apps MoniMac currently taps. The pipeline publishes an RMS.
- **Pure states in Core:**
  - **Playing:** output running, and the level is above about −60 dBFS when tapped.
  - **Silent:** connected but not outputting, or tapped and below the threshold.
  - **Muted:** the user's or the default's mute.
  - **Call active:** the duplex heuristic.

**SystemActions (writes):**

- `setAppGain(appID, gain)`; mute is gain 0.
- `setOutputDevice(uid)` and `setSystemVolume(v)`.

**Logic and execution are split:**

- **Core (`SoundPolicy`):** pure logic that computes the desired gain per app from the snapshot and Preferences:
  - per-app volume and mute keyed by bundle ID (`sound.app.<bundleID>.…`)
  - duck on/off
  - mute-new on/off
  - the set of "seen" apps
  - call state

  Tests feed snapshots and assert the recorded `setAppGain` actions.
- **System (`AudioMixer`, behind `SystemActions`):** a long-lived object that reconciles desired gains into pipelines. It:
  - creates, retargets, and destroys taps
  - reacts to the process-list and default-device listeners
  - owns the real-time IOProcs. They take no locks and no allocations; gain is an atomic float with a 20–30 ms ramp.

## What ticket 17 should build

**Build:**

- Device, volume, and activity UI. This needs no permission.
- Per-app sliders and mute, "Reset All to 100%", Duck, and Mute new apps, all behind the first-use permission flow above.
- Persistence by bundle ID.
- The process-list listener with retarget/rebuild.
- The default-device listener with rebuild.
- The silent-tap watchdog.
- The mic-stream guard.
- A self-cost check that includes `coreaudiod`.

**Don't build:**

- always-on taps for every app
- the private TCC SPI
- per-app output routing or EQ (out of scope in the spec)
- any virtual audio driver or helper

**Verify by hand** (the user, since automation can't):

- device switch while an app is lowered: speakers ↔ headphones ↔ Bluetooth
- a real call, for ducking
- what a denied grant does to a `.mutedWhenTapped` app

**Coexistence:** another tap-based mixer (FineTune, SoundSource's ARK) on the same device may interfere. A forum report says `AudioDeviceStart` blocks until the other tap is torn down. Note it, and don't fight it.

## Housekeeping observed

- **Cleanup:** after every run there were no leftover prototype or `afplay` processes, and `system_profiler SPAudioDataType` was identical before and after.
  - Every tap and aggregate destroy returned `noErr`.
  - Inside the prototype, `kAudioHardwarePropertyTapList` still listed one tap after all of its own were destroyed. That was also true in the run that created only one.
  - A separate process listed 0 taps afterwards, and private taps end with their process.
  - Ticket 17 should log the tap list on teardown to rule out a leak.
- **`open -W` message:** "Unable to block on application (GetProcessPID() returned 18446744073709551016)" is −600 (`procNotFound`). `open -W` couldn't attach to the `--status` launch, which exits within milliseconds. It reproduces intermittently and is harmless; the status was read correctly.

## Sources

- **Apple headers** (Xcode SDK, macOS 27): `CoreAudio/CATapDescription.h` (mute behaviors, `bundleIDs`, `processRestoreEnabled`), `AudioHardwareTapping.h`, and `AudioHardware.h` (process object properties, `kAudioAggregateDeviceTapListKey`, `kAudioAggregateDeviceTapAutoStartKey`, sub-tap drift keys)
- **Apple sample:** [Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps); [CATapMuteBehavior](https://developer.apple.com/documentation/coreaudio/catapmutebehavior); [bundleIDs](https://developer.apple.com/documentation/coreaudio/catapdescription/bundleids)
- **Apple technote:** [TN3127 Inside code signing: requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- **Apple forums:**
  - 771864, 756783 (no API for the permission state; denied means silence)
  - 848578 (taps from two processes interfere)
  - 825780 (silent taps after changes)
  - 741026, 748257 (input-device property bugs)
  - 678816, 730043 (ad-hoc rebuilds lose TCC grants)
  - 798941 (sample's tap-list bug)
- **Apple Mac User Guide:** [recording indicators](https://support.apple.com/guide/mac-help/mchlp1446/mac); [Screen & System Audio Recording](https://support.apple.com/guide/mac-help/mchld6aa7d23/mac)
- **[insidegui/AudioCap](https://github.com/insidegui/AudioCap):** `ProcessTap.swift`, `AudioRecordingPermission.swift`
- **[ronitsingh10/FineTune](https://github.com/ronitsingh10/FineTune):** `AudioEngine.swift`, `ProcessTapController.swift`, `AudioProcessMonitor.swift`; issue #424
- **[ThalesBMC/Mimir](https://github.com/ThalesBMC/Mimir)**
- **Blog posts:** dev.to ["2000 buffers of nothing"](https://dev.to/nickdelv/2000-buffers-of-nothing-3i8) (denied means zeros; Info.plist key pitfall); openscreen PR #740 (prompt wording)
- **Rogue Amoeba:** [ARK plug-in](https://rogueamoeba.com/support/knowledgebase/?showArticle=Misc-ARK-Plugin-Audio-Capture-Details&product=SoundSource) (SoundSource's current approach)
