# 06 — GPU end to end

**What to build:** GPU joins every surface. The sampler adds utilization (Renderer and Tiler), GPU memory, and per-process GPU use. The **GPU menu bar item** supports Value/Graph/Both. The **popover GPU tab** is a compact version of the window tab. The **window GPU tab** shows the GPU model and core count, the utilization and GPU memory cards, the 24H average compared with yesterday, the 24H peak with the responsible app and time (e.g. "Final Cut Pro export · 14:12"), a utilization history chart with ranges, and Top Apps by GPU.

**Blocked by:** 03 — Popover with CPU tab, top apps, and quit; 04 — Main window with CPU tab

**Status:** done pending a manual click-through (automation can't click the status item, tabs, or range buttons). Unchecked boxes are built but not yet exercised.

**Notes:**
- **Source:** utilization, Renderer/Tiler, and GPU memory ("In use system memory") come from the IOAccelerator's `PerformanceStatistics`; model and `gpu-core-count` are read once. Unified memory is `hw.memsize`. Only the needed registry keys are read, never the full property table (it carries large IOReport legends).
- **Per-app GPU** is the delta of `accumulatedGPUTime` (ns) summed over each pid's `AGXDeviceUserClient` children, over wall time, computed only when the process list refreshes (every 4 s). It's readable without privileges. If it isn't, the tabs say "Per-app GPU use isn't readable on this Mac".
- **Yesterday comparison:** the minute tier that serves a 24H range is pruned after about 25 hours, so a 24H query ending 24 hours ago would cover only its last hour. Yesterday's average is read from the 7D range's quarter-hour buckets instead. A test records data 30 hours old and fails with the naive query.
- **Points** compare the percentages as displayed (14% vs 17% → "3 pts lower").
- **Peak caption** is "<busiest GPU app> · HH:MM", or "at HH:MM" when no app had GPU figures at the peak.
- Tile sparklines: Utilization and GPU Memory cover the last 5 minutes (memory is scaled to its own peak); Average and Peak cover 24H.
- **Peak contributor** is the owner of the busiest single GPU process, as for CPU (`AppGrouping.busiestApp`). It isn't summed per app, so a multi-helper app can top the list without naming the peak.
- `--show-window --tab gpu` opens the window on a given tab, for screenshots.
- **Self-cost:** about 0.5% CPU for the Release app with the popover closed (0.63 s over 2 minutes), against about 0.4% before.

- [x] A GPU menu bar item can be shown (Monitor emits a live `gpu 12%` item from the real sampler, and tests cover the text and sparkline. The status item itself wasn't screenshotted: macOS doesn't expose it to the screenshot script)
- [x] The 24H peak card names the app that was top GPU consumer at the peak (verified by tests from scripted history, and live: the window showed "WindowServer · 16:40")
- [x] "N pts lower/higher than yesterday" is computed from history (verified by tests, including pruned history. Live, it reads "No history from yesterday" until a day of GPU history exists)
- [x] The popover and window GPU tabs show live values (window by screenshot with `--tab gpu`; popover tab rendered offscreen with the real sampler, since the popover can't be opened on the GPU tab without clicking)
