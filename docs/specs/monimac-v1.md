# MoniMac v1 — Umbrella Spec

Status: ready-for-agent (umbrella; implement through the child slices listed in Further Notes)
Source of truth for UI: `moni-mac-designs.pen` (Pencil). Frames: Templates, MoniMac Screens (Menu Bar, Popover & Alerts · Main Window — System Metrics · Main Window — Devices, Developer & Settings), Components.

## Problem Statement

As a Mac user — especially a developer — I can't easily tell why my Mac feels slow, hot, loud, or short on battery. The answers are spread across Activity Monitor, System Settings, the Bluetooth menu, and Terminal commands like `lsof` and `docker ps`. None of them keep history, so when something went wrong ten minutes ago I can't see what caused it. Nothing warns me when one app starts burning CPU, leaking memory, or hammering the disk. I find forgotten dev servers and Docker containers holding memory and ports only by accident. I also can't see my Bluetooth devices' battery levels in one place, or control per-app volume.

## Solution

**MoniMac** is a free, open-source, native macOS app that lives in the menu bar and has a full main window.

- **Menu bar items.** Each metric (CPU, Memory, Network, GPU, Temperature) can be its own menu bar item, shown as a value, a 60-second sparkline, or both. An item turns into a warning badge when the system is under strain.
- **Popover.** Clicking an item opens a compact popover with tabs (Overview, CPU, Memory, GPU, Network, Disk, Battery). It shows live numbers, short-range charts, the busiest apps, and one-click quit.
- **Main window.** A sidebar groups the tabs. *Monitor:* Overview, CPU, Memory, GPU, Network, Disk. *Devices:* Battery, Bluetooth, Sound, Temperature & Fans. *Developer:* Projects. Then Settings. Each tab shows live values, 12H/24H/7D/30D history, and the top apps for that resource.
- **Overview.** Overview has a Tiles view and a List view. The List view is a searchable, sortable process table grouped by app.
- **Notifications.** Actionable notifications fire when an app crosses a configurable threshold (CPU, memory growth, disk writes, network) or a Bluetooth device runs low.
- **Projects.** Projects finds running dev servers and containers, groups them by project, flags idle ones, and stops them.
- **Device controls.** Per-app volume and call ducking. Temperature & Fans is read-only: MoniMac shows fan speeds but does not control them.
- **Share card.** A light or dark image summarizing the last 7 days.
- **History.** All history stays on the Mac. Nothing is sent anywhere.

## User Stories

### Menu bar

1. As a user, I want each metric (CPU, Memory, Network, GPU, Temperature) to be its own menu bar item, so that I only spend menu bar space on what I care about.
2. As a user, I want to choose, per item, between "Value", "Graph", and "Both", so that I can trade width for information.
3. As a user, I want the Value style to use compact, monospaced-feeling numbers (e.g. `32%`, `11.2 GB`, `2.4 MB/s`), so that the menu bar doesn't jitter as values change.
4. As a user, I want the Graph style to show the last 60 seconds as a sparkline, so that I can see trends at a glance.
5. As a user, I want a menu bar item to turn into a warning badge (e.g. "⚠ CPU 98%") when the system is under strain, so that I notice problems without opening anything.
6. As a user, I want to hover or click a warning badge and see the reason (e.g. "CPU above 90% for 2 min — Xcode is using 412%"), so that I know the culprit right away.
7. As a user, I want to ⌘-drag MoniMac items to reorder them like any system menu extra, so that they fit with my other menu bar icons.
8. As a user, I want to drag a MoniMac item off the menu bar to hide it, so that removing an item feels native.
9. As a user, I want to enable, disable, and set the style of each menu bar item in Settings, so that I can restore a hidden item.

### Popover

10. As a user, I want clicking any MoniMac menu bar item to open a popover, so that I can check details without opening a window.
11. As a user, I want the popover to have tabs for Overview, CPU, Memory, GPU, Network, Disk, and Battery, so that I can drill into one resource quickly.
12. As a user, I want the popover Overview to list CPU %, memory used/total, GPU %, network down/up, disk used/total, battery % with time left, and temperature, each with a colored bar, so that I see the whole system in one glance.
13. As a user, I want a "Busiest Right Now" list in the popover showing each app's icon, name, process count, and usage, so that I know which apps are heavy.
14. As a user, I want an "Open MoniMac" link and a window button in the popover header, so that I can jump to the main window.
15. As a user, I want a settings button in the popover header, so that I can reach Settings quickly.
16. As a user, I want the popover CPU tab to show the chip name and core count, overall CPU %, and a stacked user/system history chart with 1m/5m/1H/24H ranges, so that I can see recent behavior.
17. As a user, I want the popover CPU tab to show the User / System / Idle split, so that I know whether apps or the kernel are busy.
18. As a user, I want the popover CPU tab to show 1/5/15-minute load averages, so that I can judge how much work is queued.
19. As a user, I want per-core bars split into performance and efficiency cores in the popover, so that I can see how work is spread.
20. As a user, I want "Top Apps by CPU" in the popover to have a quit (×) button on each row, so that I can stop a runaway app immediately.
21. As a user, I want an "Activity Monitor" link in the popover, so that I can open Apple's tool when I need it.
22. As a user, I want the popover footer to show a live indicator and system uptime, so that I trust the data is current.
23. As a user, I want a "Quit MoniMac" action in the popover footer, so that I can exit the app without a Dock icon.
24. As a user, I want the popover's Memory, GPU, Network, Disk, and Battery tabs to be compact versions of their main-window tabs, so that the two surfaces feel consistent.

### Main window shell

25. As a user, I want a main window with a sidebar grouped into Monitor, Devices, and Developer, plus Settings at the bottom, so that I can navigate a lot of information.
26. As a user, I want every tab header to show a title and a hardware subtitle (e.g. "MacBook Pro · M3 Pro · 18 GB"), so that I know what I'm looking at.
27. As a user, I want a toolbar share button, so that I can create a share card from anywhere.
28. As a user, I want to hide window tabs I don't use (e.g. GPU, Bluetooth) in Settings, so that the sidebar stays short.
29. As a user, I want to drag sidebar tabs to reorder them, so that my most-used tabs are on top.
30. As a user, I want to rearrange the sections inside each tab, and have that layout persist, so that each tab shows what I care about first.
31. As a user, I want every history chart to offer 12H / 24H / 7D / 30D ranges, so that I can zoom out to see patterns.
32. As a user, I want every history chart to state the peak and when it happened (e.g. "Peak 87% at 14:12"), so that I can link spikes to what I was doing.
33. As a user, I want every "Top Apps by …" section to have "Show All", which opens the Overview List view sorted by that metric, so that I can see the full ranking.

### Overview — Tiles

34. As a user, I want Overview to show tiles for CPU, Memory, GPU, Network, Disk, Battery, Temperature, and Processes, each with a big value, a sparkline, and a caption, so that I can scan the whole system.
35. As a user, I want the CPU tile caption to show the User/System split, so that I have context.
36. As a user, I want the Memory tile to show used of total and pressure state, so that I know whether memory is actually a problem.
37. As a user, I want the GPU tile to show VRAM in use and the number of apps using the GPU, so that I know how hard graphics work is running.
38. As a user, I want the Network tile to show combined throughput with down/up separately, so that I can tell whether I'm downloading or uploading.
39. As a user, I want the Disk tile to show free space of total and the current write rate, so that I know when I'm running out of space and whether something is writing heavily.
40. As a user, I want the Battery tile to show charge state and time to full or empty, so that I know how long I can stay unplugged.
41. As a user, I want the Temperature tile to show CPU die temperature and current fan RPM, so that I can link heat to fan noise.
42. As a user, I want the Processes tile to show app count split into apps, agents, and system, plus total processes and threads, so that I see how much is running in the background.
43. As a user, I want a "Busiest Right Now" list on Overview that shows each app's dominant resource (e.g. "Xcode 12% CPU", "Time Machine 9.4 MB/s"), so that I see why each app is listed.
44. As a user, I want a "Show All N Apps" link that switches to the List view, so that I can go from the summary to the full table in one click.

### Overview — List

45. As a user, I want to toggle Overview between Tiles and List, so that I can pick summary or detail.
46. As a user, I want the List view to be a table with columns App, Procs, CPU, Memory, GPU, Network, Disk, and Power, so that I can compare apps on every resource.
47. As a user, I want to sort the table by any column (with a "Sorted by …" control), so that I can find the top consumer of anything.
48. As a user, I want to search apps and processes by name, so that I can find one quickly.
49. As a user, I want a "Group processes by app" toggle, so that helper processes roll up under their parent app.
50. As a user, I want to expand a grouped app to see its helpers (e.g. "Google Chrome Helper (Renderer) ×14"), so that I can find which helper is heavy.
51. As a user, I want the table footer to show what's displayed ("Showing 14 of 61 apps · 1,048 processes grouped") and system totals (CPU, Memory, GPU, Network, Power), so that I have context for the rows.
52. As a user, I want to quit an app from the table, so that I can act on what I find.

### Quit confirmation

53. As a user, I want quitting an app to show a sheet ("Quit Google Chrome and its 23 processes?") with its total CPU and memory, so that I know what I'm about to stop.
54. As a user, I want the sheet to list the app's processes with PID, CPU, and memory (top N plus "and 18 more helper processes"), so that I can see what's inside.
55. As a user, I want the sheet to explain that Quit asks the app to close normally so I can save my work, so that I'm not afraid of losing data.
56. As a user, I want a "Reopen windows next time" checkbox, so that the app restores its windows when relaunched.
57. As a user, I want Quit, Cancel, and Force Quit buttons, so that I can escalate when an app doesn't respond.

### CPU

58. As a user, I want the CPU tab to show the chip name and core layout (e.g. "Apple M3 Pro · 12 cores (6P + 6E)"), so that I know what hardware the numbers refer to.
59. As a user, I want stat cards for CPU in use, User ("Apps & services"), System ("macOS kernel"), Idle (with "8.2 of 12 cores"), Load Average (1m, with 5m and 15m), and Threads (with process count), so that I can read every CPU figure without opening a chart.
60. As a user, I want a stacked user/system CPU history chart with time ranges and the peak, so that I can see how CPU use changed over time.
61. As a user, I want a per-core load chart labelled P1–P6 / E1–E6, so that I can see scheduling across core types.
62. As a user, I want "Top Apps by CPU" with usage bars, so that I can see which apps cause the load.

### Memory

63. As a user, I want the Memory tab to show total memory and type (e.g. "18 GB unified memory · LPDDR5") and the amount used, so that I know how much headroom I have.
64. As a user, I want a Memory Pressure card (Normal/Warning/Critical with % and throttling state), so that I know whether high usage matters.
65. As a user, I want Swap Used (of swap file size) and Compression ratio (before → after), so that I understand memory tricks.
66. As a user, I want a segmented bar breaking memory into App Memory, Wired, Compressed, Cached Files, and Free, each with a description ("Kernel, can't page out", "Reclaimable"), so that I understand where memory went.
67. As a user, I want a memory pressure history chart, colored by Low/Med/High, with time ranges, so that I can see when my Mac was short on memory.
68. As a user, I want "Top Apps by Memory", so that I can find the apps holding the most memory.

### GPU

69. As a user, I want the GPU tab to show the GPU model and core count, utilization (Renderer and Tiler), and GPU memory (shared from unified memory), so that I know how busy the GPU is and how much memory it holds.
70. As a user, I want 24H average (compared with yesterday) and 24H peak (with the app and time responsible, e.g. "Final Cut Pro export · 14:12"), so that I can explain GPU spikes.
71. As a user, I want a GPU utilization history chart with average and peak, and time ranges, so that I can see when graphics work happened.
72. As a user, I want "Top Apps by GPU", so that I can find the apps using the GPU.

### Network

73. As a user, I want the Network tab to show the active interface, network name, and link rate (e.g. "Wi-Fi 6E · Studio-5G · 1.2 Gb/s link"), so that I know which connection I'm on and how fast it can go.
74. As a user, I want live download and upload rates, and totals downloaded and uploaded this session (since a time), so that I know how much data I've moved since I started.
75. As a user, I want a live throughput chart for the last 60 seconds, so that I can watch transfers as they happen.
76. As a user, I want daily download/upload bar charts for the last 7 days and the last 30 days, with totals, so that I can track data usage.
77. As a user, I want "Top Apps by Network" with live rates, so that I can find the apps using my bandwidth.

### Disk

78. As a user, I want the Disk tab to show the volume name, format, and capacity (e.g. "Macintosh HD · APFS · 1 TB SSD") and free space, so that I know which disk I'm looking at and how full it is.
79. As a user, I want live read and write rates with today's peaks, so that I can tell how busy the disk is now compared with earlier.
80. As a user, I want "Written Today", SSD health %, and lifetime TB written, so that I can watch SSD wear.
81. As a user, I want a storage breakdown bar (Applications, Developer, Documents, macOS, Purgeable, Free) with sizes and hints, so that I know what fills my disk.
82. As a user, I want a Read & Write history chart with time ranges, so that I can see when the disk was busy.
83. As a user, I want "Disk Writes Today" ranked by app, so that I can find the apps wearing out my SSD.

### Battery

84. As a user, I want the Battery tab to show charge %, charging state, adapter wattage, and time to full or empty, so that I know my power situation at a glance.
85. As a user, I want Power Draw (battery) and whole-system power use, so that I know how fast I'm using power.
86. As a user, I want battery Health (% with design vs current mAh), Cycle Count (of rated cycles), and battery temperature with a normal/abnormal note, so that I know whether my battery is aging.
87. As a user, I want a charge level history chart that marks charging vs on-battery periods, with plug-in count and average drain %/h, so that I understand my charging habits and battery life.
88. As a user, I want "Using Significant Energy" listing apps by watts, so that I can find the apps draining my battery.
89. As a user on a Mac without a battery, I want the Battery tab and items hidden, so that I don't see empty UI.

### Bluetooth

90. As a user, I want the Bluetooth tab to show how many devices are connected, so that I know at a glance what's paired and active.
91. As a user, I want a featured card for my AirPods-class device with connection state, what it's playing from, noise-control mode, firmware, estimated listening time left, and separate Left / Right / Case battery rings, so that I know when to charge each earbud and the case.
92. As a user, I want an "Other Devices" list with each device's type, connection state, a battery bar and %, and a status hint ("Charged 6 days ago", "Low — charge soon", "Est. 58 days left", "Last seen yesterday, 10:42 PM"), so that I can charge peripherals before they die.
93. As a user, I want low batteries highlighted in red, so that I charge them in time.
94. As a user, I want an "Open Bluetooth Settings…" link, so that I can manage devices in System Settings.
95. As a user, I want a "Low battery notifications" toggle that notifies me when any connected device drops below 20%, so that I'm warned before a device dies.

### Sound

96. As a user, I want the Sound tab to summarize audio activity ("3 apps playing · 2 silent · 1 muted"), so that I can see what's making sound.
97. As a user, I want to see the current output device and sample rate, switch output devices, and adjust system volume, so that I can control output without opening System Settings.
98. As a user, I want a Per-App Volume list showing each audio app's state (Playing / Silent / Muted) with a volume slider and mute button, so that I can balance loud and quiet apps.
99. As a user, I want "Reset All to 100%", so that I can undo my changes in one click.
100. As a user, I want a "Duck background apps" toggle that lowers other apps by 50% while a call is active, so that I can hear calls clearly.
101. As a user, I want a "Mute new apps by default" toggle, so that apps that start playing for the first time stay muted.
102. As a user, I want per-app volume settings to persist across app relaunches, so that I don't have to adjust them again.

### Temperature & Fans

103. As a user, I want the tab header to show the thermal state (Nominal/Fair/Serious/Critical) and fan count, so that I know whether my Mac is throttling.
104. As a user, I want CPU, GPU, SSD, and Battery temperature cards, each with today's peak and a colored gauge, so that I can see which part is running hot.
105. As a user, I want a CPU temperature history chart with average and peak (with the cause, e.g. "during Xcode build"), with time ranges, so that I can see what made my Mac hot.
106. As a user, I want each fan's current speed (RPM and % of its maximum, with its min–max range), so that I can tell whether noise comes from the fans.
107. As a user, I want a full sensor list (performance cores, efficiency cores, GPU cluster, memory, airflow, palm rest, power supply, wireless module, ambient), so that I can locate heat precisely.
108. As a user on a fanless Mac, I want fan readouts hidden, so that I'm not shown empty values.

### Projects (Developer)

109. As a developer, I want Projects to detect running dev servers, watchers, and Docker containers, and group them by project folder, so that I can see what's running and why.
110. As a developer, I want each project to show its name, path, current git branch, server count, total memory, and a "Stop All" button, so that I can manage a project as a unit.
111. As a developer, I want each server row to show the command, a detected type (Next.js, Storybook, Vite, FastAPI, Docker, Watcher, Mock API, …), port, uptime, memory, and activity ("Active · now", "Idle 26 min", "Idle 4 days"), so that I know what each server is and whether it's still used.
112. As a developer, I want to click a port to open it in my browser, so that I can open the app I'm running.
113. As a developer, I want to stop a single server, so that I can free its memory and port.
114. As a developer, I want to reveal a project folder in Finder, so that I can jump to its code.
115. As a developer, I want a banner when servers have been idle for days (e.g. "old-landing has had no requests since Sep 27 and is holding 1.1 GB of memory and ports 5173, 4000"), with "Stop Idle Servers" and "Ignore", so that I can reclaim memory from forgotten servers in one click.
116. As a developer, I want idle servers' activity highlighted, so that forgotten servers stand out.
117. As a developer, I want the tab subtitle to summarize ("8 dev servers across 3 projects · 2.9 GB"), so that I know the total cost of my dev environment.

### Notifications

118. As a user, I want a notification when one app stays above a CPU threshold (default 80%) for 2 minutes, with "Quit <App>" and "Show" actions, so that I can stop a runaway app straight from the notification.
119. As a user, I want a notification when an app's memory grows fast (default +1 GB within 10 minutes), so that I catch leaks.
120. As a user, I want a notification for heavy disk writes (default more than 10 GB in an hour), so that I catch apps wearing out my SSD.
121. As a user, I want an optional notification for heavy, sustained network activity (e.g. 18 MB/s upload for 4 minutes), so that I notice unexpected uploads or downloads.
122. As a user, I want each notification to show the app icon, a plain-language explanation, and a metric chip (e.g. "412%", "+2.1 GB", "24 MB/s"), so that I understand the alert without opening MoniMac.
123. As a user, I want to enable each rule and set its threshold in Settings, so that I only get alerts I care about.
124. As a user, I want "Show" to open MoniMac on the relevant app or tab, so that I can investigate straight away.
125. As a user, I don't want repeated notifications for the same ongoing condition, so that alerts stay useful.

### Share card

126. As a user, I want to create a share card summarizing the last 7 days, so that I can post my Mac's week.
127. As a user, I want the card to show my Mac model, chip, and RAM; the date range; a headline and one-line summary (e.g. "Busy week, cool head." / uptime, throttling, busiest app); and stats for CPU avg/peak, Memory avg/pressure, GPU avg/peak, Network down/up, and Battery health/cycles, each with a 7-day sparkline, so that the card tells a complete story of my week.
128. As a user, I want the card in Light and Dark variants, so that it fits wherever I post it.
129. As a user, I want to copy the card or save it as an image (1200×630), so that I can share it anywhere.

### Settings

130. As a user, I want "Launch at login", so that monitoring starts without me.
131. As a user, I want a refresh interval of 1s, 2s, or 5s, so that I can trade freshness for energy.
132. As a user, I want "Show icon in Dock" (off by default, menu-bar-only app), so that MoniMac stays out of the way unless I want it there.
133. As a user, I want temperature units °C / °F, so that temperatures read the way I'm used to.
134. As a user, I want network speed units MB/s / Mbps, so that speeds match what my ISP advertises or what I'm used to.
135. As a user, I want CPU usage shown as "System" (0–100% of the whole CPU) or "Per-core" (up to 1200% on 12 cores), applied everywhere, including notifications and the popover, so that percentages read the way I'm used to and stay consistent.
136. As a user, I want notification rules with thresholds (CPU %, memory GB, disk, network) in Settings, so that alerts fit how I use my Mac.
137. As a user, I want menu bar items listed with enable checkbox, Value/Graph/Both, and a drag handle, so that I can configure the menu bar in one place.
138. As a user, I want Window Tabs chips to show or hide tabs (an enabled tab shows a ✓, a hidden tab shows + to add it back), so that the sidebar shows only what I use.
139. As a user, I want "Keep history" (e.g. 7 / 30 / 90 days) for per-app CPU, memory, network, and disk, so that I control how much disk space history uses.
140. As a user, I want to see the app version and links to the source repository, release notes, and update check, so that I know what I'm running.
141. As a user, I want MoniMac to tell me when an update is available, so that I get fixes and new features.

### Privacy, permissions, and resources

142. As a user, I want all history stored only on my Mac, so that my usage stays private.
143. As a user, I want MoniMac to ask for a permission (audio capture, location, notifications) only when I first use a feature that needs it, with a plain explanation, so that I can trust it.
144. As a user, I want MoniMac to use little CPU and energy itself, so that the monitor doesn't distort what it monitors.
145. As a user, I want features that are unavailable on my Mac (no battery, no fans, missing permission) to say why instead of showing broken values, so that I'm never misled by placeholder numbers.
146. As a new user, I want clear install steps on the download page (move to Applications, then System Settings › Privacy & Security › Open Anyway on first launch), so that the macOS warning about an unidentified developer doesn't stop me.
147. As a user, I want permissions I've granted (notifications, audio capture, location) to survive app updates, so that I'm not asked again after every release.

## Implementation Decisions

### Product and platform

- **Name:** the product is **MoniMac**. The repo is `moni-mac`.
- **Distribution:** free and open source, downloaded from GitHub Releases. It is **not sandboxed** and **not** on the Mac App Store. There is no licensing, so the design's "Lifetime License · 1 of 5 Macs · Manage…" row becomes an **About** row: version, source link, release notes, and update check.
- **Signing without a paid Apple Developer account:** the app is **not notarized** and has no Developer ID. Releases are signed with a **self-signed code-signing certificate** that stays the same across releases; its private key lives only in CI secrets. Ad-hoc signing (the default) is not enough because macOS ties granted permissions to the app's signing identity: an ad-hoc identity changes with every build, so users would be asked again after each update. Consequences:
  - On first launch, macOS blocks the app. Since macOS 15, right-click › Open no longer bypasses this; users must click **Open Anyway** in System Settings › Privacy & Security (or remove the quarantine attribute in Terminal). The README and every release note carry these steps with screenshots (story 146).
  - **Homebrew:** the official cask repository drops apps that fail Gatekeeper from September 2026, so MoniMac won't be listed there. A project-owned tap is optional, but Homebrew no longer offers a way to skip quarantine, so tap users still go through Open Anyway.
  - If a paid account is added later, switching to Developer ID + notarization is a release-pipeline change only; no app code depends on it.
- **Updates:** use an open-source in-app updater whose update archives are verified with the project's own EdDSA signing key (this needs no Apple account), reading a feed published with GitHub Releases. The release-pipeline ticket (20) must confirm that an installed update launches without triggering Gatekeeper again; if it does, fall back to "Update available" linking to the release page.
- **Stack:** native Swift. Use SwiftUI for the window and popover; use AppKit where SwiftUI falls short (status items, the popover window, sheets).
- **Targets:** Apple silicon first. The minimum macOS version is pinned by the per-app audio approach (see below). If no lower target is needed, assume macOS 14.2 or later.
- **App mode:** an accessory (menu bar) app by default; "Show icon in Dock" switches the activation policy.

### Architecture: two seams, everything else is pure

```diagram
╭─────────────────╮  Snapshot (every refresh interval)    ╭──────────────────╮
│ SystemSampler   │──────────────────────────────────────▶│ MetricsHistory   │
│ (OS reads)      │                                       │ (store, tiers,   │
╰─────────────────╯                                       │  range queries)  │
                                                          ╰────────┬─────────╯
        ╭─────────────────────────┬──────────────────────┬────────┴───────────┬──────────────────╮
        ▼                         ▼                      ▼                    ▼                  ▼
 ╭──────────────╮       ╭──────────────────╮   ╭────────────────╮   ╭────────────────╮  ╭────────────────╮
 │ AppGrouping  │       │ AlertEngine      │   │ ProjectCatalog │   │ WeeklySummary  │  │ Formatting     │
 │ (procs→apps) │       │ (rules → alerts) │   │ (servers,idle) │   │ (share card)   │  │ (units, CPU %) │
 ╰──────┬───────╯       ╰────────┬─────────╯   ╰───────┬────────╯   ╰───────┬────────╯  ╰───────┬────────╯
        ╰─────────────┬──────────┴─────────────────────┴────────────────────┴───────────────────╯
                      ▼
            ╭───────────────────────╮         user intents          ╭──────────────────────╮
            │ Feature state (per    │──────────────────────────────▶│ SystemActions        │
            │ surface/tab) → Views  │                               │ (OS writes)          │
            ╰───────────────────────╯                               ╰──────────────────────╯
```

- **SystemSampler (seam 1, reads).** This is the only module that reads OS state. On each tick it produces one immutable **Snapshot**: CPU (total, user/system/idle, per-core with P/E kind, load averages, threads); memory (used, pressure level, swap, compression, App/Wired/Compressed/Cached/Free); GPU (utilization renderer/tiler, memory); network (interface, SSID, link rate, rates, cumulative bytes); disk (capacity, free, purgeable, read/write rates, bytes written, SSD health and lifetime writes); battery (charge, state, adapter watts, draw, system power, health, cycles, temperature, time remaining); thermal (thermal state, named sensors, fans with current/min/max RPM); Bluetooth devices (type, connected, battery levels including L/R/Case, last seen); audio (output device, sample rate, system volume, audio-producing processes); per-process records (pid, parent/responsible app, name, CPU, memory, GPU, network rate, disk bytes, energy/power estimate, threads); listening sockets (port, pid, cwd, connection counts) and Docker containers. Fields the Mac can't provide (no battery, no fans, missing permission) are explicitly absent with a reason, never zero. The real implementation wraps IOKit/SMC, host and process statistics, IOReport, CoreAudio, IOBluetooth, the network statistics source, and the Docker socket. Tests use a **fake sampler** that replays scripted snapshot sequences.
- **SystemActions (seam 2, writes).** This is the only module with side effects: quit an app (graceful, with an optional "reopen windows" hint) and force quit; set per-app volume and mute, and duck apps; switch the output device and set system volume; stop a dev server process or container; open a URL, reveal a folder in Finder, open System Settings panes, and open Activity Monitor. No action needs administrator rights, so MoniMac has no privileged helper. Tests use a **recording fake** and assert which actions were requested.
- **MetricsHistory.** Takes snapshots and stores them locally (an embedded SQL store) in resolution tiers: full refresh-rate samples for about the last hour (enough for 60-second sparklines and the popover's 1m/5m), one-minute buckets for 24 hours, and coarser buckets (about 5–15 minutes, plus daily totals) up to the retention set in "Keep history". It answers range queries for 1m/5m/1H/24H and 12H/24H/7D/30D with avg, peak, peak time, and the top contributor at peak (for "Peak 91% · Final Cut Pro export · 14:12"). Per-app series are kept for CPU, memory, network, and disk. It enforces retention when the setting changes. Session counters (network since a time, disk written today, plug-ins and drain) come from here too.
- **AppGrouping.** Pure. Maps processes to apps (helpers roll up under their responsible app), classifies each app as app, agent, or system, and computes per-app totals, process counts, and the "dominant resource" label for Busiest Right Now. It backs the List view's grouping toggle, search, and sort, and the quit sheet's process list.
- **AlertEngine.** Pure state machine over history. Rules: per-app CPU above X for 2 min; memory growth of +Y within 10 min; disk writes above Z per hour; sustained network above a threshold for N min; Bluetooth device below 20%; system CPU above 90% for 2 min (the menu bar warning state); and idle dev servers (the Projects banner). Output is alert events with a stable identity per (rule, subject), so that an ongoing condition alerts once and re-arms only after it clears. A presenter delivers events as system notifications with actions ("Quit <App>" → SystemActions; "Show" → deep link into the window) and as menu bar warning states.
- **ProjectCatalog.** Pure over snapshots. Builds Projects from listening sockets and containers: process → working directory → enclosing project root (nearest git or package manifest), git branch, server type detection from command line and ports (Next.js, Vite, Storybook, FastAPI/uvicorn, Docker image, watcher with no port, mock API), uptime, memory, and activity. **Idle definition:** a server is idle when it has accepted no new inbound connections on any of its ports *and* its CPU stayed under a small floor; "Idle since" is the last time either was true. Watchers with no port are idle by CPU only. The banner threshold is idle for 2 days or more; "Ignore" suppresses the banner for that project until it becomes active again.
- **WeeklySummary.** Pure. From 7 days of history: uptime hours, throttling events, CPU/GPU avg and peak, memory avg and pressure, network totals, battery health and cycles, busiest app by CPU time, and 7-point sparklines. It picks a headline from a small rule-based phrase table (e.g. low thermal events + high CPU → "Busy week, cool head."). There is no LLM and no network. Renders 1200×630 Light/Dark images.
- **Formatting.** Pure. Units (°C/°F, MB/s vs Mbps), CPU mode (System 0–100% vs Per-core 0–N×100%), compact number formatting for menu bar items, and relative times ("Idle 4 days", "Charged 6 days ago").
- **Preferences.** One typed store for every setting in the Settings screen, plus layout state (sidebar tab order and visibility, section order per tab, menu bar item order, style, and enabled), per-app volume memory, and ignored project banners.
- **Surfaces.** MenuBar (one status item per enabled metric; renders Value/Graph/Both/Warning), Popover (7 tabs), MainWindow (sidebar + tabs + toolbar with Tiles/List toggle and Share), QuitSheet, ShareCard. Each surface reads a feature-state object derived from history and the pure modules above. Views hold no logic.

### Specific interactions and feasibility decisions

- **CPU % mode** is one setting applied everywhere. This explains why the design shows "Xcode 412%" in the popover and notifications (Per-core) and "12.4%" in the window (System). Each surface must not choose its own mode. Sample screens disagree, so the spec rules: every surface follows the setting.
- **Menu bar reorder/hide** uses the system's ⌘-drag behavior for status items. MoniMac persists visibility and order from Settings but does not build its own drag UI in the menu bar. The Settings list has drag handles for order.
- **Per-app volume, ducking, and "mute new apps"** have no simple public API. Decision: implement with Core Audio process taps feeding a MoniMac-owned aggregate output (macOS 14.2+). **Spike result (ticket 16, `docs/spikes/16-per-app-audio.md`): GO.**
  - **What was measured:** on an ad-hoc-signed, non-notarized, non-sandboxed build on macOS 27, a muted process tap per app fed a private aggregate on the output device.
    - Gain 0.25 lowered one app by exactly −12 dB, with the other app unchanged.
    - Gain 0 gave digital silence, and gain 0.5 (duck) gave −6 dB.
    - There were no glitches.
    - It added about 12 ms of latency.
  - **Permission:** it needs one "System Audio Recording" permission (`NSAudioCaptureUsageDescription`), asked when the user first turns on a per-app control, never at launch.
    - No public API reports the permission; a denied tap delivers silence, not an error.
    - While taps run, macOS shows its purple recording indicator.
  - **Cost:** each tap pipeline adds about 3% CPU in `coreaudiod`. So MoniMac taps only apps whose gain isn't 100%; an app at full volume gets no tap.
  - **MoniMac must handle these itself:**
    - **Quit:** a quit app leaves a silent tap behind.
    - **Relaunch:** a relaunched app gets a new process object, so its tap must be retargeted (11 ms) or rebuilt (54 ms).
    - **Output switch:** pipelines stay on the old device until they're rebuilt.
  - **Ducking:** call detection is a heuristic (another app running audio input and output at once).
  - **If taps fail at runtime** (no permission): show per-app *activity* only, and hide the sliders.
- **Fans are read-only.** MoniMac reads fan speeds and temperatures from the SMC but never writes to it.
- **Quit flow:** "Quit" sends a graceful terminate. "Force Quit" is a separate destructive button. "Reopen windows next time" maps to the app's state-restoration preference. Quitting a group targets the responsible app, not individual helpers.
- **Network SSID** needs Location permission on recent macOS. Request it once from the Network tab. If denied, show the interface without the name.
- **Per-app network and power** come from system statistics sources and estimates. Label power as an estimate in tooltips.
- **Disk storage breakdown** (Applications/Developer/Documents/macOS/Purgeable) is computed in the background on a slow schedule and cached. It isn't recalculated each tick.
- **Notifications** use the system notification center with action buttons. Thresholds default to the design values: CPU 80% / 2 min, memory +1 GB / 10 min, disk 10 GB / hour, network off by default.
- **Self-cost budget:** at a 2 s refresh with the popover closed, MoniMac should stay under about 1% average CPU. Sampling of hidden data (e.g. per-core while only the Overview is visible) may be reduced, but history for enabled metrics is always recorded.

## Testing Decisions

- **What makes a good test:** tests drive the app from the outside — scripted sampler snapshots and the clock go in; we assert what the user would see or what action would be taken. That means the formatted values and lists in a surface's feature state, the alerts emitted, and the actions recorded by the fake SystemActions. Tests never assert on private helpers, storage layout, or view hierarchy.
- **The seams are the only fakes.** Fake SystemSampler (scripted snapshot sequences, including "field unavailable" cases) and recording SystemActions. Nothing else is mocked; MetricsHistory runs against a real in-memory store.
- **Modules under test, mostly through feature state:**
  - MetricsHistory: tier downsampling, range queries, peak/peak-time/top-contributor, retention pruning on setting change, session counters.
  - AppGrouping: helper roll-up, search, sort by each column, totals footer, dominant-resource labels.
  - AlertEngine: each rule fires at its threshold and duration, doesn't fire below it, fires once per ongoing condition, re-arms after clearing, respects enabled/threshold settings and CPU mode; the menu bar warning state appears and disappears; idle server banner and Ignore.
  - ProjectCatalog: grouping by project root, type detection, idle definition (connections and CPU floor), Stop All → recorded actions.
  - WeeklySummary: stat values and headline selection from canned 7-day histories.
  - Formatting: units, CPU mode, compact menu bar strings.
  - Quit flow: Quit vs Force Quit vs Cancel → correct recorded action with correct target.
- **Not unit-tested:** the real SystemSampler/SystemActions implementations. Cover them with a small smoke suite that runs on real hardware in CI-optional mode (checks fields are present and in range) and with manual QA against the Pencil designs.
- **Prior art:** none. The repo is greenfield. Ticket 01 establishes the test harness (fake sampler, recording actions, clock control) that every later slice reuses.

## Out of Scope

- Mac App Store or sandboxed build; paid licensing, activation, or seat limits.
- Notarization, Developer ID signing, and a listing in Homebrew's official cask repository (no paid Apple Developer account).
- Intel Macs (may be revisited; SMC keys and sensors differ).
- Monitoring other Macs, remote or iOS companions, cloud sync, accounts, or any telemetry.
- Killing or stopping arbitrary system processes outside the quit flow; process priority (nice) control.
- Fan control of any kind (Auto/Manual/Max modes, custom RPM, fan curves). Fans are shown read-only.
- Editing Bluetooth connections (connect/disconnect/pair). MoniMac only shows them and links to System Settings.
- Per-app audio EQ or output routing per app.
- Localization beyond English for v1.
- Widgets, Shortcuts/AppleScript, and CLI.

## Further Notes

- **Design sample data is not a requirement.** The frames disagree in places: 18 GB vs 36 GB RAM, battery 84% vs 86%, Xcode 412% vs 12.4% (explained by CPU mode), popover ranges (1m/5m/1H/24H) vs window ranges (12H/24H/7D/30D), and the share card's "412 hours of uptime" in a 7-day (168-hour) window. The ranges differ on purpose; the numbers are placeholders.
- **Design updates already applied** to the Pencil file to match this spec:
  - The app is renamed from "Vitals" to "MoniMac" everywhere (text and layer names).
  - Settings › "Data & License" is now "Data & About". Its row reads "MoniMac 1.4.2 · Free and open source · You're up to date" with a "Check for Updates…" button. The window subtitle reads "MoniMac 1.4.2".
  - The share card footer is `github.com/lethanhvietctt5/moni-mac`.
  - Temperature & Fans "Fan Control" is now a read-only "Fans" card: status "Managed by macOS", plain speed bars, and an info note. It has no mode switch, sliders, or 95°C note.
- **Tickets:** the implementation is split into 20 vertical-slice tickets in `docs/tickets/monimac-v1/`, numbered in dependency order. Each lists the tickets that block it.
- No issue tracker is configured. This spec lives in the repo by choice. To publish it later, run `/setup-matt-pocock-skills` to configure a tracker and the `ready-for-agent` label.
