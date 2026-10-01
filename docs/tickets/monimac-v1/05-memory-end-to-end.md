# 05 — Memory end to end

**What to build:** Memory joins every surface. The sampler adds used/total, the pressure level, swap, the compression ratio, and the App/Wired/Compressed/Cached/Free breakdown, plus per-process memory. The **Memory menu bar item** (e.g. `11.2 GB`) supports Value/Graph/Both. The **popover Memory tab** is a compact version of the window tab. The **window Memory tab** shows memory type and size, a Memory Pressure card, Swap Used, Compression, a segmented breakdown bar with descriptions, a pressure history chart colored Low/Med/High with ranges, and Top Apps by Memory.

**Blocked by:** 03 — Popover with CPU tab, top apps, and quit; 04 — Main window with CPU tab

**Status:** ready-for-agent

- [ ] A Memory menu bar item can be shown alongside the CPU item
- [ ] The popover and window Memory tabs show live values matching the design sections
- [ ] The pressure history chart colors buckets by Low/Med/High
- [ ] Top Apps by Memory uses grouped app totals
- [ ] Feature-state tests cover the breakdown and pressure from scripted snapshots
