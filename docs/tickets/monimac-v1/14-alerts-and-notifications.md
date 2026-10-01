# 14 — Alerts and notifications

**What to build:** Adds **AlertEngine**, a pure state machine over history with these rules:
- one app above a CPU threshold for 2 min (default 80%)
- memory growth of +1 GB within 10 min
- disk writes above 10 GB per hour
- sustained heavy network use (off by default)
- system CPU above 90% for 2 min, which drives the **menu bar warning badge**, e.g. "⚠ CPU 98%" with a tooltip naming the culprit

Each ongoing condition alerts once and re-arms only after it clears. Alerts are delivered as system notifications with the app icon, a plain-language explanation, and a metric chip. Each has "Quit <App>" (opens the quit sheet) and "Show" (opens the relevant tab or app in the window) actions. **Settings › Notifications** enables each rule and sets its threshold. Thresholds respect the CPU mode.

**Blocked by:** 12 — Overview List and quit confirmation; 13 — Settings: General, Units, Menu Bar Items, Window Tabs

**Status:** ready-for-agent

- [ ] Each rule fires at its threshold and duration and not below it, verified with scripted histories
- [ ] A sustained condition produces exactly one notification until it clears
- [ ] Disabling a rule or changing its threshold in Settings takes effect immediately
- [ ] The menu bar item becomes a warning badge under system strain and returns to normal afterwards
- [ ] Notification actions open the quit sheet or the right place in the window
