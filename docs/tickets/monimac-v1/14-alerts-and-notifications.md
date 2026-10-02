# 14 — Alerts and notifications

**What to build:** Adds **AlertEngine**, a pure state machine over history with these rules:
- one app above a CPU threshold for 2 min (default 80%)
- memory growth of +1 GB within 10 min
- disk writes above 10 GB per hour
- sustained heavy network use (off by default)
- system CPU above 90% for 2 min, which drives the **menu bar warning badge**, e.g. "⚠ CPU 98%" with a tooltip naming the culprit

Each ongoing condition alerts once and re-arms only after it clears. Alerts are delivered as system notifications with the app icon, a plain-language explanation, and a metric chip. Each has "Quit <App>" (opens the quit sheet) and "Show" (opens the relevant tab or app in the window) actions. **Settings › Notifications** enables each rule and sets its threshold. Thresholds respect the CPU mode.

**Blocked by:** 12 — Overview List and quit confirmation; 13 — Settings: General, Units, Menu Bar Items, Window Tabs

**Status:** done pending end-to-end checks of real notifications. Delivery, the permission request, and the notification buttons are built but were exercised only through `RecordingActions`: during verification MoniMac ran with `--mute-notifications`, so it never asked for permission or posted a banner, and nothing was stressed to trigger a real alert.

**Notes:**
- **Threshold units:** the CPU threshold is stored in **cores** (1.0 = one core fully busy, the unit of `AppUsage.cpu`), so "default 80%" means a runaway single-threaded app trips it. The CPU mode only changes how it reads: "80%" in Per-core, "6.7%" in System on 12 cores (the design's "80%" is the Per-core reading). Memory growth is binary bytes, disk is decimal bytes per hour, network is decimal bytes per second (in + out). Keys: `alerts.<rule>.enabled` and `alerts.<rule>.threshold`.
- **Rules:** one app at or above the CPU threshold for 2 min; +1 GB memory growth within 10 min; 10 GB written within an hour; one app at or above 10 MB/s of traffic for 4 min (off by default). macOS's own processes (`AppKind.system`, e.g. kernel_task) are left out: they can't be quit and some run hot by design. The system rule (whole CPU at or above 90% for 2 min) only drives the menu bar badge; it posts no notification.
- **Cost:** the system rule reads each snapshot's CPU total. Per-app rules run at most every 4 s (throttled on snapshot time, the process list's cadence) over `Monitor.apps`' cached grouping, and only while a rule is on or the badge needs its culprit. Rolling windows live in memory as at most 60 buckets per app (10 s buckets for memory, 1 min for disk). Each bucket overlapping the window counts, so a window can be up to one bucket longer than its nominal length, but never misses its threshold at the edge. A gap over 60 s between evaluations (sleep) starts sustained conditions over.
- **Settings:** CPU and memory have a threshold menu with an "Off" entry, as the design draws them. Disk and network have a switch, as in the design, plus a threshold menu, so every rule's threshold can be set (spec story 136).
- **Notifications:** the metric chip is the banner's subtitle, since macOS banners have no pill. The app icon is an attachment. "Quit <App>" needs a category per app, registered when first needed; that registration is asynchronous, so a category's very first banner may rarely show without buttons. The badge is the CPU item, or the first item when CPU isn't shown. It is amber with "⚠ CPU 98%", and its tooltip reads e.g. "CPU above 90% for 2 min / Xcode is using 412% · click for details". Clicking opens the popover as usual.

- [x] Each rule fires at its threshold and duration and not below it, verified with scripted histories (`AlertTests`)
- [x] A sustained condition produces exactly one notification until it clears (one `deliver` per condition at the `SystemActions` seam, re-armed after clearing; real banners unverified)
- [x] Disabling a rule or changing its threshold in Settings takes effect immediately (intents tested, and the Settings › Notifications rows render; the menus and switches weren't clicked)
- [x] The menu bar item becomes a warning badge under system strain and returns to normal afterwards (feature state tested; status items can't be captured)
- [ ] Notification actions open the quit sheet or the right place in the window (built: Quit → `QuitSheetPresenter.present(appID:over: nil)`, Show → Overview › List sorted by the alert's figure with the app expanded; the payload round-trip is tested, the buttons are unverified)
