# 17 — Sound

**What to build:** The **Sound** tab. It shows an activity summary ("3 apps playing · 2 silent · 1 muted"), the current output device with sample rate, an output device switcher, and system volume. If the spike was a go, it also has a **Per-App Volume** list with each app's state (Playing/Silent/Muted), a volume slider, and a mute button, plus "Reset All to 100%", "Duck background apps" (other apps drop 50% during a call), and "Mute new apps by default". Per-app settings persist across relaunches. If the spike was a no-go, show per-app activity only, without sliders.

**Blocked by:** 04 — Main window with CPU tab; 16 — Spike: per-app audio feasibility

**Status:** ready-for-agent

- [ ] Switching output devices and changing system volume work and are recorded through SystemActions
- [ ] Per-app volume and mute work and persist (if the spike was a go)
- [ ] Ducking lowers other apps while a call is active and restores them afterwards (if the spike was a go)
- [ ] If the spike was a no-go, no per-app controls are shown
