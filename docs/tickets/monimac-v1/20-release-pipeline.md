# 20 — Release pipeline and updates

**What to build:** MoniMac can be released without a paid Apple Developer account. CI builds the app, signs it with the stable self-signed certificate (the private key exists only in CI secrets), and publishes it to GitHub Releases along with an update feed whose archives are signed with the project's EdDSA key. An in-app updater checks the feed. Settings › Data & About shows "MoniMac <version> · Free and open source" with a working **Check for Updates…** button. The README and each release note explain installation, including the first-launch **Open Anyway** step in System Settings › Privacy & Security, with screenshots.

**Blocked by:** 13 — Settings: General, Units, Menu Bar Items, Window Tabs

**Status:** v0.1.0 published (2026-10-02) by `scripts/release/release-local.sh`. The maintainer chose the simple path: an ad-hoc signed DMG built on their Mac, plus the Sparkle key for **Check for Updates…**; no certificate, CI secrets, or tag-triggered workflow (`release.yml` is now manual and optional). Open: the update path, which needs the repo public (the maintainer is doing that) and a v0.1.1 release.

**Built:**
- **Updater:** Sparkle 2.10.0 (SPM, pinned), started by `App/Sources/UpdateController.swift`.
  - The feed is `releases/latest/download/appcast.xml`.
  - `SUPublicEDKey` is a placeholder until the wizard's stage 6.
  - Only builds made by `scripts/release/build.sh` (`MONIMAC_UPDATES=YES`) start Sparkle.
  - Development builds show "Free and open source · Development build" with the button disabled.
  - The About row's second line reports Sparkle's result ("You're up to date", "MoniMac x.y.z is available").
- **Workflow:** `.github/workflows/release.yml`, on `v*` tags only. Its logic is in `scripts/release/*.sh`.
- **README:** install steps, with placeholders for the two Open Anyway screenshots.

**Verified locally:**
- `swift test` green. Debug and Release builds link and embed Sparkle with no new warnings (only the existing AppIntents notice).
- `make-release.sh v0.1.0 --dry-run` ran end to end with a throwaway EdDSA key file (scratchpad only, never in the app):
  - Release build with version 0.1.0 from the tag.
  - Re-signing Sparkle's helpers and the app (ad-hoc in the dry run); `codesign --verify --deep --strict` passes, including on the unzipped archive.
  - `ditto` zip, with the framework symlinks intact.
  - `sign_update` with the key on stdin. The signature verifies with Sparkle's own `sign_update --verify` and independently with CryptoKit against the public key.
  - A well-formed `appcast.xml` and the release notes.
- The scripts refuse what they should:
  - the placeholder key, a malformed key, and a build with updates off
  - a signature from another key, and a tampered archive
  - `--dry-run`, `import-certificate.sh`, and `publish.sh` outside their intended context
- **Debug launch:** Sparkle isn't started; no feed contact, no prompt.
- **Release build with updates on and the placeholder key:** start fails, is logged ("The EdDSA public key is not valid"), and shows no alert.
- **Screenshot:** Settings › Data & About.

**Deferred:**
- **The criterion 3 fallback** ("Update available" linking to the release page) isn't built. Sparkle clears quarantine on the update it installs (`Documentation/Installation.md`; `SUPlainInstaller.m`), so it shouldn't be needed. Wizard stage 10 checks this on a real update and points to the fallback if Gatekeeper prompts anyway.
- **Permission persistence** is exercised with Location only. Notifications (ticket 14) and audio capture (ticket 17) aren't in this build; the wizard asks the maintainer to grant them too once they are.

**Unverified until the first tags:**
- the "Check for Updates…" press and Sparkle's check window; the About line's "You're up to date" and "is available" transitions; the button disabling during a check. All of these need a real key, and wizard stage 10 exercises them.
- the workflow on a runner (`macos-26`, newest Xcode)
- the certificate import and trust on the runner
- Sparkle accepting a self-signed update on another Mac
- macOS App Management allowing a self-update without a Team ID
- Gatekeeper and permissions after an update

- [x] Publishing a release produces an update feed entry on GitHub Releases: `release-local.sh v0.1.0` published `MoniMac-0.1.0.dmg` and `appcast.xml`; the DMG downloaded back from GitHub is byte-identical and its EdDSA signature verifies against the key the app ships. (Originally "pushing a tag produces a signed build"; tags no longer trigger CI, and the build is ad-hoc signed by choice.)
- [ ] A previously installed build detects and installs the update
- [ ] An updated app launches without the Gatekeeper prompt again, or if it can't, "Update available" links to the release page instead
- [ ] After an update, MoniMac runs and its permissions are either kept or asked for again (ad-hoc signing gives each release a new signature, so macOS may ask again; the maintainer accepted this instead of a stable certificate)
- [x] The README and every release's notes contain the install steps: open the DMG, drag MoniMac to Applications, then run `xattr -dr com.apple.quarantine /Applications/MoniMac.app` in Terminal once (the maintainer's users prefer Terminal to System Settings › Open Anyway, so no screenshots are needed)
