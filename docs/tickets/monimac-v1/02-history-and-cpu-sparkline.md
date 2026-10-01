# 02 — History + CPU sparkline in the menu bar

**What to build:** Adds **MetricsHistory**: snapshots are stored locally in resolution tiers (full refresh rate for about the last hour, one-minute buckets for 24 h, coarser buckets up to the retention period) and answer range queries with avg, peak, peak time, and the top contributor at the peak. The CPU menu bar item gains the **Graph** style (a 60-second sparkline) and the **Both** style (value + graph). Tests run MetricsHistory against a real in-memory store, never a mock.

**Blocked by:** 01 — CPU % in the menu bar

**Status:** done

**Note:** the spec's "top contributor at the peak" needs per-app series, which arrive with per-process sampling in ticket 03. It is built when a ticket first shows it: ticket 06 (GPU peak with app) or ticket 10 (temperature peak with cause).

- [x] The CPU menu bar item can show Value, Graph (last 60 s), or Both
- [x] History survives an app relaunch
- [x] Range queries for 1m/5m/1H/24H and 12H/24H/7D/30D return avg, peak, and peak time, verified with scripted snapshot sequences
- [x] Older data is downsampled into coarser tiers, and data older than the retention period (default 30 days) is pruned
- [x] Recording history at a 2 s refresh keeps MoniMac under about 1% average CPU with the popover closed
