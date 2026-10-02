# 04 — Main window with CPU tab

**What to build:** The main window opens from the popover. Its sidebar has the groups Monitor, Devices, and Developer, with Settings at the bottom. Only CPU is live; the other tabs show placeholders until their tickets land. The toolbar has the title, a hardware subtitle (e.g. "MacBook Pro · M3 Pro · 18 GB"), and the toolbar actions. The **CPU tab** has stat cards (in use, User, System, Idle with cores, Load Average, Threads), a stacked history chart with 12H/24H/7D/30D ranges and "Peak N% at HH:MM", a per-core chart labelled P1… / E1…, and Top Apps by CPU with Show All. Show All is a no-op until ticket 12.

**Blocked by:** 03 — Popover with CPU tab, top apps, and quit

**Status:** done pending a manual click-through (automation can't click the status item or the window). Unchecked boxes are built but not yet exercised.

**Notes:**
- The window and its SwiftUI views exist only while it's open, so a closed window costs nothing.
- Threads and processes come from `processor_set_statistics`, which counts every process without root.
- The window CPU tab uses the design's single CPU color for all cores; the popover keeps teal for efficiency cores, as its design does.
- "Open MoniMac" in the popover lives on the Overview tab (ticket 11). The popover header's window button is wired now.

- [x] The popover's open-window button and "Open MoniMac" open the main window, on its current tab (Overview by default since ticket 11, which made Overview the first tab; this criterion originally said CPU because it predates Overview) (UI tests `PopoverTests.testOpenWindowButtonOpensMainWindow`, `testOverviewOpenMoniMacLinkOpensMainWindow`)
- [x] The sidebar shows the grouped tabs, and selecting a tab switches the content (UI test `WindowTests.testSidebarSwitchesTabs`)
- [x] The CPU history chart switches between 12H/24H/7D/30D and labels the peak value and time (UI test `WindowTests.testCPUHistoryRangesSwitchChartAndPeakLabel`)
- [x] Per-core bars show performance and efficiency cores separately
- [x] Window feature-state tests cover stat cards and the peak label from scripted history
