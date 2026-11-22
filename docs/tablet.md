# Tablet

A drawing tablet (built on a Wacom Intuos S, CTL-4100, 056a:0374, 152 × 95 mm, kernel `wacom` driver) as a shell
surface, with the kind of features OpenTabletDriver has: where the pen lands, how much of the tablet it uses,
profiles, pressure range, express keys, a live view of the pen. Asked for 2026-11-22.

**The user's picks (binding):** backend = native Hyprland + an evdev reader (not "native only", not full OTD parity);
split = the island holds the daily half, Settings the rare half; it lives on the BOTTOM-LEFT island after Workout.

## Two halves

| Half | What | How |
|---|---|---|
| Settings | area, screen, rotation, absolute/relative, pressure range | `hyprctl eval 'hl.config({ input = { tablet = {…}, tablettool = {…} } })'`. Hyprland is the driver; nothing sits between the pen and the compositor. |
| Live | pen position and pressure, report rate, express keys | `scripts/tablet-helper.py`, read-only on the evdev nodes, never grabs. Needs a udev rule (below). |

The settings half works with no permission at all. The live half and the express keys say why they are off
(`Tablet.liveBlocker()`, the `NightLight.blocker()` shape) until the rule is installed.

## Measured on Hyprland 0.57.2 (Lua config)

- Use `hl.config`, **not `hl.device`** over `hyprctl eval`: `hl.device` through eval was never run here, and a runtime
  `hl.bind` segfaulted Hyprland twice (docs/small-features.md). So the values are GLOBAL to every tablet; profiles are kept
  per tablet name but one set is sent. A true per-device setting would be an `hl.device` block written into
  `hypr/hardware.lua` through `hypr-config.py` and a reload (the Keyboard page's way).
- **A vec2 is `{ a, b }`.** The stub lists `{ x =, y = }` too, but `hl.config` answers `vec2 type requires exactly 2
  elements` and applies nothing for that key. Found by running it; `tablet.js` and its test pin the array form.
- `hyprctl eval` prints `ok`, or one `error: …` line per key that failed (and the other keys DO apply, so a half-applied
  profile is possible). The exit code is 7 on an error. `Tablet.lastError` reads the text, not just the code.
- Read back with `hyprctl getoption input:tablet:active_area_size` (vec2, `set: true`) and
  `input:tablettool:pressure_range_min`. `active_area_*` read back exactly what was sent.
- `pressure_range_min/max` are `-1` when unset. A profile at 0..1 sends `-1` so going back to the default undoes an
  earlier range. `set: true` stays after a reset until the next config reload; the value is the default, which is harmless.
- A reload resets runtime values, and the shell triggers one on every palette change: `Tablet` re-sends on Hyprland's own
  `configreloaded` raw event (as `CursorEffects` does).
- Hyprland has NO tablet events in Lua or on the socket (only `input.keyboard.key`), so the live half needs evdev.
- `eraser_button_mode` (int 0 to 6, 0 = hardware default, 1 = send a button) and `eraser_button_override` exist and are NOT
  used: the Intuos S pen has no eraser and the values past 1 are undocumented. A pen with an eraser end would want them.

**Not yet verified with a real pen:** that `active_area_*` is millimetres of the tablet's own surface and which way
`transform` (0 to 3, the quarter-turns) turns. `areaRatio()` assumes the area is cut BEFORE the turn, so a quarter-turn
swaps which tablet axis runs along the screen's width. If the pen lands wrong after a turn, that assumption is the place.

## The permission

`/dev/input/event*` are `root:input 660` and a tablet's carry no per-user ACL; the user is not in `input` (and should not
be: it reads every keyboard). `scripts/tablet-access.sh --install` writes
`/etc/udev/rules.d/70-quicktest-tablet.rules` (`SUBSYSTEM=="input", ENV{ID_INPUT_TABLET}=="1", TAG+="uaccess"`), reloads,
and re-triggers tablets only, in ONE elevated shell (sudo with a tty, pkexec without). `--status`, `--print-rule` need no
root. `--remove` undoes it. The Tablet page and Settings › Tablet both have the button; after it, a probe sees `access`.

A device that was plugged in before the rule needs unplugging once only if the trigger did not reach it (the page says so).

## The helper

`scripts/tablet-helper.py --probe` (no permission) prints every tablet: name, Hyprland spelling, model, nodes, size in mm
(from `udevadm info`, which computes it from the axis resolution), express-key count (from the pad's sysfs `key`
bitmap), and whether the user may read the nodes. Nodes are grouped by physical port and serial; the pen has a tool
and pressure, the pad has `BTN_0..BTN_9` / `BTN_A..BTN_THUMBR` and no tool.

`--pen NODE [--pad NODE]` runs it. JSON lines out (`hello`, `pad`, `pen`, `rate`, `fatal`, `gone`; the header of the
script is the reference) and `{"cmd":"watch","on":true}` in. The pen node is closed unless somebody is watching, so an idle
shell reads nothing per pen report; the express keys are always read. Lifecycle is Karaoke's: `_cycling` dips `running`,
three deaths a minute then an error, exit 3 = do not restart, exit 4 = the device left (probe again).

Stdlib only (`struct` + `fcntl`). No python-evdev dependency, no `$HOME`, nothing hardcoded to a Wacom.

## State

`tablet.json` under `XDG_STATE_HOME` (JsonStore): `{ version, devices: { "<hyprland name>": { active, profiles[], keys[] } } }`.
Up to 12 profiles per tablet, 16 key slots. Read as untrusted (`tablet.js normalise` and `deviceState`). `Config.tabletOn`
(default false, persisted) is the one preference: off means the service does not exist (`shell.qml` creates it only while
the switch is on), on with a stock profile sends nothing until something changes.

## Express keys

Each key is one of: nothing, a key chord (`wtype`, an argv built by `chordArgv`, blocker `Needs wtype` when missing),
a command (an argv, no shell: `inactivity.js parseCommand`), or a profile switch (next, previous). `wtype` comes with the
`discordkeys` pack; no new pack was added for it.

## Files

`services/tablet.js` (pure rules, `bun scripts/test-tablet.js`), `services/Tablet.qml`, `scripts/tablet-helper.py`
(`python3 scripts/test-tablet-helper.py`), `scripts/tablet-access.sh`, `modules/island/IslandTablet.qml` +
`modules/island/tablet/` (TabletMap, TabletKeys, TabletMapView, TabletProfilesView, TabletProfileRow, TabletTestView,
TabletPlateTitle), `modules/settings/pages/TabletPage.qml`. Registered in `config/islands.js` (`PAGE_META.tablet`),
`IslandCard`, `modules/island/qmldir`, `services/qmldir`, `services/SettingsIndex.qml` (page and three search entries),
`config/ConfigDesktop.qml` + `Config._persisted` (`tabletOn`), `shell.qml` (the boot `Connections`).
`island part tablet map|profiles|test` opens a view.

## Not done, on purpose

- Pressure curve, smoothing and the other OTD filters. They need the helper to GRAB the pen and re-emit it through a virtual
  uinput tablet (Hyprland would then see a different device, and a helper bug would be a dead pen). The user took the lower tier.
- Per-app profiles. Two tablets with different settings at once (global config).
- Eraser options (above). Pad rings and strips (the Intuos S has none; the helper reads keys only).
- Hot-plug is by looking again (`Tablet.reprobe()`: on opening the page, on a config reload, when the helper's device leaves),
  not by watching udev.

## Untested

Nothing on this page has been loaded. Static checks and unit tests only (`test-tablet.js` 155, `test-tablet-helper.py`
62, islands/island/settings-search/translations). To check on a reload: Settings › Tablet, turn it on, the island page
(`island part tablet map`), drag the block and watch `hyprctl getoption input:tablet:active_area_size`, move the pen to the
corners, run Allow live pen (a polkit dialog) and unplug and replug, then the dot, the express-key discs and the test pad.
