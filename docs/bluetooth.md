# Bluetooth

Moved from CLAUDE.md; the project rules there still apply.

## Bluetooth

`services/Bt` (devices, logic over Quickshell.Bluetooth) + `services/BtBridge`
(`scripts/bt-helper.py`) + `Audio` (the PipeWire side) → `modules/panels/BluetoothPanel`,
`modules/settings/pages/BluetoothPage`, the bar pill. Pure logic in `services/bt.js`
(`bun scripts/test-bt.js`); the helper's logic in `python3 scripts/test-bt-helper.py`
(fully mocked, touches no bus). Diagnose with `qs ipc -c ~/.config/quicktest call
btbridge status` — states and counts only, never a PIN or a file name.

- **The helper is the D-Bus Quickshell.Bluetooth doesn't expose**: the BlueZ pairing
  AGENT (Agent1 — without one, anything that shows a code or wants a PIN fails with
  "Authentication Failed/Rejected"), RSSI (Device1, coalesced to one update per device
  per 500ms), and OBEX file sending (obexd, SESSION bus, optional `bluez-obex`). One
  GLib loop, JSON lines, `PR_SET_PDEATHSIG` so a reload can't orphan a registered agent.
  Exit code 3 = fatal (python-dbus missing), not restarted. `Config.btAgent` flips
  registration live over stdin.
- **Eager** (shell.qml `Connections` on Bt and BtBridge): the agent must exist before a
  pairing the PHONE starts, and the OSD / battery warnings watch with nothing open.
- **A prompt opens the panel** (`UiState.openPanel`, never toggle) and sits on top. Only a
  NEW prompt id opens it — DisplayPasskey re-fires per digit typed on the remote keyboard.
  Side panels get OnDemand focus, so a PIN field needs one click first.
- **Pair = trust → pair → connect** (`Bt.pair`). Scanning is a reference count
  (`acquireScan/releaseScan`) — the panel's Nearby tab and the page's Scan both hold one.
  Never write `adapter.discovering` directly.
- **Music/Calls and the codec are both card PROFILES** (`a2dp-sink-aac`,
  `headset-head-unit-msbc`, codec-less = "best"): one `pactl -f json list cards` read
  (`bt.js parseCard`), one `set-card-profile`. Re-read when the sink node changes (a
  switch recreates it), never polled. The fixture's profile names are PipeWire's naming,
  NOT a capture — re-capture one into `test-bt.js` with a BT headset connected.
- **Sink ↔ device** is the MAC: `api.bluez5.address` on the node, node name as fallback.
- `Bt.nearby` re-sorts on every RSSI flush (closest first by BARS, not dBm — dBm jitters),
  so consumers use a `ScriptModel`. A device can be connected but NOT paired (a speaker
  accepting a bare connection); it shows in Nearby as such.
- Low battery (`bt.js batteryAlert`): threshold and half of it, once each per discharge,
  reset 5% above. `DeviceBatteries` (the stats ring) is a separate, UPower-wide view of
  the same batteries — not merged, on purpose.
- Sending: `BtBridge.stage(path)` (panel drop zone, screenshot toast's Send) → pick a
  device that advertises Object Push (the helper reads UUIDs). The helper re-validates
  the path (absolute, regular, readable) — the trust boundary is its stdin.

