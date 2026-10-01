# 09 — Battery end to end

**What to build:** Battery joins the popover and the window. The sampler adds charge, charging state, adapter watts, battery draw, system power, health (design vs current capacity), cycle count, temperature, time remaining, and per-app energy estimates. The **window Battery tab** shows the big charge card, Power Draw, Health, Cycle Count, Temperature, a charge-level history chart that marks charging vs on-battery periods (with plug-in count and average drain %/h), and Using Significant Energy by app. On Macs without a battery, every battery surface is hidden.

**Blocked by:** 03 — Popover with CPU tab, top apps, and quit; 04 — Main window with CPU tab

**Status:** done pending a manual click-through (merged as PR #13; automation can't click the status item, tabs, or range buttons). Unchecked boxes are built but not yet exercised.

- [x] The popover and window Battery tabs show live values
- [ ] The charge history chart distinguishes charging from on-battery periods (built and covered by `BatteryDetailTests`/`BatteryHistoryTests`; not seen on screen because this Mac stayed plugged in)
- [ ] Power figures are labelled as estimates in tooltips (`.help` on Power Draw and every app watts value, asserted in tests; hovering can't be automated, so the tooltips weren't seen)
- [x] With a fake sampler reporting no battery, the Battery tab and popover tab are hidden (`Monitor.hasBattery` is false in `aMacWithoutABatteryHidesBattery`; both tab lists filter on it)

**Notes:** The legend says "On power" rather than the design's "Charging", because the 1/0 series records whether an adapter is connected (a Mac held at 100% isn't charging, but it isn't on battery either). Health is nominal ÷ design capacity (87% on the M4 test Mac), while System Settings shows 89% from a private, smoothed metric.
