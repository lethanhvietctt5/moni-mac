# 17 — Sound

**What to build:** The **Sound** tab. It shows an activity summary ("3 apps playing · 2 silent · 1 muted"), the current output device with sample rate, an output device switcher, and system volume. If the spike was a go, it also has a **Per-App Volume** list with each app's state (Playing/Silent/Muted), a volume slider, and a mute button, plus "Reset All to 100%", "Duck background apps" (other apps drop 50% during a call), and "Mute new apps by default". Per-app settings persist across relaunches. If the spike was a no-go, show per-app activity only, without sliders.

**Blocked by:** 04 — Main window with CPU tab; 16 — Spike: per-app audio feasibility

**Status:** done pending the user's hands-on checks. The spike was a GO, so per-app controls are built. The running app has no audio capture permission (its signature differs from the spike's), so no tap ran here: per-app volume, mute, ducking, and mute-new-apps were exercised through Core tests with scripted readings and recorded actions, and need the user verification script (`--sound-selftest`) and a real call. Output switching and system volume were never changed on this Mac (only recorded in tests).

**Notes:**
- **Reading, no permission:** Core Audio process objects, attributed to the app responsible for them through LaunchServices (so browsers' audio helpers and Chrome's relocated code-sign clone count as the browser). macOS's background services (`/System/Library`) and MoniMac itself are left out. Also read: the default output's name, kind, sample rate, and volume, and the output device list.
- **Listeners, not polling:** a process-object read costs ~0.7 ms of IPC (40 objects took 108 ms). Listeners cover the process list, each process's running-output/input state, the default output, the device list, and the default device's volume, sample rate, and streams. A tick only copies the cache. They exist only while the Sound or Bluetooth tab is on screen, ducking or mute-new-apps is on, or an app is adjusted; otherwise MoniMac makes no Core Audio call.
- **Taps only where they change something** (spike: ~3% `coreaudiod` CPU each): an app gets a tap only while it plays and its gain isn't 100%, kept 10 s after it stops. An app that keeps its stream open while paused keeps its tap. One private `.mutedWhenTapped` stereo-mixdown tap per app over all its processes feeds a private aggregate on the output; the IO block applies the gain with a 25 ms ramp.
  - Retarget (`kAudioTapPropertyDescription`) when the app's processes change; rebuild if refused; destroy when none are left.
  - Output, sample-rate, or stream change: rebuild every tap after 2 s (5 s on Bluetooth).
  - Watchdog: rebuild a tap with no IO for 3 s, or silent for 8 s within a minute of an output change while its app plays; at most once a minute.
  - Microphone guard: the aggregate must have the output's own input streams plus exactly one tap stream; only the tap's is read, the rest are marked unused (`kAudioDevicePropertyIOProcStreamUsage`). Otherwise the tap isn't started and the tab says why. Untested with a headset.
  - Destroyed on quit (waiting at most 2 s); the leftover tap list is logged.
  - Coexistence with SoundSource's ARK or FineTune is not handled.
- **Permission (story 143):** no private TCC SPI. Until first use, the list explains in one sentence what will happen. The prompt comes when the first tap starts. Until a tap delivers sound, taps hearing only zeros for 6 s while their apps play mean "not working": every tap stops, the per-app controls are disabled (the switches can still be turned off), and the tab offers Open Privacy Settings… and Try Again. A truly silent playing app can trip this. Saved adjustments start taps at launch when those apps play, so a rebuild that loses the grant (ad-hoc signing) prompts then.
- **Ducking:** a call is one app playing and recording at once for 2 s (tick-based, so 2–4 s); it ends 2 s after (2–4 s); the call app isn't lowered. Calls whose audio runs in a daemon without an app (possibly FaceTime's `avconferenced`) aren't detected; unverified.
- **Mute new apps:** "new" means not seen playing while MoniMac watched audio (`sound.seenApps`); apps using audio when it's turned on are left alone. The tap starts from the listener, before the next tick records the app as muted.
- **Settings:** `sound.apps` (JSON, by bundle id, only non-default entries), `sound.duck`, `sound.muteNewApps`, `sound.perAppUsed`, and bookkeeping `sound.seenApps`.
- **Not built:** the output card's level meter (it would need capturing all output).
- **Bluetooth:** the featured card says "Playing from …", "Nothing playing", or "Not the current output" while audio is read; not observed with real headphones.
- **Dev flags:** `--sound-selftest <dir>` adjusts only pids a script writes to `<dir>/phase`. With `--show-window`, a covered window counts as showing for the audio reading, so the tab renders while other apps are in front.
- **Self-cost** (Release, window and popover closed, nothing adjusted, 120 s from 60 s after launch, `sample` attached): `main` 1.31% (`coreaudiod` 5.79%), this branch 1.35% (`coreaudiod` 1.57%). `coreaudiod` swings with other apps' audio. The branch profile has no Core Audio frames. One earlier branch run was discarded: the popover was opened during it.

- [x] Switching output devices and changing system volume work and are recorded through SystemActions (recorded in tests; in the real app by UI tests `SoundTests.testOutputMenuSwitchesDefaultDevice` and `SoundTests.testVolumeSliderChangesSystemVolume`, which read the result back with Core Audio and restore the original device and volume)
- [ ] Per-app volume and mute work and persist (if the spike was a go) (gains and persistence by bundle id tested; real taps need the user verification script)
- [ ] Ducking lowers other apps while a call is active and restores them afterwards (if the spike was a go) (state machine tested with scripted readings; not tried with a real call)
- [x] ~~If the spike was a no-go, no per-app controls are shown~~ Not applicable: the spike (ticket 16) was a go, so per-app controls are built
