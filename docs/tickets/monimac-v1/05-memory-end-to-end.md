# 05 — Memory end to end

**What to build:** Memory joins every surface. The sampler adds used/total, the pressure level, swap, the compression ratio, and the App/Wired/Compressed/Cached/Free breakdown, plus per-process memory. The **Memory menu bar item** (e.g. `11.2 GB`) supports Value/Graph/Both. The **popover Memory tab** is a compact version of the window tab. The **window Memory tab** shows memory type and size, a Memory Pressure card, Swap Used, Compression, a segmented breakdown bar with descriptions, a pressure history chart colored Low/Med/High with ranges, and Top Apps by Memory.

**Blocked by:** 03 — Popover with CPU tab, top apps, and quit; 04 — Main window with CPU tab

**Status:** done pending a manual click-through (automation can't click the status item, the popover's Memory tab, or the window sidebar). Unchecked boxes are built but not yet seen in the running app.

- [ ] A Memory menu bar item can be shown alongside the CPU item (built and covered by feature-state tests; the running app was launched with it enabled, but macOS doesn't expose status items to the screenshot script)
- [x] The popover and window Memory tabs show live values matching the design sections (seen in offscreen renders of the real views from live `HostSampler` data; not yet in the running app, since reaching the tab needs a click)
- [x] The pressure history chart colors buckets by Low/Med/High
- [x] Top Apps by Memory uses grouped app totals
- [x] Feature-state tests cover the breakdown and pressure from scripted snapshots

**Notes:**
- **Breakdown (Activity Monitor's definitions)**, from `host_statistics64(HOST_VM_INFO64)` page counts × `hw.pagesize`:
  - App Memory = internal − purgeable
  - Wired = wired
  - Compressed = compressor-occupied pages
  - Cached Files = external + purgeable
  - Used = App + Wired + Compressed
  - Free is the rest of `hw.memsize`, so the five segments add up to installed memory.
  - Compression's "before" is `total_uncompressed_pages_in_compressor`.
- **Pressure:**
  - The level comes from `kern.memorystatus_vm_pressure_level` (1/2/4 = Normal/Warning/Critical).
  - The percentage is 100 − `kern.memorystatus_level`, the free percentage that `memory_pressure` prints.
  - Swap comes from `vm.swapusage`.
- **Pressure history:**
  - Bar height is the pressure percentage. Color is the **worst kernel level** in the bar's span, as in Activity Monitor; a Mac can sit around 50% and still be Normal.
  - History only averages buckets, so the level is recorded as two 0/1 indicator series, `memory.pressureWarning` and `memory.pressureCritical`. A bucket average above 0 means the level occurred at least once, so short spikes still show at 7D/30D.
- **Memory type** (LPDDR5) has no cheap public source. `ioreg` has no type string, and `system_profiler` is too costly to spawn, so the subtitle reads "24 GB unified memory".
- **Units are binary**, as macOS shows them: "24 GB", not "25.8 GB". `Format.memorySize` shows one decimal below 100 GB and drops a trailing ".0", so the menu bar item is sized for `88.8 GB`.
- **Top Apps by Memory** sorts the grouped `AppUsage.resources.memory`. That's the footprint for your own processes and the `ps` resident size for other users' processes. The window shows 8 apps; the popover shows 4, with quit.
- **Warning and danger colors** aren't in `Palette` yet, so they're kept private in `MemoryViews.swift`.
- **Self-cost** (Release, popover closed, measured while five other ticket builds ran on the same Mac): about 0.5–0.6% CPU with the Memory item shown, the same as without it. The two early outliers (2.2% and 1.6%) didn't reproduce. Sampling memory is one `host_statistics64` and three sysctls per tick.
