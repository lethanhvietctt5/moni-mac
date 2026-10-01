# 08 — Disk end to end

**What to build:** Disk joins the popover and the window. The sampler adds volume name/format/capacity, free and purgeable space, read/write rates, bytes written, SSD health and lifetime writes, and per-process disk bytes. The **window Disk tab** shows free space, read/write cards with today's peaks, Written Today with SSD health, a storage breakdown bar (Applications, Developer, Documents, macOS, Purgeable, Free), a Read & Write history chart with ranges, and Disk Writes Today ranked by app. The storage breakdown is computed in the background on a slow schedule and cached; it is never recalculated on every tick.

**Blocked by:** 03 — Popover with CPU tab, top apps, and quit; 04 — Main window with CPU tab

**Status:** ready-for-agent

- [ ] The popover and window Disk tabs show live values
- [ ] The storage breakdown appears after a background scan and doesn't slow the refresh loop
- [ ] Written Today and the per-app writes reset at local midnight
- [ ] SSD health shows "unavailable" with a reason when it can't be read
