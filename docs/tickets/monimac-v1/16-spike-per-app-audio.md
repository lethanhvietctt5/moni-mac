# 16 — Spike: per-app audio feasibility

**What to build:** A time-boxed throwaway prototype to decide whether per-app volume, mute, ducking during calls, and "mute new apps by default" are feasible using Core Audio process taps feeding a MoniMac-owned aggregate output (macOS 14.2+). It must work with a self-signed, non-notarized build. Outputs: a go/no-go decision; the permissions required (audio capture) and the user experience of granting them; latency or quality issues; and how output device switching interacts with the taps. Record the decision in the spec's per-app volume implementation decision. The prototype code is not merged.

**Blocked by:** None — can start immediately

**Status:** done — decision **GO**; see `docs/spikes/16-per-app-audio.md`. Two observations are pending the user's report: the exact prompt wording, and the listening checks (no faint copy of a muted app; whether a muted-by-default app blips at start). Not exercised: output device switching (documented from the API and research), a denied grant (from research), and ducking with a real call.

- [x] The prototype changes one app's volume independently of the others on a real Mac, or a clear reason is documented why it can't
- [ ] The permission prompts and failure modes are documented (the failure modes and the prompt's timing are documented; the exact prompt wording is pending the user's report, and the denied path is from research, not observed)
- [x] The spec's per-app volume decision is updated with go or no-go
