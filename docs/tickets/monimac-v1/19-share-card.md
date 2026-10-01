# 19 — Share card

**What to build:** The toolbar share button creates a **share card** of the last 7 days using **WeeklySummary**. The card shows the Mac model, chip, and RAM; the date range; a headline chosen from a rule-based phrase table (e.g. "Busy week, cool head."); a one-line summary of uptime, throttling events, and the busiest app; and stat tiles with sparklines for CPU avg/peak, Memory avg/pressure, GPU avg/peak, Network down/up, and Battery health/cycles. It comes in Light and Dark variants and can be copied or saved as a 1200×630 image. Everything is computed locally, with no network access. The footer shows the project URL.

**Blocked by:** 11 — Overview: Tiles and popover Overview

**Status:** done pending a manual click-through (the share button, the Light/Dark switch, Copy, and Save… are built but not clicked: automation can't click. The preview was opened with `--show-share-card` and the card exported with `--export-share-card`).

**How figures are read:** uptime counts 15-minute history buckets with samples (hours awake with MoniMac recording, so at most 168 h); throttling counts spells of the new 0/1 `thermal.throttled` series (thermal state serious or critical); the busiest app is the one most often behind the hourly CPU peak (peak contributors, as there's no per-app CPU series), so the card says "top CPU user in N of M hours" rather than the design's "18 h of CPU time". Sparklines have 16 bars like the design (the spec says 7 points).

- [ ] The share button opens a preview with a Light/Dark choice (the preview with its Light/Dark control was screenshotted via `--show-share-card`; the toolbar button itself wasn't clicked)
- [x] Stats and the headline are computed from 7 days of history, verified with canned histories
- [ ] Copy and save produce a 1200×630 image (the exported PNG, rendered by the same code, is 1200×630 in both variants; Copy and Save… weren't clicked)
- [x] With less than 7 days of history, the card states the actual range covered (tests, and the real dev history: "LAST 11 HOURS · 1 OCT – 2 OCT 2026")
