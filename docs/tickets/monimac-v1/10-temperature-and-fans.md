# 10 — Temperature & Fans (read-only)

**What to build:** Temperature joins the menu bar and the window. The sampler reads the thermal state, named sensors, and fans (current/min/max RPM) from the SMC; it never writes to it. The **Temperature menu bar item** supports Value/Graph/Both. The **window Temperature & Fans tab** shows the thermal state with fan count, CPU/GPU/SSD/Battery cards with today's peak and a gauge, a CPU temperature history chart with average and peak (with the cause, e.g. "during Xcode build"), the read-only **Fans** card (each fan's RPM, % of max, min–max range, and "Managed by macOS"), and the full sensor list. On fanless Macs the Fans card is hidden. There is no fan control and no privileged helper.

**Blocked by:** 03 — Popover with CPU tab, top apps, and quit; 04 — Main window with CPU tab

**Status:** done. The menu bar item was read from the real menu bar by a UI test (`UITests/`).

- [x] A Temperature menu bar item can be shown (covered by `ThermalMenuBarTests`; in the real menu bar by UI test `MenuBarItemTests.testMemoryNetworkAndTemperatureItemsCanBeShown`, which reads the item's title, e.g. "61°C")
- [x] Temperature cards and the sensor list show live values
- [x] The Fans card shows each fan's speed and has no controls
- [x] With a fake sampler reporting no fans, the Fans card is hidden (`ThermalDetailTests.fanlessMacHidesTheFansCard`)
- [x] No code path writes to the SMC (`SMC.Command` has only read cases: read key, key at index, key info)
