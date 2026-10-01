# 01 — CPU % in the menu bar

**What to build:** The first tracer bullet. MoniMac launches as a menu-bar-only app and shows live total CPU % as a Value-style menu bar item, refreshing every 2 s. This sets up the native Swift app and the first seam: **SystemSampler** (CPU totals only for now) emits one immutable **Snapshot** per tick. Tests run against a **fake sampler** that replays scripted snapshots, with a controllable clock, and assert on the menu bar item's feature state (the text it shows), not on views. Releases and local builds are signed with a stable self-signed certificate from day one, so that permissions granted during development survive rebuilds. The project's build, test, and single-test commands are added to CLAUDE.md.

**Blocked by:** None — can start immediately

**Status:** in progress — only the signing criterion is open; it needs the maintainer to run `scripts/create-signing-cert.sh` (keychain password prompt) and set `Config/Local.xcconfig`

- [x] Launching the app shows no Dock icon and adds one MoniMac menu bar item showing CPU % (e.g. `32%`) that updates on each refresh
- [x] The menu bar text uses compact, fixed-width-feeling formatting so it doesn't jitter as values change
- [x] A fake SystemSampler and test clock exist; a test feeds a scripted snapshot sequence and asserts the menu bar item's displayed text
- [x] No module other than SystemSampler reads OS state
- [ ] The app is signed with a stable self-signed identity, documented for contributors
- [x] CLAUDE.md lists the build, test, and run-one-test commands
