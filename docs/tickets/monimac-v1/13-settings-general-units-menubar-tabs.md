# 13 — Settings: General, Units, Menu Bar Items, Window Tabs

**What to build:** The **Settings** tab. It covers:
- General: launch at login, refresh interval (1s/2s/5s), and "Show icon in Dock".
- Units: °C/°F, MB/s or Mbps, and CPU usage as "System" or "Per-core".
- Menu Bar Items: enable checkbox, Value/Graph/Both, and a drag handle for each metric.
- Window Tabs: chips that show or hide tabs (✓ when shown, + when hidden).
- Keep history retention.

Sidebar tabs can be dragged to reorder them, and sections inside each tab can be rearranged; layouts persist. **CPU mode is one setting applied on every surface**, which explains why the design shows 412% in some places and 12.4% in others. Menu bar items reorder through the system's ⌘-drag; MoniMac only persists visibility and style.

**Blocked by:** 11 — Overview: Tiles and popover Overview

**Status:** ready-for-agent

- [ ] Changing the refresh interval changes the sampling rate
- [ ] Switching CPU mode changes CPU values in the menu bar, popover, window, and list consistently
- [ ] Unit switches apply everywhere temperatures and network speeds appear
- [ ] Hiding a window tab removes it from the sidebar; the chip shows + and can add it back
- [ ] Sidebar order and section order persist across relaunches
- [ ] Changing Keep history prunes data beyond the new limit
- [ ] Launch at login and the Dock icon toggle take effect
