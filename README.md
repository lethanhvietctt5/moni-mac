<p align="center"><img src="docs/images/icon.png" width="128" height="128" alt="MoniMac icon"></p>

# MoniMac

A free, open-source system monitor for your Mac's menu bar. MoniMac shows CPU, memory, GPU, network, disk, battery, and temperatures as menu bar items, in a popover, and in a main window with history, per-app usage, and dev servers and containers grouped by project.

- Native Swift for Apple silicon, macOS 14.2 or later
- Reads the system without admin rights or a privileged helper; never writes to the SMC (no fan control)
- No account, no license, no telemetry

## Install

1. Download **MoniMac-x.y.z.dmg** from the [latest release](https://github.com/lethanhvietctt5/moni-mac/releases/latest) and open it.
2. Drag **MoniMac** onto the **Applications** shortcut next to it, then eject the disk image.
3. Open MoniMac. macOS says it can't verify that MoniMac is free of malware. Click **Done**.

   > **Screenshot placeholder:** `docs/images/install-blocked.png`, the dialog macOS shows on first launch.
   > The maintainer adds it in stage 9 of `scripts/release/setup-wizard.sh`.

4. Open **System Settings › Privacy & Security**, scroll down to **Security**, and click **Open Anyway** next to "MoniMac was blocked". Confirm with **Open Anyway** and your password.

   > **Screenshot placeholder:** `docs/images/install-open-anyway.png`, the Security section with Open Anyway.
   > The maintainer adds it in stage 9 of `scripts/release/setup-wizard.sh`.

Why the extra step: MoniMac isn't notarized by Apple, which needs a paid developer account. Since macOS 15, right-click › Open no longer gets around this; Open Anyway does, and you only do it once. If you prefer Terminal, `xattr -dr com.apple.quarantine /Applications/MoniMac.app` does the same.

## Updates

MoniMac updates itself with [Sparkle](https://sparkle-project.org). On its second launch it asks whether to check for updates automatically; you can also check any time in **Settings › Data & About › Check for Updates…**. The update feed is published with each [GitHub release](https://github.com/lethanhvietctt5/moni-mac/releases).

- **Updates are verified.** Every update archive is signed with the project's EdDSA key. Sparkle installs an update only if that signature matches the public key MoniMac ships with, *or* the new app is code-signed with the same certificate as the installed one ([`SUUpdateValidator.m`](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SUUpdateValidator.m)).
- **No second Open Anyway.** Sparkle clears the quarantine flag from the update it installs ([Sparkle's installation docs](https://github.com/sparkle-project/Sparkle/blob/2.x/Documentation/Installation.md), "Regular application installer 1st stage"), and Gatekeeper's first-launch check applies to quarantined apps, so the Open Anyway step happens on first install only.
- **Permissions carry over.** macOS remembers permissions (notifications, audio capture, location) by the app's code signature. Every release is signed with the same self-signed certificate, so an update keeps them. Builds you make yourself are signed differently; see below.

Development builds (anything you build yourself) never check for updates.

## Build from source

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
swift test --package-path MoniMacKit       # logic and tests
xcodegen generate                          # the Xcode project is generated, not committed
xcodebuild -project MoniMac.xcodeproj -scheme MoniMac -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/MoniMac.app
```

Builds are ad-hoc signed by default, so macOS asks for permissions again after each rebuild. To keep them, create a stable identity once with `scripts/create-signing-cert.sh` and add `CODE_SIGN_IDENTITY = MoniMac Self-Signed` to `Config/Local.xcconfig` (gitignored). See `Config/Signing.xcconfig`.

## Releasing

Pushing a tag like `v1.2.3` runs [`.github/workflows/release.yml`](.github/workflows/release.yml), which builds, signs, packs the app into a disk image, signs the image for Sparkle, writes `appcast.xml`, and publishes the GitHub release with install notes. The steps live in [`scripts/release/`](scripts/release/) and run locally too:

```bash
scripts/release/make-release.sh v1.2.3 --dry-run   # needs SPARKLE_ED_PRIVATE_KEY; never publishes
```

**First-time setup** (signing certificate, EdDSA key, GitHub secrets, the first two releases) is guided by the wizard:

```bash
scripts/release/setup-wizard.sh
```

It shows every command before running it and asks first. The workflow needs three repository secrets: `MONIMAC_CERT_P12`, `MONIMAC_CERT_PASSWORD`, and `SPARKLE_ED_PRIVATE_KEY`. It refuses to release while `SUPublicEDKey` in `project.yml` is still the placeholder.
