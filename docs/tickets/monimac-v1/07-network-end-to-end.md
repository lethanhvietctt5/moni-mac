# 07 — Network end to end

**What to build:** Network joins every surface. The sampler adds the active interface, link rate, network name, down/up rates, cumulative bytes, and per-process network rate. The **Network menu bar item** (e.g. `2.4 MB/s`) supports Value/Graph/Both. The **popover Network tab** is a compact version of the window tab. The **window Network tab** shows the interface line, live download/upload, session totals since a time, a 60-second live throughput chart, daily bar charts for the last 7 and 30 days with totals, and Top Apps by Network. Showing the Wi-Fi name needs Location permission: request it once from the Network tab, and if it's denied, show the interface without a name.

**Blocked by:** 03 — Popover with CPU tab, top apps, and quit; 04 — Main window with CPU tab

**Status:** done pending a manual click-through (merged as PR #14; automation can't click the status item, tabs, or range buttons). Unchecked boxes are built but not yet exercised.

- [x] A Network menu bar item can be shown (UI test `MenuBarItemTests.testMemoryNetworkAndTemperatureItemsCanBeShown`, which enables it for one launch through launch-argument settings and reads the item's title, e.g. "3.8 KB/s")
- [x] Session totals reset on app launch and show their start time
- [x] The 7-day and 30-day charts show per-day download and upload from history
- [ ] Denying Location permission leaves the tab working, without the network name
- [x] Top Apps by Network shows live rates per app

**Verification notes:**
- The Network menu bar item is covered by Core tests (text, units, sparkline). macOS doesn't expose status items to the window-ID screenshot script, so the item itself wasn't seen on screen.
- On this Mac Location access was already granted, so the SSID shows. The denied path (no name in the interface line) is covered by Core tests but wasn't seen in the running app.
