# 04 — Main window with CPU tab

**What to build:** The main window opens from the popover. Its sidebar has the groups Monitor, Devices, and Developer, with Settings at the bottom. Only CPU is live; the other tabs show placeholders until their tickets land. The toolbar has the title, a hardware subtitle (e.g. "MacBook Pro · M3 Pro · 18 GB"), and the toolbar actions. The **CPU tab** has stat cards (in use, User, System, Idle with cores, Load Average, Threads), a stacked history chart with 12H/24H/7D/30D ranges and "Peak N% at HH:MM", a per-core chart labelled P1… / E1…, and Top Apps by CPU with Show All. Show All is a no-op until ticket 12.

**Blocked by:** 03 — Popover with CPU tab, top apps, and quit

**Status:** ready-for-agent

- [ ] The popover's open-window button and "Open MoniMac" open the main window on the CPU tab
- [ ] The sidebar shows the grouped tabs, and selecting a tab switches the content
- [ ] The CPU history chart switches between 12H/24H/7D/30D and labels the peak value and time
- [ ] Per-core bars show performance and efficiency cores separately
- [ ] Window feature-state tests cover stat cards and the peak label from scripted history
