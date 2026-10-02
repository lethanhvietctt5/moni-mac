# 15 — Bluetooth

**What to build:** The **Bluetooth** tab. It shows the connected device count and a featured card for an AirPods-class device: connection state, what it's playing from, noise-control mode, firmware, listening time left, and Left/Right/Case battery rings. An **Other Devices** list shows each device's type, connection state, battery bar and %, and a status hint ("Charged 6 days ago", "Low — charge soon", "Last seen yesterday, 22:42"), with low batteries in red. An "Open Bluetooth Settings…" link and a **Low battery notifications** toggle notify you when any connected device drops below 20%, through AlertEngine. MoniMac only displays devices; it doesn't connect or pair them.

**Blocked by:** 04 — Main window with CPU tab; 14 — Alerts and notifications

**Status:** done pending checks with real connected devices. No Bluetooth device was connected to the Mac this was built on, so connected devices, AirPods levels, and "last seen" were exercised through tests and the `--bluetooth-fixture` flag, not real hardware.

**Notes:**
- **Sources (no prompt, no usage description):**
  - `system_profiler SPBluetoothDataType -json` lists every paired device, connected or not, with its type (`device_minorType`), firmware, and levels (`device_batteryLevelMain/Left/Right/Case`, percent strings). system_profiler gets them from bluetoothd through its own `com.apple.bluetooth.system` entitlement, so MoniMac never touches Bluetooth. Launching MoniMac with it running logged no `kTCCServiceBluetooth*` request in tccd, and the device list matched the paired devices.
  - IOKit `AppleDeviceManagementHIDEventService` (`BatteryPercent`, `DeviceAddress`, `BatteryStatusFlags` bit 0x2 = charging) fills in Apple's Magic peripherals, whose level system_profiler doesn't report. Three keys are read per entry, never whole tables.
  - **IOBluetooth was ruled out:** listing devices with it raises the Bluetooth privacy prompt, needs `NSBluetoothAlwaysUsageDescription`, and has no AirPods levels. No usage string was added.
- **Cadence and cost:** reads run in the background only when something needs them (`BluetoothDemand`):
  - every 30 s while the Bluetooth tab is on screen (window open on it and not covered or minimized)
  - every 5 min while Low battery notifications are on (the default), starting 10 s after launch
  - never otherwise
  - One read costs ~1 ms of CPU in MoniMac and ~30 ms in the system_profiler child (Release, averaged over 20 reads; ~80 ms wall). That's ~0.0003% (MoniMac) and ~0.01% (child) at the background cadence. `ps` on MoniMac doesn't see the child's share, so the reader logs it now and then.
  - A hung run is killed after 15 s.
- **Unavailable, with a reason in the tooltip:**
  - **What it's playing from** reads "Audio source unknown": macOS doesn't tell other apps which app plays to a Bluetooth device. CoreAudio's process objects might, but that depends on the Sound ticket's audio work (16).
  - **Noise-control mode** reads "Noise control unknown": no public or unprivileged source has it.
  - **Firmware** reads "Firmware unknown" when the device doesn't report one. `0.0.0` counts as none.
- **Listening time left and "Est. N days left"** are MoniMac's own estimates from the drain since the last charge: the level must have dropped at least 5 points, over at least 10 minutes for earbuds or a day for other devices. Until then the card reads "Listening time left: estimating…".
- **Device memory:** `bluetooth.devices` in Preferences holds, per address, the last time a device was seen connected, its levels then, when it was last charged, and the drain since. A charge is the charging flag, or a level at least 3 points above the previous reading. Records save only when a new reading changes them. Devices no longer paired are forgotten, except while Bluetooth is off. There are no device battery series in `MetricsHistory`: levels change over hours and are per device, and no chart needs them.
- **Low battery rule:** a connected device notifies when the lower of its main battery and earbuds is under 20%. The case doesn't count, since it isn't worn. The notification is once per device per episode, and an episode ends only at 25% or more, so jitter around 20% doesn't re-notify. Disconnecting while low doesn't end an episode. Episodes live in memory, so a still-low device notifies once more after a relaunch.
  - The alert's "Show" opens the Bluetooth tab, and it has no Quit. `Alert` now carries an `AlertTarget` (`.app(id, column:)` or `.tab(tab)`) instead of an app id and column.
  - The toggle is on the Bluetooth tab only: the design's Settings › Notifications has no Bluetooth row.
- **Featured card:** connected headphones, earbuds (devices that report left and right levels) first, then the most recently seen. A disconnected one shows its last levels greyed. Rings are red under 20% and amber under 50%. List bars are red under 20%, otherwise green, and grey when disconnected. Times are 24-hour ("Last seen yesterday, 22:42").
- **Development flag:** `--bluetooth-fixture <path>` reads a saved `system_profiler SPBluetoothDataType -json` file instead of running it, to check the tab with devices the Mac doesn't have.

- [ ] Connected devices and their battery levels appear and update (built and tested with scripted readings; the running app showed fixture devices with their levels, but no real device was connected, so a real connection and a level changing were not observed)
- [ ] AirPods-class devices show separate Left, Right, and Case levels when available (rings render from a fixture with AirPods-format output; real AirPods unverified)
- [x] Batteries under 20% are highlighted, and with the toggle on, one notification is sent per device per low episode (red row observed in the running app; one muted alert logged for the fixture's 14% trackpad; episodes and re-arming tested; real banners unverified because the app ran with `--mute-notifications`)
- [ ] Disconnected devices show when they were last seen (tested; in the running app the real paired devices are listed as Not connected, but none had been seen connected, so no "Last seen" hint was observed)
