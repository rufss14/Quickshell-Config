# Smaller features

Moved from CLAUDE.md; the project rules there still apply.

## Magnifier

`services/Magnifier` (+ `magnifier.js`, `bun scripts/test-magnifier.js`): Hyprland's own
`cursor:zoom_factor`, set by `hyprctl eval` and EASED here (5 steps in log-space; 1 with
motion off). SUPER+CTRL+scroll steps the stops (1 … 8×), SUPER+CTRL+Z toggles 2× (or the
last level) / off — custom events (`qs-zoom:in|out|toggle|reset`) on Switcher's channel,
so no process per notch. The OSD shows the level. Re-applied on `configreloaded` (a reload
resets zoom to 1). Eager in shell.qml. The live `~/.config/hypr` needs the binds by hand.

## Screen time

`services/ScreenTime` (+ `screentime.js`, `bun scripts/test-screentime.js`) →
`modules/bar/SideScreenTime` (one cell; hover = today's total) → `modules/panels/ScreenTimePanel`
and Settings › Sidebar › Screen time (`ScreenTimePage`), both drawing
`components/ScreenTimeView` (a week of bars, click a day; that day's apps with bars).
Off by default (`Config.screenTime`); eager in shell.qml so it counts with no view open.
Counts the FOCUSED window's app (`Hyprland.activeToplevel`, an event) while not away —
an IdleMonitor (`screenTimeIdleMinutes`, inhibitors respected, so a video counts) and not
locked; credited every 30s and on change, a span over two ticks clipped (a suspend).
Stored in `statePath("screen-time.json")`: local days → app id → seconds (app ids
validated, never a title), `screenTimeKeepDays` of them, written once a minute.
`qs ipc … call screentime status` (counts only).

## Snap zones

`services/Snap` (+ `snap.js`, `bun scripts/test-snap.js`) → `modules/desktop/SnapOverlay`
(per screen, Overlay layer, click-through, mapped only while a floating window is carried).
`Config.snapZones` (on; Settings › Window manager › Tuning). FLOATING windows only (the
user's call): SUPER-drag one to the left/right edge = half, a corner = quarter, the top band
just UNDER the bar = fill — zones are measured from the usable area, so the bar (and the
workspace pill) is never a zone. Rides the windrag hook: `UiState.windowDrag` + Pointer's
fast poll for the preview; the release arrives as `UiState.windowLanded` only when no
WorkspacesPill CLAIMED it (`claimWindowDrop`), so a drop on the pill moves workspaces and is
never also snapped. The move is `hl.dsp.window.resize` then `move` with `window =
"address:…"` and Hyprland's gaps (Blend). The `window` selector on those two is inferred
from Hyprland's error text, not tested live.

**Snap to grid** (`Config.snapToGrid`, off by default; Settings › Window manager › Tuning only — it
once had a bar pill / sidebar cell, removed on purpose: it's a setting, not a button). The same release, when it is NOT in a zone: a floating window's
top-left goes to the nearest dot of the desktop widgets' grid (`Config.widgetGrid`, measured from the
monitor's corner like the widget layer's dots), kept inside the usable area (`snap.js gridPoint`).
Position only — size is never touched, as with the widgets. Hyprland reports nothing about where a
dragged window ended up, and a toplevel's `lastIpcObject` (floating, position) is EMPTY until something calls
`refreshToplevels()` — so `Snap._land` refreshes on every drop and judges floating / zone / grid 120ms later,
never from `Hypr.windows` (the first version trusted it, read every window as tiled, and moved nothing).
Unverified live; if a window snaps from its OLD position, that delay is the suspect.
SUPER+right-drag (resize) isn't hooked, so it never snaps.

## Screenshots

`services/Screenshot.qml` → `modules/notifications/ScreenshotToast.qml` →
`modules/panels/AnnotateWindow.qml`.

- **(Superseded for SUPER+P by the snip tool below.) The shell does NOT take the screenshot.** hyprshot was bound to SUPER+P and
  works; this owns only the moment after the shutter.
- Detection is by **taking over the tool's own notification**. The shell is the
  notification daemon, so `Notifications.onNotification` offers each one to
  `Screenshot.consume()` first; a match is dropped and replaced by the shell's
  toast. No inotify, no polling. It also fixed a real warning — hyprshot passes
  the file as the notification ICON (`notify-send -i <path>`), so Quickshell was
  pushing a 4K PNG through its icon loader.
- Matching is `Config.screenshotApps`, a **list** (hyprshot/grimblast/flameshot/
  swappy/satty all announce themselves differently). A tool's *error* notification
  has no file path, so it falls through untouched rather than being swallowed.
- The annotator's canvas is the image's **natural size**, scaled for display.
  `Canvas.save()` writes at the canvas's own size, so a canvas sized to the window
  would downscale every edited screenshot. The MouseArea, inside the scaled item,
  already gets image-space coordinates.
- Shapes are a list replayed on repaint (undo is one `pop()`), with the
  in-progress stroke on a second empty canvas.
- Redaction is **pixelation, not a black box** — a filled rectangle advertises
  what you covered. Saves to `<name>-edited.png`, never over the original.
- Deleting is `gio trash`, not `unlink` — a mis-click on an auto-dismissing toast
  is exactly where "gone forever" is wrong.
- `xdg-open` is not a viewer here: the `image/png` handler is `firefox.desktop`.

## Night light

`services/NightLight.qml` → bar pill + `modules/settings/pages/NightLightPage.qml`.

- Backend is **probed, not assumed**: `hyprsunset` preferred, `gammastep`
  fallback, `blocker()` when neither is installed. Both are installed here now,
  and `scripts/install-dependencies.sh` installs `hyprsunset`.
- The backend process is held OPEN for as long as the warmth should be on screen.
  Both tools set gamma through `wlr-gamma-control`, where the adjustment belongs to
  the CLIENT and reverts when it exits — "set it and exit" cannot work. An
  unexpected exit is reported, because the screen has silently gone back to
  normal.
- The SHELL owns the schedule (sunset/sunrise from `Weather`, or fixed times), not
  the tool — a schedule inside the tool would be a second source of truth the
  settings page couldn't show.
- Invocations: `["hyprsunset", "-t", TEMP]` run in the foreground (holding the
  adjustment — not the `hyprctl hyprsunset` daemon form); `gammastep -P -O TEMP`.

## Anti-flashbang

`services/AntiFlash` (+ `antiflash.js`, `bun scripts/test-antiflash.js`, which also
compiles the shader with glslangValidator) → `modules/bar/BrightnessProbe` (inside the
FOCUSED screen's bar window — a ScreencopyView needs a window) → a Hyprland screen shader.
Settings in Night light's page (`Config.antiFlash*`, off by default); `qs ipc … call
antiflash toggle|status`.

- **Measure in the shell**: a still `ScreencopyView` (`captureFrame()` once a second, and
  150ms after focus/workspace/open/fullscreen events), hidden behind a mipmapped
  `ShaderEffectSource` at 64×36, `grabToImage` at 32×18, drawn into a Canvas and averaged
  (`getImageData`). Offscreen-verified: a half-white item reads 0.500, and a second grab
  follows a change. A transparent (opacity 0) Canvas still paints.
- **Hyprland's screencopy skips the screen shader** (`blockScreenShader` in
  ScreenshareFrame.cpp), so the probe sees the UNDIMMED screen — no feedback loop — and
  screenshots/recordings are never dimmed.
- **Dim in the compositor, gain baked in**: one shader file per level in
  `$XDG_CACHE_HOME/quickshell-quicktest/antiflash/`, two names alternated, applied with
  `hyprctl eval 'hl.config({ decoration = { screen_shader = … } })'`. A shader measuring
  brightness itself would re-render only DAMAGED regions with a fresh gain (seams); the
  `time` uniform needs damage tracking off. A changed screen_shader damages every monitor
  (PropRefresher), so one gain is one look. Eased in 4 steps (1 with motion off); gain 1
  REMOVES the shader (or restores a screen_shader of your own, read once via getoption).
  Re-applied on `configreloaded`.
- Read from Hyprland's CURRENT source (`main`), not 0.56.2's — if a reload shows seams or
  a dimmed screenshot, that's where to look.


## Polkit agent (the shell's own password prompt)

`services/AuthAgent` + `modules/panels/PolkitPopup`, `services/polkit.js`
(`bun scripts/test-polkit.js`). The dialog for `pkexec` and friends, drawn by the shell.

- **Opt-in** (`Config.polkitAgent`, default off; Settings › Setup › Password prompts). A session
  has ONE agent: with `hyprpolkitagent` (started in `autostart.lua`) still running, Quickshell's
  registration fails and `AuthAgent.blocker()` says so. Turning it on means taking the other
  one out of the autostart — the Setup page detects it (`Setup.rivalAgents`) and prints the
  `killall`. Not default-on: a published shell mustn't evict someone's working agent, or leave
  them with none if the shell crashes.
- A `LazyLoader` gates the `PolkitAgent` (it registers in `componentComplete`, unregisters on
  destruction); `path` is left alone (Quickshell refuses to change it once set).
- **The words are other processes'.** `polkit.js` flattens control characters and caps lengths;
  the view renders PlainText only; the action id is shown beside the message.
- The popup keeps `held*` copies (the flow is null the instant a request ends) — including
  `heldSecret`, or the password would be drawn in clear for the length of the fade. The field
  is emptied the moment the answer is sent. The backdrop does NOT dismiss on click.
- Exclusive keyboard focus for the life of a request; own namespace `quickshell-polkit`.

## Music recognition

`services/SongRec` + `services/songrec.js` (`bun scripts/test-songrec.js`). Two buttons in the
Now-Playing panel header (desktop audio / microphone), or
`qs ipc … call songrec toggle|toggleMic|stop`. Result: the panel subtitle for 12s, and a
notification with "Open in Shazam" / "Search YouTube".

- Optional: `songrec` (in `OPTIONAL_PKGS`; Setup › Optional extras). `blocker()` says why it's
  dead. Desktop audio = `<default sink>.monitor` from `Audio.sink.name`; no `pactl`.
- Runs under `timeout` and stops on first hit / 30 s / `stop()`.
- **Not verified against a real songrec** (it isn't installed here): `songrec.js` scans the
  output for JSON objects instead of assuming a line layout, and reads `track.title /
  subtitle / url / images.coverart` (the shape ii reads). The URL must be https or it's dropped.

## To-do list

`services/Tasks` + `services/tasks.js` (`bun scripts/test-tasks.js`), module `tasks`
(`SideTasks` → `modules/panels/TasksPanel`, bar pill via `SideModulePill`). `tasks.json` under
`XDG_STATE_HOME` through `JsonStore`; every op is pure and returns a new state (a JsonStore only
saves on assignment); `normalise()` rebuilds the state from the file on load. Ids are never reused.

## Session warnings and rivals

- `Session.interrupts` (an update run / pacman lock, a recording, a busy Claude session) is shown
  on the power menu tiles that END the session (log out, restart, firmware, shut down). Informs;
  never blocks. The pacman lock is read in the power menu's existing `probe()`. The overview's
  `PowerPanel` and the sidebar's power button don't show it yet.
- `Setup.rivalNotifiers / rivalAgents / rivalBars` — a running mako/dunst/swaync (the shell IS the
  notification daemon), a second polkit agent, a second bar. **Detected, never killed**; the
  Setup page shows the `killall` and the autostart line to drop.

## Reload card

`services/ReloadWatch` + `modules/panels/ReloadPopup`, `Config.reloadPopup` ("failures" default,
"all", "off"; Settings › Setup). A failed hot reload leaves the OLD config running and used to
say so only in the log. `Quickshell.onReloadFailed` goes to the generation still running,
`onReloadCompleted` to the new one — a singleton created by shell.qml's `Connections` hears both.
The card holds its own copy of the text, pauses its countdown while hovered, has a Copy button,
and uses `Verdict.tint()` for pass/fail. (Writing it, `property real left` on it was caught by
`check-qml-final.py` — the FINAL-property trap in CLAUDE.md, once more.)

## Secrets in the keyring

`scripts/secretstore.py` (`python3 scripts/test-secretstore.py`, against a fake `secret-tool` and
`busctl`), used by `ai-credentials.py`, `discord-credentials.py`, `lyrics-translate-credentials.py`
and read by `ai-ask.py`, `discord-rpc.py`, `lyrics-translate.py`. One Secret Service item per secret
(`application=quicktest`, `name=ai-gemini | discord-client-secret | deepl`). A secret that has moved is
absent from its 0600 file and its field is listed under `"_keyring"` (names only).

- **Nothing moves silently.** New and changed keys go to the keyring only when the Secret Service is
  already RUNNING; otherwise the file, exactly as before. Existing keys move when you press *Move to
  keyring* (Settings › Setup › Secrets, `scripts/secrets-tool.py migrate`) — the one place a service
  that isn't running may be started, because KWallet can then ask to create/unlock a wallet.
- **The presence ids too.** `presenceClientId` (Claude Code card) and `cs2PresenceClientId` are public
  app ids, but they live in the same keyring-able set (`discord-credentials.py` `ID_FIELDS`; names
  `discord-presence-client-id` / `discord-cs2-presence-client-id`), because `claude-presence.py` and
  `cs2-presence.py` read them through `secretstore.resolve` — a file value wins, the keyring is asked
  only when the field is listed under `_keyring`. Set one with
  `echo '{"presenceClientId":"ID"}' | python3 scripts/discord-credentials.py`; the daemon picks it up
  on `reloadClientId`. Hand-storing an id in the keyring does nothing unless the file lists the field.
- **Verified before forgetting:** `put()` reads the value back and compares; the file's copy is dropped
  only if it matched. A keyring that stops answering gives "" (the key reads as unset), never a wrong one.
- **On this machine** there is no `org.freedesktop.secrets` on the bus (kwallet's compat name is only
  *activatable* as `org.kde.secretservicecompat`), so everything stays in the files and the card says so.
  The real `secret-tool` path was never run here — only the fakes.

## Snip tool

`services/Snip` + `modules/panels/SnipOverlay`, geometry in `services/snip.js`
(`bun scripts/test-snip.js`). **SUPER+P = `snip save`, SUPER+SHIFT+P = `snip copy`** (replaced the
`hyprshot` bind in `hypr/binds.lua` and the live copy; hyprshot is no longer used by the shell, though
`Screenshot.consume` still adopts any screenshot tool's notification).
`qs ipc -c ~/.config/quicktest call snip copy|save|edit|pin|text|translate|record|close|select X Y W H`.

- **The whole interface:** drag a box or click a window; F is the whole screen; handles resize, inside
  moves, arrows nudge (Shift = 10 px). A dock appears by the selection in two trays — Copy · Save · Edit ·
  Pin, then Text · Translate · Record — and ✕. The FILLED, expanded button (name + ⏎ keycap) is what Enter
  does (`Config.snipAction`, the last clicked; `snip copy|save` choose it for that snip); the others are
  icon tiles, and the line under the dock says what the one under the pointer does, with its key. Esc /
  right-click clear the selection, then leave. There is no mode to pick: an earlier version had Box/Loop,
  Instant, keycaps and two trays, and was too much. C/S/E/P/T/L/R pick an action; the dock and the hint
  pill now show the keys (`SnipKeyCap`). `SnipAction` is the button (M3E: tile → filled on the spatial
  spring, corners square on press); the two live in `modules/panels/`.
- **The size chip** (under/over the selection, opposite the dock) shows the crop in the capture's own pixels
  and, with a selection up, opens a menu: lock an **aspect ratio** (Free · 1:1 · 4:3 · 3:2 · 16:9 · 9:16 —
  the box is cut to it about its middle, and every drag and handle after keeps it) or type an **exact size**
  (Enter in either field; it lets the lock go). `Snip.ratio` is per snip and starts free. The arithmetic is
  `ratioFromAnchor` / `resizeRatio` / `fitRatio` / `sizeRect` in `snip.js`, tested. While the menu is open the
  fields are typing: only Esc is the overlay's.
- **Pin** floats the crop on top of everything (`services/SnipPins` + `modules/panels/PinLayer`/`PinCard`;
  NOT `Pins` — that is the dock's app-pin singleton). The picture is a file in
  `$XDG_RUNTIME_DIR/quickshell-quicktest-pins` (0700, removed when its pin closes, swept when the shell
  starts), never in your screenshots folder. One window per screen, only while it has a pin, with a
  click-through mask built per pin (WidgetLayer's pattern). Drag to move (kept on its screen, not across
  screens), wheel to resize, hover for copy and ✕, right-click closes. `qs ipc call snippins closeAll`
  clears. No keyboard focus, and a pin does not survive a shell restart.
- **Live** (`V`, `snip livepin`) is a pin that keeps updating. A selection that IS a window (within 3 px,
  `P.matchWindow`) shows that window through a toplevel capture, so nothing drawn over it gets in; any
  other selection shows that REGION of its WORKSPACE: the workspace's wallpaper (`Wallpaper.pictureFor`) with
  its windows on it, each a toplevel capture placed in the region (floating over tiled). So it keeps showing
  the workspace it was taken from whichever one you are on, it is itself on every workspace and can be
  dragged anywhere, and — captures never contain the card — it can sit on its own source. The bar and
  desktop widgets are not windows and are not in it. Only when the workspace is unknown (`workspace` -1: a
  special workspace) does it fall back to a capture of the screen, which includes the card: `P.livePlace`
  starts a pin BESIDE its source for that reason, and the card says "On its own source: move me" if it is
  dragged back on top. Nothing is written to disk. A closed window leaves a blank card saying so. Cost: a
  region pin runs one capture per window of the workspace, repainting with each; `SnipPins` holds Hypr's
  event tier while one exists.
- **The editor** (Edit → `AnnotateWindow`): pen, highlighter, arrow, box, ellipse, text, numbered steps and
  blur, in the palette's six "look here" colours, S/M/L (keys 1 2 3; sizes scale with the image, `unit`),
  fill for boxes and ellipses (`F`), undo / redo / clear (Ctrl+Z, Ctrl+Shift+Z or Ctrl+Y). Tool keys are on
  the tiles (P H A R O T N B). Enter copies, Ctrl+S saves (`-edited` beside the original, never over it).
  Text is a TextInput in image space (Enter keeps, Esc drops; the shortcuts stand down while it is up).
  Same dock language as the snip toolbar (`SnipAction` with `capText`).
- **Opening is fast on purpose.** grim captures every output in parallel and uncompressed (`-l 0`):
  0.28 s → 0.03 s for two screens; the call-to-selecting round trip measures 0.12 s.
- **The loupe nearly took the shell down.** It was a second `Image` with `sourceClipRect` on the capture:
  Qt re-reads and re-clips the WHOLE file on the CPU whenever the rectangle changes, which pinned the main
  thread at 100% (shell 35% → 103% of a core, a few frames a second — the user saw "extremely low frame").
  Found by bisecting a private COPY of the config (so the live shell isn't hot-reloaded by every probe)
  and sampling per-thread CPU from `/proc`: the main thread was busy while the render threads were idle.
  It is now a `ShaderEffectSource` of the uploaded still, shown only while dragging (≈44% open, ≈45% with
  it forced on). The same method is the way to chase any "the shell is laggy" report.
- **The look.** The hint pill and the toolbar wear the shell's own card (`elevationCard` — what the
  bar, NotificationToast and ScreenshotToast wear; `elevationPopup` is the lifted grey and was wrong
  here), as full pills. Everything eases in: the scrim fades up, handles pop on the dock's spring when a
  selection starts, the toolbar grows out of the selection's edge with a small overshoot and its buttons
  arrive one after another, the hint rises. The dim is `Colors.shadow` (constant black) at 58% with the
  selection cut out — the palette's near-black base at 50%, which it was first, vanished over dark
  windows. **None of it can reach a screenshot**: grim runs before any overlay maps and every action crops
  that file.
- **Translate.** OCR (`scripts/lens.py`) now defaults to `Config.lensOcrLangs = "auto"`: with more than
  two languages installed, tesseract's OSD names the script and only the installed languages for it are
  read (English first); with only English installed, Settings › Setup says which `tesseract-data-<code>`
  to add, and Lens's "No text found" says so too. (The old default was `eng`, read as `auto` on load.)
  The translator (`scripts/lyrics-translate.py`) knew only six Latin-script languages, so a Dutch sentence
  matching "is" was tagged English and skipped as "already in the target language". It now knows eleven
  more (nl, sv, da, no, pl, cs, tr, id, ro, fi, hu) and, when the Latin guess is thin
  (`latin_sure`: ≥3 hits and 2× the runner-up), sends `auto` as the source — Google, DeepL and MyMemory
  detect it themselves, Argos steps aside — and never skips a translation on a thin guess.
- grim freezes every output to `$XDG_RUNTIME_DIR/quickshell-quicktest-snip/snip-<session>-<output>.png`
  BEFORE any overlay maps, each screen's overlay draws its still, and the crop is `magick -crop` in the
  capture's own pixels (`logical × scale`) as an argv. The file name carries a session id because `Image`'s
  cache is keyed by URL and would otherwise show the previous snip's screen.
- Actions reuse what exists: save → `Screenshot.saveDir` + clipboard + `Screenshot.present` (the toast),
  edit → `UiState.openAnnotate`, text/translate → `Lens.adopt()`, record → `Clips.recordArea()`.
- **Reverse image search is deliberately absent.** ii uploads the crop to a public file host (uguu.se) to
  hand Google Lens a URL — that sends the picture off the machine. "Text" + Lens's DuckDuckGo search covers
  searching for what a region says.

## Reveal rules (auto-hide)

`Config.sidebarEmptyReveal` (stay out while the monitor's current workspace has no windows) and
`Config.sidebarEdgeReveal` (default on; off = the edge brush does nothing — only an empty workspace,
SUPER+D or the ii dock's keep button reveals). Both in `SideBarHost`, both need `sidebarAutoHide`; the
empty-workspace rule shares the dodge mode's Hypr event tier (`bar.watching`).

## Icons and shapes (ii's)

- **`MaterialIcon`**: `wght` rises with FILL (`Tokens.symbolFillBoost` 200: regular → semibold), `opsz` follows
  the pixel size (20–48), no hinting, and FILL is quantised to tenths for the axis (Qt builds a font engine
  per distinct axis combination — a continuous fill animation would otherwise create dozens per icon).
  **`opsz` only takes effect after `python3 scripts/material-symbols-map.py --emit`** (the cutter used to
  pin it at 24; `PINNED_AXES` is now just GRAD) and an ALT+Q restart. Before that the axis is ignored.
- **`Config.cornerStyle`** "ii" swaps `Tokens`' radius ladder (6/12/17/23/30 for 4/8/12/16/24); the card
  corner then no longer follows Hyprland's window rounding. Settings › Appearance › Type & shape.
- **`Config.iconShape`** picks one holder for every panel-header chip and settings-section chip
  (`components/ShapeBox`: squircle, cookie, clover, circle) — "default" keeps a rounded square in headers and
  the cookie in sections. ii's general rounded-polygon library (Apache-2.0, 168 KB) was NOT vendored; these
  are the few shapes the shell would put behind an icon, on the Scallop it already has.

## The media panel's cookie cover and drift (2026-10-10)

`modules/panels/MediaPanel`'s music layout (the one with lyrics) borrows Caelestia's media tab —
look only: it is GPL-3 and this repo MIT, so every line is ours.

- **`components/CookieCover`**: the album art seen through a `Scallop` silhouette that turns once per
  23.5s while the track plays (paused, not stopped, so it resumes in place), with a ring of 32 level
  bars standing off its edge. The silhouette rotates on a CHILD inside the layer used as the mask — a
  layer renders its item without that item's own transform, so rotating the mask source does nothing.
  Each bar starts a gap outside the edge AT ITS OWN ANGLE, so the ring breathes with the petals; that
  radius is `services/cookie.js` (`bun scripts/test-cookie.js` keeps it equal to Scallop's formula).
- The ring's spectrum is the shared `Cava` service held by refcount against the player's OWN PipeWire
  node (`acquireSource`, as OverviewLyrics and the bar's visualiser do) — no process of its own, and
  released when the panel closes, the page changes, the track pauses, or Game mode hides visualisers.
  The panel passes `live: playerLive && showLyrics`, so a hidden cookie (the YouTube layout) never
  holds it. No node yet → the ring rests as dots.
- **The lyrics are a card of their own, and a QUIET one** (`modules/panels/PanelLyrics`). A first pass
  gave it a title row, a sync badge, two hairlines and a source pill, and beside the panel's own header,
  title and seek bar it said everything twice ("Lyrics", "Instrumental", "Instrumental") — "too busy".
  Now: the words, fading into the card top and bottom, and nothing else. Nothing to read (instrumental, none
  found, looking, provider down, waiting on the bridge) is one soft cookie with one line under it. Where the
  lyrics came from and the −/+ offset stepper (`Lyrics.nudge`, tap the number to zero) rise in a small pill
  only while the pointer is on the card, and only with synced lyrics.
  The body is still `OverviewLyrics` (word timing, translation are not redone); `showEmpty: false` switches
  off its built-in empty state (a spectrum, the track, a second seek bar, a pill — right for the overview,
  a repeat of the panel here) and releases the spectrum only that state uses.
  It has NO surface (2026-10-10, "sticks out too much"): a raised box with its own fill and outline stood off
  the panel, so the words sit directly on the panel over its cookie field and dissolve top and bottom through a
  transparency mask on the lyrics layer (OverviewLyrics' own `edgeFade` is a colour overlay and needs a solid
  fill to fade into — `edgeFade: false`, `tintBg: transparent`). Palette + accent colours, not the album's.
  No sad-face empty state: that icon isn't in the cut font.

- The YouTube/video layout keeps its 16:9 rectangle: a cookie would crop a third of the picture.
- Dimensions (2026-10-10, on request: bigger cover): the panel is 660 wide (BarPanelDock's cap), the cookie's slot
  176 square (136 cover inside a 20-deep ring), lyrics 240 wide and at least 224 tall. Transport still fits
  (182 of ~224px). Unverified visually: the ring's thickness and reach against Caelestia's.

## The cookie field behind every panel (2026-10-10)

`services/Drift` (+ `drift.js`, `bun scripts/test-drift.js`) is ONE set of 28 Scallops on a repeating
1000×800 plane keyed to the SCREEN; `components/DriftShapes` is one panel's WINDOW onto it, and `Card.drift`
(on in `BarDock` and `SidePanelDock`) puts one behind every bar and sidebar panel. Synced means synced in
space: each window shifts the field by its own screen position (`mapToItem(null, …)`, re-read each field
tick since a sliding or growing panel has no notifying scene position), so two panels side by side show the
same drift, a shape leaving one's edge enters the next, and a panel opening or swapping reveals the field
instead of restarting it.

- The plane repeats so it can be small: each shape has an image per tile and a panel draws the one in its
  window. The jump between images is `period` away from the window's origin — outside a panel narrower than
  `period − shape` (1000−112 covers the 660 cap; a card zoomed to 1.5× shows one faint pop at its far edge).
- Depth: size, opacity and WANDER follow one number; each shape breathes ±5% on its own beat; every third
  has a faint outline. **Not speed** — see below.
- **Why every shape drifts at exactly the same velocity (measured, 2026-10-10, "they stack up in a single
  space").** Speed by depth (3–14 px/s) made fast shapes catch slow ones travelling the same way and the
  field jammed into clumps no separation force dissolved (nine shapes inside one 130px circle after ten
  minutes). ±10% speed spread still reshuffled an even arrangement into a random one, and a random one has
  the odd tight group by chance (6 in a circle, from a start of 3). With one shared velocity the arrangement
  cannot reshuffle: a jittered grid at the start, then only a bounded sinusoidal wander (±10–26px, an
  oscillation, so it cannot accumulate), rotation and breathing. A pairwise separation (≥120px between
  centres, size-weighted, on the tile so it holds across the seam) stays as a safety net.
  `scripts/test-drift.js` enforces it: ≤4 shapes in any 130px circle over two minutes × 12 seeds.
- **Corners (2026-10-10, "very noticeable around the corners").** A panel opening does not just translate:
  `Card` scales 0.96→1 and the blob's spring deforms it, and both move things in proportion to their distance
  from the origin, so the corners slid against the screen — and against the next panel's field. Each shape is
  now placed on the SCREEN and mapped back through the card's whole transform (`mapFromItem(null, …)`), so it
  stays put on screen however the panel moves.
- **The seam between panels (2026-10-10, "still has some issues").** A round of this blurred the mask on every
  edge so the clip would dissolve. Wrong for panels that touch: BOTH sides of a shared edge faded, so a cookie
  crossing from one into the next was dimmed exactly there — a pale notch and a visible line through it. The
  mask is now the rounded rectangle with only the top fade, and a shape runs right up to the card's edge, so
  the two halves meet. (If the artefact is instead during a panel SWAP in one slot — the card collapses and
  re-grows, taking its field with it — that is a different cause; unresolved.)
- With the bar carrying no cookies (`Config.barCookies` off, or Game mode), the top edge — where the panel
  meets the bar — fades in over 32px instead of being clipped, and a hairline `seam` (Divider, inset by the
  corner radius) runs along it. The seam sits OUTSIDE the masked layer or the fade would swallow it. Corners
  are masked rounded (the content area clips to a rectangle). With them on (`Drift.flows`) there is neither,
  and the mask is square at the card's WELDED corners only (`Card.driftJoin`: a floating card joins nothing).
- One frame loop, refcounted like Cava: it runs only while a window is on screen, and `Config.motionEnabled`
  off freezes it. `Config.panelCookies` (Settings › Bar › panels › Panel backdrop) removes it.

### Across the bar, the sidebar and the frame: one strength per picture (2026-10-17)

`Config.barCookies` puts the field on the rest of the material too (`modules/bar/FrameDrift`: the bar's band,
the frame strips and the sidebar, each cut into pieces narrower than the tile, plus `DriftBridge` strips over
the gaps the blob bridges). User, on "everywhere": "it does cut out when moving surfaces, e.g. from bar to
panel". Two causes, both fixed:

- **Each window chose its own strength.** A panel drew every shape at 1; the bar's pieces drew double
  strength on a 70s life ("everywhere") or only what had come out of a panel ("panels"), and "everywhere" also
  kept the panel's top fade and seam. So the same picture of the same shape was drawn at two strengths on the
  two sides of a join, and the join cut it. Now the strength is the PICTURE's (`drift.js strength`, via
  `Drift.strength`): a pure function of its screen position, the shape, the clock and the panels, so every
  window that can see a picture computes the same number. A panel (`DriftShapes.source`, the default) draws 1;
  any picture overlapping a fully open panel is 1 everywhere else too; away from panels it is the mode's own
  (`base`: lit ? 1 : 0, or `BOOST × presence`); in between it eases over `REACH` (48px) as the shape drifts.
  The cost: in "panels" mode a shape about to drift into an open panel shows on the bar for its last
  REACH px — the alternative is a shape appearing out of nothing at the join.
- **A recorded picture wandered off its shape** ("panels"): the carry ran BEFORE the separation, so a push
  never reached it — measured 54px off in two minutes, the bar drawing a cookie where the panel did not, and
  16 duplicate pictures. The carry now runs after it (tested: 0px, no duplicates).
- Panels publish how far each card has faded in (`a`) and whether it is still wanted (`open`)
  (`Bar._panelRects`, cut at the bar's underside so the hidden start of the slide counts for nothing). The
  pull around a panel is scaled by `a`, so it fades in and out WITH the card's own cookies; only a fully open
  panel lights anything (lighting at once put the bar's half of a straddling shape up at full strength while
  the panel's half was still invisible); a closing panel takes the pictures in it with it, so it leaves no
  half-cookie on the bar's edge.
- Plain rectangles (every FrameDrift piece and gap strip) clip instead of masking: the MultiEffect mask was
  a full white rectangle there, i.e. an offscreen render per piece per frame for nothing.
- `scripts/test-drift.js` asserts the join property (4000 random straddling pictures, both modes), a frame-
  by-frame crossing bar → panel with no jump over 0.01, the open/close fades, and the carry.
- **Covered since the blob draws the field** (2026-10-17, docs/bar-and-blob.md): the blob's fillet outside
  the card's box where it meets the bar or a strip. Without the rebuilt plugin, no window draws cookies there. Worked from `blob.frag`'s circular `smin` (k 20): with the card's corner at 23
  ("ii") it is ~13px along the bar and ~6px down the card's side; at the default 16, ~16px and ~20px.

## The power menu (2026-10-10; one look since 2026-10-18)

`modules/bar/PowerDock` — a column of big rounded buttons welded into the frame's right edge, the design
borrowed from Caelestia's session panel. It offers FOUR actions — lock, log out, restart, shut down; it had
seven (+ suspend, hibernate, firmware) and that was too many to read at a glance for a quick, deliberate
choice. Those three are still `Session` functions and `Session.run` still knows their keys; to bring one
back add its row to `powermenu.js` (`needs` still gates one the machine can't do). The action table
(keys, order, letters, which ask twice and what; `bun scripts/test-powermenu.js`) is
`services/powermenu.js`, and `Session.run(key)` is the one key→command table.

There was also a full-screen wlogout-style overlay (`modules/panels/PowerMenu`, with `Config.powerMenuStyle`
choosing between them). It was removed 2026-10-18 on the user's say-so ("I won't use it"), along with its
setting and its `quickshell-power` blur layer rule. It was ALSO what answered under a fullscreen window
(Hyprland hides the bar's layer there), so now nothing can: a request made on a monitor with a fullscreen window
is DROPPED (`PowerDock.blocked` resets `UiState.powerMenuOpen`) rather than left open, invisible, with the
bar's window holding the keyboard. User's call: "do nothing". Lock still works from the sidebar's middle-click
and the launcher.

- Unlike Caelestia's, nothing but Lock fires on the first press: the button ARMS (the warning tone rises up it and DRAINS over `disarmMs` = 4s — the level is the countdown —
  and the icon → check), the caption beside it asks the
  question and lists what the action would cut off (`Session.interruptText`, only for session-ending ones).
  Colour alone can't carry the warning (on a wallpaper palette `danger` and `primary` can be one ramp).
- Keys: letters L E R P, ↑/↓ and Tab move the selection, Enter/Space press it, Escape disarms then closes. The
  Bar window goes Exclusive while it is up (`powerDock.wantsExclusive`: it is opened from another surface, so
  OnDemand would never deliver keys). Click anywhere outside closes: an invisible layer under the card, and the
  window mask is the WHOLE window while it is up.
- Buttons are 80px, shrunk only as far as a short screen forces (`buttonSize`); an action with a `needs` is
  hidden in place (not filtered out of the model) until logind says the machine can — none is, today. The action runs after the column
  has finished closing, so the lock screen comes up over a closing menu.
- The OSD is quiet while the menu is up (`Osd.suppressed`). The caption sits OUTSIDE the card (the card clips),
  is display-only and not in the mask.
- Unverified visually: the lobe's fusion with the frame and the caption's position.

## Media panel: icons, buttons, volume bar, and "Connecting to Spotify" (2026-10-10)

- **Transport icons are Caelestia's, by NAME** (Material Symbols already in the cut font — nothing to
  regenerate): `shuffle`, `skip_previous`, `play_arrow`/`pause`, `skip_next`, `repeat`/`repeat_one`.
- **`CookieButton` was redone** (shared with the overview's now-playing, the power panel and Bluetooth
  settings; API-compatible — `name`, `checked`, `spinning` are additions). It moves on SPRINGS (`SpringAnimation`:
  wind, lean), not eased tweens, so it overshoots and settles, and letting go mid-turn carries on from where it
  was. `checked` (shuffle, loop on) fills the cookie, firms the outline and fills the icon (the FILL axis,
  animated); `spinning` turns it slowly while true (play, while a track plays; held, not reset, when it stops);
  a ring-shaped ripple leaves on press; the icon squashes to a speck and back when it changes (play ↔ pause),
  swapping at the bottom of the squash. The swap is guarded by `_ready`: change handlers fire for values given
  at instantiation, and every button would otherwise squash on first appearance.
- **`components/ThickSlider`** (Caelestia's audio-settings slider; the look, not the code): an 18px bar (was 24,
  then "a little smaller") with BLOCKY corners — a fixed 30% of the height, not a pill; the handle bar and end dot
  squared to match — filled
  with the accent, a thin handle bar standing clear of the fill (taller than the track, taller still held), the
  rest of the track beyond it, a dot at the end; `[filled][gap][handle][gap][rest]`, the rest fades as it runs
  out of room. A drag is RELATIVE to where it was grabbed (taking the handle does not make it jump), a plain
  click goes where it was made, the fill is pinned to the pointer while held. Used for a player's own volume;
  the seek bar stays the wavy `WaveSlider`.
- **"Connecting to Spotify…" forever.** Two causes. (1) `PanelLyrics` held a copy of its words that refreshed
  only on `Lyrics.state`, but the bridge settling changes `blockedReason`, not `state` — so the copy went stale.
  (2) The bridge only counts as having answered once it records a verdict for THIS uri, and for some tracks
  (an instrumental, one with no uri) it never does. `Lyrics.blockedReason` now gives the two WAITING reasons
  ("connecting", "waiting") 8 seconds per track (`_waitExpired`, restarted in `load()`), then drops them,
  leaving the honest state: "Instrumental" if a provider said so, "No lyrics found" if not. "unanswered" is a
  verdict, not a wait, and stays. An instrumental still needs a provider to SAY so (LRCLIB does, via the
  fallback lookup); with `Config.lyricsFallback` off nothing can.
- **Player | Settings is a `SegmentSwitch`** (new; `TabStrip` stays the restrained one for settings pages, same
  model shape): a 36px pill of solid container fill, a FILLED accent indicator whose x and width are separate
  springs (so it stretches toward the new segment and gathers into it), the chosen icon filling in, a hover wash on
  the others; text on the indicator is `fgOnPrimary`, not the accent's own tint. It doesn't glide in from the left
  on creation (`_settled`).
- **Volume**: a real Material speaker by level (`volume_off` / `_mute` / `_down` / `_up`), filled, in a `PanelButton`
  that mutes THIS player's stream; ghost while muted, disabled with no stream. Transport buttons are 32/36/46/36/32
  (were 26/30/38/30/26): 198px with gaps against ~204px for the details column, so it fits, tightly.
- **The play button's "weird little visual bug" (2026-10-11).** Cause not seen, two found by reading: the whole
  button was rotated and the icon counter-rotated to stay upright, which for the play button — the only one that
  spins for as long as music plays — means a glyph re-rotated and re-rasterised every frame (a shimmer/wobble on
  the icon); and on pause it froze at a random angle. Now only the cookie BODY (`shapeBox`) turns, the icon never
  rotates, and `spin` is driven by a `FrameAnimation` and, on stop, eased to the nearest multiple of one petal
  (360 ÷ points — indistinguishable from where it was, since the shape repeats) so it rests upright. The swap
  squash is untouched. If the bug is something else, it is not these two.
- **The header actions are a `ChipTray` of `ChipButton`s** (2026-10-11; new, media panel only — `ActionGroup` +
  `PanelButton` are what every other panel's header still wears and are untouched). A solid pill tray; each chip
  is a round icon that, ON, is a filled disc of its `tint` growing from the middle (OutBack) with the icon filled
  in, and OFF is an icon on the tray with a hover wash; spring lean/press like `CookieButton`. The icon on a filled
  disc is `base` on a light tint and `fg` on a dark one (by `hslLightness`) — a fixed colour vanishes into some
  tints. The equalizer (desktop visualiser) chip's tint is `Colors.of(…).ansi(12)`, pywal's colour 12 with the
  palette's own fallback, on request; it is the one chip not about THIS player. "The sound icon" was read as that
  chip (the sound bars); if the volume speaker in the volume row was meant, it is one line there.

## The cookie field across a seam, the lyrics' lit colour, and the wallpaper panel (2026-10-11)

- **A cookie cut where two welded panels meet.** Welded panels are held `mergeGap` (= `Morph.filletRadius`, 10px)
  apart so the blob can bridge them: two card rectangles with a strip of bridge material between, and each card's
  `DriftShapes` stops at its own edge — so a crossing shape was cut at both and absent in the strip.
  `modules/bar/DriftBridge` is one more window onto the shared field laid over that strip (`BarPanelDock._bridge`
  → `bridgeLC` / `bridgeCR` / `bridgeLR`; only with the plugin present and the cards within `Morph.smoothing`,
  inset at the foot by the fillet radius, 1px overscan under the cards' edges, a plain rectangle, no seam line).
  Every window maps the field through screen coordinates, so it lines up with both neighbours by construction.
- **Lit lyrics use the cover's colours again (the MATCHED set).** `PanelLyrics` had overridden the text colours with
  the palette's and the accent with the album's; the lit word is drawn by `LyricGlyphs` as a blend of `fg` and
  `accent`, so a palette `fg` with an album `accent` came out the wrong colour next to the desktop lyrics widget,
  which takes `AlbumArt.fg / fgDim / fgMuted / accent` together. (A first fix changed only the accent — still a
  mismatched pair.) `PanelLyrics` now overrides NO colours except `tintBg: transparent`, so the card's own
  defaults apply (`Config.albumCardColors ? AlbumArt.* : palette`).
- **The media header's equalizer chip: the CIRCLE is colour 12.** `ChipButton.solid` keeps its disc up in its tint at all
  times (full on, softer off); the icon is the contrast colour on it and says on/off by its fill. (It first only
  filled when on.) `ChipButton` also gained `label` (it becomes a pill) and `iconAngle` (a spinning refresh).
- **Wallpaper panel, restyled** (`modules/panels/WallpaperPanel`, still the pinned 620×394): the header's two
  `ActionGroup`s are `ChipTray`s of `ChipButton`s in the panel's `info` tone; the Images/Scenes switch is a
  `SegmentSwitch` (counts in the labels; the "can't pick Images while assigning a monitor" rule is kept); the
  search is a full pill at the switch's height; the hero card is a flat container (no gradient, no outline) with
  larger corners; the browse/settings/properties toolbars are chip trays. Tiles: transparent at rest (the picture
  is the box — it was a card behind every tile), a wash under the pointer or while current, concentric radii,
  spring lean/press, a staggered SPRING entrance (`slot`, capped at 10; off with `Config.motionEnabled`), the
  "showing now" tick on a cookie, the name on a pill that fills when it is the wallpaper, and the "Add images"
  card's icon in a `ScallopChip` that winds on hover. List rows: card radius.
  NOT touched: the apply-progress pane, the renderer-settings and scene-properties page contents, the workspace
  picker, and the panel's open/close melt (that is BarDock/the blob, shared by every panel).

## Wallpaper panel, round 2 (2026-10-11)

- **One accent with the media panel.** The panel wore `info` (a muted ramp colour); the media panel wears what its
  visualiser module resolves to (`Config.moduleAccent("visualizer", focus)`), so the two headers sat in different
  colours. `WallpaperPanel.accent` asks for the SAME thing and every highlight in the panel (48 sites) follows it.
- **No more snapping to the top on star / remove.** The grid and list were handed a fresh JS array each time
  `galleryModel` recomputed, which REPLACES the model and resets the view's scroll. They now take a `ScriptModel`
  (`values: root.galleryModel`, as the launcher does), whose diff compares strings exactly and objects structurally
  (`scriptmodel.cpp`), so a change lands as inserts / removes / moves on the delegates already there. A starred tile
  still re-sorts to the front, but the view stays where it was.
- **Apply** is a pill that pops in on a spring (from 0.72, rising 8px) with the `wallpaper` icon; while applying the
  icon is swapped for a small cookie turning, the pill breathes and a ring pulses off it. Success is the "showing
  now" cookie badge. **Star / remove** are real buttons top-right on a solid pane (they were 20px outlined dots): the
  bin ARMS on the first press into a red "Remove?" pill with a bar draining over `ArmLatch.timeoutMs`; the star fills
  gold and bumps when toggled. Both spring in on hover; a starred tile keeps its star lit.
- **Hero card:** the title (slides up into place on change) with its kind on a pill; one chip for where the colours
  are from + the mode; the palette is a stack of six overlapping dots that pop in on springs, one after another, when
  the palette changes (was a long strip of bars + three icon lines).
- **Loading** is calm: a tint breathing slowly with one small cookie turning in the middle, instead of a bar of light
  sweeping across plus a spinner; the picture then fades in and settles from 1.06×. **Switching tabs:** the new page
  slides in from its tab's side with a small overshoot, settling from 0.97×, while its tiles (new delegates) pop in
  one after another on `WallpaperTile.arrive`.
- **Parallax icon:** `layers` → `deployed_code` (an open cube). Not in the cut font, so the fonts were REGENERATED
  (`material-symbols-map.py --emit`, approved; 391 symbols) — restart with ALT+Q, not a hot reload. Caelestia has no
  parallax icon (its nearest are `wallpaper`, `tune`, `swap_vert`), so this is from the same Material Symbols family.

## Cookies on the bar, sidebar and frame — an experiment (2026-10-11)

`Config.barCookies` (default on; Settings › Bar › panels › Bar & frame backdrop). `modules/bar/FrameDrift` puts
windows onto the SAME shared field (`services/Drift`) over the rest of the shell's material, so a shape drifting out
from under a panel carries on across the frame.

- **Placement was wrong the first time (user: "I don't see the cookies").** I put one layer at `z: -0.5` — under
  the bar's band (`unifiedBar`'s `Surface`) and the sidebar's body (`SideBarHost`), which are drawn at DEFAULT z and
  so hid it completely; only slivers over the thin frame strips were left. Now two layers, each declared in
  `Bar.qml` directly AFTER the surface it belongs over and BEFORE the controls (same z, so declaration order is paint
  order): `part: "ring"` after `unifiedBar` (the frame and the bar's band), `part: "side"` after `SideBarHost`
  (before the dock icons and the small modules). The ring itself is the blob's, at z -1, so it is below both.
- **They come and go (user: "if they go to the bar they should eventually go away").** On a panel a shape drifts
  forever; on a surface that is always there that is a permanent crowd. On these layers each shape has a LIFE
  (`lifetime`, 70s): there for half of it, fading in (sin²) and out on its own phase — `drift.js presence`, tested
  never to pop (steps under 0.01 per 50ms), 0..1, and out of step between neighbours. Panels are unchanged. A band is
  16–40px, so it shows a sliver of a faint shape: these layers draw at `boost` ×2.
- **Geometry is `drift.js`, tested** (`frameRects`, `chunks`, `framePieces`, `subtract`; rects carry a `kind`,
  "ring" or "side", which survives cutting so a layer asks for its own): the ring is a top band (the bar's
  `barSurfaceHeight` when anchored, else just the frame depth), two side strips between it and the bottom strip, and
  the bottom strip — no two overlap, together they are exactly the ring. The sidebar lobe
  (`SideBarHost.blobX/Y/W/H`) is added with whatever the ring already covers SUBTRACTED, or that band would be drawn
  twice and read twice as opaque. Long bands are cut into pieces no wider than `Drift.periodW − 120`, because a window
  only shows the field's repeat seamlessly while it is narrower than the period less a shape (see `place`); each
  piece is a `DriftBridge` (no corners, no seam, `fade: 0`).
- **Cost, and why it is behind a switch.** A panel closes; the bar never does, so this keeps the field's frame loop
  — and the bar window's redraw — running for as long as it is on. It stands down for Game mode and under a
  fullscreen window on that monitor; `Config.motionEnabled` off still freezes it. Not measured. (A shape that is
  currently absent is taken out of the scene entirely, `visible: opacity > 0.003`, though its bindings still run.)
- **Deliberately unmatched, for a test:** the frame's inner corners are concave arcs and the pieces are plain
  rectangles, so a shape can show a hair into a corner; the sidebar lobe's rounded ends likewise.

### …and where they come from (2026-10-11, same experiment, round 3)

`Config.barCookiesFrom` ("panels" — the default — or "everywhere"), picked under the on/off switch. Asked for as
"cookies should only spawn on panels; when they drift off to the bar/sidebar/frame they go away shortly after",
and then, "or instead make that an option" — so both are kept.

- **"panels"** (`FrameDrift.flow`). The bar, sidebar and frame have no field of their own: a shape shows there only
  as strongly as it has recently been in a panel. Each shape carries a `glow` (`drift.js wake`): 1 while its box
  overlaps any open panel (measured on the tile, by centres and half-sizes), falling to 0 over `GLOW_FADE` = 1.4s
  once it has left them all — a shape that drifts out of a panel carries on across the bar and fades shortly after,
  and one that was never in a panel is never there. The pieces draw at the panels' own strength (boost 1) with
  `wake`. The panels' rects are published by each Bar window (`Bar._panelRects` → `Drift.setPanels(screen, rects)`:
  the three bar-group cards + the sidebar panel, in window = screen pixels). `Drift.alive` (a panel open, or any glow
  left) gates the layer, so with no panel open nothing is shown and the layer lets go of the field's frame loop —
  the idle cost the first version had is gone in this mode. The pieces are built once and the layer is just hidden,
  not torn down (≈300 shape items would otherwise be rebuilt every time a panel opened).
- **The transition (user: "the same non-perfect transition between surfaces").** A panel's top fade and its seam line
  were what cut a shape where it met the bar — they dimmed it right at the edge, then the bar showed it at full
  strength. With cookies flowing onto the bar, both are off (`Config.cookiesFlow` = on and not "everywhere"; read by
  `DriftShapes`' `fade` and `seam` defaults and by `DriftBridge`, so the cards and the gap bridges agree).
  Still not identical: the bar and the cards are different base colours, and a translucent shape reads differently
  over each.
- **"everywhere"** is the earlier behaviour: a field of their own, each shape on a 70s life (`presence`), ×2 strength,
  always running — and the panels keep their top fade and seam, since there the bar's shapes are not the panels'.

### …correction: they DRIFT OFF the screen, per picture (2026-10-11, round 4 — supersedes the "glow" above)

User: "when I meant they go away, I meant they drift off screen, not fading", "I also don't want cookies to spawn on the
bar/sidebar/frame as soon as I open a panel", and the cut cookie at the panel/bar join, "urgently". Two things were
wrong with the glow, and one thing with the join:

- **Per shape instead of per picture.** The field repeats every 1000×800, so a shape has a picture at every repeat and
  a 1920 screen shows several. Lighting the SHAPE when it overlapped a panel lit every picture of it — over the bar and
  frame far from any panel — the instant a panel opened. That was the "spawning". Now `drift.js wake` records only the
  one PICTURE that overlaps a panel (`lit[screen] = [{x, y}]`, the picture nearest the panel, which is the one the
  panel's own window shows) and carries it with the shape's own motion each step (by the shape's displacement —
  drift, wander and separation alike). The bar/sidebar/frame layers draw exactly those recorded pictures, where they
  are NOW (`DriftShapes.wake` + `litKey` = the screen's name), and nothing else.
- **It fades instead of leaving.** There is no fade any more (`GLOW_FADE` is gone). A lit picture stays lit and keeps
  drifting across the bar until it is wholly off the screen (`offScreen`, against the largest screen), unless a panel
  still has it. Cost of that: after a panel closes the field's loop runs for as long as a cookie that left it is still
  crossing the bar (`Drift.anyLit`) — minutes at 6px/s — and then stops.
- **The join.** The bar now draws the picture where the panel does (same position, same strength, no panel top fade, no
  seam), so a straddling cookie is one shape across the join, not two clipped ones. If a cut remains, `qs ipc -c
  ~/.config/quicktest call drift status` prints what the field believes (refs, running, panels as published, lit
  counts) — the next step is to read that, not to guess. Candidates I could not rule out without seeing it: a gap
  between the bar band's bottom and the card's top that the pieces don't cover; the pills' own backgrounds.
- A `drift.js` bug the test caught on the way: `wrapDelta(a, b)` is b − a, and `imageAt` had its arguments the wrong
  way round, which would have drawn each cookie on the bar mirrored about the panel's centre.

### The weld, and the cut at the join (2026-10-11, round 5)

User: "I think the weld is part of this, the transition is weird." It was. A WELDED card is still drawn with all four
corners rounded (`BarDock`: `blobWeld ? radius : …`) and the blob fills the wedge between each rounded corner and
the bar — real material, in the bar's colour. `DriftShapes`' mask rounded the same corners, and the bar layer stops at
the bar's edge, so that wedge had no cookie in it and anything crossing was cut along an ARC (~(1−π/4)·r² per
corner, bigger than the fillet). Fix: `DriftShapes.joins` — the edge(s) welded to a surface that carries the field
on — squares the mask's corners on those edges (per-corner radii) when cookies flow (`Config.cookiesFlow`): `Card.driftJoin`
is "top" for a bar panel ("top left" / "top right" for a left / right one, whose outer side meets the frame's strip),
and a sidebar panel passes `dock.edge`. Not covered: the blob's concave fillet OUTSIDE the card's box (~10px, a few
dozen px² per corner; a rectangle there would overshoot the curve onto the desktop).

### The power menu, animated (2026-10-11; redone calm 2026-10-18)

The first pass was all springs: buttons popping in one after another with an overshoot, a lean toward the
pointer, one focus ring gliding between buttons, a flood circle on arming, a squash-and-wiggle icon swap, a bloom
on firing. The user didn't like it ("try something different"; picked "calm and snappy" from four directions
— cookie buttons, expanding pills and press-and-hold were the others). Now it is the house motion
(`Motion.qml`: decelerate-only, nothing overshoots):
- **Entrance**: the card melts out of the frame as before and the buttons fade up WITH it, together — no stagger.
- **Pointer / keys**: no lean, no per-button tint. ONE highlight (tint + focus border, `radiusCard`) marks the
  pointed-at or keyed-to button and TRAVELS between buttons: two edges, one target, two speeds
  (`Motion.standard` lead / `Motion.trail` lag — the workspace pill's indicator), so it stretches across the gap and
  contracts onto the next. Redone 2026-10-18: the first calm pass had each button tint and round on its own, so a
  move read as two buttons cross-fading and "didn't transfer". It doesn't slide in on first show; leaving the column
  clears a POINTER selection (`byMouse`) but not a key's, and the gaps are inside the column so crossing one keeps it
  travelling. A press dips the button (and the highlight) 3%. No keycap is drawn (removed on request; the letters
  L E R P still work).
- **Arming**: the warning colour RISES up the button to full, then DRAINS linearly over the arm — the fill level IS
  the countdown (it replaces the bar along the foot). Its duration is a literal `disarmMs` (the time is the
  information, so it runs with animations off too). The icon swaps to a check through `SwapFade`. Disarming drains
  it out fast; firing holds it full — `press()` fires BEFORE clearing `armedKey` so the button can tell
  "fired" from "disarmed".
- **Firing**: the chosen button holds full while the others dim to 40%, as the column melts shut and then the
  action runs.
- **Tooltip** (was the "caption"): a `radiusCard` card beside the selected button — name + what it does; armed, the name
  becomes the question in the warning tone, "Press again to confirm", and what it would cut off. Eases out from under
  the column, glides between buttons on the highlight's lead edge, and swaps its words through `SwapFade` (taken at
  once while hidden, so it never shows empty).

### The strip between a panel and the sidebar, and the master switch (2026-10-11, round 6)

- **The cut at the sidebar's face.** A welded panel is held a fillet radius (`mergeGap`, 10px) off the bar, the frame and
  the sidebar so the blob can bridge the two. That strip belongs to neither rectangle, so neither window onto the field
  covered it, and a cookie crossing from a panel onto the sidebar was cut on both sides of it (the same family as the
  gap between two panels — `DriftBridge`). `drift.js gapPieces(panels, surfaces, maxGap)` (tested) finds every strip
  where a panel faces a surface across a gap the blob can bridge (`Morph.smoothing`, 20px) with the two overlapping on
  the other axis — flush, overlapping or further-than-blend need none — and `FrameDrift` lays a window onto the field
  over each: a FIXED POOL of 8 `DriftBridge`s bound by index (the rectangles change every frame a panel animates, and a
  Repeater over a changing array would rebuild its delegates each time), filtered by the layer's `part`. None without the
  plugin (the gap is then just room, with nothing to bridge). The sidebar's rectangle now comes from its own body
  (`SideBarHost.maskItem`) rather than its blob geometry, which is zero unless the weld is on.
- **Diagnostic that found the next thing:** `qs ipc -c ~/.config/quicktest call drift status` showed one shape holding SEVEN
  lit pictures. That is correct, not a leak: on a 1920×1080 screen the 1000×800 tile gives a shape up to six pictures
  and each is lit when it overlaps a panel.
- **Master switch (user: "add a setting to disable this from going to the bar/frame and sidebar entirely").** It exists as
  Settings › Bar › panels › "Cookies on the bar, sidebar & frame" (`Config.barCookies`; renamed from "Bar & frame
  backdrop" so the title says all three and the settings search finds it). "Entirely" is now true of the machinery too:
  with it off, `Bar` publishes no panel rects, `Drift` tracks no pictures and drops any already lit (no bounds = off
  screen), `FrameDrift` is hidden and holds no loop, and the panels go back to their own top fade and seam
  (`Config.cookiesFlow` is false). Panels keep their own cookies — `Config.panelCookies` is the separate switch for those.
  The settings search index (`build-settings-index.py`, generated) was regenerated so the new sections are searchable.

### The panel swap (2026-10-11, round 7)

User, on the cookie seam they had left open: "address the panel swap" — and then "it gets cut on the edges of the panel".
A SWAP (one panel replacing another in the same bar slot) runs the Accordion: `contentVisible` false, the content changes
after `Motion.exit`, then true again. `BarDock`'s Card followed `shown`, so on every swap the card — and the cookie field in
it — faded out and back, scaled to 0.96 and slid up `slideDistance` (24px) and back, while the panel's real box (the blob
lobe, bound to `card.height`) stayed full size and merely resized. Two faults:
- the field **blinked out and back** while the bar's layer (a separate window) kept showing what had left the panel;
- it was **cut inside the panel's real edges**: clipped to a card that had shrunk and risen, not to the box it was in.
Fix (`BarDock.holding`): while `Config.panelCookies` is on, a card that has been open (`_open`: set when `shown` first goes
true, cleared when the slot closes) stays up — full opacity, full size, in place (no `-slideDistance`) — across a swap, and
only its CONTENT changes (the content Loader has its own fade, keyed on the real `shown`). The first opening (which fades in
after the box has grown) and a close are unchanged, and with panel cookies off the old swap animation is exactly as before.
Cost: with cookies on, the swap no longer slides/scales the card; the content crossfade is what you see.

### A divider across the join: BarDock's seam erasers (2026-10-18)

User: "search if there's a divider between surfaces — the floating cookies keep getting cut when transitioning certain
surfaces". With the blob drawing the field (`Drift.inBlob`) a join between two welded surfaces is one merged SDF and the
shader gives each pixel one owner, so the blob itself has no divider. What was left was QML painted OVER the blob:
`BarDock`'s "Erasing the seam" — two plain `Rectangle`s of `Colors.surface`, one along the card's top (`hugBar`: the
bar↔panel join) and one down its outer side (`hugFrame`: the frame / sidebar↔panel join), each `Tokens.borderWidth`
(1px). They exist to paint over the card's own border, but a welded card has `border.width: 0` (the blob strokes the
silhouette), so they erased nothing and were a 1px opaque line, in a slightly different colour from the blob's fill,
exactly where a cookie crosses from the bar/frame/sidebar into a panel. `underlineErase`, beneath them, was already
gated on `!dock.blobWeld` for this reason; these two were missed. Now gated the same way. (Also true without the plugin's
cookies: they cut the top row of a QML cookie too.) Unverified by eye.

Not ruled out, and not touched (needs a plugin rebuild): `BlobShape::cullCookies` keeps at most `MAX_COOKIES` = 24
pictures PER QUAD, first come first served in field order, and drops the rest silently. The bar's band / the frame ring
is one huge quad that touches far more pictures than a panel's does (28 shapes × up to ~6 images on a 1920×1080 screen;
"everywhere" mode shows about half of them at once), so a cookie can be kept by the panel's quad and dropped by the
ring's — absent on one side of a join, which reads as a cut. Likely only in "everywhere" mode or after several panels
have lit pictures that are still crossing the bar. To check: count the pictures a quad touches against 24, or raise the
cap (the shader's `cookieData[48]` and the C++ constant together).

## Colours panel, restyled — stage 1: the chrome and the Editor tab (2026-10-12)

`ColorSchemePanel` brought to the recipe the wallpaper and media panels wear. Stage 2 (the Presets cards and the Album page)
is NOT done: those two views keep their old contents under the new header and switch, and only gained the `ViewEnter`.
- **Header**: the two `ActionGroup`s are `ChipTray`s of `ChipButton`s in one panel accent (`root.accent` = `primary`; there is no
  module to resolve one from, as the wallpaper panel's `visualizer` is). The restart notice is no longer a text pill — one lit
  `restart_alt` chip (warning tone) and a `close` chip beside it for "leave them"; the subtitle names the apps instead
  (`restartNote`). The lock chip is lit while colours are held.
- **Palette | Presets | Album is a `SegmentSwitch`.** It gained an optional `lit` per segment (an icon filled in the accent while
  NOT chosen) so the Album tab still says "the music is driving the shell" from another tab — the old strip did that by hand.
- **Workbench**: a flat card (no outline, like the wallpaper hero). Seed swatches are pills with a selection RING that closes in on
  the swatch and a fill that pulls back from it on a spring (`inset`); they lean to the pointer and dip on a press. The Slots grid
  is the same at swatch size, its pin / pencil mark popping in. A swatch's colour follows the picker, so it uses `Motion.track`
  (an eased colour would chase the drag). The hex is a colour DISC beside a pill `InputField`; the sixteen colours Apply will
  commit are one ribbon with rounded ends (the outline is laid OVER it so a background nearly the card's colour still has an edge).
- **`InputField` replaces the three hand-rolled `TextInput`s** (hex, scheme name; the preset rename is stage 2). The hex field
  commits only a real `#rrggbb` that differs from the colour in use — `InputField.committed` also fires on blur, and an untouched
  blur must not stage a slot as edited — and puts back whatever else was typed; Enter lets go, Esc restores and lets go (accepted,
  so it does not close the panel). `InputField.blur()` is new: `focus = false` on the field is not enough, the inner TextInput holds it.
- **`setCurrent` / `curHex`**: the one place the picker and the hex field write the colour in use. They each carried a copy of the
  simple-vs-advanced branch.
- **`ViewEnter`** (new, `components/`, non-visual like `SwapFade`): when `active` turns true the target rises `rise` px and fades
  up (OutBack, a hair of overshoot), after `delay`. In only — going out is `visible` false, and the panel's surface is resizing
  in that same moment. Used on all three views, the seed row / slot grid (a small rise on a mode switch), and the footer, which
  arrives a few `Motion.stagger`s behind the card.
- **`SpectrumPicker` glides when the colour comes from OUTSIDE** (a different swatch, a typed hex, the album changing): the cursor
  and hue thumb travel, the base hue crossfades. A drag never glides (`_drag`); nothing glides in from 0,0 on creation (`_settled`).
  `ColorField` (settings) shares the picker and gets the same.
- **Footer**: the status line is a pill whose text is REPLACED when what it says changes (`SwapFade`, holding its own copy), a tray
  of the secondary actions, and Apply as the one lit chip.
- NOT touched: the apply-progress pane (its `PanelButton`s stay, as in the wallpaper panel), and everything the panel does —
  every `ColorScheme` call is the same.

## Colours panel, restyled — stage 2 and extras (2026-10-12)

User: "when switching tabs, the animation is so jumpy that the header moves" — and "think of more additions/improvements".
- **The header moved on a tab switch.** `BarDock` animates the card's height to the view's `implicitHeight`, and the panel's
  column was `anchors.fill: parent`: while the card was taller than the content (every switch to a shorter tab) the surplus went to
  each child that defaulted to `fillHeight` — the header row, and the switch under it — which slid down and back. The column is now
  pinned to the top at its OWN height, so the card's edge reveals or trims rigid content and nothing moves. (This is what
  `check-qml-fillheight.py`'s PanelHeader line was saying; it is also now `Layout.fillHeight: false` throughout, and clean.)
- **Presets are miniatures of the palette**: the preset's own background, its name in its own text colour, a ribbon of its colours.
  The loaded one wears the ring-and-inset of the editor's swatches; cards arrive on a spring EVERY time the tab is shown
  (`replay()`, snapping to 0 unanimated while hidden — not once when the delegates were built behind it) and lean to the pointer.
  Edit / delete live in a `ChipTray` that springs in under the pointer, and the name gives way to it. **Delete now asks twice**
  (`ArmLatch`, "Delete?"): it removed a saved file on one click. Rename is an `InputField` in place (Enter commits, Esc / blur cancels).
  A TapHandler on the card does not stop the tray's own, so the card's tap checks the tray's hover. Empty state is an icon and a line.
- **Album**: "Applies to" is a `SegmentSwitch`; the explanation under it is replaced when it changes (`SwapFade`); the status card is flat,
  its note in a disc that lights while the album drives the shell, the eight colours one ribbon.
- **Contrast readout** (`Text · AAA 12.4`, warning tone at "Low"): `palette.contrastGrade` over the existing `contrast()`.
- **Shuffle** (simple mode): redraws the two accents, keeps background and text. `palette.suggestAccents` — a random hue and a
  lightness chosen for the ground, a partner at a random harmony (analogous / split / triad / complementary), both lifted to 3:1.
  `bun scripts/test-palette-harmony.js` checks that over 400 draws on four grounds.
- **Applied tick**: after an apply THIS panel started lands, the Apply chip becomes a tick in `Verdict`'s pass colour for 1.8 s. Not for
  a failed run (that takes the body over) and not for a run another part of the shell started.

## Colours panel, round 3: the six extras and tighter presets (2026-10-12)

User: build all of the offered ideas except the eyedropper ("I already have a bar module that handles that"), and "make [the presets]
tighter, too much empty space around the colour scheme and text".
- **Presets, tight**: ~52px a card (was ~76). The ribbon sits right under the name, margins are halved, the loaded ring is 2px with a
  2px gap, the grid gap is 4px. Edit / delete no longer take their own row: they spring in over the card's right edge and the name AND
  ribbon give way to them (`cardFill.gap`, a plain property — a Behavior can't sit on `anchors.*`). Rename covers the whole card.
- **Search and sort** (appear at `libToolsFrom` = 6 schemes): a pill `InputField` (Esc clears) and two chips, A–Z / Recent. Searching HIDES
  cards, it does not rebuild the list, so the rest glide together (`Flow.move`) instead of re-arriving on every keystroke; a card searched
  back in does re-arrive. Sorting reorders the model, which rebuilds it — a sort that re-arrives is the right look. "Recent" is the file's
  mtime: the listing script now prints `name\tmtime\tjson` and `presets` rows carry `mtime`. Local to the panel; not persisted.
- **Peek** (footer, beside Apply): HOLD to wear the pending scheme on the whole shell, let go and it is gone. It is a new `Colors.preview`
  layer over EVERYTHING (file, workspace palettes, the album overlay), not `Colors.overlay`, because the album reassigns that one on every
  track change and would overwrite a peek, then restore a stale album afterwards. `Colors.baseData` is `data` without it — the editor's
  `editBase` reads that, or a peek would feed its own colours back into the untouched seeds (colour4 of a derived palette is NOT the seed).
  `ColorScheme.peek()/endPeek()` own it; the panel ends it on destruction. In memory only. `ChipButton` gained `pressed` for it.
  Only the panel reads `Colors.data` (services read `fileData`), so nothing regenerates cursors or the like during a peek.
- **Undo** (tools row): a stack of what the editor held before each step — a whole picker drag (`SpectrumPicker.dragging`), a typed hex,
  Shuffle, a harmony, a scheme loaded, a discarded draft. A step is the four seeds, the loaded scheme and the staged slots, so it is the
  same in Palette and Slots. Capped at 30, a no-op press is not a step, no redo (there is no `redo` symbol in the cut font).
- **Harmony** (tools row, Palette mode): Near / Split / Triad / Opposite set Accent 2 to that partner of Accent (`palette.partner`, kept
  3:1 legible on the background, tested) and select Accent 2; the chip stays lit while Accent 2 IS that partner. Shuffle moved here from
  the label row, and now builds on the same `partner`.
- **Copy**: the colour disc (tap) and a chip beside the hex both copy the hex (`Clipboard.copyText`); the chip ticks for 1.2s.
- Icons: all existing names (`visibility`, `content_copy`, `text_fields`, `schedule`, `undo`, `search`) — no font regeneration.
- `check-qml-palette.py` now knows `baseData`, `preview` and `previewing` are shared state, like `data` and `overlay`.

## Colours panel, round 4: smoother presets and peek, a livelier Palette tab, the album refresh (2026-10-12)

User: the Presets tab's animations ran at a low frame rate; Peek did not transition smoothly; the Palette tab wanted more animation;
"Near / Split / Triad" meant nothing; the lit palette icon looked wrong; and with album colours on, the refresh button went back to
the WALLPAPER's colours instead of reloading the album's.
- **Album refresh (bug).** The chip called `ColorScheme.regenerate()` — rebuild from the wallpaper. In the "Everything" reach
  `colors.json` IS the album's palette, so that overwrote it with the wallpaper's and nothing re-pushed the album; in the shell-only reach
  it fought the overlay. While `AlbumScheme.active`, the chip now calls `AlbumScheme.reload()` (forget the cached palette, re-extract the
  cover on screen, push it) and spins for as long as `AlbumScheme.extracting`. Not active: rebuild from the wallpaper, as ever.
- **Peek was stepped, not blended.** `PaletteRoles` eases a palette in 12 steps over `Motion.emphasized` (340ms): one jump every 28ms
  (a step re-evaluates every colour binding on the screen, which is why it is 12 and not per-frame). A peek now eases over `Motion.exit`
  (200ms) with the same 12 — one step a frame at 60Hz, and quicker to answer. `Colors.fastEase()` is called BEFORE the preview is set or
  cleared (the ease it starts must already be the quick one); `easeMs` drops back a moment after. `PaletteRoles.steps` is settable now.
  Whether the 12 re-evaluations fit in 16ms on a busy screen is not something I measured.
- **Presets frame rate — found by reading, not profiled.** (1) Delegates are built behind a page with no width, so on the first show EVERY
  card ran `Flow.move` from the corner while also running its own entrance: the glide is now off until the tab has settled
  (`chipFlow.glide`). (2) The whole pane faded and shifted around cards that each fade and spring: only the search row enters as a block now.
  (3) Hovering a card animated its content inset every frame, re-eliding the name and re-laying out 15 ribbon cells per frame per card
  the pointer crossed: the inset now changes once, under the tray as it springs in. (4) The ribbon is cells placed by arithmetic (no layout
  engine), rounded to whole pixels, which also removes the hairline seams.
- **`PopIn`** (new, non-visual): the spring entrance the preset cards carried inline, as three numbers to fold into a caller's own
  `opacity` / `scale` — not a `target:`, because these items already drive `scale` themselves (lean, press). Used by cards, seeds, slots.
- **The Palette tab, livelier**: the card fades while its parts rise one after another (seeds, tools, picker, then the footer);
  seed swatches and slot cells pop in as a wave whenever the page is shown; on a discrete change (Shuffle, a harmony, a scheme loaded, an
  undo — `ripple()`) the swatches bump in turn and the ribbon re-colours left to right, while a DRAG still just tracks; the contrast badge
  pops when its grade changes; Save ticks ("Saved") for a moment, like Apply and Copy.
- **Harmony in words**: Similar (30°) / Triad (120°) / Split (150°) / Opposite (180°), in order round the wheel. Each chip carries a DOT
  of the colour it would give (`ChipButton.dot`), and a line under the row says what the chip under the pointer does (`ChipButton.hovered`;
  the line is replaced as the pointer moves, `SwapFade`).
- **The lit palette icon.** The FILL axis turns Material's `palette` into a blob (the paint dots fill in). `ChipButton.fillIcon: false`
  keeps its outline; used by the header's palette chip and by Apply.
- (`check-qml-aliases.py` only reads an `id:` at the start of a line, so `ChipButton`'s `HoverHandler { id: hover; … }` on one line looked
  like an alias to nothing; the id is on its own line now rather than the checker loosened.)

## Colours panel, round 5: stars, a sync chip, and walking two things back (2026-10-12)

User: remove the harmony explanation ("make the panel tighter"); add a refresh beside undo that re-reads the colours in use into the
selector; "the animation on the presets is now very snappy, revert that"; star colour schemes; fix the palette icon on the tabs.
- **Harmony hint line removed** (and its `SwapFade`, hover state and `ChipButton.hovered`, which existed only for it). The dots on the
  chips are the explanation now. Round 4's hint paragraph above is superseded.
- **Presets animation, reverted to how it felt**: the pane rises and fades in again (`ViewEnter` on the pane) and the name and ribbon slide
  over on a spring when the tray arrives (`Behavior on gap`). KEPT, because neither is visible as an animation: the glide gated until the
  tab has settled (the cards flying in from the corner) and the ribbon placed by arithmetic.
  (If the cost of the two reverted pieces comes back as dropped frames, that is the trade the last round was making.)
- **Sync chip** (beside undo): throws the edits away and re-reads the colours the shell is wearing — the album's while it drives the shell
  (`editBase`) — into the four seeds, dropping staged slots and the loaded scheme. One undo step; greyed while the editor already matches
  (`editorDiffers`).
- **Stars**: `Config.colorFavorites` (persisted; `colorFavToggle`, as the wallpaper favourites) holds scheme NAMES. Starred schemes float to
  the front of the library in whichever sort is chosen; a star chip on the hover tray toggles it, a filled star sits after the name, and a
  star chip in the search row shows only starred. `ColorScheme` keeps it in step: a rename moves the star, a delete drops it.
  Toggling a star reorders the model, which rebuilds it, so the grid re-arrives.
- **The palette icon on the tabs**: `SegmentSwitch` takes `fillIcon: false` per segment (the Palette tab uses it; Slots' icon still fills),
  and the footer status line no longer fills it either.

## Colours panel, round 6: light / dark, and schemes that hold both (2026-10-12)

User: a light/dark switch on the panel; presets able to hold both modes; refresh LEFT of undo; a better icon for a filled star.
- **The file format** (`palette.js` unpackScheme / packScheme / pickVariant, `bun scripts/test-palette-scheme.js`):
  `{ "special", "colors", "variants": { "dark": {…}, "light": {…} } }`. The PRIMARY variant (dark if there is one) stays at the top level,
  exactly where the old single-palette format had its only palette, so anything that reads the old shape — `check-contrast.py`, a shell that
  has not updated, the update script that ships `colorschemes/` — still works. A file with no `variants` is a legacy scheme and its mode is
  read off its background, so the bundled library is untouched and a scheme gains its second mode only when someone saves it. The test runs
  against the REAL shipped schemes: each unpacks to one variant and re-saves with its top level byte-identical.
- **Saving merges.** `ColorScheme.saveScheme(name, { dark?, light? })` — a mode left out keeps what the scheme already holds (updating its
  Light version never costs it the Dark one). The panel writes the current mode's palette, and the OTHER mode's too if you made one while
  away from it (`stash`); a mode you never touched is not written. Loading picks the version for the current mode; a scheme that has only
  the other one loads that, the subtitle says so and what Save will do (`fallbackNote`), the card shows it dimmed.
- **The switch** is a sun / moon pair in the header, lit for the mode in use, off while wallpaper theming is off or a palette is being made
  (as Settings › Appearance is). It, Settings, the launcher's Theme action and `qs ipc … wallpaper theme` ALL go through
  `ColorScheme.switchMode`: set the mode, then re-derive from the wallpaper as before — UNLESS the scheme being worn is a saved one with a
  version for the new mode (compared with what is on screen, so a scheme merely looked at in the editor is not applied by a flip), in which
  case THAT version is applied. Without that, a scheme made in both would have fallen back to the wallpaper's colours at the first flip.
- **The editor keeps each mode's work.** It holds one palette, the current mode's; flip away and what you were making is kept (only if it IS
  something made — `editorDiffers`), flip back and it is as you left it; a mode with nothing kept loads the edited scheme's version for it, or
  else waits (≤10s) for the shell's new palette and syncs to that. The panel reacts to the mode CHANGING, not to its own click, so a flip from
  Settings does the same. Undo history is cleared on a flip (a step back would cross the mode).
- **Cards** show the version for the mode (dimmed if it is the other one) and two small marks, sun and moon, lit for the versions it holds.
- **Undo / refresh swapped**: refresh is on the left.
- **The star**: the glyph is fine at large size; at ~13px beside a name the rounded Material star blurs to a blob. A starred scheme is now a
  filled `bookmark` (a solid shape that holds up small), at `iconSm`, on the card, the hover tray and the filter chip. (`star` or `keep`
  are one word each in the file if you prefer them.)

### Live config

`~/.config/hypr/binds.lua` lines 127-128 (the brightness keys) now call `qs ipc -c ~/.config/quicktest call brightness
step up|down` instead of `brightnessctl s 10%±` — done on request, after backing the file up to `~/.config/hypr/.bak/
binds.lua.20261011-brightness`; `luac -p` passes and the running shell already exposes the `brightness` IPC target.

## Clock panel, restyled (2026-10-12)

`ClockPanel` (Weather | Calendar) brought to the recipe the wallpaper, media and colours panels wear. Nothing it DOES changed — the ring
physics, the month pager, the editor draft and every service call are the old code; what changed is the chrome, the structure around them,
how each page arrives, and what it costs to open.
- **Chrome.** The page switch is a `SegmentSwitch` (Weather | Calendar, `lit` when something is live on the other page: rain on its way; an
  overdue reminder or an event under way). Back-to-now is a lit `ChipButton` pill that opens beside it; unit and refresh are a `ChipTray`
  (`°C` / `°F` flips `Config.weatherMetric` — every temperature in the shell — and stays on both pages: the Calendar's today card shows one). The optional
  `PanelHeader` (module setting `clockPanelHeader`) is unchanged, its icon now follows the page.
- **Flat cards, no outlines.** Weather: the ring + hour is one card, the week another, the outdoors a row of pills (a `Flow`, so a narrow
  panel wraps rather than clips). Calendar: see round 2 below (this first layout was too tall). Fields are pill `InputField`s; the editor's buttons are chips.
- **Arriving, every time.** The old `Entrance` ran once, at creation — so the Calendar page, built while hidden, never cascaded when you
  switched to it. Now `ViewEnter` on each card and `PopIn` inside play whenever the page is SHOWN (`weatherOn` / `calendarOn`); the ring
  spins in again (`ring.arrive()`); `lead` holds only the very first one back for the dock's open pause, then is 0. Reminders cascade with
  the page but one added later just appears (`late`); picking a day rebuilds the agenda, which cascades.
- **New motion.** A wash slides between the week's days on a spring (SegmentSwitch's indicator, for days); day tiles lean to the pointer;
  range bars grow on the tile's spring; the sun walks to where it is each time the page is shown; the facts and detail cells pop in; a
  reminder's chips spring in under the pointer (`HoverTray`) and the text gives way to them.
- **New: the week's range bars.** Each day's low–high on ONE scale for the whole week (`weekRange`), a gradient from the cold end's tint to
  the warm end's, with a bead for the temperature right now on today's.
- **New: the rain, quarter hour by quarter hour.** `Weather.nowcast` already worded it ("Light rain starting in ~20 min") and nothing
  showed it. Now a pill: icon, the short wording (`nowcast.short`: "Rain in ~20 min", "Rain ends ~30 min", "Dry for 3 h") and, when it is
  wet or coming, twelve bars, one per slot (`W.bars`). No bars for a dry spell. The Weather tab's icon lights while it is on its way.
- **New: next up.** Under today's facts, the next TIMED event — under way (`now · until 11:00`) or inside 36 h (`in 25 min`, `at 15:30`,
  `tomorrow 09:00`) — in the accent. `Ics.nextUp`; all-day entries aren't "up next".
- **Cost.** (1) A hidden `MonthGrid` built only to read one height back — 42 cells — is arithmetic now (`pageH`); (2) the month pages,
  reminders and agenda are empty models until the Calendar page is first shown (`calendarSeen`), where a panel opened on Weather used to
  build ~1000 items it never showed; the pager's cache is one page each side, not two; (3) `sun`, a reminder's overdue state and an event's
  "past" read `Clock.minutes`, not the per-second `now` — they were rebuilt sixty times a minute; (4) the rain bars are replaced only when
  the picture changes. Not measured — read from the code; `QSG_RENDER_TIMING=1` on a reload is the check.
- **New shared bits.** `components/HoverTray.qml` (a `ChipTray` that springs in on `shown`; the colours panel's presets still carry their own
  copy of the same thing, left alone), `PopIn.delay`, `ics.js nextUp`, `weather.js bars` / `nowcast().short`. Tests: `test-ics.js` (78),
  `test-weather.js` (41).
- Not touched: `Weather`, `Calendar`, `Reminders`, `AirQuality`; the editor's validation; the ring's drag, fling and wheel.

## Clock panel, round 2: a shorter Calendar, and cookies through the cards (2026-10-12)

User: the Calendar tab was "too tall"; and "I want to be able to see the floating cookies" through the section cards (at ~95% opacity).
- **`Tokens.sectionAlpha` (0.95 then; 0.85 now, see round 3) and `Colors.section`** (`PaletteRoles.section` = `surfaceContainer` at that alpha): a SECTION card — a panel's flat
  container for a group of controls — is no longer solid, so the cookies drifting behind the panel (`Drift` / `DriftShapes`, drawn under the
  content) read through it. Used by the clock panel's cards and pills and the colours panel's workbench and album status card. NOT for
  controls (SegmentSwitch, ChipTray, the footer status pill) or the preset cards, which are miniatures of their own palette. 0.95 is a hint,
  not a window: the shapes are faint to begin with; lower it in `Tokens` to show more (one number, everywhere).
- **Calendar, rethought: ~270px of content instead of ~470.** The old page stacked four cards (today, reminders, month, agenda) in two columns,
  and the taller column set the height. Now it is two cards side by side, each as tall as the MONTH:
  - **Left: the month**, cells 30px (was 36), title in `title` size level with the arrows. Always there.
  - **Right: the agenda**, one card. Header: the time, the date · ISO week · the moon (drawn, with its %), today's weather, and the add-event
    chip — what the big clock card and the facts row said, on three lines. The next-up pill under it when there is one. Then ONE scrolling list:
    reminders (tick, words, when, a hover tray for snooze / delete), then the days ahead. At its foot the quick-add: the words, a single chip
    that STEPS through when (In 1 h → Tonight → Tomorrow → At… → No time; a time box appears only for At…), and a check lit once there is text.
    Errors take a line only while there is one.
  - **The editor takes the agenda's place**, and the month stays: the date is the ringed day, set by CLICKING the month (`setDraftDay`; the
    month turns to an existing event's own, `goToDay`). That dropped the date stepper and the Cancel button (the back chip is Cancel), and put
    the times, location and repeat in four short rows. It fits the month's height; if it ever does not, the card grows by the excess.
  - Dropped from view: day-of-year / days-left (the week and moon stayed). Say if you want them back.
- Not touched: the Weather page, ring, services, the draft's validation, `Reminders` / `Calendar`.

## Clock panel, round 3: Caelestia's calendar touches, a day strip, quick-add that reads, feeds, a planner, keys, Clocks (2026-10-12)

User: more transparent cards; no weather on the Calendar tab; "copy the notes from Caelestia" (read: my notes on its calendar — behaviour only,
nothing copied; Caelestia is GPL-3); and build every suggestion except its resource rings ("doesn't make sense in a clock/weather panel").
- **`Tokens.sectionAlpha` 0.95 → 0.85.** The Calendar header lost the weather glance (the Weather tab has it).
- **Month grid** (`MonthGrid`, rewritten; the clock panel is its only user now): the neighbouring months' days fill the first and last rows,
  dimmed, and are clickable (the month turns to theirs); Saturday and Sunday lean toward the accent; the picked-day ring is ONE ring that
  springs between cells (and fades between pages) instead of a ring per cell; the middle button, or a click on the month's name, goes back to
  now. `picked(y, m, d)` carries the cell's own date.
- **The day strip** (agenda card, under the header; `services/dayplan.js`, tested): 00→24 across, each timed event a bar (a second lane when they
  overlap), a line at now, 06/12/18 ticks, and "Free until 14:30" / "Busy until 11:00" / "3 events · from 09:00" beside it. Follows the picked
  day. A bar of your own opens its editor. Bars wear their calendar's colour.
- **Quick-add reads** (`services/quickadd.js`, 70 cases, run under three timezones): "dentist tomorrow 9am", "gym every monday 7am", "tea in
  20 min", "film tonight", "trip 3rd of november", "workshop friday 9-10:30am"… A day or time in the line makes an EVENT (or, by the chip, a
  reminder at that moment); the line under the field says what it understood, in the accent, before you press Enter; "Added to your calendar"
  afterwards (`Verdict`'s pass colour), and the month turns to the day. No day or time in the text: the plain reminder it always was, timed by the
  when chip. A bare number is never a time ("table for 2"); a bare range needs "from"/"at" ("meeting 9-10" stays a title). A repeat forces an
  event (a reminder has none). `Reminders.addDue(text, ms)` is new, and refuses a moment already past.
- **Subscribed calendars** (`.ics` feeds): `Config.calendarFeeds` ([{ id, name, url, color }], `color` a palette ROLE), `Calendar.addFeed /
  removeFeed / setFeedColor`, fetched with curl one at a time on first use and every 30 minutes while the panel holds the service, read-only.
  Their events carry the feed's id as `source`: month dots, strip bars and agenda icons wear its colour (resolved against the panel's own
  screen's palette, via `Calendar.feedRole`), the agenda names the feed and doesn't offer to edit it. A feed that fails keeps what it had and says
  so. The URL is a curl ARGUMENT after `--`, under `--proto =http,https` (`Ics.feedUrl` checks it; tested), and is never logged — a Google
  "secret address" is a password. It is stored in `config.json` (the state dir, not the repo). Added in **Settings › Desktop › Style › Calendars**
  (next to the weather location). Not cached on disk: the panel shows nothing from a feed until the first fetch lands (~a second).
- **Weather planner** (`weather.js`, tested): a thin card under the ring — one bar an hour for the day on the ring (chance of rain, tinted when
  it is wet: ≥50 % or ≥0.3 mm), the ring's hour lit, hover reads an hour, click turns the ring to it — with "Dry until 17:00" / "Rain until 15:00" /
  (another day) "Rain 14:00–16:00" beside it. A **Golden hour** pill in the footer (the hour before sunset; "now · until 18:58" while it lasts).
- **Keys** (no focus stolen): `EscapeGuard` now emits `keyPressed` for what Escape doesn't take; `BarPanelDock` / `SidePanelDock` hand it to the
  open panel's `handleKey(event)` (and Escape first to `handleEscape()`, so it can leave a sub-view before closing). Only while no text field has
  focus, so typing "t" in a box is never "today". Clock panel: Tab / Shift+Tab / 1 2 3 the page; T or Home: now; Weather ← → the hour, ↑ ↓ the day;
  Calendar ← → a day, ↑ ↓ a week, PgUp / PgDn a month, N a new event; Escape leaves the editor first. The editor's and quick-add's fields take Escape
  themselves (back to the month / let go of focus).
- **Clocks**, a third page: **World** (the machine's own clock first, then up to 8 cities: day/night icon, "Tomorrow · +8 h · JST", the time; type a
  city to add — the list comes from `timedatectl list-timezones`, fetched when you first search) and **Alarms** (the same `Timers` alarms the
  sidebar's timer panel lists, now with repeat: one chip steps Once → Weekdays → Every day → Weekends, `alarms.js`, tested; a repeating alarm
  re-arms itself, one that slipped past while the shell was down moves to its next day silently). `services/WorldClock.qml`: QML's JavaScript
  has no time zones, so each zone's offset and name come from `date` (TZ per zone, as a positional argument to a fixed script) every 15 minutes
  while the page is open, and the clock is UTC arithmetic (`worldclock.js`, tested). The tab's icon lights when an alarm rings within the hour.
- **Not built**: Caelestia's CPU / RAM / disk rings (the user's call). Not done: a disk cache for feeds; Escape-to-leave in the Clocks page's fields
  is the only keyboard use there.
- Tests: `test-ics` 90, `test-weather` 66, `test-dayplan` 27, `test-quickadd` 70, `test-alarms` 14, `test-worldclock` 31.

### Clock panel, round 3 follow-ups (2026-10-12)
- **`Audio.profileOf` collided.** `services/Audio.qml` had `profileOf(node)` (a device's profile label: EqualizerPanel, SoundPage) AND a new,
  uncommitted `profileOf(player, appId)` (the mixer's volume profiles) — `Duplicate method name`, which took down every service and
  `shell.qml`. The new one is `Audio.volumeProfileOf` (MediaPanel's caller and VolumeProfiles' comment follow). Not the clock panel's change;
  found by the user's reload. `check-qml-duplicates.py` does not see duplicate FUNCTIONS — a scan for them (same name, same indent, one file)
  came back clean after the rename.
- **Weather icons are Caelestia's set, drawn outlined.** `Weather.symbol`: `clear_day`, `partly_cloudy_day`, `cloud`, `foggy`, `rainy` (every rain
  code, as Caelestia has it), `cloudy_snowing`, `snowing_heavy`, `thunderstorm`; Material's own `clear_night` / `partly_cloudy_night` after dark
  (Caelestia has no night). Every consumer (the panel's ring, detail and week; the desktop widget's hours and disc) now draws them at FILL 0:
  filled, a cloud with a moon or rain in front closes into one blob and loses what names it. **`clear_day`, `cloudy_snowing` and `snowing_heavy`
  are not in the bundled font yet** — `python3 scripts/material-symbols-map.py --emit`, then ALT+Q (all three exist in the installed font; `--emit`
  collects every quoted icon name in the tree). Until then those show as help-circles. `test-icons.js` cannot see them (they are `return`
  values, not `name:` literals), so it passes either way.
- **Cut-off text on the thin cards.** The rain card's label was as wide as its shortest string ("Dry until tomorrow 03:00"); "Rain 08:00–10:00 ·
  15:00–16:00 …" and the hover read-out ("23:00 · 100% · 12.5 mm") were elided. It is now as wide as the widest of the three. The Calendar's
  day-strip label got the same (it is as wide as "10 events · from 00:00" or "Nothing timed today").

## Clock panel, round 4: a livelier Clocks page (2026-10-12)

User: "Clocks page feels boring and needs improvement."
- **`components/ClockFace.qml` (new, shared):** an analog clock for any time handed to it (hours / minutes / seconds as numbers), so one face
  serves now, a zone, and a scrubbed moment. Small (a tinted disc, two hands) or big (`scalloped`: the shell's Scallop cookie, twelve dots, a ticking
  second hand). Hands never go backwards — each follows an angle that moves the SHORTEST way to the new time and may run past 360° (a spring carries
  it), so a scrub from 23:50 to 00:10 turns ten minutes, not 23 hours. An optional `ring` (0..1) sweeps round the rim over a faint track. `tone`
  tints the face day (warm) / night (cool).
- **World is a meeting planner.** Each row: a small face turned to the time THERE, the city and "Tomorrow · +8 h" (warm when it is another date),
  a 24-hour ribbon, and the time. The ribbons share one axis — YOUR hours, six behind to eighteen ahead, moving only on the hour — and show night
  (dim), daylight 06–18 (warm) and office hours 09–17 (the accent), so where two places are lit together lines up vertically. Drag (or click) across
  any ribbon: a cursor line with a knob goes there on a quarter hour, and every row, face and clock turns to that moment; the header says
  "Tue 03:00 here" and a Now chip comes back (the cursor does not outlive the page). `worldclock.js`: `windowStart`, `bands`, `pointAt` (tested, 43).
  The search moved into the header row, which freed a row for the list.
- **Alarms sit under a clock.** Your time as a big cookie face — seconds ticking, tinted by your day or night — and beside it the NEXT alarm
  as a countdown ("10h 45m", "Tue 07:30 · Weekdays"). The `Timers` countdown lives here now: 5m / 10m / 25m chips, then the time left and a
  cancel; while it runs a ring sweeps round the face (it fills gold at "Time's up" until dismissed). Each alarm row's weekdays are seven tappable
  dots (M T W T F S S; none lit = once) — `Timers.setAlarmDays`, which re-aims a switched-on alarm at its next matching moment — replacing the
  preset chip as the way to edit (the chip beside the add field still sets what a new alarm starts with); a cross removes (it warms to danger
  under the pointer); the switch animates because rows are keyed by id, not rebuilt.
- Checker caught one real bug on the way: a `Behavior` on a `readonly` property in ClockFace (a hard load failure) — fixed.

## Watermark (2026-10-21)

[Quickshell mark] "Quicktest v0.3 by rufss" (`components/Watermark`; the version is `Config.version`), in a pill (the bar's surface fill and border, title-size
text — the first cut was bare caption text at 85% and got lost on busy wallpapers). The shine is ONE number (`phase`, a 1.7s sweep, a 3.6s rest — a pause,
not a slow tween, so the surface idles between sweeps) and every effect is a function of it: each letter turns to the accent, rises and swells as the sweep
reaches it; a soft accent glow rides behind the name; the pill's border catches the accent; the gear logo makes one full turn; an `auto_awesome` sparkle pops
at the name's end as the sweep leaves. Colours are the screen's `fg` → `primary`; with animations off everything stays at rest. The logo is `quickshell.svg`
in full colour, or with `Config.colorizeIcons` on `quickshell-mono.svg` stencilled in the accent (`TintedIcon`) — the same switch the tray and dock obey.

- **Two places, always on, no switch** (the user's call, 2026-10-21 — it started as three per-surface `Config.watermark*` toggles on the About page, default
  on for desktop and lock; all of it, the properties, the `_persisted` entries and the tiles, is gone, and so are the desktop and lock-screen copies). An
  older `config.json` may still carry the three `watermark*` keys: nothing reads them, and the next save drops them.
  - **The overview**: INSIDE the middle card, top left, beside workspace 1 (`gridCard` in `Overview.qml`; it was bottom left for a moment and the user put it back), in the room the grid leaves on the left. It arrives with the card. The
    grid can overlap it when the cards are wide.
  - **Settings**: the foot of the rail in `SettingsCard`, so the window and the docked panel both have it. Caption size, and `compact` (the logo alone) when the
    rail is folded; scaled down rather than clipped if the words would be wider than the rail (a larger `fontScale`).
- Each is a `Loader` / built with its surface, so nothing runs while the overview or settings is closed.
- **Not on the greeter, on purpose.** Its `Config` is all defaults (`greet-export.sh` exports three fields, not `config.json`).
- Never seen at the rail's width: the 216px rail is tight for the words at caption size (estimated ~190px), hence the scale-to-fit.

## Desktop visualiser: colours, ring, music only, caps, glow (2026-10-31)

`modules/panels/CavaBG.qml`, Settings › Sound › Desktop visualiser. The user asked for its colours to be
customisable, then picked a ring style, "music only", and peak caps + glow (placement stays the bottom
edge for the other styles).

- **Colour** (`Config.cavaBgBlend`, `cavaBgBlendDir`, `cavaBgOpacity`): every renderer draws a STENCIL (only
  its alpha counts) and one fill shows through it (MultiEffect mask), so every style takes every blend.
  The user then asked for "more colors from the scheme" and picked BLEND SEVERAL: 1–5 of
  `Config.cavaBgColors` (primary, focus, vivid, tonal, the six scheme slots, text, album) in the order
  tapped, laid "across" (left to right; round the ring, mirrored) or "up" (base to tips; circle out).
  Nine fixed GradientStops sample `viz.at(t)` (exact for 2, 3, 5 colours). `Config.cavaBlendClean`
  validates the stored list; `_loadCavaBlend` migrates `cavaBgColor`/`cavaBgColor2` ("palette" → the
  whole scheme across; a fade → "up"). Sound page: numbered swatches, a direction ChipRow, "Whole scheme".
- **"It doesn't show up" (2026-10-31)**: the Waveform style drew nothing. `WaveformSpectrum` had gained
  `if (!root.visible) return ""` (a perf skip), and inside CavaBG's stencil — a `visible: false` layer
  the mask reads — `visible` is false while the ribbon is exactly what's on screen. It now follows
  `drawing` (default `visible`; CavaBG sets `true`). Also: Game Mode hides CavaBG by design
  (`Config.gamemodeVisualizer`), and it was on (following a game) when the user looked.
- **Ring** (`cavaBgStyle: "ring"`): the mirrored spectrum as 64 spokes round the screen's middle — treble
  at the top, bass at the bottom, the halves matching. The window takes the whole screen (`anchors.top`
  while ring; still click-through, still the `bottom` layer), but the drawing, the mask and the glow
  are a square round the middle (`ringBox`), not a full-screen pass. Radius 14% of the short side,
  spokes 0.6× a bar's height. Fills go round it: the fade is a RadialGradient from the circle out, the
  palette a ConicalGradient (mirrored stops). `Config.cavaBgRingCover`: the player's cover in a circle
  inside it while music plays (not part of the stencil, so it keeps its colours).
- **Music only** (`Config.cavaBgMusicOnly`, default on): `Cava.acquireSource(MusicPulse.sourceNode)` —
  the player's own node, the bar visualiser's way (one shared source name) — and `Cava.sourceShaped` /
  `sourceShapedMirrored`, shaped once in the service like the shared ones. A player PipeWire names no
  stream for falls back to the shared output while it plays; nothing playing shows nothing. Off: the
  shared output, as before.
- **Peak caps** (`Config.cavaBgPeaks`, bars and ring): `components/PeakCap.qml` — up with the bar at once,
  a hold (`Motion.emphasized`), a fall of `Motion.slow × 2` from the full height (less from lower).
- **Glow** (`Config.cavaBgGlow`): a MultiEffect shadow (blur 1.0, no offset) on the masked fill, in its
  colour (`vivid` for the palette ramp). The window grows 24 px for it, and 8 px for caps.
- **Traps hit**: an inline `component PeakCap` in CavaBG (a PanelWindow-rooted file) failed every load
  with "PeakCap is not a type" at its own declaration, in three forms — hence a file (no other
  window-rooted file has an inline component; the cause is inferred, not known). Inside a
  `ClippingRectangle`, a child's `parent` is its content item, not the rectangle — use an id.
  `QT_QPA_PLATFORM=offscreen` `qml` renders no layers or MultiEffects (all white): the ring's geometry
  was checked headless with the stencil unlayered; the fills and glow only on screen.
- **Unverified on screen** (Game Mode was on, which hides it): the ring, its fills and cover, caps, glow,
  and the music-only switch-over.

## Game Mode (panel redone 2026-11-07)

`services/Gamemode.qml` owns the mode; `modules/panels/GamingPanel.qml` shows it. Before this round the panel
was a header toggle, two stat cards and a column of switch rows that dimmed while the mode was on. It is now
the Material 3 Expressive dialect, picked by the user (hero + tiles; every extra offered was accepted):

- **Hero** — the mode as the panel's subject: an M3E `MorphShape` (disc off, `cookie9` on, `burst` when
  stalled), the state, what is running and for how long, "Today … · this week …", and one capsule button.
  `primaryContainer` while on, `section` while off, warning-toned when on but gamemoded did nothing.
- **Live** — GPU and CPU on wavy `RadialGauge`s (both the accent: the old CPU card wore `focus`), VRAM/RAM
  `Meter`s, swapping flagged only when it happens.
- **Chips** — two `ToggleChip` groups: *when it turns on* (a gamemoderun game; a Steam game) and *what it does*
  (eight effects, one list `_effects` drives the chips and the "n of m" count, so they can't disagree).
  A missing optional tool dims its chip with the reason as the tip (`_blocker`).
- **Tune** — CPU governor and frame cap on `SegmentSwitch`es, MangoHud preset on chips (not a switch: a
  hand-written config has no marker and then none should look chosen). The frame cap is the HUD's own
  `Gamemode.setMangohudFps`; it needs a preset first.
- **Ready to play** — status chips, the fix for what isn't (governor/GPU stalled, the profile's Set up), the
  Steam launch options with a copy chip. Replaces a warning band, a profile row and three captions.
- **Free up memory** — only while RAM is over half used and a window holds ≥ 400 MB.

**Round 3 (same day): the game's picture, and history.**
- **Picture** — `scripts/gamemode-art.py <appid>…` finds Steam's own library cache
  (`appcache/librarycache/<id>/<hash>/library_header.jpg`, else hero, else capsule — measured on this machine for
  1030300; a top-level `<hash>.jpg` is an icon and is never used), so it costs nothing and sends nothing. Only for a
  game Steam never showed does it fetch Steam's public header ONCE from its CDN (the request names the app id and
  nothing else) into `XDG_CACHE_HOME/quicktest/gamemode-art/<id>.jpg`. `Gamemode.requestArt(id)` (called from a
  `Component.onCompleted`, never a binding; same pattern as `ScreenTime.nameOf`) fills `artPaths`; `gameArt` is the
  running game's. The id comes from the same environment scan as the Steam trigger, which now ALSO runs while the mode
  is on whatever `gamemodeSteam` says (the trigger list stays the setting's). The hero shows it on its right, fading
  into the hero colour (`ClippingRectangle`, so the corners stay round). A game that isn't from Steam has no picture.
- **History** — a fifth page. `gamemode-sessions.json` (state dir): `{ start, seconds, game, appId, auto }` per
  session of ≥ 60 s, newest first, 60 kept (`gamemodewatch.js addSession` / `cleanSessions` / `whenLabel`, tested),
  written when the mode ends (`_recordSession`, from the `_active` handler, before `_auto` and the game name are
  cleared). The page lists the latest six with a thumbnail, "Today 18:20", the length and Followed / By hand; Clear is
  two taps. Empty: a disc and a sentence.
- **Round 3b — history keeps name and picture.** The name was already stored per row; the picture was only looked up
  by app id, so it vanished when Steam cleared its cache or the game was uninstalled. Now `gamemode-art.py` answers from
  its own `gamemode-art/<id>.jpg` first and COPIES a Steam-cache hit there, and each row stores the picture's path
  (`art`, absolute, ≤ 400 chars, validated in `_artPath`). A row shows the fresh lookup if there is one, else its saved
  path. Rows written before this have no `art` and fill from the lookup as before. Tests: art 14, watch 56.

**Round 2 (same day):** the pages box is as tall as the page you are on and follows it on a spring with no overshoot
(`pagesBox.wanted` → `SpringValue hv`, `Motion.springEffects`), so no page leaves empty room under it. The effect tiles
are `components/ShapeTile.qml`: the icon on an M3E shape that is a disc off and morphs into the effect's own shape on
(burst, clover, sunny, squircle, cookie7, pentagon, hexagon, cookie12), a spring press, an On/Off capsule. Tune's
MangoHud card has a **preview stage**: the real preset's lines (`generate-mangohud-config`'s `PRESET_BODIES`) with this
machine's live numbers, the frame cap as the frame rate, a ticking frame-time graph (140 ms, only while that page is
open), and hover on a chip previews it before you pick. Palette colours approximate the config's wal colours.

**Pages, not a stack (same day, the user's call: "way too tall")** — four pages of a `SegmentSwitch`, sliding on one
`SpringValue` (slide + fade): **Play** (hero; session / today / this-week-as-bars tiles; GPU/CPU rings and VRAM/RAM;
memory card), **Effects** (when it turns on, and the eight effects, as `QuickToggleTile`s whose second line says what
the setting does right now), **Tune** (governor, frame cap, overlay — each with what the current pick means), **Setup**
(one row per fact: installed / ready / info, the profile's Set up, the launch options' copy). The box is as tall as the
tallest page. The Play tab is `lit` while on, Setup while stalled. The title row is `Config.gamemodePanelHeader()`
(a module setting, like the clock's: Settings › Bar › Game mode › Panel header). Fun: two rings leave the hero shape
when the mode turns on, the cookie turns slowly while it is on (a `RotationAnimator`: render thread, no outline rebuild),
the week bars grow on the house curve. First try put the header switch on the Setup page; the user wanted it in
Settings › Bar, where the clock's is.

**What changed in the service**

- **Effects apply live.** `_enable`/`disable` are now one helper per effect (`_holdIdle`, `_holdQuiet`,
  `_holdSession`, `_holdWallpaper`, `_holdCompositor`), each idempotent, and a `Connections` to `Config` calls
  the right one when its flag flips while the mode is on. Visualiser and typing sounds already read their
  flag live. The old "applies at the next switch-on, rows dim" is gone. `_holdWallpaper` is the riskiest (it is
  the stop → relaunch cycle, now reachable mid-session): its restore path is the existing
  `_tryRestoreWallpaper`, unchanged.
- **Steam games as a trigger** (`Config.gamemodeSteam`, **off**): a window is "a game" when its class is
  `steam_app_<id>` (Proton; instant, from `Hypr.windows`) OR its process has `SteamGameId` / `SteamAppId` in its
  environment (`scripts/gamemode-steam.py`, reads `/proc/<pid>/environ` of each `hyprctl -j clients` pid). The
  class alone MISSED native Linux games — Hollow Knight: Silksong's class is "Hollow Knight Silksong" (the user's
  report, 2026-11-07; measured on the live window: `SteamAppId=1030300`). Steam sets the id for every game it
  launches, native or Proton, with or without launch options; the client's own windows carry neither. The script
  runs, debounced 800 ms, only when the SET of open window addresses changes and only while the setting is on; a
  result for a closed window is dropped at once. Rows are `{ address, appClass, title, appId }`; the follow rules
  watch `gamesLive` (a bool: registered PIDs OR Steam windows), so Proton registering new PIDs under one game wakes
  nothing. A Steam window has no gamemoded registration behind it, so `_holdSession` takes our own `gamemoderun cat`
  hold for it; a registered game (`_auto` with PIDs) still skips it. This is *not* "follow fullscreen", which the
  header of `Gamemode.qml` still declines.
- **Which game** — `gameName`: a Steam window's title (the appmanifest, via `ScreenTime.nameOf`), else the
  registered process's `comm` with Wine/Proton/launcher plumbing filtered out (`labelFor`, `tidyComm`).
  Best effort and said so; "" means the hero says "A game is running".
- **Time in game mode** — `~/.local/state/…/gamemode-time.json`, `ScreenTime`'s own shape with one key, so
  `screentime.js` (credit across midnight, clip a suspend, prune) does the work. Total only: per-game time is
  ScreenTime's, and its `appKey` rejects titles anyway. `lastGame`/`lastSeconds` are in memory for the hero.
- **Clips follows the mode** (`Config.gamemodeClips`, **off**): `Gamemode.holdsClips` is read by
  `Clips.wantBuffer`. A hold; `Config.clipsBuffer` is never written. This overrides Clips' old "no auto-start
  on games" line, at the user's request; its header says so.
- **Lighter desktop** (`Config.gamemodeCompositor`, **off**): blur, shadows and animations off through
  `hyprctl eval 'hl.config(…)'` (`services/gamemodefx.js`). What is read BEFORE (`hyprctl -j getoption`) is what
  is put back — the user may already run some off. The snapshot is also written to `gamemode-compositor.json`
  (state dir) because this is system state outside the shell: at the next start `fxFile.onLoaded` puts back and
  empties (`{}`) a snapshot left by a crash or a restart. If nothing could be read, nothing is turned off.
- **Memory scan** — `scripts/gamemode-hogs.py`: windows grouped by process, each tree's RSS (proc-cost's
  helpers), games never listed. Run when the panel opens and 1.5 s after a Close. Close is Hyprland's own
  (the app may ask to save); nothing is killed.

**Tests:** `bun scripts/test-gamemodewatch.js` (53), `bun scripts/test-gamemodefx.js` (11),
`python3 scripts/test-gamemode-hogs.py` (10), `scripts/test-gamemode-steam.py` (10), `scripts/test-gamemode-art.py` (12), `python3 scripts/test-gamemode-profile.py` (unchanged).

**Unverified — only a reload shows it:** the whole panel (nothing was loaded); live-apply of each effect,
above all the wallpaper one; the Steam trigger on a real Steam game and the hold it takes; `labelFor` against
a real Proton registration; `hl.config` off/back on this Hyprland (the same call HyprLayout makes, but not
these keys); the crash-recovery path; the Clips hold starting and stopping the buffer. New persisted
properties: `gamemodeSteam`, `gamemodeClips`, `gamemodeCompositor`; the header is a module setting (`gamemode.panelHeader`).

## Audio Mixer (panel redone 2026-11-07, fourth attempt)

`modules/panels/EqualizerPanel.qml` (the bar's volume pill and the sidebar's volume cell open it). Four attempts, in
order: a hero + app cards (the user: "don't like the style and layout" — the screenshot also showed the list clipped and
dimmed mid-animation); flat vertical channel strips ("don't like what you did"); the original tabs restyled ("still not
satisfied"); and finally the user named the **Game Mode panel** as the look to copy. Presets (Quiet / Gaming / Call) were
built and removed on request. This is that look, with the two real faults fixed:

- **Pages** (SegmentSwitch on a spring, as Game Mode): **Mixer** — a neutral hero for the output (an M3E shape that is a
  disc muted, a cookie at rest, a sunburst while sound comes out, swelling with the peak; tap = mute; device name, codec /
  limit badges, rolling level, thick fader, one-tap output chips), then a `ChannelCard` per playing app (orb = meter + mute,
  fader, route pill, pin). **Devices** — `DeviceCard`s for outputs (Options: volume limit, balance) and inputs, Remembered
  apps (Forget), and `ShapeTile`s for Boost and per-output volume memory plus Restart audio (two taps). **Input** — the mic
  card, "Hear yourself", who is recording. A dot on Input says an app is recording.
- **Room.** `SidePanelDock` cuts a panel to the room it has and sets `maxHeight`; a list taller than that was simply cut
  (only the first app showed). The pages now sit in a `Flickable` no taller than `maxHeight` minus the title row and switch,
  with a `Scrollbar`.
- **Sound effects.** Each cue is a `pw-play` process, i.e. a short-lived playback stream on every hover and keystroke.
  Bound to `Audio.streams`, the app list was rebuilt and every row's entrance replayed with each one ("glitching with the
  sound effects"). `pw-play` is left out of the list and it is a `ScriptModel` keyed by node id, so one app starting or
  stopping adds or removes only its row (which fades in; nothing else moves).
- The title row is `volume.panelHeader` (Settings › Bar › click the Volume module › Panel header), default on. Boost and
  Restart used to be header buttons; they live on Devices so they survive it being off.

**Pins (per-app memory).** `services/MixerMemory.qml` + `mixermemory.js` (tested: `bun scripts/test-mixermemory.js`, 12).
The pin on an app card saves its level, mute and output under the app's lower-cased id (`Audio.appIdFor`) in
`mixer-memory.json` (state dir, 40 kept, newest first). When a stream of a pinned app appears it is put back, ONCE per
stream, 700 ms after it shows (`settle` timer), so a player that rewrites its own level later (Spotify on a track
change) is not fought; a change the user then makes on the card becomes the new record (`MixerMemory.note`). Apps that
were not pinned are never touched. Routing goes through `Audio.moveStream`.

**New files:** `components/ChannelCard.qml`, `components/DeviceCard.qml` (in `components/qmldir`), `services/MixerMemory.qml` (singleton, in `services/qmldir`), `services/mixermemory.js`.

**Unverified — only a reload (ALT+Q, new files) shows it:** the whole panel; the
pin restoring a stream that starts later; `pactl move-sink-input` from a restore; the pages scrolling with 5+ apps playing and a small `maxHeight`; the sound effects no longer disturbing the list.

## Displays (2026-11-08)

Settings › Devices › Displays (`modules/settings/pages/DisplaysPage.qml`, `services/Displays.qml`,
`services/displays.js`, `scripts/hypr-monitors.py --write-spec`). Arrange screens on a map (drag;
`displays.js snapPosition` lands a screen flush against a neighbour, top/left-aligned first), and
pick mode, scale, rotation, VRR and on/off per screen. Edits are a copy until Apply.

- **Apply = write + reload, never `hyprctl eval 'hl.monitor(…)'`.** The spec is validated by
  `hypr-monitors.py` (names, numeric ranges, at least one screen on — the values become Lua
  source) and written into the bundled `~/.config/hypr/hardware.lua` monitor block, then
  `hyprctl reload`. Runtime Lua through eval is only proven safe for `hl.on`/`hl.config` here
  (a runtime `hl.bind` segfaulted Hyprland twice).
- **15 s keep-or-revert.** Applied = pending; no answer reverts to the snapshot taken just before
  (another write + reload), because a mode the screen can't show can't be clicked away. A shell
  that dies mid-countdown leaves the new layout: fix the block on a TTY.
- **Not the bundled config** (no `-- ── Monitors` section): the page offers "Copy lines" instead,
  and `--write-spec` refuses that file outright.
- Tests: `node scripts/test-displays.js` (26), `python3 scripts/test-hypr-monitors.py` (16). The
  lines for the current layout round-trip byte-for-byte with what install wrote. Never applied
  live: a real Apply/Keep/Revert is the user's test.

## Mouse & touchpad (2026-11-08)

Devices › Keyboard & mouse (`KeyboardPage.qml`): pointer speed, acceleration (adaptive/flat), scroll
speed, left-handed; touchpad natural scroll, tap to click, tap and drag, ignore while typing,
two-finger right-click, scroll speed. Written to `~/.config/hypr/hardware.lua` by
`hypr-config.py set-input` and applied by the shared `HyprApplyBar` reload, like Desktop › Tuning
(sensitivity and natural scroll moved here from there).

- Keys are found BY TABLE (`input = {` / its `touchpad = {`, brace-matched), not first match:
  `scroll_factor` and `natural_scroll` exist in both. A key the file lacks reads as Hyprland's
  default and is INSERTED on first write (inline table → `, key = v`; multi-line → a new line).
- `accel_profile = ""` is refused by Hyprland 0.56's Lua config (measured with
  `--verify-config`: "allowed values are: adaptive, flat, custom*"), so the page offers those two.
- `python3 scripts/test-hypr-input.py` (56): every key on temp copies of the repo's and the
  installed hardware.lua, each result through `Hyprland --verify-config`.
