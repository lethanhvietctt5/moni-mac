# 03 — Popover with CPU tab, top apps, and quit

**What to build:** Clicking the menu bar item opens the popover. The header has the MoniMac title, an open-window button, and a settings button. The tab bar is visible: tabs other than CPU are placeholders for now. The footer has a live indicator with uptime, plus Quit MoniMac. The **CPU tab** shows the chip and core count, overall CPU %, a stacked user/system chart with 1m/5m/1H/24H ranges, the user/system/idle split, 1/5/15-minute load averages, and per-core bars split into P/E cores. **Top Apps by CPU** lists apps with usage bars and a × button. This ticket introduces per-process sampling, **AppGrouping** (helper processes roll up into their responsible app), and the second seam, **SystemActions**, with a recording fake. The × requests a graceful quit of the app. An "Activity Monitor" link opens Apple's app.

**Blocked by:** 02 — History + CPU sparkline in the menu bar

**Status:** done. The range buttons, ×, Quit MoniMac, and Activity Monitor were clicked in the real app by the UI tests in `UITests/` (see CLAUDE.md › UI tests). The tests open the popover with `--show-popover`, so the status item click itself is still unexercised.

**Decisions made while building:**
- **Process sampling without a privileged helper.** Your own processes are read with `proc_pid_rusage` (every 4 s). Other users' processes (WindowServer, root daemons) are invisible to that API, so they're read from the setuid `/bin/ps` in the background every 15 s, with rates averaged over that interval.
- **Attribution.** Helpers roll up under macOS's *responsible* process (private `responsibility_get_pid_responsible_for_pid`, resolved at runtime), falling back to the outermost `.app` in the path.
- **The × appears only for running regular (Dock) apps.** Quitting e.g. WindowServer would log the user out.
- **Default CPU mode is System** (per the Settings design). The popover shows whole-CPU percentages until ticket 13 adds the switch.
- **Copy change:** the Load Average subtitle reads "Runnable threads, averaged" instead of the design's "Runnable threads per core", because load average isn't per core.
- **Kernel tick counters can report zero change over a short interval.** HostSampler then keeps its baseline and repeats the last value instead of flashing "—".
- **Self-cost:** about 0.4% CPU for the Release app with the popover closed, plus about 0.1% for the `ps` runs.

- [x] Clicking the CPU item opens the popover on the CPU tab with all sections populated from live data (popover verified via `--show-popover`; the click handler itself is not yet exercised)
- [x] Range buttons switch the chart between 1m, 5m, 1H, and 24H (UI test `PopoverTests.testRangeButtonsSwitchPopoverChart`)
- [x] Top Apps groups helpers under their app (e.g. Chrome helpers count toward Google Chrome)
- [x] Pressing × on an app opens the quit sheet, and the sheet's Quit quits the app gracefully (the action is verified with the recording fake; in the real app a throwaway app was quit this way: UI test `PopoverTests.testPopoverQuitButtonThenQuitQuitsTheApp`)
- [x] The Quit MoniMac and Activity Monitor actions work (UI tests `PopoverTests.testQuitMoniMacQuitsTheApp`, `PopoverTests.testActivityMonitorLinkOpensActivityMonitor`)
- [x] Tests cover AppGrouping roll-up and the CPU tab's feature state from scripted snapshots
