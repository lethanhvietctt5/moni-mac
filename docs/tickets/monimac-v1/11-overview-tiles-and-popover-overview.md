# 11 — Overview: Tiles and popover Overview

**What to build:** The window's **Overview** tab in the Tiles view shows tiles for CPU, Memory, GPU, Network, Disk, Battery, Temperature, and Processes. Each has a big value, a sparkline, and a caption, e.g. "User 21% · System 11%", "Charging · Full in 38 min", or "61 apps · 38 apps · 17 agents · 6 system". **Busiest Right Now** lists apps with their dominant resource (e.g. "Time Machine 9.4 MB/s"). The **popover Overview tab** lists every metric with a colored bar, plus Busiest Right Now with process counts and an "Open MoniMac" link. AppGrouping classifies apps as app, agent, or system.

**Blocked by:** 05 — Memory end to end; 06 — GPU end to end; 07 — Network end to end; 08 — Disk end to end; 09 — Battery end to end; 10 — Temperature & Fans (read-only)

**Status:** in review. Seen in the running app (window and popover screenshots). Clicks automation can't make are not yet exercised: the popover's "Open MoniMac" link, the Overview tab buttons, and the Tiles/List toggle (List is ticket 12 and is disabled).

- [x] The window Overview Tiles view shows all 8 tiles with live values and sparklines (the Processes tile shows the design's apps / agents / system bar in the sparkline's place)
- [x] Busiest Right Now labels each app by the resource it uses most
- [x] The popover Overview tab shows every metric row and the busiest apps
- [x] The Processes tile counts apps, agents, and system processes, plus total processes and threads
