# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

MoniMac is a free, open-source macOS system monitor (menu bar items, a popover, and a main window). Native Swift 6, Apple silicon, macOS 14.2+.

## Commands

```bash
# Logic and tests (fast, no Xcode project needed)
swift test --package-path MoniMacKit
swift test --package-path MoniMacKit --filter MoniMacCoreTests.MenuBarTests   # one suite
swift test --package-path MoniMacKit --filter "MenuBarTests/showsTotalCPUPercent()"   # one test

# App (requires `brew install xcodegen`; the .xcodeproj is generated and gitignored)
xcodegen generate
xcodebuild -project MoniMac.xcodeproj -scheme MoniMac -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/MoniMac.app
```

Rerun `xcodegen generate` after adding or removing app source files or editing `project.yml`.

`--show-popover` and `--show-window` open the popover or main window on launch. Add `--tab <name>` (or `--tab=<name>`, a tab's raw value, e.g. `--tab gpu`) to choose its tab, e.g. `open …/MoniMac.app --args --show-window --tab disk`. Automation can't click the status item or the window without Accessibility permission, so use these flags to check UI.

**Screenshots:** use `scripts/screenshot-window.sh window|popover out.png`, which captures one MoniMac window by window ID. **Never capture the full screen or a screen region**: they record the user's other apps. Menu bar items can't be captured, so they're verified by tests.

**Self-cost** (budget: under 1% CPU with the popover and window closed):
- **Build:** measure a **Release** build; Debug is several times slower.
- **Wait:** start at least 60 s after launch. Startup work (SMC key discovery; the storage scan when no saved one is under 6 h old) isn't steady state.
- **Measure:** take the `ps -o cputime` delta over 120 s, or log it in 5 s windows to spot bursts.
- **Compare:** run back to back against a `main` Release build on the same machine, since load from other work skews single readings.
- **Popover:** if someone opens it during a run, SwiftUI re-renders every tick and the reading is invalid; check a `sample` profile for `statusItemClicked`.

## Layout

- `MoniMacKit/`: Swift package with all logic.
  - `MoniMacCore` is pure: Snapshot, the SystemSampler seam, math, formatting, and feature state (`Monitor`).
  - `MoniMacSystem` holds the real sampler and is the **only** target allowed to read OS state.
  - `MoniMacSystemTests` are smoke tests that run against the real Mac.
- **History:** `MetricsHistory` is SQLite (system `SQLite3`) at `~/Library/Application Support/MoniMac/History.sqlite`. Tests use `.inMemory`. Preferences are UserDefaults (`io.github.lethanhvietctt5.MoniMac`), so `defaults write` can switch settings while developing.
- **Per-metric files:** each metric (Memory, GPU, Network, Disk, Battery, Thermal) has its own files, so tickets don't edit shared code:
  - **`MoniMacCore/Metrics/<Metric>.swift`** holds:
    - the reading type
    - `Snapshot.<metric>Series` (`[SeriesSample]`; a sample can carry a `contributor`, e.g. the busiest app, which peaks report)
    - a `MenuBarMetric` (text, sparkline bars, and widest text that follows units)
    - `Monitor.<metric>Subtitle`, plus feature state as further `Monitor` extensions (e.g. `hasBattery`)
    - metric-specific settings, as `Preferences` extensions keyed `"<metric>.…"`
  - **`MoniMacSystem/<Metric>Reader.swift`** is the sampler. GPU and Network also have an `annotate` hook that adds per-process figures, called only when the process list refreshes.
  - **`App/Sources/<Metric>Views.swift`** holds the popover and window tabs. They get a `range` binding kept by the popover or window.

  Shared switches already route to all of these. Per-process memory, disk, and power (`ResourceUse`) come from `ProcessReader`.
- **Metric-file names** are prefixed with the metric (`DiskFormat`, `SeriesKey.networkDown…`, `Palette` extensions), so files written in parallel never declare the same name.
- **History for totals:** series that record an amount per sample (e.g. bytes since the previous sample) support `MetricsHistory.sum(from:to:)` for "since launch" (`Monitor.startedAt`) or "today", and `dailyTotals` for per-day charts.
  - **Per-app series** use keys `<metric>.app:<id>`, recorded only when nonzero, and are read with `sums(prefix:from:to:)`. `peak(from:to:)` gives a peak since a time, e.g. midnight.
  - **Past windows:** query them through a range whose tier still holds the data. The minute tier behind 24H is pruned after about 25 h, so "yesterday's 24H average" must come from the 7D (15-minute) tier.
  - **Worst level in a bucket:** buckets keep averages. To show a bucket's worst level (e.g. memory pressure), record 0/1 indicator series.
- **Naming:** data types say *Thermal* (thermal state, sensors, fans). UI says *Temperature* (`Metric.temperature`, `TemperatureMenuBar`, the "Temperature & Fans" tab).
- `App/`: thin AppKit shell (status items now, the popover and window later) that renders `Monitor`'s feature state. `project.yml` builds it.
- **Signing:** `Config/Signing.xcconfig` defaults to ad-hoc. For a stable identity, so that granted permissions survive rebuilds, run `scripts/create-signing-cert.sh` once and set `CODE_SIGN_IDENTITY` in the gitignored `Config/Local.xcconfig`.

## Sources of truth

- **Spec:** `docs/specs/monimac-v1.md`. It is an umbrella spec: problem, user stories, architecture, testing decisions, and out of scope.
- **Tickets:** `docs/tickets/monimac-v1/`, one file per vertical slice, numbered in dependency order. Each has "Blocked by", "Status", and acceptance criteria. Pick any ticket whose blockers are done, and follow the workflow below.
- **UI designs:** `/Users/mb/Documents/moni-mac-designs.pen`, which is outside the repo. Read and edit it only through the Pencil MCP tools (`mcp__pencil__*`). Never use Read or Grep on `.pen` files; they are encrypted. Top-level frames: Templates, MoniMac Screens (Menu Bar, Popover & Alerts · Main Window — System Metrics · Main Window — Devices, Developer & Settings), Components (reusable: Sidebar Item, App Row, Metric Tile, Segmented Control, Section Header, Toggle).
- Numbers in the designs are sample data, not requirements. The spec's Further Notes lists the known inconsistencies.
- New specs go in `docs/specs/` as markdown. There is no issue tracker.

## Workflow per ticket

1. Branch from an up-to-date `main` as `feat/NN-slug`, one branch per ticket.
2. Build the slice: Core feature state and tests first, then the sampler, then the UI.
3. Verify:
   - `swift test` is green.
   - The app builds with no warnings.
   - Screenshots of the new UI match the Pencil design.
   - Self-cost on a Release build stays under 1% CPU when the ticket adds sampling.
4. **Review before merging.** Run the `mattpocock-skills:code-review` skill on the changes since the branch's merge-base with `main`. Fix what it finds and rerun the checks in step 3. Findings you deliberately don't fix go in the PR with the reason.
5. Tick only the acceptance criteria you actually observed. Note anything built but not exercised (e.g. clicks automation can't make).
6. Open the PR. Its body says what was verified, the review outcome, and what's still unverified. Merge with a merge commit and delete the branch.

## Architecture (from the spec; built incrementally by the tickets)

Native Swift: SwiftUI for the window and popover, AppKit where needed (status items, popover window, sheets). Apple silicon, macOS 14.2+.

There are two seams, and they are the only things faked in tests:

- **SystemSampler:** the only module that reads OS state (IOKit/SMC, host and process statistics, IOReport, CoreAudio, IOBluetooth, network statistics, Docker socket). On each refresh it emits one immutable **Snapshot**. Data the Mac can't provide is absent with a reason, never zero.
- **SystemActions:** the only module with side effects: quit or force quit an app, per-app and system volume, output device, stop a dev server or container, and opening URLs, Finder, System Settings, or Activity Monitor.

Everything else is pure logic over snapshots and history:

- **MetricsHistory:** a local SQL store with resolution tiers. It answers range queries (1m/5m/1H/24H and 12H/24H/7D/30D) with avg, peak, peak time, and the top contributor at the peak.
- **AppGrouping:** rolls helper processes up into their apps.
- **AlertEngine:** threshold rules, one alert per ongoing condition.
- **ProjectCatalog:** finds dev servers and containers, groups them by project, and decides idleness.
- **WeeklySummary:** the share card.
- **Formatting:** units and CPU mode.
- **Preferences:** all settings plus layout state.

Views hold no logic; they render feature state derived from the modules above.

Tests feed scripted snapshots and a controlled clock through the fake sampler, then assert on user-visible feature state, emitted alerts, and actions recorded by the fake SystemActions. Run MetricsHistory against a real in-memory store, not a mock.

## Decisions that constrain code

- **CPU % mode** ("System" 0–100% vs "Per-core" up to N×100%) is one setting applied on every surface, including notifications. Never let a surface pick its own.
- **No fan control.** Temperature & Fans is read-only. MoniMac reads the SMC and never writes to it, and there is no privileged helper or anything needing admin rights.
- **No paid Apple Developer account.** There is no notarization and no Developer ID. Releases are signed with a stable self-signed certificate, so that granted permissions (notifications, audio capture, location) survive updates; ad-hoc signing breaks this. The official Homebrew cask repository is not an option.
- **Not sandboxed, not on the Mac App Store, no licensing or payments.**
- **Menu bar reorder and hide** use the system's ⌘-drag behavior. Don't build a custom drag UI in the menu bar.
- **Per-app volume** (Core Audio process taps) needs a feasibility spike first. If it fails, Sound ships without per-app sliders.
- **Process sampling (no privileged helper):** own-user processes come from `proc_pid_rusage` (every 4 s; its times are Mach absolute units, converted with `mach_timebase_info`). Other users' processes come from the setuid `/bin/ps` in the background (every 15 s). Helpers are attributed via the private responsible-pid call, with a fallback to the outermost `.app` in the path. Quit (×) is offered only for running regular apps.
- **Metric sources** (no privileges needed; each reader is throttled to how fast its value changes):
  - **Memory:** `host_statistics64` VM info, `vm.swapusage`, `kern.memorystatus_vm_pressure_level`. Sizes are binary (GB = 2³⁰); there's no cheap memory-type source, so it reads "unified memory".
  - **GPU:**
    - totals come from the IOAccelerator `PerformanceStatistics` dictionary
    - per-app use comes from `AGXDeviceUserClient` `AppUsage.accumulatedGPUTime` (ns)
    - read single keys only, never whole property tables
  - **Network:**
    - totals sum the `en*` interfaces' 64-bit counters (`NET_RT_IFLIST2`), timed with a clock that runs through sleep
    - per-app traffic comes from `nettop -t external` in the background
    - Location (for the Wi-Fi name) is requested only when a Network tab appears; ad-hoc rebuilds can reset the grant
  - **Disk:**
    - read/write rates come from `IOBlockStorageDriver` statistics
    - SSD health comes from NVMe SMART through the NVMeSMARTLib plug-in
    - purgeable space is read every 5 min in the background
    - the storage scan never reads Documents, Desktop, Downloads, or other apps' containers (Documents is a remainder, so no privacy prompt). It is saved in `StorageScan.json` and reused for 6 h.
    - sizes are decimal
  - **Battery:**
    - `IOPowerSources` plus the `AppleSmartBattery` registry; on macOS 27 temperature and capacity keys moved under `BatteryData`
    - health = nominal ÷ design capacity
    - the charging series records "adapter connected"
    - `hasBattery` is false before the first sample
  - **Thermal:**
    - SMC read-only calls, with sensor key tables per Apple silicon generation. Unknown keys are counted, never given guessed names.
    - IOHID is a fallback only
    - chart times use 24-hour `HH:mm`
- **Name:** the product is **MoniMac**; the repo is `moni-mac`. "Vitals" was its old name.
