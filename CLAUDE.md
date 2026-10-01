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

`--show-popover` (e.g. `open …/MoniMac.app --args --show-popover`) opens the popover on launch. Automation can't click the status item without Accessibility permission, so use this flag to screenshot the popover. Measure self-cost (budget: under 1% CPU with the popover closed) on a **Release** build; Debug is several times slower.

## Layout

- `MoniMacKit/`: Swift package with all logic.
  - `MoniMacCore` is pure: Snapshot, the SystemSampler seam, math, formatting, and feature state (`Monitor`).
  - `MoniMacSystem` holds the real sampler and is the **only** target allowed to read OS state.
  - `MoniMacSystemTests` are smoke tests that run against the real Mac.
- **History:** `MetricsHistory` is SQLite (system `SQLite3`) at `~/Library/Application Support/MoniMac/History.sqlite`. Tests use `.inMemory`. Preferences are UserDefaults (`io.github.lethanhvietctt5.MoniMac`), so `defaults write` can switch settings while developing.
- `App/`: thin AppKit shell (status items now, the popover and window later) that renders `Monitor`'s feature state. `project.yml` builds it.
- **Signing:** `Config/Signing.xcconfig` defaults to ad-hoc. For a stable identity, so that granted permissions survive rebuilds, run `scripts/create-signing-cert.sh` once and set `CODE_SIGN_IDENTITY` in the gitignored `Config/Local.xcconfig`.

## Sources of truth

- **Spec:** `docs/specs/monimac-v1.md`. It is an umbrella spec: problem, user stories, architecture, testing decisions, and out of scope.
- **Tickets:** `docs/tickets/monimac-v1/`, one file per vertical slice, numbered in dependency order. Each has "Blocked by", "Status", and acceptance criteria. Pick any ticket whose blockers are done, and tick its criteria and update its status as you finish.
- **UI designs:** `/Users/mb/Documents/moni-mac-designs.pen`, which is outside the repo. Read and edit it only through the Pencil MCP tools (`mcp__pencil__*`). Never use Read or Grep on `.pen` files; they are encrypted. Top-level frames: Templates, MoniMac Screens (Menu Bar, Popover & Alerts · Main Window — System Metrics · Main Window — Devices, Developer & Settings), Components (reusable: Sidebar Item, App Row, Metric Tile, Segmented Control, Section Header, Toggle).
- Numbers in the designs are sample data, not requirements. The spec's Further Notes lists the known inconsistencies.
- New specs go in `docs/specs/` as markdown. There is no issue tracker.

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
- **Name:** the product is **MoniMac**; the repo is `moni-mac`. "Vitals" was its old name.
