# 19 — Share card

**What to build:** The toolbar share button creates a **share card** of the last 7 days using **WeeklySummary**. The card shows the Mac model, chip, and RAM; the date range; a headline chosen from a rule-based phrase table (e.g. "Busy week, cool head."); a one-line summary of uptime, throttling events, and the busiest app; and stat tiles with sparklines for CPU avg/peak, Memory avg/pressure, GPU avg/peak, Network down/up, and Battery health/cycles. It comes in Light and Dark variants and can be copied or saved as a 1200×630 image. Everything is computed locally, with no network access. The footer shows the project URL.

**Blocked by:** 11 — Overview: Tiles and popover Overview

**Status:** ready-for-agent

- [ ] The share button opens a preview with a Light/Dark choice
- [ ] Stats and the headline are computed from 7 days of history, verified with canned histories
- [ ] Copy and save produce a 1200×630 image
- [ ] With less than 7 days of history, the card states the actual range covered
