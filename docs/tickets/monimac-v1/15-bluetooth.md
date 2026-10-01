# 15 — Bluetooth

**What to build:** The **Bluetooth** tab. It shows the connected device count and a featured card for an AirPods-class device: connection state, what it's playing from, noise-control mode, firmware, listening time left, and Left/Right/Case battery rings. An **Other Devices** list shows each device's type, connection state, battery bar and %, and a status hint ("Charged 6 days ago", "Low — charge soon", "Last seen yesterday, 10:42 PM"), with low batteries in red. An "Open Bluetooth Settings…" link and a **Low battery notifications** toggle notify you when any connected device drops below 20%, through AlertEngine. MoniMac only displays devices; it doesn't connect or pair them.

**Blocked by:** 04 — Main window with CPU tab; 14 — Alerts and notifications

**Status:** ready-for-agent

- [ ] Connected devices and their battery levels appear and update
- [ ] AirPods-class devices show separate Left, Right, and Case levels when available
- [ ] Batteries under 20% are highlighted, and with the toggle on, one notification is sent per device per low episode
- [ ] Disconnected devices show when they were last seen
