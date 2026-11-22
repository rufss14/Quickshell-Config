# Bar, dock and the blob

Moved from CLAUDE.md; the project rules there still apply.

## Bar, dock and the blob

- `Bar.qml` is instantiated per screen by `shell.qml`. `BarPanelDock.qml` owns the
  plain panel columns (left / middle / right; the islands are `modules/island`, see "Bar islands");
  `BarDock.qml` animates one card's geometry.
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
- **Workspace glance (2026-11-09).** Rest on a slot of the bar's workspace pill (400ms, the dock's dwell) and that
  workspace's windows melt out of the bar's underside as live tiles. It is `DockPreview` itself in a workspace mode
  (`key` = `__ws:<id>`, `edge: "top"`, `fused` while `Bar.blobRing`), not a second card: `modules/bar/WorkspaceGlance`
  plays the dock strip (`previewKey`, `groupFor` = `Taskbar.workspaceGroups`, dwell/grace as `DockIconStrip`), the
  pill reports its hovered slot through `hover()`, and `BlobBarLayer` has its own `glance*` lobe (not `previewRect`,
  which the sidebar's dock owns). Tiles name and icon their own app (`DockPreview.keyOf`), the workspace badge is
  hidden, an empty workspace gets the label card. Click goes there, middle-click closes, right-click brings it here;
  `Config.dockPreviews` / `dockPeek` apply. Bar pill only — the sidebar's workspaces row has no glance. No Config
  switch for it yet. Unverified visually: nothing loaded.
  The card stays off a left or right sidebar: Bar.qml hands it `sideRail.band` (`clearLeft/Right` → `DockPreview.clearLo/Hi`),
  and it stands on that face as `PillTip` does; it used to clamp to the screen edge only and lie over the sidebar.
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
- **The gradient (2026-11-22)**: the blob's fill can be three colours along a line (`BlobGroup.gradAxis` /
  `gradMid` / `gradColor0-2`, appended after the rim sweep in the uniform block at 2336..2416; `gradMid` 0 is off).
  It is the SAME fill the cookies and outline draw over, so it reaches the bar, the screen frame and every welded
  island at once, in screen pixels, and nowhere that paints its own flat fill (a floating bar, a free popup, no
  plugin). `Config.barGradient` is the document (`services/gradient.js`: `clean` is the one door, `axis` the line,
  `colours` the stops with `strength` already mixed in, so the shader holds no strength and text keeps its
  contrast at a low setting; `bun scripts/test-gradient.js`). `BlobBarLayer` sets it through Bindings behind
  `gradOk` like the rim, and only while `Drift.inBlob`. `Morph.gradient` (`MorphGradientProbe`, the fourth file
  allowed to import the plugin) is false for a plugin built before it: the Gradient view says so. The shader
  dithers by under one 8-bit level, or a dark gradient bands across the screen. The plugin has to be REBUILT
  (`scripts/build-blobs-plugin.sh`), then the shell restarted, for any of it to show.
  - **Strength 100% is 60% of the way to the colours** (`STRENGTH_MAX`, the user's call: above that it is garish).
    Off by default.
  - **Per scheme, by any route**: `ColorScheme.syncGradient()` runs whenever `worn` (the scheme the colours on screen
    match) changes, so a card, the editor's Apply, the wallpaper or the album all end the same: the gradient is that
    scheme's, or off. Editing it while a SAVED scheme is worn writes it into that scheme's file (`rememberGradient`,
    700 ms after the last edit, `saveScheme(..., quiet)`); a classic, the wallpaper's colours or an unsaved palette
    keep it only until `worn` changes. Saving a scheme never copies the gradient on show into it.
  - The gradient belongs to the scheme: a file may carry `"gradient": { on, angle, strength, mid, stops }` (stops:
    palette roles or `#rrggbb`). `ColorScheme.wear()` puts it on (`wearGradient`) and takes it off for a scheme
    without one. `saveScheme(name, variants, gradient)`: left out saves the gradient on show (none when off), `null`
    drops it. `packScheme` knows nothing of it: the key is added after packing.
  - **Glass** (`Config.barGlass`, `Tokens.glass` = 1 down to 0.4): the blob layer's own opacity (the shader writes
    coverage as alpha and the scene graph multiplies it in, no plugin change), the card, gradient plates and desktop
    tiles at the same alpha, and `hypr/rules.lua` blurs `quickshell-bar` (`ignore_alpha = 0.15`, so the window's
    empty parts stay sharp). That rule needs deploying to `~/.config/hypr` and a `hyprctl reload`. Without it the
    glass is translucent but not blurred. `PaletteRoles.veiled` (gradient or glass) is what makes everything
    standing on the material a veil.
  - **What stands on it follows it**: `PaletteRoles.plate` / `plateLow` are `surfaceHigh` / `surfaceContainer`, or
    veils of the same lift while `veiled`; the island, panel, component and widget files use them for their tonal
    fills (a sweep of 130 lines; lines that feed `legible()` or `alpha()` keep the opaque ones, and so do popups and
    tips, which stand over arbitrary content). Also: while it is on, `PaletteRoles.section` (island plates, cards) and the bar's and
    sidebar's inner pills are `wash`, a thin veil of text and accent, instead of an opaque tonal fill that would
    sit on the gradient as a flat block. Not covered: desktop widgets (on the wallpaper, not on the blob), the hero
    chip (an accent on purpose), Discord and Spotify (their theming is CSS through other scripts).
  - **Surfaces off the blob**: `GradientPlate` (the gradient over a `ground`, across its own box) is what a tile or
    popup wears. `WidgetFrame` (desktop tiles) and `Card` (a card the blob does not draw) have it; a `Surface` opts in
    with `gradient: true` (+ `gradientGround` when its fill is not the elevation's): PillTip, WindowPeek, the bar
    context menu when not welded, the desktop menu. Everything else (launcher, notifications, OSD, lock, settings
    window) is flat; opt a surface in when it is wanted, mind the text on it.
  - **Desktop tiles with glass**: the lens samples the wallpaper in SCREEN coordinates. The widget layer starts where the
    compositor's reserved edges (bar, sidebar) end, so `WidgetLayer` hands each tile `insetX/insetY` (the reserved
    left/top) and the real `screenW/H`, and its `WallBackdrop` is screen-sized and placed at minus the inset; a
    layer-sized texture looked at the wrong part of the picture at the wrong scale. A tile is the bar's own fill
    (`frameFill`, not a container tone of its own), and under a gradient it wears the slice of the SCREEN's gradient
    that lies under it (`GradientFill.line`), so it is the colour of the bar and sidebar beside it. The dock's run pill,
    `IconButton`'s container and `SpacerPill`'s chip are veils while `veiled`, like the inner pills. With the gradient on, the tile's
    plate lies over the lens at 42% as a tint. The lens's own tint is `surfaceContainer`, not `plateLow` (a veil's
    RGB is the text colour, which made the glass pale).
  - **Apps**: `ColorScheme` writes the resolved gradient to `$XDG_STATE_HOME/quicktest/gradient.json` (600 ms after the
    palette settles) and runs `scripts/app-gradient.py all --reload` (`bun`-free sandbox test:
    `python3 scripts/test-app-gradient.py`). Each app gets a MARKED block in a file of its own, removed when the gradient
    is off: kitty (a PNG as `background_image` in current-theme.conf), GTK4 (`window.background` in gtk.css, headerbars
    transparent; views and text areas stay flat), Discord (the quicktest Vencord theme: the three `--background-base-*`
    go transparent over `#app-mount`), Spotify (the active QuickZiro/QuickSpice `user.css`, then `spicetify refresh -s -n`
    and the bridge's `/restyle`). The files those apps' colour steps rewrite whole (kitty's theme, gtk.css) are patched
    again right after by wave-lib.sh and reload-theme.sh; Discord's and Spotify's keep the block across a recolour and
    get fresh colours from the next run. Stale until then: a gradient of palette roles after a palette change.
- `scripts/build-blobs-plugin.sh` compiles `plugin/` and installs to
  `$XDG_CACHE_HOME/quickshell-quicktest`, never the system Qt QML dir. `plugin/build/`
  is gitignored.


## Bar islands (2026-11-13, redone 2026-11-14)

Three islands hang from the bar: LEFT, MIDDLE, RIGHT. All three are `modules/island/IslandDock` (`side`), the
main island's own dock: a hover handle on the bar's lower edge, a blob lobe that grows on springs, `IslandCard`
with the vertical `IslandRail`, the same size. A rail with more pages than its height holds squeezes its slots
(`IslandRail.slot`, down to the icon) so the last page never runs under the lock. A first pass (2026-11-13) put a horizontal icon strip in the
`BarDock` cards; the user rejected it ("use the style of the main island", same dimensions, three hover handles).
The user's picks, by question:

- **The main island IS the middle one.** Its rail carries its own four (Dashboard, Media, Performance, Weather:
  `services/island.js`, `Config.islandPages`) and then the panels placed on it (Clock, Notifications).
- **Pages are panels, grouped by theme** (`config/islands.js`, `bun scripts/test-islands.js`): left = wallpaper,
  colorScheme, equalizer, window, layout; middle = clock, notifications; right = wifi, bluetooth, brightness,
  gaming. `Config.panelPlacement` (Settings › Bar & sidebar › Panels) moves one; `Config.panelSide` answers
  through `sideOf()`. The same table names and draws a page (label, icon, the rail indicator's shape); icons are
  names the bundled font already carries (the test checks), so a page with a new icon needs the font regenerated.
- **No sidebar panels on a rail** (`OFF_RAIL`): stats, clipboard, timer, claude, screentime, inactivity, tasks,
  clips, and also launcher, update and media (the middle's Media page is the player on the rail; my call, not
  asked). They open ALONE in the plain `BarPanelDock` column on their side, as before. *Superseded 2026-11-14 by
  the board, below: these are now only the DEFAULTS for opening alone.*
- **The board (2026-11-14, Settings › Desktop › Island)**: the user asked to rebuild the Island page for
  arranging what each island holds. Their picks: a BOARD (one column per island, its rail in order, then
  "Opens alone"; a tray under it for own pages taken off every rail), ANY page on ANY rail (the middle's own
  four and the sidebar's eight panels too; launcher and update stay locked alone in the middle), arranging
  in Settings only (the live rail stays a navigator), shared options with per-island overrides.
  - Model (`config/islands.js`, `bun scripts/test-islands.js`): `Config.islandRails` `{ left, center, right:
    [ids], off: [ids] }`, `{}` until the board is first used, when `layoutOf()` derives the rails from the
    older `Config.islandPages` + `Config.panelPlacement` (an upgraded shell keeps its islands). A page in no
    saved list (one a later build adds) stands at its default (`RAILS`). `Config.panelPlacement` keeps
    meaning the plain COLUMN: every panel's while the islands are off, an alone panel's while they are on,
    so bar presets that carry it still work. `move()` is the only writer; `UiState.islandLayout` the only reader.
  - Off-rail rule: a page with a bar panel opens alone in its column (Media → Now Playing); Dashboard,
    Performance and Weather have none, so off every rail they are hidden.
  - With the islands off the board is "Columns": a drag between columns only sets `panelPlacement`.
  - `Config.islandOverrides` `{ side: { openBy, delay, linger, handle, scale, effects } }`;
    `UiState.islandOpt(side, name)` / `Islands.optionOf` (clamped to the Settings ranges). `IslandDock.opt()`
    reads it; the pages read `UiState.islandEffectsOn` (the open island's).
  - Sidebar panels on a rail are the bar dock's components in `IslandCard.componentFor`, at island width
    and their own height; an unknown id now draws nothing (it used to draw the Dashboard).
  - Dashboard tiles jump with `UiState.islandGo(page)`: on this island, or handed to the island that has it.
  - "Open on the song" needs Media on the MIDDLE rail (the pill is the middle's). An empty middle has no
    handle and so no live pill: a recording is then stopped from the Clips button.
  - Bar › Panels lost its placement rows (a card points to the Island page).
- **One at a time** *(superseded 2026-11-15, see "The bottom row" below: each island has its own state now)*. The three islands share one state (`UiState.islandOpen/Side/Page/Pinned/Screen`), so only
  one can be open; `UiState._soleIsland` closes an island when a plain column opens and the reverse. The middle
  column's launcher / update / placed panel keep the centre Accordion's order.
- **Routing** (`UiState._rail`, `togglePanel` / `openPanel` / `closePanel` / `isOpen`): with `Config.island` on
  and not arranging, a rail panel opens as its island's page, PINNED (the pointer is on the bar, not the island);
  the same button closes it. With `Config.island` off (the default) every panel opens in its plain column exactly
  as before the islands, so nothing depends on the switch being on.
- **Hover**: rest on a handle and that island opens on the page it was last on (the middle: `Config.islandTab`;
  the sides: `UiState.islandTabs`, this session only); leave and it goes. Moving to another handle hands the
  card over. Hover stands down while a plain panel is open or another island is pinned. Only the middle has the
  live pill. `Config.islandOpenBy/Delay/Linger/Scale` apply to all three; `islandAlign` moves the middle only (set
  to left or right it lands on a side island's handle: not handled).
- **Size**: a page built for an island says its size (`body` in `islands.js`; the Dashboard's 780 × 384). A panel
  not rebuilt yet is shown at the island's width and its own height, never shorter than the Dashboard and capped
  at what is left of the screen (`IslandDock.maxBodyH`). It keeps its own header and padding inside the card's
  gutter until it is rebuilt.
- **Keys**: each dock has an `EscapeGuard` (Escape after the page's `handleEscape()`, other keys to `handleKey`)
  and the bar window gives the keyboard on demand while a card is open.
- **Blob**: `islandL*` / `islandR*` lobes and deform matrices beside `island*` in `BlobBarLayer`.
- **Pages rebuilt as island pages** (`modules/island/Island*.qml`, each a bento of `IslandPlate`s with one
  loud `hero`, no header, the Dashboard's 780 × 384): Bluetooth, Wi-Fi (`NetworkBrowser` + `VpnList` in a
  scrolling card), Brightness (one vertical `FillSlider` card per display), Game Mode (a card per effect,
  `services/gamefx.js` + `Gamemode.effectBlocker`, shared with the panel), Focused window, Window layout,
  Notifications (`NotificationCentre { compact; fill }`). `IslandTile` is the card you press.
  - Bluetooth scanning is a switch, not held by the page being open: discovery can make a headset stutter.
  - What a page does not carry stays in the bar's full panel, shown in the page's place when asked
    (`classicRequested` → `IslandCard.classicOf`): Bluetooth's renaming / forgetting / codecs / files, Game
    Mode's tune / history / setup. Bluetooth's also shows by itself while `BtBridge.prompt` or a staged file
    waits.
- **Notifications on the clock pill (2026-11-15).** While an island or bar panel is open (`UiState.barSurfaceOpen`) the
  toast deck would collide with it, so `Notifications` routes the toast to the clock pill instead (`glance`; the app's
  icon and the title, for the toast's dwell; click opens the notification centre). Only when the focused monitor's bar
  has a clock (`acquireGlance`, held by `ClockPill`), no deck is up, nothing is fullscreen, and it is neither critical nor
  transient; otherwise the toast as before. Still a record, still chimes. Claude's events ("needs you", "finished") take
  the same route (`ClaudeSessions` → `Notifications.glanceEvent`, `Config.peekClaude`), with Claude's mark; click focuses
  its terminal. A panel that opens over toasts ALREADY up moves them too: the newest goes to the pill, the others close keeping their records (critical and transient ones stay toasts). Never loaded.
- **Round 4 (2026-11-14), the user's asks:**
  - **Now Playing redirects** to the middle island's Media page while that page is kept
    (`UiState._rail("media")`); `MediaPanel` stays for islands-off and a hidden Media page. `IslandMedia` gained
    what the panel had, kept quiet: one `ChipTray` under the volume (SongRec, translate, romanize when the song
    has another script, karaoke), one status line under the artist only while there is something to say, the
    Karaoke join / results overlays, and the panel's volume row: a `ThickSlider` on the PLAYER's stream
    (`Audio.playerLevel` / `setPlayerLevel`, boost past 100% as before) with the speaker badge folding it into
    `VolumeProfiles` (the user: "trigger with the current mute button, just like it was before"). No scores
    page: a result's "scores" just dismisses.
  - **Game Mode is the old panel again** (the user liked it over my card-per-effect page, which is deleted):
    `GamingPanel { island: true }`: no title row or padding, Play fixed on the left (`playBox`), Effects / Tune /
    History / Setup taking turns on the right, as tall as the taller side.
  - **Clock on an island has no weather page** (`ClockPanel.island`: Calendar and Clocks only). The weather
    view is still in the file for the sidebar and islands-off; removing it outright is not done. From it,
    `IslandWeather` gained UV and air-quality pills beside sunrise and sunset.
- **Round 5 (2026-11-14): Wallpaper, Colour scheme, Audio mixer re-laid** (the user's pick: the existing panel,
  nothing removed, its main card in a LEFT column; `island: true` on each, set by `IslandCard`):
  - *Wallpaper* ("side column + full grid", chosen knowing three redesigns of this panel were rejected on
    2026-11-06 for leaving too little grid): `sideCol` holds the hero card turned upright (its inner row is a
    `GridLayout`, one column on an island: picture at 16:9, name, colours, actions at the foot) in `heroSlot`,
    then the header's tray and its line on a card; tabs, search and the grid take the full height beside it.
  - *Colour scheme*: `sideCol` holds a loud card (six live swatches, light/dark, `headerLine`) over the header's
    three trays, which reparent themselves into `toolsCol`; the tabs and the page on show keep their full width.
  - *Audio mixer*: the Mixer page leaves the pager and scrolls in its own left column (`mixBox`); Devices and
    Input take turns on the right.
- **Round 6 (2026-11-14), after the user's screenshots** ("wallpaper doesn't look good enough", "colorscheme
  should also be rethemed", "the audio mixer is way too busy"):
  - *Mixer, less at once* (island only): Devices is two tabs, "Devices" (outputs, inputs) and "Options"
    (remembered apps, behaviour, restart) — both are `devicesPage`, half shown each (`pageKey`, `optionsPart`);
    the hero's output chips are hidden (the Output list stands beside it); an app's route picker shows only under
    the pointer (its second line already says where it plays).
  - *Wallpaper hero*: flat on `primaryContainer` with the hero corner and an "ON SCREEN" caption, no blurred
    backdrop. The tabs, search, tiles and sub-views are NOT restyled yet.
  - *Colour hero*: the worn palette as four `MorphShape`s filling the card, the light/dark pair at its foot
    (`wornFoot`), the other two trays side by side under it. The workbench, library and album are NOT restyled yet.
- **Round 7 (2026-11-14, "go ahead with the full restyles")**: the colour workbench is two flat cards (which
  colour: seeds / slots / tools; what colour: picker and readout) on a transparent holder, for the bar's panel
  and the sidebar's too (`ColorSchemeWorkbench` is shared). The wallpaper header's tray reparents itself into
  the side card, centred under its line. Left alone on purpose: the wallpaper tile and the dashed "add" tile
  (the user's own live-approved polish, 2026-11-06), the colour library and album (already flat cards).
- **Round 8 (2026-11-14, "I want a full restyle to wallpaper and colorscheme pages", judged from live
  screenshots: `qs ipc … call panel toggle <key>` pins the page, `grim -g` the island's box only):**
  - *Wallpaper*: the island's gallery cells are `modules/panels/wallpaper/WallpaperCard` (the picture IS the card:
    no caption row; name, star, bin, scene options and Apply ride on it on surface-toned pills, mostly under the
    pointer; the one on screen wears an accent frame, a cookie with a tick and the hero corner; the add tile is a
    tonal card with a morphing badge). Behaviour is still `WallpaperEntry`, shared with the bar's tile and row.
    `WallpaperPanelBody` puts the island's grid and list on a `radiusXl` section plate (`plate`, `inset`,
    `ground`; the scroll fades wear the plate's tone) and picks the cell (`cardCell` / `tileCell`). The hero's
    picture takes the card's spare height, its action chips stand free (`ChipButton.tonal`, new: a quiet plate
    while off), and the header's chips move in declaration order into a 3-across pill grid (`toolsGrid`), as the
    Dashboard's switches. The page declares 780 × 412. The bar's own panel keeps `WallpaperTile`.
  - *Colours*: the four seeds are discs that bloom into a shape of their own when chosen (squircle, hexagon,
    cookie, clover) inside a ring, names under them (`ColorSchemeWorkbench`, shared, so the bar's and the
    sidebar's panel too). The hero draws the palette being BUILT as it will be worn (`preview`: "Aa" and text
    bars on the background seed, a button in the accent, the second accent as the shape behind). The header's
    tools are a pill grid (`toolsGrid`), light/dark at the hero's foot.
  - Seen on screen: both pages at rest. NOT seen: any hover state (the pointer cannot be driven safely),
    Scenes / Material / list view / select mode, the Presets and Album tabs, a current IMAGE (a scene was on).
- **Round 9 (2026-11-14, the user's wallpaper list, judged from live screenshots of both pages at rest):**
  - *Hero*: 16:9 for real. A preferred height alone was shrunk with the rest of the column (the source cards
    wanted more than was left), so `WallpaperNow` carries min = max = preferred, and `WallpaperSources` is compact
    (badge left, count right, name under; no caption) so the column fits in 412. A scene whose preview is a GIF
    plays it (`AnimatedImage` over the still; `Motion.ambientOn`, not while a game has it paused); a JPEG-only
    preview has nothing to play. While the Material tab is open the hero previews Material (labelled PREVIEW until
    applied) and a part chosen on the Shapes plate dims the rest (`panel.materialSlot`).
  - *Gallery*: two columns on an island (`panel.gridCols`, also the keyboard's `kbCols`), each card mounted on a
    canvas (`panel.cardMat` wide, `surfaceHigh` with a hairline; the frame for the one on screen is that canvas in
    the accent). The grid's cell height allows for the mat so the picture stays 16:9.
  - *Search row*: a tonal pill ringed in the accent while it has the keys, a `/` keycap while idle, and the
    options button is a round `ChipButton.tonal` of its own (a count while filters or the sort are changing the
    view) instead of an icon inside the field. The library popover opens under it (`WallpaperPopover.rightInset`).
  - *Status line*: no dashes (the user: "looks AI like"). Colons and full stops.
  - *Parallax*: the popup is gone. Pictures / Scenes switches are the top of the effects view, which is now
    "Motion" (parallax, then music); one `animation` chip in place of the two, lit while any of them is on.
  - *Material*: one scroll of `WallpaperMaterialPlate`s (actions, Looks, Colour, Shapes, Motion) in place of the
    four-page switch. Each look is drawn as itself (`MaterialWallpaper` is given the look's own style, so its
    `forms` is now an ordinary property); the preview is the side hero, or the first plate on the bar's panel.
  - *Open and close of every island*: the box's springs are the spatial spring with damping 1 (`IslandDock.boxSpec`;
    1.5% of a 412 px card was a 6 px wobble). Contents come in a third of the way through and leave in the first
    tenth, before the box shrinks (they were cropped by it, then faded); `ca` is the spring that follows that curve.
    The card settles from 95% and the page rises a little.
  - Seen on screen: both pages at rest. NOT seen: the GIF moving, the Motion view, the Material plates below
    Looks, any hover, the open/close motion itself, a light scheme, the bar panel (non-island) versions.
- **Round 10 (2026-11-14, second wallpaper list):**
  - *Opening*: still abrupt, because one critically damped spring starts with its hardest push. The box now chases
    a point travelling with `rv` (a second, stiffer spring: `IslandDock.followSpec`), so it starts gently, speeds
    up and settles; the contents wait until the box is a third open (`ca`, on `springEffects`).
  - *Hero*: a video scene plays its own file (project.json's `file`, via `ClipPlayer` by `Media.playerUrl`, muted,
    looping) over the GIF, which stays as the first frame and as the fallback without qt6-multimedia. Measured: the
    shell goes from about 120% to 160% CPU (top, one core = 100%) while the page is open, 4K file. A non-video scene
    keeps its GIF, which is all the Workshop ships.
  - *Cards*: tools are a capsule under the pointer (bookmark, a scene's options, the bin: `CardTool`), a
    bookmarked card keeps a small mark. The bin lays a confirm over the picture (Keep / Remove) instead of arming
    in place. Icons: bookmark and delete_forever. `favorite` / heart are NOT in the cut font and `--emit` is not
    to be run (the user reverted it once), so the choice is from what `services/icons.js` has.
  - *Add images* tile hovers to a squircle, not a burst. *Source cards*: the count large bottom left, the name
    under it, one big badge in the top corner cut by the card's curve (ClippingRectangle).
  - *File picker* (`WallpaperBrowse`): places (Home, Pictures, Downloads, Library; `Places.picturesDir`), the path as
    pressable steps (`wallpaperlib.js crumbs`), All, folders as cards, pictures on canvases with a tick cookie, a
    floating Add capsule. Seen on screen: NO (the pointer cannot open it).
  - *Library options*: the popup is an inline drawer under the search row (`drawer`, critically damped), the
    gallery gives way while it is open. `WallpaperPopover` is deleted. The options chip's tip is right-aligned
    (`HoverTip.alignEnd`) so the island's clip no longer cuts it.
- **Round 11 (2026-11-14, third wallpaper list):**
  - *Colour*: a sort ("Colour", `Config.wallSort = "color"`: the hue wheel from red, then neutrals light to dark,
    favourites do not float out of it) and a colour SEARCH (type `blue`, or press a swatch). Both read
    `WallColors.map` ({ path: "#rrggbb" }, from `scripts/wall-colors.py`: the dominant vivid hue, else the average,
    cached by path and mtime in `$XDG_CACHE_HOME/quicktest/wall-colors.json`; a scene's colour is its preview's).
    Logic and its tests are in `wallpaperlib.js` (`colorKey`, `colorName`, `colorWord`) and
    `scripts/test-wall-colors.py`. A new singleton: a cold start if a hot reload does not pick it up.
  - *Library options drawer*: three rows of `OptionCard`s (sort; kind + favourites; shuffle, starred only,
    apply log) in place of chips; on, a card goes round and its disc blooms into a shape. Intervals are one chip row
    under them while the shuffle is on.
  - *Search field*: types its own hints while idle (`TypedPlaceholder`, the launcher's and the settings'), the eight
    hues as swatches while it has the keys and is empty, "n of N" while it has text, the glass bumps per key.
  - *Tip*: it hung over the drawer and the gallery, which paint after the search row; the row is `z: 50`.
  - *Source rail* (`WallpaperSources`): one pill that slides between three rows (IslandRail's idea), badge blooming on
    the row it lands on, the number large at the right. The big-badge cards were rejected twice.
  - *Hero*: a scene shows a spinning cookie until the proper video's first frame is up (or the project says it is
    not a video: then the GIF), never the GIF first. 12 s or a player error gives the GIF its turn.
  - *Cards*: bin is an X, the capsule and the mark are `iconXl`, Apply is a tick on a disc that spins into a cookie
    while applying and fills with a pop on "Applied" (the pill lingers 1.1 s).
  - *Ctrl+V* adds what the clipboard holds, on every tab like the drop: copied files (text/uri-list, through
    `dropPaths`) or a picture's data, saved as `Pasted <date>.<ext>` (`Wallpaper.pasteFromClipboard`,
    `wallpaperlib.js pasteKinds`: PNG / JPEG / GIF kept, other image types converted to PNG with magick). In the
    search field a picture is taken and text still pastes as text. `Wallpaper.pasteNote` is said on the status line
    for 3.5 s. The shell snippet was run against a stub `wl-paste`; the key itself is untested.
  - Seen on screen: the rail, the typed hint, the bigger mark, the hero playing. NOT seen: the drawer, colour sort and
    search, the tip, the loading mark, the Apply animation (hover only).
- **Round 12 (2026-11-14, the colour scheme page, rebuilt to the wallpaper page's bar):** the page is a fresh
  layout, one size (780 × 436, `body` in islands.js) for the island AND the bar's plain dock (the old bar-sized
  `ColorSchemeWorkbench` / `ColorSchemeLibrary` / `ColorSchemeAlbum` and the header trays are gone). `ColorSchemePanel`
  keeps ONLY the editor's state and logic (seeds, staged slots, undo, ripple, light and dark kept while away); the
  views are `modules/panels/colorscheme/`:
  - *Left column* like the wallpaper page: `SchemeWorn` (the loud card: the palette being built drawn as a miniature
    of the island itself, "Wearing" or "Preview" and the scheme's name, the light / dark pair, contrast pill, and four
    tools: rebuild from the wallpaper, hold, bind to this wallpaper (press again to go native), apply log; an app
    that needs a restart takes the line's place with Restart / close) over the island's source rail
    (`components/SourceRail`, now shared with `WallpaperSources`: Palette with its contrast grade, Presets with
    the count, Album with On / Off and a dot while it is live).
  - *Palette* (`SchemeEditor`): four colour CARDS whose faces are the colours (the chosen one goes round, its badge
    blooms into a shape with a tick) or, in Every slot, eighteen chips that do the same; a mode switch, undo, "back to
    what the shell wears" and Discard in the plate's header; a picker, name, big hex, contrast as a large numeral,
    the ribbon of what Apply will commit; Shuffle and the harmony pills under it (or, in Every slot, Release);
    then name + Save / Update, Peek (hold) and Apply (`SchemeApply`: disc that spins into a cookie, then a tick).
  - *Presets* (`SchemePresets`, `SchemeCard`): cards that are miniatures of what they wear (their background, name,
    accent as a badge, ribbon), a card that is in use or in the editor blooms its badge into a cookie with a tick and
    goes rounder; a capsule under the pointer: put it on NOW (stays on Presets, `panel.holdView`), bookmark,
    workspaces, rename, remove (Keep / Remove layer). Search is `components/SearchPill` (typed hints, "n of N").
  - *Album* (`SchemeAlbum`): the cover on a canvas with the track and the cover's eight colours, the follow switch;
    Where and Applies to as `OptionCard`s with a one-line meaning under each (replaced, not rewritten, by SwapFade);
    Lock as a full-width card. Strings have no dashes; `AlbumScheme.reasonText` lost its one.
  - Shared parts moved to `components/`: `OptionCard` (was WallpaperOptionCard), `CardTool` (was WallpaperCardTool),
    `SourceRail`, `SearchPill`. `qs ipc call island part colorScheme <edit|slots|library|album>` opens a view.
  - *Tweaks, same day*: the hex and the name are `SchemeField` capsules (badge, text, a copy tool or a Save pill at the
    end) instead of form boxes; the lock is a labelled pill on the loud card ("Colours held" / "Follows wallpaper";
    it was an unlabelled icon nobody found); the wallpaper's colours are a hero at the top of Presets (its picture,
    the eight colours, "Use these colours" / "In use"); a card's tools capsule pushes only the NAME in, never the
    ribbon; "Yours" and "Classics" fold (`panel.folded`, session only, ignored while searching); every Album option
    can be set BEFORE following is switched on.
  - *Album, second pass*: it works BEFORE following is on. `AlbumScheme.previewWanted` (set by the view while it is
    open) reads the cover into `previewPalette`; `coverPalette` is that or the live palette. The loud card wears
    it on this view ("Cover preview"). One scroll of plates: the cover plate (artist, player, eight colour tiles),
    Follow as a loud pill with Peek / Keep as preset / Edit beside it (`ColorScheme.openPalette`), While it plays
    (the lock, and `Config.albumHold`: 5 s, 20 s, 2 min, stay until replaced; was a hard 20 s), Where, Applies to.
  - *The hold on the loud card*: `ColorScheme.toggleLock()` now ONLY locks (pins what is showing) or unlocks (drops
    the pins). It no longer regenerates from the wallpaper on unlock, so nothing repaints; the next wallpaper
    change brings the wallpaper's colours. `releaseAll()` / `useWallpaper()` are the explicit "give them back now".
  - Seen on screen: Palette (Four colours and Every slot), Presets and Album at rest; the wallpaper page after the
    moves. NOT seen: any hover or press, the tooltips, the delete layer, rename, the workspace picker, Peek, the
    Apply animation, a light scheme, the progress view, the bar's plain dock form.
- **Not rebuilt yet**: System update (still opens in the plain middle column: its sudo prompt needs the
  exclusive keyboard grab the islands do not take). The sidebar keeps every panel file as it was.
- **Merged with the frame / sidebar**: a side island's lobe stands ON the frame's strip (`Config.frameDepth`)
  or the sidebar's face (`SideRail.panelFace`) when welded, the usual margin off them when not; it opens at
  full width and grows down. The middle one still hangs free.
- **The handle is on the bar's TOP edge** (`IslandDock.barTop`), `Config.islandHandle` long (Settings › Desktop
  › Island › Handle length). A side island's stands over the middle of the card it opens. The live pill still
  hangs under the bar.
- **Not overlays**: HoverCard, PolkitPopup, ReloadPopup, LensOverlay, AnnotateWindow, SnipOverlay,
  CheatsheetPopup, ClipEditor, HotCornerPanel, the Karaoke screens and the peeks stay floating surfaces.
- **The plain columns keep their motion** (`BarDock`'s curves, the user's pick over springs). Their corner is
  `min(Tokens.radiusXl, height / 2)`, with the lobe on the same number (`BlobBarLayer.leftR/centerR/rightR`).
- Unverified visually: nothing was loaded on purpose. Only static checks and the tests ran.

### The bottom row, and who may be open together (2026-11-15)

The user: the sidebar should open islands on the BOTTOM the way the bar opens them on top (no more panels
clipping beside the sidebar), and the one-at-a-time rule becomes "both sides may be open, the middle alone",
the bottom row behaving the same. Their picks (AskUserQuestion, binding):

- **Six islands** (`config/islands.js` `SIDES` = `COLUMNS` + `BOTTOM`: `bottomLeft`, `bottomCenter`,
  `bottomRight`; `rowOf()` / `hOf()`). The bottom ones are `IslandDock { island: "bottom…" }` in Bar.qml: the
  handle on the screen's bottom edge (its reach is in the window mask: no strip there takes the pointer), the
  card standing on the frame's bottom strip (or a bottom sidebar's face, `bottomFace`) and growing UP
  (`joinY`, the Loader anchored to the bottom). Welded only where there is blob to melt out of (`bottomWelded`).
  Blob lobes `islandBL/BC/BR*`. The window reaches the screen's bottom while the bottom row has pages.
- **Defaults** (user's pick "three by theme", then revised mid-task): bottom-left = Desk, Timer; bottom-middle =
  Clips; bottom-right = Screen time, Claude. Their panels' plain column stays `right` (`BOTTOM_COLUMN`).
- **No copies** (the user: "don't copy already built page like stats"; small panels are "worth mixing in a
  dashboard"): `ALIAS` / `pageFor()`. Stats opens Performance; To-do, Clipboard and Idle open **Desk**
  (`modules/island/IslandDesk`, `PAGE_META.desk`, 780 × 384): a loud timer glance, the idle rules' switch, the
  to-do list, the last three copies as cards; the idle editor and the whole clipboard open in place behind a
  Back chip (`view`, Escape goes back). A panel put on a rail itself wins over its stand-in; with the stand-in
  off every rail the panel opens alone again.
- **Routing**: a sidebar button whose page is on any rail opens that island pinned (`UiState.openSidePanel` /
  `toggleSidePanel`); a button's lit state is `UiState.sideShows(key, screen)`. Beside the button
  (`SidePanelDock`) is now only for what is on no rail: voice, hover cards, the clips' target and peek.
- **State**: `UiState.islandSet` `{ id: { pinned, screen, page, part } }` (an id in it is open), `islandLast`,
  `openIsland(id, o)` / `closeIsland` / `closeIslands` / `setIslandPinned`, `islandPartFor(page)` /
  `islandScreenFor(page)` for pages. `islandEffectsOn` follows the island opened last.
- **Who may be open together**: in a row the middle is alone and the two sides coexist, unless their cards would
  meet (docks report their open span, `islandSpan`; a narrow screen makes them one or the other). Rows are
  independent; with both rows present the top gets 55% of the screen's height and the bottom 45%
  (`IslandDock.share/room`), and a fixed-size page taller than its room is scaled down whole (`fitScale`, not
  below 0.6). Plain columns keep one-at-a-time among themselves; a column closes the top islands that cover it
  (its side's and the middle), a top island the columns it covers. The bottom row ignores the columns. Hover
  stands down where opening would close something pinned or a column (`islandBlocked`).
- **Board**: an "Along the bottom" row of three rail-only columns (no plain column down there). A layout saved
  before the bottom row existed brings its bottom-default pages to their islands even though `off` listed them.
- Tests: `bun scripts/test-islands.js` (123).
- **Screen time and Clips on an island** (same day, the user: "need a rework to match the island style and M3E";
  780 × 412 each, `island: true` from `IslandCard`):
  - *Screen time*: `ScreenTimePanel.island` hides the title row and the wide hero; the loud card stands upright
    (`screentime/ScreenTimeIslandHero`: state + pause / stop tools, today as a big number, pace or "vs usual",
    the goal bar, the 24 hour bars) over a `SourceRail` (Today / Week / Apps with their figures); the same page
    files fill the right (`pagesBox` is reparented there). `island part screentime week` opens a page.
  - *Clips*: `ClipsPanel.island` loads `clips/ClipsIsland` (logic, keys, clocks and the latest list stay in
    ClipsPanel): the loud card is the replay buffer (switch, a big ring with the held time, Clip it as the one
    loud pill, the lengths), the record card under it; right, a warning plate only when there is one, capture
    (screen, mic / desktop sound as `LitTool`s, the profiles as `OptionCard`s), and the library (count, weight,
    disk meter, clean-up with a Keep / Trash confirm, folder, Library) over a 3-column gallery of the latest nine
    on canvases with edit / copy under the pointer. `stepAside()` closes the island (or the side slot) before a
    clip plays, the editor opens or a region is dragged; the capture target picker opens beside the sidebar's
    Clips button.
  - Seen on screen at rest: both. NOT seen: hover, a running buffer or recording, the warning plate, the confirm.
- **Timer as a dashboard** (same day, the user: "like a dashboard instead of lots of tabs"): `modules/island/IslandTimer`
  (780 × 412), island only; the sidebar and islands-off keep `TimerPanel`'s tabs. The countdown is the loud card
  (time, Ends, bar, h + min steppers while idle, the usual lengths or +1 / +5, Start / Pause, stop; a ringing alarm
  or a finished countdown takes it over with Snooze / Again / Dismiss); Stopwatch and Focus rounds side by side;
  Alarms under them as a horizontal row of cards (on = loud and rounder, repeat / remove under the pointer) ending in
  a new-alarm card (time, days, Add).
- **Workout on an island** (2026-11-16, the user: "start a workout which would start a timer and let me write the
  exercise, reps, sets, extra weight or time based … track workouts by date", then "I still don't like the UI … make it
  like a checking list with beautiful animations … a dumbell"): `workout` page, bottom-left after Files (`PAGE_META`,
  780 × 412), `modules/island/IslandWorkout`. Rules are `services/workout.js` (pure, `bun scripts/test-workout.js`, 97
  checks, now 155; run it under `TZ=Pacific/Auckland` too: the date maths), state and file are `services/Workouts`
  (`workouts.json` under XDG_STATE_HOME, the running workout is saved too; the 1 Hz clock runs only while one runs).
  - **A checklist.** An exercise is added with its sets PLANNED (`done: false`); a set is ticked off (`toggleSet`, `at` =
    when). Only ticked sets count and finishing keeps only them (`finish`); a set with no `done` field is done (every
    set before the checklist). `tweakSet` changes a set's reps / seconds / weight, `addSetLike` adds one more.
  - **Left:** the loud card (idle: this week, the streak, Start; running: the clock, the done count that bumps on each
    tick, one pill per set that fills and swells, volume, the rest since the last tick, Finish, a discard that asks Keep /
    Discard on a layer) over a `SourceRail` Checklist / History.
  - **Checklist:** a field + the six most recent exercises as chips (one tap adds it with last time's numbers) + a fold
    (the `tune` chip, a spring-height row) for Reps | Time and the sets / reps or time / weight steppers. Each exercise is
    a card: a badge (disc with `done/total`, a `cookie9` with a tick when complete), its summary line, under-the-pointer
    tools (add a set, remove), and a body of set rows that folds itself away 0.9 s after the last tick (the header
    folds it by hand; a hand fold wins). A set row is a checkbox: tap anywhere; the disc blooms into a `cookie9` with an
    overshooting tick and a ring leaves it, the row goes round and takes `primaryContainer`; − / + for the reps (or
    seconds) and the weight come out under the pointer.
  - **The add field is a feature** (`modules/island/WorkoutField`, built like SearchPill / the launcher field: a capsule that types
    its own hints idle, a dumbbell that lifts on every key, a focus ring, a `↵ 3 × 8 · 60 kg` pill that springs in when Enter
    has something to add). `workout.js` `parseQuick` reads habits ("bench 3x8 60kg", "squat 5x5 @ 100", "plank 3x45s",
    "pull-ups 12", "135lb" converts to the log's unit), `quickSpec` fills what was not typed from the last time you did it,
    then the steppers; `suggest` matches your own exercises first, then a built-in list of 42 (`LIBRARY`). Typing highlights
    the best match (Enter adds it, Up / Down move, Up from the first is the text exactly as typed, Tab takes the name into the
    field and keeps the numbers); a tap on a chip adds it too. Idle, the chips are your six most recent, one tap each.
  - **Next up:** the loud card shows the first set still to do with a button that ticks it, so a workout can be done from the
    card. **Records:** a done set better than everything done of that exercise before (`score`, an estimated one-rep max for
    loaded sets, reps for bodyweight, seconds for time; never the first time) wears a `★ PR` pill that pops in with the tick,
    and the card says how many. **Repeat last** (idle card): `startFrom`, the last workout's exercises and numbers, all to do.
  - **Polish round (same day):** a rest bar comes up from the foot of the list after a tick (the rest so far filling to a goal,
    "Go" and one swell when it is reached, the goal in 15 s steps; `Workouts.restGoal` is saved in `workouts.json`, 15 s to
    10 min), each exercise's badge wears a progress ring (`RadialGauge`), Finish lays a recap over the loud card (a `cookie9`
    that blooms, the time, sets, exercises, volume; History / Done; 9 s), and the two views crossfade and slide.
    **A trap found:** `SpringValue.jump()` before the spring's own `Component.onCompleted` is lost (`_go()` returns while
    `!_ready`) and the value stays where it jumped: a pill lit from the start sat at 1.5× forever. Guard a jump in a
    property-change handler with an `armed` flag set in `Component.onCompleted`, or use a `SequentialAnimation`.
  - **History:** twelve weeks as a heat grid (tap a day, chevrons page back), this week / streak / total, the picked day's
    workouts with a Keep / Delete layer.
  - **The dumbbell is drawn.** The bundled font has no `fitness_center`, and re-cutting it (`material-symbols-map.py
    --emit`) rewrites both icon fonts (measured in a scratch copy 2026-11-16: it would also add ~29 names the tree uses
    that the font lacks, and change the glyph font), so `components/Dumbbell` draws it and `MaterialIcon` shows it for
    `name: "dumbbell"` (width / height set to the font size so layouts still hold). Rails, chips and the board get it free.
  - An upgraded shell's saved layout gets the page at its default place. Seen at rest (empty list); the cards, ticking,
    the folds and the heat grid not seen: they need data and a pointer.
- **Tablet on an island** (2026-11-22): `tablet` page, bottom-left after Workout (`PAGE_META`, 780 × 412), `modules/island/IslandTablet`
  and `modules/island/tablet/`. The loud card draws the tablet to its real shape with the active area as a block to drag and
  resize, the live pen dot and the express keys; a rail under it holds Map, Profiles and Test. Four faces before it is a page (off,
  looking, no udevadm, no tablet). `island part tablet map|profiles|test`. Everything about it is in `docs/tablet.md`.
- **Voice on an island** (same day, "make a page for the discord panel I had"): `voice` is a page (META, bottom-middle
  after Clips). `VoicePanel.island`: `voice/VoiceIslandHero` (call, connection, duration, faces ringed while
  speaking, mic / deafen / share / camera / open as `LitTool`s, Leave on a Keep / Leave row) over a `SourceRail`
  (People, Your audio, Board); the faces' `body` moves onto a section plate on the right. Out of a call the page
  stays on the Board. `UiState.openSidePanel` now keeps `sidePanelArg` on an island too (a right-clicked person).
  The call's duration is the service's (`Discord.durationText`); in testing it restarted each time the page opened.
  - *Second pass* (the user: "the discord page looks quite empty"): on an island People is `voice/VoicePeopleGrid`:
    a tile per person sharing the height (two in a call = two tall tiles; a floor and a scroll past what fits), a big
    face ringed while speaking, name, state, mute-for-me + a volume slider (0 to 200%) on the tile, your own tile with
    mic / deafen / Your audio; a "Most time together" strip (CallLog's top three) leads to the Board. Balance stays in
    the sidebar's list.
  - *Alarms, second pass* ("still looks a bit weird"): an empty state where the cards go, cards show the week as
    seven dots, and a new alarm is one pill row along the foot (time, a repeat chip cycling the presets, Add).
- **Eight new pages** (same day; the user picked all eight from a list of pages built on services the shell
  already had). Each is `modules/island/Island<Name>.qml` (or a panel's `island` form), 780 × 412, a loud card on
  the left and plates on the right, registered in `PAGE_META` (own pages) and `IslandCard.componentFor`:
  - *Captures* (bottomCenter): newest shot large, Copy / Read text / Pin / Record cards, Snip pill; the screenshots
    folder (FolderListModel of `Screenshot.saveDir`) as a gallery, copy / remove (Keep / Remove layer), press to
    edit (`UiState.openAnnotate`). Pictures stay hidden while `StreamMode.active` (a screen share), with an
    eye-off mark. `Clips.showFolder(dir)` added for opening a folder in the chosen file manager.
  - *Network* (right): rates now + two curves (NetStats, held while open), speed test, DNS presets as option cards,
    apps moving data (NetApps).
  - *Power* (bottomRight): this computer's battery or mains, device batteries as rings (DeviceBatteries), power
    profile (needs power-profiles-daemon, `PowerSaver.profilesOk`) and `Config.powerSaver` as option cards.
  - *Files* (bottomLeft): newest downloads, place cards, trash with an Empty confirm; recent files from any app
    (`Recents.recent(n)` → `xbel.js recent()`, tested in `scripts/test-xbel.js`; `Recents.revision` makes it live),
    pin to dock (FilePins); disks (Storage).
  - *Agenda* (center): next event, next holiday, world clocks; a typing line through `quickadd.js` (the clock
    panel's parser: Reminder or Event, Enter adds); today + tomorrow; open reminders.
  - *Displays* (right): night light (warmth on a ThickSlider, by hand / at sunset), screens to scale with Hz and
    scale chips and the keep-or-revert apply (Displays.apply), anti-flashbang.
  - *Assistant* (bottomCenter): who answers + one-press asks; the overview's `FeedAssistant` on a plate (same
    conversation as the overview's).
  - *System update* (right; the middle rail was full at seven): `UpdatePanel.island` with `update/UpdateIslandHero`
    (count, Official / AUR / Flatpak, re-check, the log and Cancel with a confirm row while running) and the
    panel's three views on a scrolling plate. `LOCKED` is only the launcher now; `update` is in `ISLANDS.right`,
    out of `OFF_RAIL`, its column still the middle (`sideOf`) and its pre-board rail found by `_railCol`.
    `UiState` routes `updateRequestId` to the island (BarPanelDock stands down), `updateOpen` no longer clears the
    middle column while it is railed, and `IslandDock.wantsExclusive` (the page's `wantsExclusiveKeyboard`) puts the
    bar window on the exclusive grab only while the password or a question needs typing. Opened mid-check (total 0),
    the page follows the count back to the pending list. Its package list stays folded by default: unfolding it
    on the island by default left the list at zero height (not understood; needs a click to test).
  - Seen on screen at rest: all eight. NOT seen: hover, a speed test or update run, any typing, Apply on Displays.
- **Update panel's password and buttons** (same day, the user: "I don't like its current pill for inputting
  password… a little shape animation for the digits… don't overdo it"): `update/UpdatePasswordField` (InputField's
  API: text, clear, forceFocus, accepted, keyPressed) is a tonal card: a key badge that blooms while there is text
  and fills in the accent with the keys; each character a small `MorphShape` that pops in (spring from 0) as a dot
  and settles into one of six calm shapes, the newest in the accent, Backspace shrinking the last away (a ListModel
  grown and cut at the end, so only the newest animates); hold the eye to see the text; a send button that pops in;
  "Caps Lock is on" under it (KeyLocks.caps). The keys go to a never-drawn TextInput (echo Password). Used by the
  main and caught-up views (the running view's answer field stays InputField: it also takes numbers and text).
  `UpdateActionButton` is a card too: primary loud in the accent (quiet until it can act), secondary quiet, a badge
  that blooms under the pointer, a lean and a press dip. Bar panel and island alike. Seen at rest, empty and with
  eight characters (pre-filled for the shot, reverted); the typing motion itself, focus fill and Caps line unseen.
- **Update hero, second pass** (the user: Official / AUR / Flatpak "more expressive, don't exaggerate", the left
  card "feels too empty"): the three tiles became one share bar (rounded pieces with a gap, widths by share with a
  pill's minimum, the accent then two quieter steps) and a legend whose `MorphShape`s bloom for a source with updates
  and rest as a small dot at zero; under it "Biggest jumps", the three largest version changes from
  `Updates.packages` by `updatefmt.js bump` (major, then minor / new), each with a Major / Minor / New tag.
- NOT re-laid yet: Claude still shows as its sidebar panel on the island.

## Hiding the status bar (2026-11-19)

`Config.barHidden` (transient, not persisted, like `UiState.sidebarHidden`; set by `UiState.setBarHidden`, the desktop menu's View
and `qs ipc call statusbar toggle|show|hide`). It is in Config because `barExtent` depends on it: hidden, the bar owns the ring's
depth (`frameDepth`) while the frame is on and 0 when it is off, `barSurfaceHeight` follows, so every site that asks where the bar
ends (the window's exclusive zone, its mask, the blob's top border, ScreenFrame, the islands, toasts) follows without a change. The
pills, the unified surface and the three regions fade on `Bar.barShown`; the zone itself snaps (a per-frame exclusive zone
re-tiles every window every frame) and Hyprland animates the windows. Hiding closes every panel (`closeAllPanels`). Untested on screen.

With the frame off, an inner pill (BarGroup's runs, SpacerPill's chip, SidePill's inner pill) wears `frameFill` instead of the
nested tone, and drops the item's own translucency so it isn't applied twice.

## Pill tooltips and quick cards (2026-11-15)

A bar pill's tooltip (`modules/bar/PillTip`, words from `ModuleGlance.tip`) is a lobe of the blob under the pill. A module can
give it a QUICK card: `PillTip._quickOf(id)` maps a module id to a component in `modules/bar/quick/`. Nineteen exist: wallpaper,
volume, wifi, bluetooth, palette (Colour scheme), notifications, nightlight, idle, clips, timer, gamemode, brightness, update,
tasks, clipboard, screentime, stats, power, battery. `BarIconPill` passes its `moduleId` through `IconButton.quickId` →
`HelpTip.quick` (Volume / Wi-Fi / Bluetooth / Update / Battery pass it by hand); an id with no card stays words. A new card is
one `QuickFrame` file, a qmldir line, and a case in `_quickOf`.
- **Look (the islands' dialect)**: `QuickFrame` is a bento of two `IslandPlate`s, concentric with the card: a hero on
  `primaryContainer` (a `MorphShape` badge in the module's own shape, name, state line, `trailing` for the main switch) and a
  section plate of controls: `OptionCard`s (off a lifted plate, on a round primary container with a blooming badge),
  `ValueSlider { expressive }`, `ChipButton` rows, the plates cascading in with `PopIn`. No header words above it.
- **Wallpaper**: what is on screen as a picture (a shape and its name for a scene or Material), and three random others to
  try (`quickpicks.js`, seeded: opening rolls, the dice re-roll; `bun scripts/test-quickpicks.js`). Shuffle in the hero,
  Undo / Auto / Gallery below. The first version showed starred wallpapers; the user asked for something else.
- **Power** offers Lock and Sleep only; anything that ends the session stays behind the power menu. **Update** runs no update
  (the password flow is the panel's). **Clipboard** shows `Clipboard.label`, which masks text on a stream. **Tasks** only checks
  off (a field to type in needs the keyboard focus the bar window doesn't take). Not built: Voice, Claude, Colour, Lens, Tools,
  Now Playing, Layout, Keyboard, Privacy, Stream.
- **Idle** gained `Idle.keepFor(minutes)` (timed hold, `manualUntil`, not persisted). The palette card lists the user's saved
  schemes once `ColorScheme.presetsReady` (opening the panel lists them), the classic ones before.
- A card is something to press: it takes the window's mask (`maskItem`, in Bar.qml's Region list), opens after 450 ms (words:
  900), and stays while the pointer is on it (`cardHovered`; a 280 ms grace bridges pill to card).
- **Corners weld.** A card pushed against a side STANDS on what is there and the blob merges it: the sidebar's face
  (`clearLeft/Right` = `sideRail.band`), else the frame's strip (`Config.frameDepth`, when `frameFused` and `screenFrame`), else a
  margin (`PillTip._stand`). Words-only tips do the same. A card that is not pushed to a side hangs free under its pill.
- Any island or panel opening (`UiState.barSurfaceOpen`) kills the tip with no fade (`_kill`, `_snap`) and mutes that pill until the
  pointer leaves it; no pill tip shows while a surface is open. `TipBubble` (the unwelded fallback) follows the same rule.
- Welded bar only: unwelded or in safe mode the pill falls back to the plain `TipBubble` words. Never loaded.

## Arrange mode (2026-11-11)

`UiState.arrange` arms the bar and the sidebar together. It closes every panel and keeps them shut
(`UiState.closeAllPanels()` and a `Connections` that resets any key set while arranging). The window then wears
what the desktop widgets' arrange mode wears (`ArrangeBackdrop`: the 45% dim and the snap dots, z -2 under the blob
layer; each module's primary outline, brighter in the hand; the "Done arranging" button and Escape; the window
grows to the screen's height so the dim reaches the bottom). The hint card is `components/ArrangeHint`: welded
(`blobRing`, and `rail.welded` for the sidebar) it is a lobe of the blob (`arrBarRect` under the bar,
`arrSideRect` off the sidebar's face, hero corner) that melts out of the surface it stands on; floating it is a
popup card. The Settings window (class `org.quickshell`, title "Settings", found in `Hypr.windows`) is cut out of the dim by an inverted `MultiEffect` mask and edged in primary, so it reads as lit; the dots sit inside the shade and are cut with it. Pill tooltips (`PillTip`) stand down while arranging. Unverified visually: nothing loaded.

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

## The spacer module

`spacer` (config/modules.js, both forms): an empty module that takes room. Its length is `Config.spacerSize()` (0 to `spacerMax`, a
per-module setting like any other) plus the length of the module it follows (`spacerFollow()`), or, in "fill" mode (`spacerFill()`),
the size less it, never below 0; `services/spacer.js length()` (`bun scripts/test-spacer.js`) is the one formula for both surfaces.
What it may follow is `Config.spacerCanFollow`: a module on its own surface, never another spacer, and on the sidebar a SMALL module
only (the dock's length depends on the room the small ones leave, so following it would be a cycle). It never has an inner pill
(`moduleInnerPill`), so on the sidebar the region's pill splits round it and it reads as a gap.

- **Bar** (`widgets/SpacerPill`): follows the followed module's SLOT live through `Bar.moduleSlots` (id to slot Item; BarGroupRow's
  `slotSeen` / `slotGone` fill it, and the whole map is replaced on a change so a reader re-evaluates). A spacer in a library tile or the
  settings preview doesn't follow (no slots there).
- **Sidebar** (`SideSpacer`, `SideRail.smallLengths`): its length is data like every small module's, worked out after the others so it
  can read theirs; `SideGroupHost` hands the module its `length` (any module that declares one).
- **Editing:** an empty module can't be picked up, so while the bar or sidebar is arranged it shows as a module: a glyph in a pill at
  least one cell long (the rail lifts it, as it does the window cell), on its own inner pill. A library tile shows the bare glyph.
