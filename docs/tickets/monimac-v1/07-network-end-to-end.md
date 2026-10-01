# 07 — Network end to end

**What to build:** Network joins every surface. The sampler adds the active interface, link rate, network name, down/up rates, cumulative bytes, and per-process network rate. The **Network menu bar item** (e.g. `2.4 MB/s`) supports Value/Graph/Both. The **popover Network tab** is a compact version of the window tab. The **window Network tab** shows the interface line, live download/upload, session totals since a time, a 60-second live throughput chart, daily bar charts for the last 7 and 30 days with totals, and Top Apps by Network. Showing the Wi-Fi name needs Location permission: request it once from the Network tab, and if it's denied, show the interface without a name.

**Blocked by:** 03 — Popover with CPU tab, top apps, and quit; 04 — Main window with CPU tab

**Status:** ready-for-agent

- [ ] A Network menu bar item can be shown
- [ ] Session totals reset on app launch and show their start time
- [ ] The 7-day and 30-day charts show per-day download and upload from history
- [ ] Denying Location permission leaves the tab working, without the network name
- [ ] Top Apps by Network shows live rates per app
