<p align="center"><img src="docs/images/icon.png" width="128" height="128" alt="MoniMac icon"></p>

# MoniMac

A free, open-source system monitor for your Mac's menu bar. MoniMac shows CPU, memory, GPU, network, disk, battery, and temperatures as menu bar items, in a popover, and in a main window with history, per-app usage, and dev servers and containers grouped by project.

- Native Swift for Apple silicon, macOS 14.2 or later
- Reads the system without admin rights or a privileged helper; never writes to the SMC (no fan control)
- No account, no license, no telemetry

**Website:** the landing page's source is in [`site/`](site/README.md) (React and Vite; deploys to Vercel from `site/`).

## Install

1. Download **MoniMac-x.y.z.dmg** from the [latest release](https://github.com/lethanhvietctt5/moni-mac/releases/latest) and open it.
2. Drag **MoniMac** onto the **Applications** shortcut next to it, then eject the disk image.
3. In Terminal, run this once:

   ```bash
   xattr -dr com.apple.quarantine /Applications/MoniMac.app
   ```

4. Open MoniMac from Applications, or with `open -a MoniMac`.

Why step 3: MoniMac isn't notarized by Apple, which needs a paid developer account, so macOS blocks it while it carries the "downloaded from the internet" flag. The command removes that flag. You only do it on the first install; updates from **Check for Updates…** don't need it.

## Updates

MoniMac updates itself with [Sparkle](https://sparkle-project.org). On its second launch it asks whether to check for updates automatically; you can also check any time in **Settings › Data & About › Check for Updates…**. The update feed is published with each [GitHub release](https://github.com/lethanhvietctt5/moni-mac/releases).

- **Updates are verified.** Every update archive is signed with the project's EdDSA key. Sparkle installs an update only if that signature matches the public key MoniMac ships with, *or* the new app is code-signed with the same certificate as the installed one ([`SUUpdateValidator.m`](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SUUpdateValidator.m)).
- **No Terminal step for updates.** Sparkle clears the quarantine flag from the update it installs ([Sparkle's installation docs](https://github.com/sparkle-project/Sparkle/blob/2.x/Documentation/Installation.md), "Regular application installer 1st stage"), so the `xattr` command is needed on the first install only.
- **Permissions may be asked again.** macOS remembers permissions (notifications, audio capture, location) by the app's code signature. Releases are signed ad-hoc, so each version has a new signature and macOS may ask for them again after an update.

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

Releases are published from the maintainer's Mac. No Apple account, signing certificate, or CI secrets are needed: the app is signed ad-hoc and packed into a DMG, and only the Sparkle update key is required, so that installed copies trust updates from **Check for Updates…**.

**Once:** create the update key. `generate_keys` (from the Sparkle package, after one build) stores it in your login keychain and prints the public key; `-x` exports a copy for the release script. Back that file up somewhere safe: without it, installed copies can't be updated.

```bash
SPARKLE=build/release/SourcePackages/artifacts/sparkle/Sparkle/bin
$SPARKLE/generate_keys                                  # prints the public key
mkdir -p ~/.monimac && $SPARKLE/generate_keys -x ~/.monimac/sparkle-ed-key && chmod 600 ~/.monimac/sparkle-ed-key
```

Put the public key in `project.yml` (`SUPublicEDKey`) and commit it.

**Each release**, from an up-to-date `main`:

```bash
scripts/release/release-local.sh v1.2.3 --dry-run   # builds dist/MoniMac-1.2.3.dmg and appcast.xml, publishes nothing
scripts/release/release-local.sh v1.2.3             # tags, then publishes the GitHub release with the DMG and appcast
```

Because each release is signed ad-hoc, macOS may ask users again for permissions after an update. A stable self-signed certificate avoids that; [`.github/workflows/release.yml`](.github/workflows/release.yml) (run by hand) and `scripts/release/setup-wizard.sh` set that up, with three repository secrets.
