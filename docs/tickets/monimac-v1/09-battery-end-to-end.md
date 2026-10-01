# 09 — Battery end to end

**What to build:** Battery joins the popover and the window. The sampler adds charge, charging state, adapter watts, battery draw, system power, health (design vs current capacity), cycle count, temperature, time remaining, and per-app energy estimates. The **window Battery tab** shows the big charge card, Power Draw, Health, Cycle Count, Temperature, a charge-level history chart that marks charging vs on-battery periods (with plug-in count and average drain %/h), and Using Significant Energy by app. On Macs without a battery, every battery surface is hidden.

**Blocked by:** 03 — Popover with CPU tab, top apps, and quit; 04 — Main window with CPU tab

**Status:** ready-for-agent

- [ ] The popover and window Battery tabs show live values
- [ ] The charge history chart distinguishes charging from on-battery periods
- [ ] Power figures are labelled as estimates in tooltips
- [ ] With a fake sampler reporting no battery, the Battery tab and popover tab are hidden
