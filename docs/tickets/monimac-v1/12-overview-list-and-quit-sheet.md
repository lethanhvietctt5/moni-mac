# 12 — Overview List and quit confirmation

**What to build:** Overview gains a Tiles/List toggle. The **List view** is a table with columns App, Procs, CPU, Memory, GPU, Network, Disk, and Power. It is sortable by any column ("Sorted by …"), searchable by app or process name, and has a "Group processes by app" toggle with expandable groups (e.g. "Google Chrome Helper (Renderer) ×14"). The footer shows what's displayed and system totals. Every "Show All" link opens this view sorted by its metric. Quitting from the table, the popover ×, or a notification shows the **quit sheet**: "Quit <App> and its N processes?", the app's CPU and memory, its top processes with PID/CPU/Memory plus "and N more", a short explanation that Quit closes the app normally, a "Reopen windows next time" checkbox, and Quit, Cancel, and Force Quit buttons.

**Blocked by:** 11 — Overview: Tiles and popover Overview

**Status:** ready-for-agent

- [ ] Sorting, search, and grouping work together, and the footer counts stay correct
- [ ] Show All from a Top Apps section opens the List view sorted by that metric
- [ ] Quit records a graceful quit; Force Quit records a force quit; Cancel records nothing (verified with the recording fake)
- [ ] Quitting a grouped app targets the responsible app, not individual helpers
- [ ] The popover × now opens the quit sheet instead of quitting directly
