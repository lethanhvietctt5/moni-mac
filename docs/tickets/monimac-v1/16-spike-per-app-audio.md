# 16 — Spike: per-app audio feasibility

**What to build:** A time-boxed throwaway prototype to decide whether per-app volume, mute, ducking during calls, and "mute new apps by default" are feasible using Core Audio process taps feeding a MoniMac-owned aggregate output (macOS 14.2+). It must work with a self-signed, non-notarized build. Outputs: a go/no-go decision; the permissions required (audio capture) and the user experience of granting them; latency or quality issues; and how output device switching interacts with the taps. Record the decision in the spec's per-app volume implementation decision. The prototype code is not merged.

**Blocked by:** None — can start immediately

**Status:** ready-for-agent

- [ ] The prototype changes one app's volume independently of the others on a real Mac, or a clear reason is documented why it can't
- [ ] The permission prompts and failure modes are documented
- [ ] The spec's per-app volume decision is updated with go or no-go
