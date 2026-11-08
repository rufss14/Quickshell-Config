# Bar, dock and the blob

Moved from CLAUDE.md; the project rules there still apply.

## Bar, dock and the blob

- `Bar.qml` is instantiated per screen by `shell.qml`. `BarPanelDock.qml` owns the
  left / right / centre panel groups; `BarDock.qml` animates one card's geometry.
- **Drag a window onto the workspace pill** to send it there. Hyprland owns a SUPER+drag,
  so the shell never sees it: a pair of non-consuming Lua binds in `hypr/binds.lua` note
  the window under the pointer on SUPER+press and, on release, call `qs ipc … windrag
  drop <address> <monitor> <x> <y>` (monitor-local). `UiState.windowDropped` → each
  `WorkspacesPill` hit-tests it (the bar window sits at the monitor's origin, so those
  are its scene coordinates) and runs `Hypr.moveWindowToWorkspace` without following.
  Hyprland emits nothing mid-drag, so the press also sends `windrag begin <address>`
  (`UiState.windowDrag`), and while that's set each pill holds `Pointer.acquireFast()`
  (a 33ms socket poll, only for the drag) and lights the slot under the cursor. The
  highlight and the drop share `WorkspacesPill.slotAt()`, so what lights is what you get.
  A lost release can't strand it: `windowDrag` clears itself after a minute.
- `BarPanelDock.panelWidth` (535) is the shared panel width. The wallpaper gallery
  pins wider (620×394); every other panel content-hugs via `implicitHeight`, and
  `heightFor()` / `widthFor()` only enforce a ceiling.
- `Accordion` sequences one panel out before the next comes in — it's what makes a
  panel swap read as one motion rather than a pop.
- **The blob** (`Quicktest.Blobs`, a C++ QML plugin — a metaball SDF shader) fuses
  the bar and an open panel into one shape. `state/Morph.qml` is the ONLY safe way
  to know if it's present: it probes `components/blob/MorphProbe.qml` via
  `Qt.createComponent` and reads the status. A missing QML module makes the
  importing file fail to EXIST, not just fail to run, and that cascades — if
  `Bar.qml` or anything it imports carried `import Quicktest.Blobs`, a machine
  without the plugin would lose the entire bar. `MorphProbe.qml` is the only file
  that imports the plugin; nothing else may.
- `Morph.available` false → silent graceful fallback (panels just open, no morph).
  `Morph.smoothing` (20) and `filletRadius` (10) live there once — two copies is
  two shapes disagreeing about where the join is.
- The **deform matrix**: the blob computes each card's velocity and hands back a
  `matrix4x4` that `BarPanelDock` applies to the card's *content*, so the card and
  what's in it move as one body during the spring. Identity while the plugin is
  absent.
- **The cookie field is drawn BY the blob (2026-10-17)** when the installed plugin can
  (`Morph.cookies`, probed with `components/blob/MorphCookieProbe.qml` — the third file allowed to
  import the plugin) and the bar is anchored with both cookie switches on (`Drift.inBlob`).
  `BlobGroup.cookies` is a flat list from `drift.js pictures()` (8 numbers per picture, screen
  pixels); each shape keeps the ones touching its quad and the shader draws them as Scallops inside
  the merged SDF, so a cookie follows every fillet, bridge and weld exactly. The welded surfaces
  then paint no fill of their own — the bar's Surface, the sidebar's SidePill, BarDock/SidePanelDock
  cards (`Card.blobMaterial`), the OSD and power columns, welded toasts and the tray menu — because
  the blob's fill is the same colour (the blob draws OPAQUE: `alpha` is coverage only, `color.a` is
  never used). Set through `Binding`s in BlobBarLayer, never as properties on the group, so a plugin
  built before them still loads; until it is rebuilt nothing changes (the QML cookie windows stay).
  - The shader now lets only a pixel's OWNER draw the interior (`mergedSdf < -1.5`); every quad near
    a join used to paint all of it, harmless for an opaque fill, not for translucent cookies.
  - The field steps at ≤60 Hz while only the blob draws it (each step repaints the silhouette).
  - **Rendering the blob offscreen to look at it:** `/usr/lib/qt6/bin/qml` under
    `QT_QPA_PLATFORM=offscreen` uses the SOFTWARE scene graph (no custom materials — `QT_FORCE_STDERR_LOGGING=1`
    shows "Loading backend software"); `QT_QUICK_BACKEND=rhi` + `QSG_RHI_BACKEND=opengl` then gets a GL 2.0
    context and finds no GLSL 120 in the baked shaders; Vulkan segfaults offscreen. What works: a
    10-line C++ harness that sets a 4.5 core default `QSurfaceFormat` before `QGuiApplication`, run with
    `QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl QT_QPA_PLATFORM=offscreen QML_IMPORT_PATH=<build>/qml`,
    and `contentItem.grabToImage` in the scene.
- `scripts/build-blobs-plugin.sh` compiles `plugin/` and installs to
  `$XDG_CACHE_HOME/quickshell-quicktest`, never the system Qt QML dir. `plugin/build/`
  is gitignored.


## The entrance (2026-10-06)

The shell arrives on launch and on every reload: the bar drops out of the top edge, the
frame traces down the sides from it, the pills fade in left to right, the desktop widgets
rise last (~700ms, `Motion.intro`). The user's choice over a wave flood-in or a plain fade.

- **One clock:** `state/Intro.qml`, `t` 0 → 1. Each part reads its own window of it
  (`bar`, `frame`, `widgets`, `pill(pos)`, `front(band, total)`) — the choreography is the
  four ranges at the top of that file. Retime there, nowhere else.
- **`components/IntroStage`** puts a whole window on it without restructuring the file: it
  ADOPTS its window's other children (in stacking order) into a window-sized `inner` and
  clips/lifts/fades that. Used by `Bar.qml` (drop + front), ScreenFrame's overlay (same
  front, same arguments — one edge across two windows) and `WidgetLayer` (rise). Inert
  after the entrance. Verified offscreen with `/usr/lib/qt6/bin/qml` (adoption, anchors,
  clip, lift); a layer + MultiEffect mask was rejected — renders the window offscreen, and
  can't be checked offscreen either (effects don't show in a grab).
- **Pills** stagger from `BarGroupRow`'s slot Loader (`introPos`: region third → group →
  slot, counted not measured), so the settings preview shares it.
- **Reload exit:** `reload-quickshell.sh` calls `qs ipc -p <repo> call intro leave` — the
  clock run backwards over `Motion.introExit` — waits the ms it answers (capped 1s, 1s
  timeout), then kills. `qs ipc -p <repo> call intro play` replays the entrance.
- **It can't strand the shell hidden:** motion off = `t` 1 at once; a 4s failsafe forces 1
  if nothing started it. It waits for `Config.prefsLoaded` (motion settings) + 120ms.
- **No fallback flash:** `Colors` reads `colors.json` synchronously the first time
  (`blockLoading` + one `text()` in `Component.onCompleted`), so the first frame wears the
  real palette, never the monochrome fallback.

## The OSD: level sliders and announcement tiles (2026-10-10, redone 2026-11-05)

ONE vertical surface on the RIGHT edge answers everything the OSD says. The bottom-centre
card (`OsdOverlay`) is gone; its announcements are tiles in the same column.

- **Levels**: volume, brightness and the mic (when it was the mic you pressed) are `FillSlider`s —
  Material 3 Expressive's slider, vertical: a rounded track split `[fill][gap][handle][gap][rest]`, a
  handle bar that thins while held, a stub of track kept at BOTH ends (`capH`) so a full or empty slider
  still shows the round end, and under it a `MorphShape` badge (volume `cookie9`, mic `clover`,
  brightness `sunny`; a circle while muted) carrying the icon, which squashes into the number while the
  value moves. The fill's top edge ripples while the level moves (a sine on a spring, 30 Hz, flat and
  static at rest). The fill is clipped to the track (`ClippingRectangle`), not drawn rounded, so a fill
  shorter than the track's radius still follows its round end. Geometry is `components/fillslider.js`,
  tested by `bun scripts/test-fillslider.js`. Level moves on `Motion.springEffects` (no overshoot).
- **Tiles**: a caption (Bluetooth connect/disconnect, the magnifier), a media pill's player icon, or an
  IPC kind the shell doesn't know — a badge (shape per kind: `hexagon` Bluetooth, `squircle` magnifier,
  `burst` otherwise; circle while off/disconnected), the name (3 lines max), a `Meter` when there is a
  level, and the value. Read-only; hovering still holds it open. A media pill's volume stays a TILE with
  the app's icon rather than a slider, because the slider would drive the MASTER volume.
- `Osd.sliders` is the test that tells them apart (a level kind with no caption/icon hint is the sliders);
  `modules/osd/OsdColumn` is both, once (local copies refreshed imperatively, hover/drag holds it open,
  rows collapse to zero height on springs). Sizes are `modules/osd/osdmetrics.js`, called by the column
  AND by `OsdSliders` for its window, so the two cannot drift. Two hosts: `modules/bar/OsdDock` —
  INSIDE the bar's window, welded (`osd*` lobe in `BlobBarLayer`, mask region in `Bar.qml`; not welded
  it is a floating card a gap off the edge, as `SidePanelDock`; the lobe's width eases when a tile
  replaces the levels) — and `modules/osd/OsdSliders`, an Overlay-layer window that answers only while a
  window is fullscreen on that monitor (Hyprland hides the bar's layer under one; the notification deck
  hands off the same way, on `Fullscreen.byMonitor`).
- Interactive levels: drag, scroll, hover holds it open. It never takes the keyboard.
- **Brightness is ROUTED, not observed.** `XF86MonBrightness*` call
  `qs ipc call brightness step up|down` (`hypr/binds.lua`; the LIVE `~/.config/hypr` is a
  substituted copy and needs the same two lines by hand), `Brightness.stepKey` steps the
  monitor the pointer is on (falling back to the first dimmable one) through the usual
  queue — so the laptop floor applies and DDC monitors respond — and emits `keyStepped`,
  the only brightness event the OSD listens to (a slider drag elsewhere is feedback enough).
  The first key of a session lands mid-probe; the net distance is kept and applied when the
  probe finishes (`_pendingKeyDelta`). `Services.Brightness` is held eagerly in `shell.qml`
  (a `Connections`) so the IPC target exists; the `ddcutil` probe is still lazy.
- The blob group draws at most 16 rects PER SHAPE (the ones near it, non-empty) — one more
  named lobe is fine; a screen-wide pool would not be.
- `osd status` now reports the column: `card` = its width, `glyph` = the slider/badge width, `meter` = the
  meter (tile) or slider width, `label` = the value text's width (tile only).
- Unverified visually (2026-11-05, nothing loaded): the whole redesign — the ripple, the badge squash, a
  tile's wrapping of a long device name, the lobe's width ease, `surfaceContainer` as the rest tone on the
  card. The dock's flush on the sidebar's face when the sidebar is on the right edge (`rail.panelFace`).
  `OsdSliders` (fullscreen only, where the sidebar is hidden anyway) just keeps `spacingXl` off the edge.
  `modules/osd/qmldir` lost a line, and qmldir edits do not hot-reload: restart the shell once.

## Hover, the active mark and the rim sweep (2026-10-27)

- **Hover reveal.** `StateLayer.reveal` (opt-in) draws the hover tint as a soft disc that grows from where the pointer
  came in and fades on leave; the owner passes `pointerX/Y` (`mouse.mouseX/Y`) and `hovered`. `IconButton` and
  `CellFeedback` use it at 0.26 with a hairline ring (`ringOpacity`) and a plate that grows `spacingXs` along the bar
  (`_grow`; since 2026-10-31 along only, on a spring — see the Material 3 Expressive section) — at 0.18 and flat, a 24px
  bar button's hover barely read. The icon also rises 8% (`_lift`) and
  leans toward the pointer (`components/MagnetLean`: a twentieth of the distance from the centre, never over 1px — anything bigger
  read as a wobble on a 24px button). It moves the glyph, symbol, label, SVG and the custom `overlay` content of every `IconButton`
  (so the window pill's row too), the sidebar glyphs, and each tray icon. No press-scale: the ripple is the press
  cue, and a second one thuds. `SideCell` mirrors the lift and lean (`glyphScale` stays the modules' own pop).
- **Hover handlers and buttons.** Measured on Qt 6.12 (headless `qmltestrunner`): a `HoverHandler` on a LOWER SIBLING of
  a hoverEnabled `MouseArea` is not hovered while the pointer is over the button; one on an ANCESTOR stays hovered; one
  ABOVE a button steals its hover. `BarGroup` keeps one handler on the group and `PointerGlow.origin` shifts it into each
  pill's coordinates.
- **The mark travels.** `IconButton`'s active underline hands off through `services/markhandoff.js` (`.pragma library`,
  per window): a mark that goes out and one that comes on within 900ms read as one mark flying between the buttons,
  starting at the old width. Unverified: that no ancestor clips the flight.
- **Focus trace.** `components/FocusTrace` draws two strokes from the top-centre of an `InputField` round to the bottom on
  focus (a dashed `ShapePath`, the second half mirrored), then holds; the field's own outline still says "focused" at once.
- **The rim sweep.** `BlobGroup.rimSweep` (x, y, radius, width) and `rimColor` (alpha = strength) brighten the merged
  outline where its distance from a centre is near a radius; `BlobBarLayer` runs it outward from a panel's join (top-centre
  for bar panels, the middle for the rest) when a slot goes from closed to open. Needs the plugin rebuilt
  (`scripts/build-blobs-plugin.sh`); set through `Binding`s gated on `rimOk`, so an older plugin simply does nothing. The
  uniform block grew by two vec4s after `cookieData` (2304, 2320).
  Besides a panel opening it also runs when a notification toast arrives (`toastRects` grows; from the newest toast's join)
  and when a volume key tops the OSD out at 100% (`Osd.value` reaches 1 — from the OSD column's middle).

## Material 3 Expressive on the bar and sidebar (2026-10-31)

The desktop widgets' motion and shape language, carried onto both edges. The sidebar wears the top
bar's parts (IconButton's ladder through `CellFeedback`/`SideCell`), so each change below lands on
both at once. The user's calls: the active underline stays (no tonal capsule, no shape change), the
workspaces pill keeps its look, hover stays as loud as it was (Material's 8% didn't read on a 24px
button, see above).

- **Springs, not curves.** `SpringValue` (`Motion.springSpatialFast` / `springSpatial`) drives the
  hover swell and lift (`IconButton`, `CellFeedback`, `SideCell` — one 0→1 spring each, both effects
  riding it), the active mark's length and its hand-off flight (`markW`, `markFly`: the flight is a
  1→0 factor of the stored offset), `BarGroup.reveal` (it starts AT its target, which is what the old
  `_ready` flag did), and the workspaces indicator's two edges (lead on the fast spring, trail on the
  standard one). A spring keeps its velocity when the target moves, so a pointer that leaves mid-swell
  or a second workspace switch mid-flight carries on instead of restarting. `Motion.springTime` 0
  (motion off) puts every one straight at its target.
- **The plate is concentric with the inner pill** (second pass, same day — the user: the clicks "don't
  really match with the inner pills"). A bar button is `barPillHeight` inside a BarGroup chip that
  reaches `spacingXs` past it across the bar and `spacingSm` past a run's ends; a sidebar cell sits in
  `SidePill` with the same margins. So the hover/press plate (`IconButton`, `CellFeedback`, and the
  tray, which had a rounded square of its own and a 0.82→1.10 scale bounce) keeps one even
  `spacingXs` gap: radius = `barRoundness − spacingXs` (capped at half its height), hover grows it
  `spacingXs` ALONG the bar only (`CellFeedback.alongY`: the sidebar's edge, or false for the tray),
  never across — the old all-round swell filled the chip top to bottom. Press is a squash and stretch
  (half a step longer along, half shorter across, `springSpatialFast`) instead of the first pass's
  corner squish, which drew a squarer block inside a round pill. The spring is a 0→1 FACTOR, never a
  radius: a sprung radius chased the height from 0 at creation and opened every button's corners on
  each reload. `DockIconStrip.cellRadius` (sidebar), the workspaces indicator/runs/drop mark
  (`slotRadius`, `spacingSm` in) follow the same rule. `CellFeedback.lift` is the glyph's hover lift
  on the plate's spring (SideCell and the tray read it).
- **The hover track** (third pass, same day — the user: buttons in one pill "should be connected … similar to what
  workspace pill does"). `components/HoverTrack` is ONE hover plate per pill that slides between its buttons:
  `IconButton` / `CellFeedback` find the first ancestor offering `hoverTrack` (BarGroup; the sidebar's hosts hand
  out their region pill's), `claim(this)` on hover and `release(this)` on leave, and stop drawing their own hover
  tint and ring (the ripple, lift and lean stay theirs). The plate's two ends along the bar are two springs, the
  leading one on `springSpatialFast` and the trailing one on `springSpatial`, so it stretches across and
  contracts (the workspaces indicator). A release lingers `Motion.fast`, so a claim inside it slides from there
  (crossing the gap between buttons) and none fades it out where it stands. From nothing it jumps into place
  and fades in. It re-reads the rect on a claim, on the claimed item's own geometry changes and on the host's
  `refresh()` (BarGroup's row reflowing, the rail re-laying); it never maps every frame. It is zero-sized so it
  can't feed a host's size. Headless-tested (qmltestrunner with stubbed singletons): slide, stretch, gap,
  press, linger, fade, jump.
- **Workspaces and the clock chip** (2026-10-31): an empty workspace is a small dot (`emptyDot`, a quarter of
  the slot's height, at 40%), Material's page indicator, where a full-size disc at 10% read as a hole; the
  clock's weather symbol wears `fgOnPrimaryContainer` while the clock is the hero (`info` vanished on the chip).
- **One icon family.** Every bar icon is Material Symbols Rounded from the bundled font, through
  `symbol` / `MaterialIcon`: the SVG assets (wallpaper `format_paint`, `palette`, overview and bar
  mode `menu`, `settings`, the four bell states incl. DND `bedtime`, update `terminal`, the shape
  toggle `fullscreen`/`fullscreen_exit`, the mic, reload `refresh`) and the Fluent ones (volume
  `headphones`/`headset_off`, battery `battery_N_bar`/`battery_full`/`battery_charging_full`/
  `battery_alert`, weather `Weather.symbol()`, the lyrics badge, the context menu's chevron) moved
  over, so they share the icon weight and fill while active. The SVG files stay for `notify-send
  --icon` (it needs a path). `MediaController`'s transport buttons are still Fluent: that instance is
  never shown.
- **Wavy rings.** The sidebar's timer and clips rings are `RadialGauge { wavy: true }`. The gauge now
  floors the wave at 1px amplitude and 6px between crests (a 2px ring's quarter-stroke wave drew as a
  plain ring) and uses 8 points a crest, 48–160 round the circle, since a small gliding ring rebuilds
  the outline every frame of its glide. The stats glance is bars, not a ring, so it is unchanged.
- **The media pill's cover sits in a wavy progress ring** (`VisualizerPill`): the ring takes the
  pill's height, the cover is a circle inside the trough, and `RadialGauge.flat` lays the wave down
  while paused without the ring changing size or tone. There was no progress on the bar before: the
  strip in `MediaController` is never shown (that instance only picks the player). The position is
  `controller.sync()` once a second while playing and on screen, rounded to the ring's pixels, so the
  outline redraws every couple of seconds, not per frame.
- **The hero pill.** `Config.moduleHero(id)` puts a module on a `primaryContainer` chip of its own
  (`BarGroup` splits it out of the inner-pill runs); `BarGroupRow` hands the module `hero` if it
  declares one, and it moves its text to `fgOnPrimaryContainer` (secondary text at 0.78, the widgets'
  alpha). Only modules whose bar form says `hero: true` in `config/modules.js` (clock, visualizer)
  offer the switch (module inspector › Hero); the clock is the hero by default. Bar-only: sidebar
  modules don't go through `BarGroupRow`.
- **One label style** (2026-10-31, the user's pick): `components/BarLabel` — Material's label role, medium weight,
  `Config.barFontScale`, tabular digits (`font.features: ({ tnum: 1 })`; Adwaita Sans "1111" vs "0000" is 23 vs
  36px proportional, 36/36 tabular, measured on Qt 6.12). Every primary bar label uses it: battery, wifi and
  bluetooth (and their width measures), the volume level, the clock's time and temperature, the media title, the
  workspace numerals (at their own micro size), and IconButton's `label` (keyboard, locks). They were bold, regular
  caption and bold body by turns. Secondary lines (date, artist) stay plain StyledText. The clock keeps its seconds;
  the tabular digits stop them shifting the chip.
- **Volume's slider stays always shown.** Showing it only on hover was built and undone the same day (the user
  preferred it always there). What stayed: muted, the level's slot closes and the icon says so (it read "mut"; the
  sidebar's volume caption still does).
