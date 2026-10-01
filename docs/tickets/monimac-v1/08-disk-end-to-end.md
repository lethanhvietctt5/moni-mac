# 08 — Disk end to end

**What to build:** Disk joins the popover and the window. The sampler adds volume name/format/capacity, free and purgeable space, read/write rates, bytes written, SSD health and lifetime writes, and per-process disk bytes. The **window Disk tab** shows free space, read/write cards with today's peaks, Written Today with SSD health, a storage breakdown bar (Applications, Developer, Documents, macOS, Purgeable, Free), a Read & Write history chart with ranges, and Disk Writes Today ranked by app. The storage breakdown is computed in the background on a slow schedule and cached; it is never recalculated on every tick.

**Blocked by:** 03 — Popover with CPU tab, top apps, and quit; 04 — Main window with CPU tab

**Post-merge (perf/self-cost):** the storage scan is now saved and reused across relaunches for 6 h, or until free space moves by more than max(5 GB, 2%). Surfaces show "Scanned … ago" once it's 10 min old. The self-cost figures below predate this.

**Status:** done pending a manual click-through (range switching and tooltips need clicks). Unchecked boxes are built and covered by tests but not observed live.

**Notes:**
- Each tick costs a `statfs` and one IOKit read of the startup drive's `IOBlockStorageDriver` "Statistics". The drive is found by walking up from the root volume's media, so disk images and other drives aren't counted.
- SSD health and lifetime writes come from the NVMeSMARTLib plug-in. It works unprivileged on Apple silicon (98% / 54 TB on the dev Mac). Drives without it show "SSD health unavailable" and the reason.
- Purgeable space (`volumeAvailableCapacityForImportantUsage`, ~15 ms per read) and the macOS volumes' size (`ATTR_VOL_SPACEUSED` on the Data volume) are read in the background every 5 minutes.
- The storage scan runs at utility QoS 10 s after launch, then every 6 hours. It walks about 1.15M entries in ~23 s wall and ~10 s CPU on the dev Mac, and is capped at 5M entries. It reads only folders that never prompt for privacy. **Documents is the remainder** of the Data volume after the other categories, labelled "Files, app data & other". `StorageBreakdown` documents each category.
- Per-app writes are sparse `disk.written.app:<app id>` amounts, each a rate × the time since the previous sample, so the 4 s process rates reused on 2 s ticks aren't double counted. Apps that wrote and then quit stay ranked for the rest of the day. These are each process's logical writes to any volume, so they needn't add up to the drive's Written Today.
- Peaks are today's (from local midnight) and keep the busiest app as contributor, which the tooltip shows.
- Shared edits: `MetricsHistory.sums(prefix:from:to:)` and `peak(_:from:to:)`, and `CPUDetail.xAxis` made internal so Disk reuses it.

- [x] The popover and window Disk tabs show live values (screenshots of both, Release and Debug builds)
- [x] The storage breakdown appears after a background scan and doesn't slow the refresh loop ("Scanning storage…" then the bar. Release, popover closed: 0.43% over 60 s from t=85 s vs 0.48% on main; a 120 s window starting 15 s after the scan's log line read 0.83%. A profile shows disk code at ~0.02% of a core per tick)
- [ ] Written Today and the per-app writes reset at local midnight (feature-state tests with a controlled clock, for both raw and bucketed history; not observed across a real midnight)
- [ ] SSD health shows "unavailable" with a reason when it can't be read (feature-state tests for each reason; this Mac's SSD reports health, so not seen live)
