# 16 — Spike: per-app audio feasibility

**What to build:** A time-boxed throwaway prototype to decide whether per-app volume, mute, ducking during calls, and "mute new apps by default" are feasible using Core Audio process taps feeding a MoniMac-owned aggregate output (macOS 14.2+). It must work with a self-signed, non-notarized build. Outputs: a go/no-go decision; the permissions required (audio capture) and the user experience of granting them; latency or quality issues; and how output device switching interacts with the taps. Record the decision in the spec's per-app volume implementation decision. The prototype code is not merged.

**Blocked by:** None — can start immediately

**Status:** done — decision **GO**; see `docs/spikes/16-per-app-audio.md`. The user saw the prompt (system audio recording, Allow / Don't Allow) but doesn't remember its exact wording. Three things are not confirmed by ear and were measured digitally only: that a muted app is fully silent, whether a muted-by-default app blips at start, and the purple recording indicator. Not exercised: output device switching (documented from the API and research), a denied grant (from research), and ducking with a real call.

- [x] The prototype changes one app's volume independently of the others on a real Mac, or a clear reason is documented why it can't
- [x] The permission prompts and failure modes are documented. The prompt and its Allow / Don't Allow buttons were observed, and its timing was measured. The exact wording is unconfirmed, and the denied path comes from research, not observation.
- [x] The spec's per-app volume decision is updated with go or no-go
