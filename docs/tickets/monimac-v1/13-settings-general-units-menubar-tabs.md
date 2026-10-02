# 13 — Settings: General, Units, Menu Bar Items, Window Tabs

**What to build:** The **Settings** tab. It covers:
- General: launch at login, refresh interval (1s/2s/5s), and "Show icon in Dock".
- Units: °C/°F, MB/s or Mbps, and CPU usage as "System" or "Per-core".
- Menu Bar Items: enable checkbox, Value/Graph/Both, and a drag handle for each metric.
- Window Tabs: chips that show or hide tabs (✓ when shown, + when hidden).
- Keep history retention.

Sidebar tabs can be dragged to reorder them, and sections inside each tab can be rearranged; layouts persist. **CPU mode is one setting applied on every surface**, which explains why the design shows 412% in some places and 12.4% in others. Menu bar items reorder through the system's ⌘-drag; MoniMac only persists visibility and style.

**Blocked by:** 11 — Overview: Tiles and popover Overview

**Status:** done pending a manual click-through (automation can't click or drag: the switches, segmented controls, chips, the Keep history popup, sidebar and section dragging, the popover gear, and the right-click menu are built and their intents covered by `SettingsTests` and `LayoutTests`, but not clicked). Settings were set with `defaults write` before launch and read back on screen.

**Notes:** the Menu Bar Items drag handles are drawn as in the design but do nothing: the menu bar's order is the system's ⌘-drag, and the list's order isn't used anywhere. Sidebar tabs reorder within their group. Notifications (ticket 14) and Check for Updates (ticket 20) are shown disabled.

- [x] Changing the refresh interval changes the sampling rate (CPU samples recorded over 30 s: 29 at 1 s, 15 at 2 s, 6 at 5 s; the switch itself wasn't clicked, and a live change restarts the loop, covered by an Observation test)
- [x] Switching CPU mode changes CPU values in the menu bar, popover, window, and list consistently (tests across all surfaces; Per-core seen on Overview tiles, the popover CPU tab, and the List footer and rows)
- [x] Unit switches apply everywhere temperatures and network speeds appear (tests; °F and Mbps seen on Overview, Temperature & Fans, and the List)
- [x] Hiding a window tab removes it from the sidebar; the chip shows + and can add it back (UI test `WindowTests.testTabChipHidesAndRestoresSidebarTab`)
- [x] Sidebar order and section order persist across relaunches (a stored custom sidebar order and CPU section order are applied after relaunch; dragging itself is unverified)
- [x] Changing Keep history prunes data beyond the new limit. Verified against a real (in-memory) SQLite history in `SettingsTests` (`shorteningKeepHistoryPrunesOlderData`, `ninetyDaysKeepsDataFromTwoMonthsAgo`) and `MetricsHistoryTests.shorteningRetentionPrunesImmediately`; deliberately not run on the maintainer's real history, which it would delete
- [ ] Launch at login and the Dock icon toggle take effect (Dock: clicking the switch changes MoniMac's activation policy and clicking again restores it, UI test `WindowTests.testShowIconInDockTakesEffect`, which passes alone but loses its click in full-suite runs, so it is quarantined (run it alone with `TEST_RUNNER_MONIMAC_UITEST_DOCK=1`). Launch at login is only tested through `RecordingActions`, never registered on the dev Mac, so this stays a maintainer check)
