# 06 — GPU end to end

**What to build:** GPU joins every surface. The sampler adds utilization (Renderer and Tiler), GPU memory, and per-process GPU use. The **GPU menu bar item** supports Value/Graph/Both. The **popover GPU tab** is a compact version of the window tab. The **window GPU tab** shows the GPU model and core count, the utilization and GPU memory cards, the 24H average compared with yesterday, the 24H peak with the responsible app and time (e.g. "Final Cut Pro export · 14:12"), a utilization history chart with ranges, and Top Apps by GPU.

**Blocked by:** 03 — Popover with CPU tab, top apps, and quit; 04 — Main window with CPU tab

**Status:** ready-for-agent

- [ ] A GPU menu bar item can be shown
- [ ] The 24H peak card names the app that was top GPU consumer at the peak
- [ ] "N pts lower/higher than yesterday" is computed from history
- [ ] The popover and window GPU tabs show live values
