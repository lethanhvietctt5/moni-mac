# 03 — Popover with CPU tab, top apps, and quit

**What to build:** Clicking the menu bar item opens the popover. The header has the MoniMac title, an open-window button, and a settings button. The tab bar is visible: tabs other than CPU are placeholders for now. The footer has a live indicator with uptime, plus Quit MoniMac. The **CPU tab** shows the chip and core count, overall CPU %, a stacked user/system chart with 1m/5m/1H/24H ranges, the user/system/idle split, 1/5/15-minute load averages, and per-core bars split into P/E cores. **Top Apps by CPU** lists apps with usage bars and a × button. This ticket introduces per-process sampling, **AppGrouping** (helper processes roll up into their responsible app), and the second seam, **SystemActions**, with a recording fake. The × requests a graceful quit of the app. An "Activity Monitor" link opens Apple's app.

**Blocked by:** 02 — History + CPU sparkline in the menu bar

**Status:** ready-for-agent

- [ ] Clicking the CPU item opens the popover on the CPU tab with all sections populated from live data
- [ ] Range buttons switch the chart between 1m, 5m, 1H, and 24H
- [ ] Top Apps groups helpers under their app (e.g. Chrome helpers count toward Google Chrome)
- [ ] Pressing × on an app records a graceful-quit action for that app (verified with the recording fake) and quits it in the real app
- [ ] The Quit MoniMac and Activity Monitor actions work
- [ ] Tests cover AppGrouping roll-up and the CPU tab's feature state from scripted snapshots
