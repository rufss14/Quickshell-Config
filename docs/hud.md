# The HUD — cards in the overview, widgets on screen

`services/Hud` + `modules/hud/`. Four widgets — **performance** (+ the FPS cap and Game mode),
**clips**, **voice** (Discord), **input** — that live as cards in the overview, and
that you can PIN to be drawn over fullscreen games, or always, as a plain overlay. (The desktop
widgets are the opposite: under windows.)

    qs ipc -c ~/.config/quicktest call hud open        # the overview, a card tuned (also: toggle, close, status)
    qs ipc -c ~/.config/quicktest call hud arrange     # drag the widgets on the real screen

## Everything is in the overview (2026-10-20)

The user: "the HUD lives inside the Overview… not an extra keybind just to open HUD". So:

- **No SUPER+G, no edit overlay.** The bind was removed from the live `~/.config/hypr/binds.lua`
  (backup `.bak/binds.lua.20261020-hud`); the repo's copy never had it. The old studio, name tags
  and per-widget toolbars are gone, and so is `shown` — a widget has ONE switch, `pinned`.
  `hud.js normalise` migrates old files: pinned-but-never-shown stays unpinned.
- **The corners** (`Overview.qml`, the user's call 2026-10-20: "instead of the HUD living on the
  side of the workspaces, we make it live above and under… the workspaces keep being on the
  center"; then "the performance part is quite big"; then "swap the position of clips and
  performance"): one `HudCard` per widget, ALL the same size (`stage.sideW`, 11 card units max),
  in the four corners round the grid — Clips and Voice above with the overview's header + search
  between them, Performance and Input below with the island between them. A card: the shared
  cookie field (DriftShapes), a header (cookie chip, name, a where-badge that springs in once
  pinned, a status line that fades between kinds of status) and PIN / MOVE / TUNE chips; it
  LEANS toward the pointer (2.2°) with PointerGlow on the edge facing it. The widget's full
  version laid out in a ROW inside:
  - `HudPerfCard`: CPU, GPU, RAM as three RINGS (RadialGauge, the figure rolling in the hole —
    the desktop Sysmon's language, the user's pick of four mock-ups), name + temp/GB under each,
    a dot on each track at the last minute's PEAK; the frame cap and Game mode in a column
    beside them. Third version: rows over sparklines and 72px gauges + a shared trace before it.
  - `HudVoiceCard`: server › channel and the line (quality dot + ping); faces in a row ("+N"
    past what fits), each rippling while they talk (Discord says only THAT, not how loud);
    CLICK a face and the bottom row becomes their volume for you (0–200 %) + mute-for-me,
    else it's your mic volume (debounced — every send is an RPC message); mute/deafen/
    leave-twice stacked. Out of a call: three empty seats.
  - `HudClipsCard`: the buffer switch + what it holds + "All"; the TIMELINE — a film strip back
    from now, filled as far as it holds, a notch per `saveLengths` length spaced by
    `clips.js timelineAt` (square root; notches only while buffering); hover lights what it'd
    save, click saves, the span flashes when the file lands (only for saves made from the
    card); then "+ next 30s" and record/pause; the SHELF — the last three clips as a deck that
    fans out on hover, click plays, drag one OUT as a file (dropped under 10 card units).
  - `HudInputCard`: the overlay drawn idle, fitted to the height; what it's for; size and opacity
    steppers.
  Built only while the overview is; the cards that tick hold `Clock.acquireSeconds()` only while
  something runs.
- **Dragging a clip out of the overview** (the shelf): the overview covers the screen, so a drag
  sets `UiState.overviewLending` — the stage and dim fade and the window's mask goes EMPTY
  (transparent for input, `proxywindow.cpp`) so the drop lands on the window beneath; a taken
  drop closes the overview, a refused one brings it back. **Unverified:** whether Hyprland picks
  the drop target by input region during a Wayland drag at all.
- **One card height** (`HudCard.bodyHeight`, 2.5 card units): the strips' height is a constant,
  so the grid's room never depends on the cards' widths (which follow the grid). Nothing in a
  card may wrap into a taller card.
- Before the corners (same day): a full-height rail beside the grid (pushed the workspaces off
  centre), then full-width strips (Performance stretched across).
- **Arranging = the real screen** (`HudArrange`, a card's MOVE chip, the inspector's, or
  `qs ipc … call hud arrange`): `Hud.arranging` fades the overview's stage out, lifts the dim to
  0.12 and hides the cookie field, and draws every widget at its true place and size (unpinned
  ones faint). Drag one: it snaps onto the centre lines and onto a `Tokens.spacingXxl` margin in
  from each edge (`hud.js snapPlace`, tested) with the line drawn, and commits once on release.
  Each wears a tag (name, where, pin). Arrows nudge 1 px (Shift 10), Tab picks the next,
  Escape/Enter/Done ends it and gives the search back the keyboard.
- **Where: over games, or always** (`where`, per widget, the user's ask 2026-10-20: "an option
  for it to work outside games, as a normal overlay"). `"games"`: over a fullscreen window on the
  focused monitor, as before. `"always"`: a plain overlay over everything, on the overlay's
  HOME monitor — `layout.home`, the monitor it was last placed on (every `Hud.move` passes it),
  falling back to the focused one when that monitor is gone (`hud.js homeScreen`). Home, not
  focus, so it doesn't hop screens as focus follows the mouse. Set from the inspector's switch or
  the arrange tags. An "always" Performance samples SysInfo the whole time it's up — that's what
  it's for.
- **Placing = the island** (`HudInspector`, the third face of `OverviewIsland` after the controls
  and the window inspector; a window pick and a HUD pick clear each other in `services/Hud`). A
  MAP of the screen — the wallpaper, the real `HudWidget` frames at their places (the placed one
  full, other pinned ones faint). Press = put it there, drag = follow, snapping onto the centre
  lines (`hud.js snapCentre`, 12 px of what you SEE) with a guide; commits once on release
  (`HudWidget.override` meanwhile). Nine dots on the map are `hud.js ANCHORS`. Beside it: pin,
  click-through, opacity (the cards' fill), size (input). Escape lets go of it first.
- **On screen** (`HudLayer`): mapped only while the overview is CLOSED and something pinned
  belongs on this monitor (`hud.js visible(entry, { game, home })`): an over-games widget needs a
  fullscreen window here (`Fullscreen.byMonitor`, the user's call) on the focused monitor; an
  always widget needs this to be home. Bodies are Loader-gated on that (`HudWidget.live`), so a pinned Performance doesn't
  sample on the desktop. Never takes the keyboard. The monitor name is captured imperatively
  (CavaBG's binding loop).
- **No corner illustration** (removed 2026-10-20, the user's call): `HudArt`, a turning cookie
  + motif in each card's top-right corner, was cut by the chips and read as a glitch. It was never
  committed. Illustrations, if they come back: palette roles, never image assets.
- Retired 2026-10-20 (the user: "simple and honestly useless"): the volume, to-do and standalone
  FPS widgets (FPS lives in the performance card). In git history.
- Removed 2026-10-20, later the same day (the user: "Remove the crosshair stuff"): the crosshair
  widget, its card, its options (style/size/role) and the CS2 share-code import that was planned
  for it. `HudCrosshair.qml` is in git history (its card never was); `hud.js normalise` ignores a
  saved one.

## Decisions worth keeping

- **Positions are the widget's CENTRE as a fraction of the screen** (`cx`, `cy`), so a layout
  survives another monitor and a widget can be exactly central. `clampCentre` keeps the
  whole rectangle on screen.
- **Click-through is the window's input mask**, not per-widget hit testing. An empty
  Quickshell `Region` mask makes the window transparent for input
  (`proxywindow.cpp`: `Qt::WindowTransparentForInput` when the mask is non-null and empty), so
  a pinned overlay costs no clicks. One `Region` per widget points at the frame while
  `hit`, at `null` otherwise.
- **The layout is `hud.json`** under `XDG_STATE_HOME`, via `JsonStore`, not `Config`: it is
  rewritten on every placement. `normalise()` rebuilds it from whatever is on disk (known widgets,
  right types, fractions clamped; a saved `crosshair` entry from before 2026-10-20 is dropped).
  Edits are refused until the file has been read.
- **Colours** are palette roles, never hex. The voice ring is `focus`, not Discord's green.
- **Input's preview never installs the key hook** (`HudInput.listen: false` in the card and the
  map) — the hook is a Hyprland Lua subscription, only for the real overlay.

## FPS limit — what is and isn't known

`Gamemode` owns `MangoHud.conf`. `setMangohudFps(n)` rewrites the one active `fps_limit=` line
(`services/mangohud.js`, tested), or appends one; nothing else in the file moves, the
generator's marked regions included. It **refuses when there's no config at all**: a file
holding only `fps_limit` would replace MangoHud's default readout with an empty one.
**Not verified:** whether a running game picks the change up live or needs MangoHud's reload
key. ii sends `pkill -SIGUSR2 mangohud`; that matches the *wrapper script's* process name,
which `exec`s into the game, so it was not copied.

## Input overlay — the keys and mouse on screen

`modules/hud/HudInput` draws a block of keys (Tab Q W E R / Shift A S D F / Ctrl Space) and a
mouse (left, right, middle, both side buttons) that light while held, plus clicks per second
(left, right) and keys per second, each with the session's best. The key set and its layout are
ONE table, `services/inputkeys.js KEYS` (evdev keycodes, in key units; both Shifts and both
Ctrls light their one cap). The caps are `HudCap` — the shell's flat surfaceContainer + outline,
solid accent when lit.

- **Size and transparency** are the widget's `opts.scale` (0.5–2, the island's size slider —
  `HudWidget.resizable`, body gets `sizeScale` and lays itself out bigger, not stretched) and
  `opts.opacity` (0.1–1, the island's opacity slider). Transparency fades the card and the idle
  keys only: a lit key and the text are always solid. Both clamped in `hud.js`.
- **Keys** come from the SfxKeys route — a runtime `hyprctl eval` Lua hook on
  `input.keyboard.key` posting custom events (`services/InputKeys`).
- **The key event's codes are evdev + 8, not evdev** (`inputkeys.js XKB_OFFSET`). MEASURED
  2026-10-19: with the table looked up at plain evdev, a socket recording of every drawn key
  pressed came back 72/72 anonymous — none matched, which read as "some keys don't light"
  (the few that DID light were other keys landing 8 off). +8 is xkb's numbering, confirmed the
  same day (Q W E A S D F then arrived named). `sfxkeys.js` and `KeyLocks` assume plain evdev
  (space 57, Caps 58) and were never checked against this.
- **Every press shows, even in a burst**: `HudCap` is lit exactly while held; a press SNAPS
  the accent to full and a release drains it fast (Motion.fast, OutCubic), by explicit
  animations — a `Behavior` whose duration binds to the same flag isn't ordered against it, so
  a tap could run the release's fade and never light. A minimum-hold latch was tried and
  dropped: past ~8 CPS its holds overlapped and a burst read as one long press.
- **The mouse is tiled, never stacked** (buttons, wheel, palm, side strip, each a key-gap
  apart): stacked layers turned into a tangle of outlines once the overlay was see-through.
- **Mouse buttons are STATIC binds in `hypr/binds.lua`** (installed into the live config
  2026-10-19; Hyprland reloaded it by itself, and kept window-drag's identical-looking
  `mouse:272` release bind beside ours — no de-duplication) (the `>>> qs-input` block), silent
  unless `_G.qs_input_on`, which the hook sets. **Never `hl.bind` from `hyprctl eval`:** the first
  build did, and Hyprland 0.56.2 SEGFAULTED on every re-install of it (every shell reload, hot
  ones included) in `CLuaKeybind::push` — crash reports 2026-10-19 23:13 and 23:18. A segfault is
  past any `pcall`. The hook now only touches its event subscription; an install left over from
  that build has its keybinds left alone (gone on the next Hyprland config reload).
- **The wheel isn't shown**: a wheel bind would be a static bind on every scroll in every app.
  Not added until tried.
- **What leaves the compositor**: the hook names only the drawn keys; any other key's PRESS goes
  out as a bare `qs-input:k` (no identity, no release — the cadence SfxKeys already sends), so
  KPS counts every key. It exists only while the widget is over a game (the body is Loader-gated
  and holds `InputKeys.acquire()`; previews pass `listen: false`), never while locked. **While it's up, the drawn keys' presses
  are on the event socket**, readable by every process the user runs.
- **Physical positions, QWERTY labels**: on AZERTY the "W" cap is the key printed Z.
- `held`, the rates and the bests start over whenever the hook goes in or out (a key held across
  that would never get its release).
- **Not verified on a live Hyprland**: that the static press bind on `mouse:272` coexists with the
  SUPER-drag bind and the window-drag release bind already there; whether a SUPER+drag swallows
  the LMB release (LMB would stay lit until the next click).
  `qs ipc -c ~/.config/quicktest call inputkeys status`.

Tests: `bun scripts/test-hud.js` (layout rules, migration, snapping, anchors + the fps line), `bun scripts/test-inputkeys.js`
(the table, the parser, the rates, the hook run under lua5.4 on a stub `hl` — it never calls
`hl.bind`, never names an undrawn key — and binds.lua's static block).

## Round 4 (2026-10-20)

- **Chips on hover**: a card's pin / move / tune tray fades and slides in only while the pointer
  is on the card (or the card is in the island). Faded, never hidden, so the header doesn't reflow.
- **Clip hover preview**: rest 400 ms on a clip in the shelf and it plays muted and looping in its
  frame (`ClipPlayer` by URL with `crop` and `loopAll`, only when `Media.available`).
- **Performance** fix: the frame-cap column is a layout, and a layout's `Layout.fillWidth` defaults
  to TRUE — it took the whole row and pushed the rings out of the card. It states `false` now.

## The input overlay's keyboards (2026-11-03)

The user: make the keyboard-and-mouse overlay customisable — a full keyboard, numbers, and so on.

- **Layouts** (`services/inputkeys.js`): one master table of keys (`DEF`: id, label, evdev codes) and six presets that only PLACE
  them — **WASD** (the old 12-key board, still the default), **Games** (Esc, numbers 1–5 and the keys round WASD), **4K** (D F J K in one
  row, for osu!mania; names only those four, so exposure "few"), **60%** (the main
  block), **TKL** (+ function row, navigation, arrows) and **Full** (+ the number pad, 104 caps). A layout is rows of
  `"id"` / `["id", w]` / `["id", w, h]` / gaps, built by `_build`; `layoutOf(id)` caches it; an unknown id is the default.
  Both copies of a modifier (two Shifts, two Ctrls) are the same id and light together. The old `KEYS / COLS / ROWS` are the WASD board.
- **Options** (`hud.js`, the input widget's `opts`): `layout`, `mouse` (draw the mouse), `stats` (draw the click and key rates), next to
  `scale` and `opacity`; each is clamped like the disk is (`INPUT_LAYOUTS` must equal `LAYOUT_IDS`: `bun scripts/test-hud.js`, 114).
- **The hook names only the layout on screen** (`installLua(layoutId)`): `InputKeys.layout` follows the option and a change
  re-installs (the install replaces the old copy). Every other key is counted, never named — as before.
- **PRIVACY — read before widening it.** The event socket is readable by every process this user runs. WASD and Games name a
  handful of keys; **60% / TKL / Full name every key you type** while the overlay shows (a hidden overlay installs nothing, and the lock
  screen removes it). The island's Keys page says so in the danger tone when one of those is picked, and `bun scripts/test-inputkeys.js`
  (84, including the Lua of EVERY layout under lua5.4) checks that each layout names exactly its keys and that "all" really
  includes every letter and digit. Don't type passwords with a full layout showing; "Games only" (the default `where`) limits it to a game.
- **UI**: the Key display card's `tune` chip opens the island's HUD inspector on its **Keys** page (it replaces the sliders: a layout
  switch, Mouse and rate toggles, a size stepper and the exposure line). The mouse is three rows tall at most and centred on the keys.
- Not exercised: a live install of a big layout into the compositor (it is the user's pin that installs the hook), and the labels at
  very small sizes (Prt / Scr / Pse are short for that reason).
