# 20 — Release pipeline and updates

**What to build:** MoniMac can be released without a paid Apple Developer account. CI builds the app, signs it with the stable self-signed certificate (the private key exists only in CI secrets), and publishes it to GitHub Releases along with an update feed whose archives are signed with the project's EdDSA key. An in-app updater checks the feed. Settings › Data & About shows "MoniMac <version> · Free and open source" with a working **Check for Updates…** button. The README and each release note explain installation, including the first-launch **Open Anyway** step in System Settings › Privacy & Security, with screenshots.

**Blocked by:** 13 — Settings: General, Units, Menu Bar Items, Window Tabs

**Status:** ready-for-agent

- [ ] Pushing a release tag produces a signed build and an update feed entry on GitHub Releases
- [ ] A previously installed build detects and installs the update
- [ ] An updated app launches without the Gatekeeper prompt again, or if it can't, "Update available" links to the release page instead
- [ ] Permissions granted before the update (notifications, audio capture, location) are still granted after it
- [ ] The README contains the install steps with the Open Anyway screenshots
