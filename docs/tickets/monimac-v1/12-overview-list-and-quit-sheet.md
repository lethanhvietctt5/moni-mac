# 12 — Overview List and quit confirmation

**What to build:** Overview gains a Tiles/List toggle. The **List view** is a table with columns App, Procs, CPU, Memory, GPU, Network, Disk, and Power. It is sortable by any column ("Sorted by …"), searchable by app or process name, and has a "Group processes by app" toggle with expandable groups (e.g. "Google Chrome Helper (Renderer) ×14"). The footer shows what's displayed and system totals. Every "Show All" link opens this view sorted by its metric. Quitting from the table, the popover ×, or a notification shows the **quit sheet**: "Quit <App> and its N processes?", the app's CPU and memory, its top processes with PID/CPU/Memory plus "and N more", a short explanation that Quit closes the app normally, a "Reopen windows next time" checkbox, and Quit, Cancel, and Force Quit buttons.

**Blocked by:** 11 — Overview: Tiles and popover Overview

**Status:** done pending a manual click-through. The List view (Chrome expanded), the Tiles view, and the quit sheet were seen in the running app through launch flags (`--overview-list`, `--expand <app>`, `--show-quit-sheet <app>`). Clicks automation can't make are not yet exercised: the Tiles/List toggle, column headers, the sort menu, search typing, the group toggle, disclosure, Show All links, the table's hover × and context menu, the popover ×, and the sheet's buttons. Their logic is covered by Core tests (`OverviewListTests`, `QuitSheetTests`).

**Reopen windows:** the checkbox sends the quit Apple event with `kAEQuitPreserveState` (what ⌥⌘Q uses), but macOS gates that event behind Automation consent like any scripting event, and MoniMac doesn't ask for it. So the option takes effect only where the user already allowed MoniMac to control the app; otherwise the app quits normally. The checkbox is off by default.

- [x] Sorting, search, and grouping work together, and the footer counts stay correct
- [x] Show All from a Top Apps section opens the List view sorted by that metric (UI test `WindowTests.testShowAllOpensListSortedByThatMetric`, for CPU, Memory, GPU, Network, and Disk)
- [x] Quit records a graceful quit; Force Quit records a force quit; Cancel records nothing (verified with the recording fake)
- [x] Quitting a grouped app targets the responsible app, not individual helpers
- [x] The popover × now opens the quit sheet instead of quitting directly (UI test `PopoverTests.testPopoverQuitButtonOpensQuitSheetAndCancelKeepsAppRunning`, which presses Cancel and checks the app is still running)
