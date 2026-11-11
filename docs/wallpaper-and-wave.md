# Wallpaper and the wave

Moved from CLAUDE.md; the project rules there still apply.

## Wallpaper

Two libraries behind one gallery. Images: `scripts/apply-wallpaper.sh` →
`services/Wallpaper.qml`. Scenes: `services/WallpaperEngine.qml` driving
`linux-wallpaperengine`. Both surface in `modules/panels/WallpaperPanel.qml` and
`modules/settings/pages/WallpaperPage.qml`.

- A gallery entry is a **string (image path), a scene object, or the action
  card**. Delegates branch on the ENTRY's shape, never the images/scenes flag:
  during a tab switch the flag flips while the outgoing delegates still exist for a
  frame, so a string would get asked for `.id`.
- `linux-wallpaperengine` has **no IPC**; every option is a startup argument, so
  changing one means relaunching the scene. Options are collected and spent by one
  explicit Refresh — don't apply on change, or a slider drag restarts the
  wallpaper per tick. `--layer background` is load-bearing: the default `bottom`
  sits above the background layer and buries `CavaBG`.
- **A Workshop "Preset" is a real item** (`scripts/wpe-scan.py`, `python3 scripts/test-wpe-scan.py`):
  no `file`, a `dependency` on another item and a `preset` blob of its property values.
  The renderer has no preset concept, so the item carries `base` + `props` and plays as
  `--bg <base>` plus `--set-property`. `props` keep only keys the base's schema declares
  (the rest of the blob is Wallpaper Engine's own per-wallpaper settings). The renderer
  reports the BASE in argv, so `_parseRunning` maps it back to the configured preset —
  otherwise Refresh re-applies the plain base. A preset whose base isn't installed is
  still skipped (counted). **Colours go to the renderer as `r g b` floats, never `#rrggbb`**
  (`WallpaperEngine._wire`): its `ColorBuilder` reads a 6-digit hex as RGBA, so `#dcddff`
  came out cyan — this hit every scene's colour override, not just presets. Read from the
  renderer's source at the installed commit. **A preset's pictures are `.tex` files, not
  properties**: a `scenetexture` value via `--set-property` is stored and never read. The
  scene binds a picture with a material `"usertextures": ["customimageleft"]`, which the
  renderer resolves as a texture NAMED that — `materials/customimageleft.tex` in any
  mounted folder. `wpe-scan.py` writes each picture as a
  TEXV0005/TEXB0003 `.tex` (the image embedded as-is; stb_image decodes it) into a project
  folder built for the preset, `$XDG_CACHE_HOME/quickshell-quicktest/wpe-textures/<id>/`
  (the base's `project.json` as a REAL copy, its `.pkg` symlinked), and `_launchCommand`
  passes that as `--bg` instead of the base — which also makes argv name the preset.
  **Not the renderer's cwd**: the Arch package's `/usr/bin/linux-wallpaperengine` is a
  wrapper that `cd /opt/linux-wallpaperengine` first (tried, and it didn't work).
  **`project.json` must be a copy, not a link**: the directory adapter `canonical()`s
  every path and rejects one that leaves the mounted folder; the `.pkg` is fine (its
  adapter opens the file itself). A base that isn't packed (loose files) gets no
  pictures. One `--bg` per screen, so each preset keeps its own. Layout read from
  `TextureParser.cpp` and round-trip tested, **not yet seen rendering**. The scene's
  scripts also fail in this renderer (`layer.update: TypeError`, tens of thousands of log lines), which is why its clock/words/log windows stay empty —
  not the shell's to fix.
- It is an **optional AUR build and may not be installed**.
  `WallpaperEngine.blocker()` is the gate.
- **Removing a scene cannot unsubscribe** (2026-10-30): the subscription list is on Steam's
  servers (`appworkshop_431960.acf` lists installed items only), and the only local route,
  Steamworks `UnsubscribeItem`, needs a `libsteam_api.so` the repo may not ship. The Steam CEF
  debug port could POST it, but it is unauthenticated (the shell no longer opens it for anything),
  so it is not the route. `WallpaperEngine.removeAndUnsubscribe(id)` is the one entry: it opens
  the item's page (`openWorkshop`: inside Steam via `steam://openurl` when `pgrep -x steam`, else
  the browser), deletes the files, and remembers the id in `Config.wpeUnsubPending`.
  `stillSubscribed(id)` = pending AND installed again after a rescan, which the UI words as
  "Steam put it back". Applying the scene clears the id. Unverified on a live Steam.
- The renderer's log is a FILE, not a pipe: a detached child inherits Quickshell's
  stdout, and its first write after Quickshell closes the read end is a silent
  SIGPIPE death ~1.6s in. Matching is on the unhyphenated name anchored to a path
  boundary — Linux truncates `comm` to 15 chars, so `linux-wallpaperengine` and
  the unrelated `linux-wallpaper-engine` GUI are both exactly `linux-wallpaper`.
- Wallpaper Engine's logo comes from Steam's own cache, never vendored — someone
  else's trademark. `WallpaperEngine.logoFile`; absent when the app isn't owned,
  so every consumer needs a fallback.

- **Material Wallpaper** (`Config.wallMaterial`; 2026-10-17, built, never loaded): End-4's default
  wallpaper is a fixed PNG of tonal Material shapes, so it ignores the palette. This draws the same
  idea live: `components/MaterialWallpaper` fills a screen with the composition in
  `services/materialwall.js` (`bun scripts/test-materialwall.js`), each shape the palette's base mixed
  toward a role by a `tone`, read from THAT screen's roles. It sits in `WallpaperView` over the picture
  and UNDER the water, with the parallax framing (zoom as a scale, so a glide doesn't rebuild the
  Repeater). Shell renderer only (awww draws a file, not shapes).
  - **A third wallpaper kind, and the last one applied wins.** `Wallpaper.applyMaterial()` stops a
    running scene, forgets the workspaces' own pictures and turns scene autostart off (what choosing a
    still does). A picture applied over it takes the flag off as its water LANDS
    (`_materialOffOnLanding`, the same trick as `_stopSceneOnLanding`: the shapes fade under water that
    already covers them), and a scene starting takes it off (`onRunningChanged`), so the flag is never
    left on under something that covers it. The shuffle timer skips it, like a running scene. It is
    refused while Game Mode holds the wallpaper (`materialBlocker()`, which also names awww).
  - **Two doors, one call.** The Wallpaper panel's third tab (Material — a `view`, not a `source`, so
    the gallery's branches on `source` are untouched) and Settings › Wallpaper's tile both go through
    `applyMaterial()`. The tab shows the live preview (the same component, in the screen's aspect) and
    the style (below). The preview shows it whether or not it is applied; changes are live on the
    desktop when it is.
  - **The tab is two cards, like the hero strip**: the picture with Apply / Shuffle and the awww
    fallback toggle, and a card of four pages — Looks (presets + Mirror), Colour (role swatches, Contrast,
    Ground tint), Shapes (a slot chip, a grid of the 19 forms drawn from their own outlines, Softness,
    Size) and Motion. The style is read as ONE flat object (`services/materialwall.js` `STYLE`,
    `CONFIG_KEY` says where each field lives in Config), so a LOOK (`PRESETS`: Classic, Calm, Bold, Duo,
    Sunny, Drifter) is a few fields over the defaults, "Reset style" is the default look, and
    `lookOf()` lights the look currently in force (none once you tweak). A look leaves the seed alone.
  - **Saved looks, and the lock** (`services/MaterialPresets`, eager from `shell.qml`; `bash
    scripts/test-material-presets.sh` runs the real service against a stub Config/ColorScheme). The Looks
    page lists the built-in looks, then the user's own (`Config.wallMaterialSaved`, a whole style with its
    seed; saving under an existing name replaces it; a hover × arms and then removes it). A look has a
    KEY — a built-in's id, or `my:<name>`. The lock is the colours panel's twin for the picture: it LINKS the
    look in use to the colour scheme the shell wears (`Config.wallMaterialLinks`, scheme name → key), in the
    panel header and on the Looks page; a mix that is not saved is saved first, under the scheme's name. Both
    maps are read through `MaterialPresets` (`normaliseStyle` clamps and drops what a hand-edited config
    got wrong; a link to a look or scheme that is gone is ignored/pruned — the latter only once the library
    has read something, so a failed read forgets nothing).
  - **Which scheme is worn is read back from the colours**, because nothing records it (an unlocked scheme
    is a staged palette the next wallpaper replaces): `palette.js findScheme` picks the saved scheme whose
    variant for the current mode is within 3/255 per channel of `Colors.fileData` (the closest bundled pair
    is 12). A wallpaper change makes it "" and a light/dark switch re-reads it, so neither is "applying" a
    scheme: `_last` is only forgotten after 8 s of "".
  - **When a link loads.** A scheme becoming the worn one while Material is on; or Material being applied
    while a linked scheme is worn, but only over a style that IS one of the looks (an unsaved mix is the
    user's, and Apply puts it on screen as it is). Never at start-up — the baseline is taken once the library
    and the live palette have both been read. Inside `wornScheme`'s own change signal read `wornScheme`, not
    `linkedKey`: a binding that depends on it has not followed yet (this loaded the OLD scheme's look; the
    scratch test caught it).
  - Applying a look sets ~15 Config values one by one, so `MaterialWallpaper` lays out once per event-loop
    turn (`Qt.callLater` on a key of its layout inputs) instead of once per value.
  - **It is reflected wherever "the current wallpaper" is shown**: the panel's and Settings' hero strips
    (a live thumbnail, "Material Wallpaper · Live", no gallery tile marked current, the header note says
    applying a picture replaces it), Settings' DesktopMap, the workspace cells and the picker (Material is
    on every workspace), the lock screen's backdrop (drawn, held still, through the same blur) and the
    widgets' glass (sampled from its own drawing instead of the picture). The palette still comes from
    the last picture — Material is drawn FROM it — and the hero says so.
  - **Shapes are Material's own, by slot.** `services/materialwall.js` holds 19 of the Material shape set
    as vertex lists with a radius per corner (soft burst, cookies, clovers, flower, gem, ghost…) and
    rounds every corner with a real circular arc (corners sharing a short edge give way in proportion).
    The composition names SLOTS (`stack`, `centre`, `side`, `corner`), not shapes; the Shapes page picks a
    form per slot and `""` means the slot's own, so a default is never baked into the config.
  - **Colours are roles, never hexes.** Main colour and Accent shapes (was Second colour) pick from `Config.accentRoles`; shapes
    marked `alt` (the second stack, the edge shapes) wear the second one. Contrast, softness, size and a
    seeded Shuffle shape the rest. Ground tint (0–0.3) washes the ground behind the shapes with the first
    colour; Mirror flips the whole picture left to right (inside the snapshot's item, so the fallback
    still is flipped too).
  - **Motion is one clock.** Drift and Spin advance `t` (a `FrameAnimation`, scaled by Speed) and every
    shape reads its own place and turn off it (`wander`, `spin`: pure, tested). Off by default — a frame
    loop on a full-screen surface — and stopped while a fullscreen window covers the screen or Game Mode
    holds the wallpaper. (Measure it before leaving it on: not yet profiled.)
  - **It stays when the shell is not up** (`Config.wallMaterialFallback`, on by default). Each
    `WallpaperView` renders a still of what it shows (its screen's palette and style, physical pixels,
    2.5 s after the last change) into `$XDG_CACHE_HOME/quickshell-quicktest/material/<output>.png` and
    `MaterialFallback` has `scripts/material-fallback.sh` hand it to awww, which is a daemon of its own and
    outlives the shell (`bash scripts/test-material-fallback.sh`). awww and the shell both draw on the
    background layer and the later to map is on top, so when the script had to START the daemon every
    view remaps over it (the same picture, so nothing is seen). Turning Material off stops the daemon only
    if the script started it. Not covered: a login where the shell never starts (nothing has started
    the daemon then) — `awww-daemon` + `awww restore` from the compositor's autostart would.
- **The album colour scheme** (`services/AlbumScheme.qml`, decoded by
  `services/albumscheme.js`, extracted by `scripts/album-colors.py`, tested by
  `scripts/test-albumscheme.js`) re-themes the shell from the current track's
  cover art. `Colors.fileData` is the palette on disk; `Colors.data` is that
  merged with `Colors.overlay` (the album overlay). Two reaches:
  **shell-only** (default — `Colors.overlay` in memory, nothing written) and
  **system-wide** (`Config.albumSchemeSystem` — writes `colors.json` and runs
  `reload-theme.sh`). `Config.albumSchemeLock` pins the album palette while music
  plays so other schemes don't overwrite it. It's eager-loaded in `shell.qml`
  because it must theme while music plays and nothing is on screen; inert while
  `Config.albumScheme` is off. **Per-wallpaper saved palettes** live in
  `theming/wallpaper-palettes/<key>.json` (key = image basename or `scene_<id>`)
  and are restored by `apply-wallpaper.sh` step 1c before pywal runs; clearing one
  regenerates the original with pywal. `scripts/wal-from-json.py` expands a saved
  palette into a full pywal `colors.json`. The "fade must outlive its data" rule
  applies here too — the panel's status chip and the wallpaper hero read a local
  copy, not the overlay directly.

- **A wallpaper per workspace** (2026-10-04; the user: the shell AND the apps on a workspace
  wear its wallpaper's colours — "fast and clean, no rough reloads"). No button
  (the user's call, 2026-10-05): **right-click a wallpaper** (picture or scene; tile, row, panel
  or page) = `Wallpaper.choose(value)`, a left click applies everywhere. The pick becomes
  `Wallpaper.pending` and the gallery FOLDS INTO `components/WorkspacePicker` (no overlay — the user's call): the panel's
  toolbar/hero/grid fade and drop away under the header (`swapped`, after `Motion.fast`), and
  BarPanelDock lets go of the 620×394 pin for the panel's `pinnedHeight`, so the card shrinks
  around title + picker; the page crossfades the same component in. Cells are each
  workspace's wallpaper DIMMED with its number big in the middle (the overview's cell); a
  chosen one reveals the new picture. Apply → `Wallpaper.assign` (`Config.wallWorkspaces`
  { "3": path }, validated on load; all ten = a plain apply); ↺ on a dotted cell =
  `forgetWorkspace`. A left click is everywhere and clears them all. **Apply stays up** on the
  current wallpaper while any workspace overrides it (`Wallpaper.everywhere`, a tile's `applied`);
  `isCurrent` still draws the highlight. Each monitor's `activeWorkspace` is watched by an
  Instantiator in WorkspaceTheme, because the rawEvent lands before Quickshell updates it
  (an unfocused monitor got no later event to correct the stale read).
  - **No wave on a workspace switch** (the user, 2026-10-05: a per-screen front was built — Infection
    `wsMode`, snapshot, shorter front — and read as "a split frozen frame"; removed). A screen's
    palette is assigned directly (`WorkspaceTheme._wear`) and the shell's own colour behaviours
    ease it. Don't bring a snapshot back for this.
  - **Scenes a workspace owns stay running** (`services/ScenePreload`, `Config.wpePreload`,
    default on, cap 4): one `scripts/wpe-window.py` renderer per scene in WINDOW mode, parked on
    `special:qswpe` by a RUNTIME window rule (title `^wallpaperengine$` — the renderer's class
    is empty; re-put on `configreloaded`), silent; `WallpaperView` draws a `ScreencopyView` of
    the window for its screen's workspace over the scene's still (`liveTop`). Switching = a swap
    of capture. **Measured** (throwaway probe, 2026-10-05): a renderer window on a special
    workspace kept its CPU use (13%→13%, ~250 ctx switches/s) and a capture reported content.
    The layer renderer is told those screens are picture screens (`_sceneScreens` maps them to
    ""), so a preloaded scene is never also relaunched there. **A scene that crashes in window
    mode** (3661092645, a 4K h264 video layer, segfaults in libmpv setup) is marked `failed` and
    plays from the layer renderer as before (`ScenePreload.usable`). Costs: every owned scene
    renders all the time at the biggest screen's size, silently (no sound; the shared scene is the
    exception, below), and the scene's own mouse/layer-depth reaction doesn't exist in a window —
    the parallax is the shell's pan of the whole captured frame. **They are DETACHED** (`setsid --fork`) and the next shell ADOPTS them (`_scan`: a
    bash `pgrep` that keeps only renderers whose stdout is one of our `quickshell-quicktest-wpe-*.log`
    files, so a preview someone runs by hand is left alone; `_reconcile` starts the missing, kills
    the stale, counts three starts without a window as failed) — a reload therefore doesn't load the
    scenes again, and they end with the session, preload off, a reassignment or Game Mode. Until the
    first answer a screen that expects a scene HOLDS what it shows (`ScenePreload.settling`, 6s
    cap → `WallpaperView.liveWait`) instead of flashing the scene's still. Switches between
    scenes use two capture slots and never pass through the still (the old one stays opaque until
    the new one is). **Unverified live:** the
    capture's frame rate and GPU cost, that the rule really keeps focus, how a screen with a
    different aspect crops (cover). `qs ipc … call scenepreload status`.
  - **The shared scene plays this way too** (2026-10-12, `WallpaperEngine.windowShared` /
    `windowPlanned` / `windowDrawn`). Why: the layer renderer gets its pointer from a `wl_pointer`
    on its own background surface (`WaylandMouseInput` in the library) — over a bare desktop only —
    and only moves a scene whose author set `general.cameraparallax`; **33 of the 36 scenes
    installed here have it false** (3 on: 3532169013, 3236329909, 3563328202; read out of
    `scene.pkg`), and `--disable-parallax` can only turn it off, never on. So "the Scenes switch
    does nothing" was true for nearly every scene. Now the scene applied as THE wallpaper
    (`sharedIsScene`, no per-monitor overrides, shell renderer, `wpePreload` on) is the first entry
    of `ScenePreload.assigned`, and `WallpaperView.liveId` falls back to it for a workspace with no
    wallpaper of its own, so the pan (`Config.wpeParallax`, strength = Pictures' zoom + pointer
    sliders) reaches every scene wherever the cursor is. **Costs, chosen with the user:** a flat
    pan of the frame instead of per-layer depth, a crop of `wallParallaxZoom`, the scene always
    rendering at the biggest screen's size. **Sound is kept** — `windowArgs` gives only the shared
    scene's window `--volume`/`--noautomute`/audio processing; every other window stays `--silent`.
    **The layer renderer steps aside**: `_shared().isScene` is false while `windowPlanned` (so
    `effective()` asks it for nothing and `_applyNow` doesn't launch), a layer renderer that is
    already playing the scene (a reload) is stopped by the workspace sync only once `windowDrawn`
    (the window has mapped), and `running`/`current` fold `windowDrawn` in so the ~60 readers (panels,
    Game Mode, palette, lock) are unchanged; `layerUp` is the layer renderer alone (WallpaperView's
    `sceneHere`). **Falls back by itself**: `ScenePreload.failed` (3 starts, no window) or `ruleBad`
    (Hyprland refused the parking rule) → `windowPlanned` false → the sync relaunches the layer
    renderer. Stop sets `_heldStopped` (no layer renderer to kill); the next apply clears it.
    An image applied over it keeps the window under the water until it lands
    (`Wallpaper._stopSceneOnLanding` is in `windowShared`; autostart is turned off AFTER the run is
    queued for that reason) and `WallpaperView._liveGone` releases the await. **Not a launch
    argument any more** for a window scene: `wpeParallax`/`wpeMouse` (no relaunch, no "Refresh"
    nag); volume/fps/particles apply on `_applyWindow` → `ScenePreload.restart`.
    **Unverified live (never loaded):** the layer→window hand-over (a beat of the still between the
    layer renderer ending and the capture fading in), scene→scene (the old window is killed at
    once — no crossfade), the capture's frame rate, sound from a parked window, the first-run race
    where `ruleOk` lands after the apply.
  - **Two layer renderers at once** (seen 2026-10-12: pids 5 s apart, the older one with parallax on,
    the newer `--disable-parallax`, both playing sound, ten minutes later). The retire-by-pid in a
    change lives in memory, so a hot reload inside the fade forgets it; the log showed several. The
    probe now keeps every pid and `_dropDuplicates` ends all but the newest after seeing more than
    one on two idle probes, 3 s apart. The cause is a theory; the net doesn't depend on it.
  - **The panel's layout is unchanged by design** (2026-10-05): a big preview + filmstrip, then a grid with
    a hover card, were each built and rejected by the user. The original grid + hero strip stays; don't
    redesign it again without asking what is wrong with it first.
    **Superseded 2026-11-05:** asked what was wrong with it, the user said the M3E round showed too little
    and chose a bento gallery, image-card tiles and a floating toolbar (see "Wallpaper panel round"). The
    two rejected layouts (preview + filmstrip, grid + hover card) are still rejected.
  - **A switch runs NO theming pipeline.** (The first cut ran apply-wallpaper.sh scoped per
    switch — a palette commit and the 1.7s frozen wave each time; reverted, don't go back.)
    The picture: WallpaperView's `src` is `Wallpaper.pictureFor(its monitor's workspace)` →
    its own cur/prev crossfade, per screen (needs the shell renderer). The palettes:
    `services/WorkspaceTheme` makes each assigned picture's palette AHEAD — and the picker's
    picture the moment it's clicked — with `scripts/workspace-theme.py palette`
    (stage-palette.py, apply-wallpaper.sh's exact arguments, into
    `$XDG_CACHE_HOME/quickshell-quicktest/ws-palettes/<key>/`, never committed; cached by
    picture+mode+held colours), remade on a commit (`Colors.fileData`).
  - **The shell, PER SCREEN** (the user: "make it separate by monitors" — focus follows the
    mouse here, and one shared palette flipped as it crossed screens): `Colors.screenOverlays`
    (screen name → palette) gives each screen a `PaletteRoles` of its own, and every visual
    file reads `Colors.of(QsWindow.window)` (2,894 reads in 234 files converted by script,
    2026-10-04). `_wear()` is imperative — on workspace/monitor events, palettes landing,
    assignments, the library loading — never a binding over Hyprland.monitors. A palette
    not ready yet keeps what that screen wears (no flash through the shared one). The
    shared palette (services, the cursor theme) never changes on a switch.
  - **Wallpaper Engine scenes too** (the user: "make sure WPEngine also works"). A
    workspace's own wallpaper is a path or `"scene:<id>"` (`workspacetheme.js parseOwn`; the
    Config loader validates both); the Choose-workspaces button works on the Engine tab
    (`Wallpaper.pickScene`). WorkspaceTheme hands `WallpaperEngine.workspaceScreens` (screen →
    the scene its active workspace owns, "" for a picture of its own; unlisted = follow the
    shared wallpaper), and `effective()` (`workspacetheme.js effectiveScenes`) is what each
    screen plays. The renderer has no IPC, so a new map is a RELAUNCH through apply()'s own
    crossfade (`_relaunch`: old keeps playing until the new maps and fades, then is retired by
    pid), `syncMs` (450) after the last switch, compared against what argv says is playing
    (`_runningMap`, presets in argv's base-id terms) so an unchanged map never restarts.
    `_skipPaletteOnce` keeps the shared palette out of it. In ws mode the launch is one
    `--screen-root` per scene-playing screen (no spans), and a picture workspace's screen
    isn't given to the renderer at all. WallpaperView decides PER SCREEN in ws mode
    (`sceneOn(name)` + `coversScreen(name)`): it keeps the scene's still
    (`Wallpaper.displayOf` → `WallpaperEngine.stillFor`/preview) up until the renderer
    really covers that screen. "The shared wallpaper is a scene" = `Config.wpeAutoStart`
    with a scene configured (an image apply turns it off); the sync does nothing unless a
    workspace has (or just had) its own (`_wsTouched`), so a scene started by hand is left
    alone. A scene's palette is its preview's (`workspace-theme.py palette --key
    scene_<id>`, a GIF read from its first frame), so a saved scene palette wins.
    Unverified live: how long a relaunch takes per scene (the load time is the scene's own).
  - **The apps wear their OWN workspace's palette**, wherever you are
    (`workspacetheme.js plan`, `bun scripts/test-workspacetheme.js`): borders by `set_prop`,
    terminals by pywal's sequences to their shells' ptys (`workspace-theme.py terminals`,
    a /proc walk), Discord/Spotify via `scripts/workspace-apps.sh` (apps-lib's own
    prep/publish on a private stage). Re-planned when assignments or palettes change, a
    window opens or moves, or a wave settles (it recoloured everything to the shared
    palette); a switch needs nothing. Each is told only when its palette changes
    (`_wears`). Browsers (Pywalfox reads the live palette) and GTK/Qt (system-wide) keep
    the shared colours. `python3 scripts/test-workspace-theme.py` (temp cache, real pywal,
    fake /proc). `qs ipc … call wstheme status`.

### A colour scheme per workspace, and the album on some workspaces (2026-10-18)

The user: apply colour schemes per workspace "similar to what the wallpaper panel does", and the same for Follow
album cover, with an option to apply only to the workspace Spotify is on. "It all depends if they're in the
workspace that is being targeted" — so every app follows the workspace it is ON, not the one you are looking at.
Both ride `services/WorkspaceTheme`'s existing pipeline, which now treats a workspace's colours as a VALUE
(`/path`, `scene:<id>`, `scheme:<name>` or `album`) and a palette made for it. Precedence on a workspace:
**album (if its scope names it) > its scheme > its wallpaper's colours > shared.** The picture stays under a scheme.

- **Schemes** (`Config.schemeWorkspaces` { "3": "Name" }, `ColorScheme.assign / forgetWorkspace / schemeFor`):
  RIGHT-click a card in the Colours panel's Library → `ColorScheme.pending` → the library folds into
  `components/WorkspacePicker` in its scheme mode (each cell keeps the workspace's wallpaper, dimmed; a chosen one is
  washed with the scheme's background and gets its colour ribbon; it starts with the workspaces already wearing it).
  Left-click still loads it into the editor. A scheme is held BY NAME: saving over it updates its workspaces, a rename
  carries them (`_renameWorkspaces`), a delete lets them go. A card shows its workspaces. All ten is NOT turned into
  a plain apply (the wallpaper's is) — a plain apply of a scheme is temporary (the next wallpaper replaces it) and
  these persist, so they are different things. Only the scheme's own variant for the current mode is worn
  (`Palette.pickVariant`, the loader's rule); held colours are NOT laid over it, it is the scheme verbatim.
- **How a palette that is already colours becomes a file**: `scripts/workspace-theme.py palette-json` reads the
  document from the environment (`WS_PALETTE`, not argv), keeps only known slots holding `#rrggbb`, expands it
  (`wal-from-json.py`'s rule) into `ws-palettes/json-<hash>/out/colors.json`, same cache and prune as a picture's.
  No extraction, ~tens of ms. An entry carries `src` (the JSON it was made from): a scheme saved over, the mode
  flipped or the next track makes it STALE — the old one stays worn until the new one lands (no flash), and it is
  remade. `_schemeUnknown`: a scheme assigned while the library hasn't been listed yet is held, not read as deleted.
- **The album** (`Config.albumScope` "all" | "workspaces" | "spotify", `Config.albumWorkspaces`; Colours › Album ›
  Where): narrower than "all" is a THIRD reach — `Colors.overlay` stays empty and colors.json is never written;
  `AlbumScheme.scopedPalette` is published and WorkspaceTheme places it (per-screen overlay + every window,
  terminal, Discord and Spotify on those workspaces — so Discord's Vencord theme and Spicetify are restyled ON EVERY
  TRACK CHANGE while it is on; the user chose "Everything" over borders+terminals only). "Everything" (system-wide)
  is ignored under a scope and its control is disabled with the reason — it IS the global files. Moving between
  reaches cleans up (`_rescope`: global→scoped drops the overlay and, if system-wide had written the album, regenerates
  the wallpaper's palette). GTK/Qt and browsers can't follow one workspace (one system theme), as with wallpapers.
  `Chosen workspaces` asks straight away when none are chosen; the picker's album mode REPLACES the set.
- **"Spotify's workspace"** is read from the `hyprctl clients -j` WorkspaceTheme already runs on window events
  (`openwindow` / `movewindowv2` / `closewindow`), not from `Hypr.windows` — that only refreshes while something holds
  it. It is looked for while the scope is "spotify" even with nothing playing (`_watchSpotify`), so the panel can say
  where it is. Spotify is matched by `contagion.js kind()` (class `spotify`).
- Diagnose: `qs ipc -c ~/.config/quicktest call wstheme status` (now `albumOn albumWs spotifyWs`) and
  `… call albumscheme status` (`scope=`). `python3 scripts/test-workspace-theme.py` covers `palette-json`.
- Unverified live: none of it has been loaded. The picker's scheme/album cells, the Where control, what a track change
  costs with Discord/Spotify restyled, and that Spotify's workspace follows the window.

### The depth clock (`Config.wallDepth`; 2026-10-29, rounds 1–2, built, never loaded)

A big clock drawn BETWEEN the picture and whatever stands in front of it in the picture (a subject's hair,
a raised leg, a butterfly), so the time reads as part of the scene. Idea from dhruvinsh/dotfiles (r/hyprland);
that repo has no licence, so the code here is written from the description, not copied.

- **The mask** (`scripts/wallpaper-depth.py`, run by `services/WallpaperDepth`; still called `cutout` in the entry): a grey+alpha
  PNG at the wallpaper's own size (~0.3 MB), opaque only where something is nearer than the plane under the clock (Depth Anything V2 **small**, Apache-2.0) or is
  the main subject (BiRefNet via rembg: the crisp outline, which is what carries an illustration). Maps are cached per
  wallpaper (16-bit PNGs), the cutout and the clock's place per wallpaper AND screen aspect, because a cover-crop moves what
  is behind the clock. A wallpaper edited in place is noticed by mtime. The script's one json line names the image, aspect and
  clock it answers (`image`/`aspect`/`clock`), because a Process's stdout can close after its exit.
  **Why a mask and not the picture's own pixels over the clock (round 3, 2026-10-29):** the first two rounds drew a copy of the
  picture, clear except over the foreground, on top of the clock — and it was "very noticeable". Measured headless (the same
  picture alone vs with the copy over it, diffed): Qt scales and premultiplies an image with alpha, so the copy differed from the
  picture under it by up to 47 levels along the WHOLE subject (an outline) and by noise in every soft zone. Nothing the mask
  does can show except the clock, cut: `components/DepthMasked` — the clock in a layer, a ShaderEffect (`shaders/depthmask.frag.qsb`,
  source `depthmask.src.frag`: `out = clock × (1 − mask.alpha)`), and the mask as a plain hidden `Image`. The mask is cut by the
  script to the screen's shape (`cover_box`, the crop PreserveAspectCrop makes), so it maps onto the clock's box edge to edge and
  the shader has no framing maths.
  **Round 4 — "it doesn't render the clock":** round 3 used `MultiEffect`'s mask with the mask in an INVISIBLE LAYERED item, and the
  clock drew nothing at all. `shaders/liquidglass.src.frag` already says why: an invisible layered source yields a 0x0 texture and the
  effect draws nothing (measured there, then repeated here; MediaPanel's `artMask` and GreetScreen's `avatarMask` use the same
  invisible-layer pattern and are worth a look). A bare hidden `Image` as the source is the ordinary idiom and has a texture.
  **A mask that has gone missing means no occlusion at all** (the clock shows whole, in front): the script used to delete the
  previous placed mask when you placed the clock again, while the running shell still remembered the answer for it, so going back to
  that spot (the "Top right" preset) pointed at a deleted file — `DepthMasked: the mask could not load`. Now: the script keeps the 8
  newest placed masks (`KEEP_PLACED`) and re-makes any cached answer whose file is gone or whose `fmt` is old (`FORMAT`, 2 = mask;
  answers from rounds 1–2 are redone on next use, ~1 s each with the maps cached); and a mask that fails to load tells the service
  (`DepthMasked.failed` → `WallpaperDepth.stale`, once per answer), which forgets it and asks again. Mask files carry the format in
  their name (`…-f3.png`), so an older one is never mistaken for a newer one by Qt's image cache, and the format-1/2 file is deleted.
- **The mask's edge, analysed (round 5, "the pixels are noticeable")** — measured on Furina's foot, in `scratchpad` experiments:
  - *Cause 1, the staircase:* the first version took rembg's `post_process_mask=True`, which THRESHOLDS the model's soft output to 0/1 at
    the model's own 1024 px (the cached map held exactly two values), then stretched to 4K: a step every ~3.75 px along every edge.
  - *Cause 2, tightening alone doesn't cure it:* the model's contour is stepped at its own grid, and any steep curve over it shows the
    steps again (wobble ~2 px). Now the soft output is **smoothed first** (three box passes of radius 3, ≈ σ 3.5 px: the grid step), then
    tightened by `smoothstep(0.35, 0.65)`: curvature smoothing, edges stay put, wobble drops by more than half, the edge is ~2–3 px of
    anti-aliasing. Subject map is `.subject3.png` (`.subject.png` = thresholded, `.subject2.png` = soft unsmoothed; both deleted).
  - *Tried and dropped:* a guided filter against the picture (r 2–3, several eps), to snap the edge to the line art — it haloed 8+ px
    around the foot, because subject and ground are both near-white. A second model run on just the clock's region (more effective
    resolution; sharper toe) — ~17 s per spot, which would make dragging the clock slow.
  - *Then, at display time:* `Config.wallDepthSoft` (Edge softness, default 1.2 px) blurs the occlusion's own edge in the shader with a
    3×3 binomial kernel on the COVER (not the clock), so what you see is a soft cut, not the mask's pixels.
- **Where the clock goes** (round 5): a 3×2 grid, not three spots, each judged on overlap AND on how readable text will be over the part of
  the picture that stays visible (`legibility`: calm = low luma spread, clear = far from mid-grey; `ROW_COST` keeps the top row unless
  another is clearly better).
- **A text colour that always reads** (round 5): `services/depthink.js` (`bun scripts/test-depthink.js`). The palette's colour is a
  PREFERENCE; what is drawn is the first that reaches 3.5:1 (the time) / 4.5:1 (the date) over the picture's measured brightness, else the
  best one pushed toward black or white by as little as it takes. `luma` (mean) and `spread` come from the script.
- **Remembered across restarts** (round 4, "make it cache"): every answer is written to `$XDG_CACHE_HOME/quickshell-quicktest/depth/index.json`
  (2 s after it changes; entries carry their mask `fmt`, and one of another format is not trusted — `WallpaperDepth.formatWanted` must
  equal the script's `FORMAT`, which the test checks) and read back at start, so a reload no longer begins with the clock waiting, breathing, for a python process
  per wallpaper — it rises at once. Only "ready" and "none" are kept. Not noticed: a wallpaper edited in place under the same path
  (its mask is stale until the cache dir is cleared). Measured earlier: a cached script run is ~25 ms, a new aspect or placement ~1 s,
  a new wallpaper ~27 s on the CPU; the library pass (Settings › Prepare the library) is what keeps the last one off the user.
- **The place**: automatic = the first of top-centre / top-left / top-right whose box (40% × 36% of the screen) the foreground
  covers ~20% of (`TARGET_OVERLAP`), penalised past 45% so the time isn't hidden. Or yours: `--clock X,Y`, kept per wallpaper in
  `Config.wallDepthPlaces` (`WallpaperDepth.place/unplace`) — the mask is then measured at THAT spot (~1 s, maps cached), and
  its cutout is named for the spot so Qt's image cache can't keep the old one. Under 1% covered = `state: "none"`: the clock is
  still drawn, plainly, in front. The text colour comes from `luma` (how light the picture is behind the clock) through
  `WallpaperDepth.ink(roles, luma)`: the palette's darker end on a pale picture, the lighter on a dark one, whichever way the
  scheme runs — or the user's pick (accent / palette text).
- **Look** (round 2): the lock screen's pairing — `Tokens.fontBlock` ExtraBold digits (mono, so a minute change never moves the
  layout) over a quiet, opened-up date — at 23% of the screen's height × `wallDepthScale`. The lock's code is ExtraBold even
  though its comment says "light, not bold"; this follows the code. 12-hour and date on/off are `wallDepthHour12` / `wallDepthDate`.
  The size is NOT part of the mask's judgement: the box measured is the default size's.
- **Motion** (`WallpaperView`, the `depth` item; a small state machine — read its header): `shown` is a held copy of the entry on
  screen and `want` is the entry asked for (a "ready" or "none" entry, `ghost`, or null). Coming in, the clock waits for its mask
  to decode (never seen whole for a beat), then RISES from below, decelerating on `Motion.emphasizedDecel` with a touch of scale;
  the digits roll (`RollText`). While a picture is analysed the clock waits where the last one was, **breathing** (ghost), still cut by the old
  mask when it is the same picture (it has not moved) and uncut for a different one (wrong shape); the answer glides it to its place
  (`Motion.glide`) and the new mask replaces the old once decoded — no jump. A different picture's clock sinks first (`leaveAnim`).
  The mask is not faded (a mask has no opacity): it is switched while the clock is unseen, or swapped for a near-identical one.
  **Layered**: the box rides the picture's zoom and pan, and the clock is pulled back against that pan by `wallDepthDepth` (0 rides
  it, 1 stays put on the screen), so a workspace switch or a pointer drift slides it behind the subject. It needs
  `wallParallax` on; without parallax there is no pan to layer against.
- Off while a scene, the Material Wallpaper, the game card or a change's water is up (the water brings the new picture in, and a
  clock for it would sit over the old one); back when the water hands over.
- **Setup**: a private environment (`scripts/wallpaper-depth-setup.sh`: `uv`, Python 3.13 because onnxruntime's wheels
  trail the system Python, ~1 GB with the models) under `$XDG_DATA_HOME/quicktest/depth`, built by the "Depth clock" tile in
  Settings › Wallpaper on first press. `WallpaperDepth.blocker()` says why it can't run (no `uv`, not set up). Nothing is
  installed system-wide: removing it is `rm -r` of that folder plus `$XDG_CACHE_HOME/quickshell-quicktest/depth`.
- **Settings › Wallpaper › Appearance**, while it is on: a "Depth clock" card with `components/DepthPlacer` (the picture and the
  masked clock in miniature — drag the clock; it runs behind the subject as it goes, commits once, on release, and stays where it
  was dropped until the new answer lands; `preventStealing` because the page scrolls), four preset spots, Size, Depth, text colour; tiles for
  Date and 12-hour; and "Prepare the library" (`wallDepthPrepare`): every still is analysed ahead at `nice -n 19`, one at a time,
  user-waited jobs first, paused while Gamemode is active (retried each minute). A cached wallpaper answers in ~25 ms.
- **Measured** (Furina.png, 3840×2160, RX 6700 XT so CPU): ~27 s the first time with the small model, ~1 s for a second screen
  shape or a placed clock, instant when cached. Base model gave the same position (0.74, 0.08) and 25% vs 24% overlap, so small is
  enough. `python3 scripts/test-wallpaper-depth.py` covers the box mapping, the alpha, the choice, `--clock` parsing and `luma`.
- **Unverified**: all of the QML (never loaded). **The mask's rendering in particular**: this machine's headless Qt (the offscreen platform) draws no ShaderEffect or
  MultiEffect at all — even a passthrough of my own — so the shader has been compiled (`qsb --qt6`) and read, never seen. If the clock
  is hidden everywhere, shown over the subject, or upside-down against the mask, it is `depthmask.src.frag` (the two samplers share
  `qt_TexCoord0`). Also: the motion state machine (commit / morph / leave, and flipping back mid-sink), the
  ghost's breathing, `RollText` at this size (its half-line travel inside clipped cells), `Tokens.fontBlock` at this size, the
  placer's drag, the setup tile's states, the Bento layout with the new card, the library pass, and a 4K cutout's decode cost.
  A later idea: a shadow cast by the subject onto the clock.

### Widgets per wallpaper (live layouts; 2026-10-30, built, never loaded)

A wallpaper can have desktop widgets of its own. `services/DesktopWidgets` › "Live layouts per wallpaper" has the model;
Settings › Widgets › Content › **Presets** drives it, below the saved-preset chips (acts on the wallpaper the chosen
screen shows now). The UI calls this a wallpaper's "own widgets", never a "layout" — that word was shared with the
saved-preset feature above it and nobody could tell the two apart (restructure, 2026-11-01); the service and
`widgets.json` keep calling the binding a layout internally.

- **Live, not a preset applied on switch** (the user's call): a layout's tiles are ordinary records with `layout: "<name>"`
  (the normal layout has no field, so every older record is in it). Moving a tile or typing in a note on a wallpaper's
  layout is saved in place; switching is a filter; nothing is copied over anything.
- **Bindings** `{ wallpaper key → layout name }` live in `widgets.json` beside the tiles. A key is the wallpaper's VALUE —
  `~`-relative path, `scene:<id>`, or `material` — not a scene's still (that changes when its first frame is captured).
- **Per screen**: each `WidgetLayer` computes its key from ITS workspace (`DesktopWidgets.wallKeyFor(ws)`), so a per-workspace
  wallpaper brings its own layout. It holds the old layout while its tiles spring away (`WidgetFrame.leaving`), switches, and
  the new tiles pop in staggered (`staggered`). It publishes what it SHOWS (`DesktopWidgets.setActive`) — `forScreen`,
  collisions, the one-per-type rule, the settings map and `shown` all read that, so everything agrees with the desktop.
- **Data-loss traps closed**: the load-time de-dupe (`dropStacked`) keys on the layout too (a copied layout is the same type at
  the same spot — it would otherwise delete one); `applyPreset` replaces only the layouts on screen; `savePreset` saves what is
  on screen, without the layout field; deleting a layout returns what it removed for the page's undo.
- Unbinding keeps the layout (listed, can be bound again, or shared by several wallpapers); deleting is separate.
- Tests: `bun scripts/test-desktopwidgets.js` (layout key in the de-dupe, `uniqueName`, `wallName`).
- Unverified (never loaded): the swap choreography, the first-answer-at-start being instant (`_settled`), per-workspace switching.

### Music effects (`Config.wallFx`; 2026-10-31, built, the drum detection running live)

The user: effects that "go along with the music, kinda like cava … Glow, Blur, Zoom, Shake, Pulse, Glitch,
Ripple and Bloom … not only images but also Wallpaper Engine". Picked: per-effect switches with strength,
a master intensity, and presets. Then, more than once: the effects "feel off or slow compared to the song"
— the reason for the beat clock below.

- **One pass over everything the surface draws.** `WallpaperView`'s content Item (`content`: the pictures,
  the depth clock, a captured scene window, the material wallpaper, the water) is the source of
  `modules/desktop/WallFx` — a `ShaderEffectSource` (mipmapped, `hideSource`) drawn through
  `shaders/wallfx.frag`. So a Wallpaper Engine scene gets the effects exactly when the SHELL draws it (a
  scene playing from its window, ScenePreload); a scene the layer renderer draws is another program's
  surface (`shellDraws` false) and is untouched. Under the Game Mode card, so that still covers it.
- **Nothing while nothing moves**: `allowed` (`shellDraws && !covered && !gameCard`) gates acquiring
  `services/MusicPulse` (refcounted; `MusicRim` holds it too), which listens only while an MPRIS player
  that isn't Discord is PLAYING and Game Mode is off. `active` (wanted, and live or still winding down) is
  the one switch for the texture and the shader; off, the content draws as it always did. WallFx samples
  `amounts()` once per drawn frame (a FrameAnimation while `active`), not in a binding: MusicPulse moves
  ~90 times a second a field at a time, and a binding re-ran it per field.
- **The music — the drums, heard** (`scripts/music-pulse.py`, `python3 scripts/test-music-pulse.py`, 40
  checks). numpy, and `pw-record --raw --rate 48000 --channels 1 --format f32 --latency 256` on the
  PLAYER's node (`Audio.streamsFor`, so a call or a notification isn't music). 1024-sample Hann window,
  256 hop (5.3 ms); band envelopes normalised to their own recent peak (attack 8 ms, release 110 ms).
  Line out, every 2 hops: `level bass mid high kick beats flash bpm locked snare snares hat boom booms
  impact impacts`.
  - **One sound per effect** (the user, after the first beat clock: "each effect should have a sound it
    should trigger after, not all at once, it feels weird for the screen to be shaking and zooming
    without kicks"). Two causes: every hit effect followed the one `kick`, and the locked clock FIRED
    its predicted grid whether a kick was there or not. Picked: the drum-kit split, fixed (no per-effect
    picker) — see the effects below. Nothing fires unless heard. Rebound the same day — the user: zoom
    and shake "are the most intense so they should be Bass and Kicks, glitch and blur should also be
    rebound"; picked Shake → bass notes, Blur → snare, Glitch → the hardest hits.
  - **Kick**: kick-band (35–130 Hz) flux onset whose rise is ≥ 4× the snare band's (a snare's body
    leaks into the kick band). The **beat clock** is now a gate: `BeatTracker` finds the tempo (onset
    autocorrelation, 8 s, 70–180 BPM, prior 120) and phase (click-aware kick onsets — low rise × the
    570 Hz–4 kHz rise — folded over 6 s; NOT the top band, where off-beat hats over off-beat 808s locked
    the grid onto the 808s). Locked, a kick counts only within 40 ms / 12% of a beat of the grid, with a
    lower threshold there (`GATE_K` 0.8 — an 808 still ringing hides the next kick's rise; it was found
    up to 28 ms late); unlocked, only a clear kick (2.6σ, 250 ms apart). A syncopated kick off the grid
    is missed while locked — the price of not firing on 808s.
  - **Snare/clap and hi-hat**, measured on synthetic hits (band RMS per bin, first 20 ms): kick ~100 in
    the kick band, ~1.4 in 1.5–6 kHz; snare ~8 in 1.5–6 kHz, ~6 above 7 kHz, a 150–400 Hz body; clap ~7 in
    1.5–6 kHz, almost nothing above; hat ~4.5 above 7 kHz, ~0.1 below; 808 the kick band only. A snare is
    a flux onset in 1.5–6 kHz (2.5σ, 120 ms) rising ≥ 0.8× the hat band and ≥ 0.04× the kick band; a hat
    an onset above 7 kHz rising 2× the snare band, and not a snare. `flash` = a strong kick or snare,
    ≤ 3 a second.
  - **Bass note** (`boom`, Shake's): the kick band's ENERGY rising (1.8σ, 150 ms; per-bin flux fired on
    every 808 glide), at least `BOOM_LEVEL` 4 RMS (a clap's leak is ~1.3), not a snare's body, and not a
    kick — held 11 ms in case the kick is called a hop later, and never within 80 ms after one. Real
    track (150 BPM): 26 in 15 s, mostly one beat apart.
  - **Hardest hit** (`impact`, Glitch's): a kick or snare in the top 15% of the last 48 hits' strength
    (z over its band's mean), at least 1 s apart — rare on a loud track and a quiet one alike. `flash`
    fired 28 times in those 15 s, too often for Glitch.
  - Measured on real tracks (15 s each, recorded and deleted): a slowed phonk montagem at 110 BPM — 28
    kicks, 17 of the 18 locked ones on the grid, 27 snares mostly one beat apart (a clap on the beat);
    SNARE_K 1.8 had found 47 (half just over the threshold), so 2.5. A funk track at 135 BPM: 15 of 16
    locked kicks on the grid. Spectral flatness doesn't separate a snare in a mix (sustained sounds leave
    most bins flat); breadth (bins rising) didn't either. Latency: a kick found a mean 6 ms after it
    starts (9 ms over an 808). Cost: 3.8% of one core (Ryzen 5 5600X, Python 3.14), pw-record 0.2%.
  - **Sync** (`Config.wallFxSyncMs`, 0–300 ms, `--offset-ms`): holds every line back, for speakers slower
    than the screen; nothing can land before it is heard. Handed over 500 ms after the fader settles
    (each restart relearns the tempo).
  - **The QML side** (`MusicPulse`): probes `pw-record` + `import numpy` once (`dspOk`, `probed`); the
    helper's `running` is a binding dipped through `_cycling` for a restart (CavaStream's reason —
    assigning it would leave the helper running after the music stops); an exit of its own restarts after
    1 s, backing off to 30 s, and an exit WE caused (`_stopping`) is not one. The helper's counts restart
    with it, so `beats`/`snares`/`booms`/`impacts` are a base + its count. On stop, the fallback's state is seeded from the
    current values so the FrameAnimation's `rest()` eases down from where the helper left off.
  - **The fallback**, without numpy or pw-record: a CavaStream of the player's node tuned for beats (24
    bars, 40 Hz–8 kHz, sensitivity 100, noise reduction 0.1) into `services/musicpulse.js` (`bun
    scripts/test-musicpulse.js`, 18 checks): spectral flux over the lowest 4 bars, 1.5σ over its 900 ms
    mean, 160 ms refractory; a rough snare (bars above ~1.4 kHz) and hat (the top bar). cava can't tell a
    bass note from a kick, or the hardest hit from a strong one: there `boom` is the kick and `impact` the
    flash. The Effects page says which one is listening, and Sync is off with it.
- **The effects — one look per sound, the song decides** (third pass, 2026-10-31). The user: the looks
  didn't "portray the element that they should per sound", Shake "looks quite odd", the preset tiles
  all read Off, and "instead of presets, the effects should adapt to the song itself, letting the user
  change intensity". Then: "the blur should go away by itself when the song ends" and "make the
  overall animations smoother". `services/wallfx.js` (`bun scripts/test-wallfx.js`, 61 checks):
  - `SOUNDS`: kick → Zoom (punch + outward colour split) & Pulse; bass note (`boom`) → **Rumble** (a
    7–13 Hz tremble, gated per note: holds while the bass stays at 60% of its start, dies in 90 ms
    once it falls or after 1.2 s; NO zoom — the shader MIRRORS the edge instead, so the old
    zoom-by-twice-the-jolt on every bass note is gone); snare/clap → **Shockwave** (one
    derivative-of-Gaussian ring at 2.2 screen heights a second, fading over 250 ms); hats →
    **Shimmer** (3 px cells twinkling on bright areas, a new pattern per hat); vocals → Bloom;
    loudness → Glow; hardest hit → Glitch; **breakdown → Blur** (the drums dropping out; only with
    music under it — `level` ≥ 0.15 counts in full — so a song's end is not a breakdown; never on a
    kick, so the drop snaps sharp); strong hits → Strobe, OPT-IN only (photosensitivity warning).
    Ripple is gone (hats are ticks, not rings).
  - **No presets.** `MusicPulse.song` (`musicpulse.js songStep/songView/character`, `bun
    scripts/test-musicpulse.js`, 30 checks) keeps hit rates (τ 8 s, bias-corrected for the first
    seconds) per drum — hats counted off the `hat` envelope (on 0.6, re-armed under 0.3) since the
    helper doesn't count them — energy (kicks + 0.7 snares + 0.5 bass notes a second, / 3), and
    breakdown (drums of the last 1.5 s against the last 20 s, from 80% of usual down). Not the level:
    the helper normalises bands to a 4 s peak, so quiet stretches read loud again. Stepped per pulse
    while live, reset per track. `adapt(view)`: past an ordinary rate (`ORDINARY`) a hit plays
    √(ordinary / rate), floored 0.35; energy trades hits (×0.45–1) against washes (glow/bloom ×1–0.55).
  - **The user's say**: `Config.wallFxIntensity` (master) and `Config.wallFxMix` (id → 0..2 trim,
    absent = auto 1, 0 = off; strobe absent = off). Replaced `wallFxEffects` (a stale key is ignored).
  - **Smooth**: `amounts` is the target, `glide(prev, raw, dt)` follows it per effect (`GLIDE` rise/fall
    ms: zoom 25/140, glow and bloom 120/450, blur 600/160…); glitch and strobe pass straight through.
    Rumble and shockwave ease in over ~30 ms. `WallFx` keeps a per-screen `_motion` (`step`: rumble
    gate, shockwave age, clock), reset when it wakes so a stale count doesn't fire.
- **Fourth pass — the song's vibe** (same day). The user: "too intense in calmer parts of the song and
  when the drop hits it's quite underwhelming … the rumbling … should be playing when big bass kicks
  come … the principal goal is to make it match the song's vibe. Sometimes the effects should calm
  down." Cause, measured on a recorded cinematic track: every helper envelope is renormalised to a 4 s
  peak, so the calm part (sub band 16–20 dB vs 36–41 dB in the big part) read as loud as the big one,
  and the first cut gave calm tracks MORE glow.
  - `scripts/music-pulse.py` prints three more fields (19): `loud` (whole band) and `sub` (35–130 Hz),
    power over 300 ms in dB under the song's loudest so far (falls 0.1 dB/s, floored at
    `REF_LEVEL_DB` 17 / `REF_SUB_DB` 34 — one track's big part, this file's FFT scale; ranges 15 / 24
    dB), and `heavy` (the sub band's peak in the 35 ms after a kick, on `sub`'s scale; held). On that
    track: calm `sub` 0–0.18, big 0.7–1.0; kick `heavy` 0–0.24 calm, 0.8–1.0 big. 44 checks.
  - `musicpulse.js`: `section` = ½ loud + ½ sub (fallback: drums now vs the song), up in 150 ms, down
    over 1.5 s; a **drop** = section ≥ 0.7 and 0.3 over its 6 s average, after 6 s of song, ≤ 1 per
    8 s, fading over 3 s. Breakdown now also needs the section small (sparse drums under a full
    orchestra were called one).
  - `wallfx.js`: `vibe` = smoothstep(0.3, 0.85, section); hits keep 8% in a calm part, hats 15%,
    washes 30%; a drop boosts hits ×1.8 and washes ×1.3. The punch scales 0.35–1 with `heavy`; **rumble
    fires on kicks** (not bass notes) by smoothstep(0.65, 1, heavy). Zoom 0.14 × punch.
  - Replayed the track end to end (helper → song → effects, 60 fps, intensity 0.7): big part zoom
    ~0.055 and rumble 4–6 px, the drop zoom 0.089, glow 0.65; the calm part zoom ≤ 0.012, glow ~0.16, no
    rumble.
- **Fifth pass — missed kicks, the spammed ring, sync** (same day). The user: "the ripple [the
  shockwave ring] is constantly getting spammed, and the rumbling, zoom and pulse … miss some of the
  kicks. It still feels out of sync." Measured on a recorded 128 BPM funk track (30 s, deleted):
  - **Kicks**: 49 of ~64 found. A flux onset started the 140 ms refractory BEFORE the kick-vs-snare test
    and the gate, so a clap rising a hop ahead of its kick (or, unlocked, a first rising hop that wasn't
    "clear") hid the kick's real peak 5–10 ms later — strong ones (z 5–6.6), on the grid. Now only a
    CALLED kick starts it while locked; unlocked keeps the old rule (it is what kept the synthetic
    kit's off-beat 808s out). After: every kick once locked; misses only in the ~3 s before lock.
  - **The ring**: every clap/tamborim was a snare (75 in 30 s, 230–370 ms apart) and each restarted the
    shockwave. The helper's 20th field `accents`: snares among the strongest of the last 32 for how
    busy they are (quantile 1 − 1.2 / rate), ≥ 350 ms apart — a backbeat keeps every snare, that
    track 26 of 75. The shockwave follows `accents` (fallback: snares ≥ 400 ms apart).
  - **Sync**: `heavy` was reset to 0 at each kick and rebuilt over 35 ms, so every punch started small
    and peaked late; now the previous kick's value holds until the new one is measured. Kick glides
    rise in 8 ms (was 25). Replay: zoom peaks ~11 ms after the kick is heard. Bluetooth or a slow sink
    is the Sync fader's job.
  - Tests: helper 47, song 38, effects 78.
- **Sixth pass — the rhythm engine** (same day). The user: the snare "still quite annoying", the big
  hits "quite off rhythm and sometimes still miss some notes … I want a complex and reliable system".
  Picked (AskUserQuestion): our own RHYTHM MODEL (no ML dependency), the ring on BACKBEAT snares only,
  the big hits on SONG STRUCTURE. Built while the user was away and nothing played, so against
  ground truth instead of ears:
  - **The benchmark.** `scripts/synthkit.py` (the test sounds, moved, plus a produced kick, sidechained
    bass, cowbell, tamborim, crash, pad and whole arrangements: groove · breakdown · drop, at 128/130/
    174/90 BPM — EDM, phonk, J-core, boom-bap) and `scripts/bench-rhythm.py` (kick recall/precision/
    timing against the old detector, backbeat-ring recall/precision, drop placement; `--check` against
    floors, phonk on its own). `scripts/fit-rhythm.py` fits the two acoustic models from it.
  - **What it found, and fixed** (each measured, the comments say where): the tempo flipped between
    174/116/87 on a real J-core track (bare autocorrelation; now a metre comb — beat, 2, bar, 2 bars,
    half — at quarter-hop lags, a prior-free refinement, smoothed rival switching, a 6 s first guess);
    a 1024-sample FFT makes a 40–60 Hz bass swing ±6 dB a hop, so every bass note looked like kicks
    (now a band-pass + Hilbert envelope of 35–150 Hz at 3 kHz for the kick's ATTACK); candidates that
    opened on a threshold took pre-rises 30–70 ms early (now peak-picked events); a refractory started
    by rejected onsets hid real kicks (only accepted kicks start it); the beat clock's phase signal was
    dead on kicks whose click sits under its noise floor (the engine now feeds it its sure kicks and
    backbeat snares); boom-bap's "a of 2" kick dragged the grid (follow window 15%); funk percussion
    out-shouted the snare in the snare band (a fitted snare model — sustain, body, air); drops came
    0.2–2 s late or every 8 s on hip-hop (now judged on the drop's own kick after a quiet 2 s, scaled
    to the song's range); the loudness floor made quiet playback read calm (floors −10 dB).
  - **Results** (bench, three levels): kicks EDM 94–100% / 98–100%, J-core 100% / 98–100%, boom-bap
    92–100% / 86–100%, timing 1–7 ms (the old detector 2–92%); backbeat rings 62–96% at 100% precision;
    drops 12/12 exact, none false. Phonk 61–69% — its synthetic 808s rise out of near-silence at full
    flux while 808 tails shrink the kicks, so the 808s sound the bigger kick (the known weak case).
    A real J-core recording: tempo steady at 174 throughout; kicks median 14.5 ms off a steady grid
    (old: 22.3); 11 rings in 45 s where the funk track had rung 75 times in 30.
  - **Shown when heard.** The helper prints timestamped lines — `s` state (~94/s), `e` events (kick/snare/
    hat/drop/phrase with strength, heavy, role) and `latency` once (PipeWire's quantum + the sink's
    headroom and period, + 150 ms for Bluetooth; 32 ms on the USB headset). `musicpulse.js schedLine/
    schedAt` map its audio clock to the wall clock (the earliest arrival over 128 lines — PipeWire
    hands audio over in 21 ms bursts) and show each event at t0 + latency + Sync; envelopes are
    computed from due times, so a hit lands on the frame it's heard. Sync no longer restarts the
    helper. `MusicPulse.pulseAt(now)` is WallFx's per-frame read; a 16 ms Timer publishes the same to
    the properties (rim, Effects page). Glitch and Strobe follow drops and phrases (rows relabelled
    "Drops & phrases" / "Song changes", ids unchanged); a drop's or phrase's kick punches ×1.4.
  - Tests: helper 47, song/scheduler 46, effects 79; the bench `--check` passes. Helper cost ~6.7% of
    one core (was 3.8%). **Unverified**: all of it on screen and by ear — no reload happened, and
    the synthetic songs are only as real as synthkit's sounds.
- **Settings › Wallpaper › Effects**: the master tile, "Bars glow with the music", an Intensity card
  (the beat clock's state as its subtitle, Intensity, Sync) and the **Sound map** — a row per sound: a
  dot lit while it's heard, "Kick · Zoom & pulse", its trim fader ("auto" / "off" / %), an Auto chip
  when anything is trimmed, the song's character as the subtitle ("This song: Driving · kick-led").
- **Shader traps** (qsb's `--qt6` set includes GLSL ES 100): no `textureLod`/`textureSize` — the soft copy
  for blur/glow/bloom is `texture(src, uv, bias)` on the mipmapped source (sampled 1:1, so the bias is
  the level), and the texel size comes in as `texelX`/`texelY`. Rebuilt with `scripts/build-shaders.sh`
  (it compiles every `*.src.frag`; the others came out byte-identical).
- **Unverified**: the third pass's looks (rumble, shockwave, shimmer, breakdown blur), the glide feel,
  the adaptation's weights on real tracks (all tuned on paper and synthetic streams), whether each effect
  feels tied to its drum, the snare/hat detectors on more kinds of music than two, the look
  and strength of every effect, the GPU cost of the extra full-screen pass on two screens, mipmapping a
  full-screen NPOT texture every frame, the first frame of `hideSource` (a blink when music starts?), and
  how a captured scene looks through it.

## The wave (wallpaper & colour transition)

Ported from the user's other shell (2026-09-30), replacing a light band that swept
the bar left→right while colours snapped. A change arrives as ONE front from the
bottom middle of each screen: the new picture spreads like water, and the new
colours eat the old look off the shell on the same front, glowing in the new accent.
`services/WallWave.qml` (the one clock) → the WATER in `modules/desktop/WallpaperView`,
the INFECTION in `components/Infection.qml` (last child of every shell window), the
APPS in `services/Contagion.qml` (+ `contagion.js`, `modules/desktop/WaveCurtain`). One shape for all three:
`shaders/wavefront.glsl`, pasted into `wallwave` / `infect` / `infectglow` `.src.frag`
by `scripts/build-shaders.sh` (qsb; commits only the `.qsb`). Tests:
`python3 scripts/test-apply-wallpaper.py` (fake pywal CLI AND library, awww, gsettings,
pkill, curl on a temp PATH/PYTHONPATH + temp HOME — safe), `python3
scripts/test-stage-palette.py` and `test-palette-prefetch.py` (real pywal, generated
images, temp caches — byte-for-byte against the `wal` CLI), `bun
scripts/test-contagion.js`. Diagnose:
`qs ipc -c ~/.config/quicktest call wallwave status`; `… wallwave demo` plays the
whole thing with nothing changing.

- **Every theming run rides it through ThemeRunner** — `run(cmd, label, wave)` with
  `{ image, output, recolor, keep }`. Wallpaper, scheme, pins, rebuild, light/dark,
  scene palette: no per-caller wave code. Animations off (`WallWave.enabled`) → no
  wave, the scripts run the old way (awww's own transition first, instant colours).
- **The protocol is stdout lines**, paced by the script (env `QS_WAVE=1`,
  `QS_WAVE_FREEZE_MS`, `QS_WAVE_LAND_MS`): `WAVE=ready` (palette computed; the shell
  snapshots — script waits freezeMs) → `WAVE=go` (committed; shell reloads Colors,
  lets colour animations finish under the snapshots for `Motion.standard`, spreads —
  script waits for the water to land — see below) → `WAVE=done` (the real wallpaper
  is under the water). Exit
  = `finish()` (go + done), so a dying script can't leave the shell frozen. The
  freeze is taken as LATE as possible, so a cold 4s pywal run keeps the shell live.
- **colors.json changes ONCE per run.** It used to be rewritten 4–5 times (pywal, the
  black point, light mode, the override merge, the export) and the shell recoloured
  on each. Everything is built in `$XDG_CACHE_HOME/wal-stage` and committed by one
  rename in `scripts/wave-lib.sh` `commit_stage` (sourced by both scripts; flock'd,
  since a wallpaper and a scheme can run at once). `reload-theme.sh --committed` is the
  fan-out only. Apps run only after the water has landed, so nothing stutters it.
- **Speed (2026-10-01, the user: "optimize the living hell out of it").** Measured,
  script side: cached wallpaper palette-ready 289→~135ms and done 1.73→~0.73s; scheme
  1.57→0.47s; an uncached 5.6K picture 3.3s→~0.13s once prefetched; the wave's frozen
  hold for Discord/Spotify ~1–2s → see below. How:
  - **`scripts/stage-palette.py` is the whole palette in ONE process**: `wal -i`'s own
    calls with its parser's arguments (backend/sat/cst None, c16 False — the CACHE
    KEY), the black point, light fix, saved palette, override merge (it imports
    merge-overrides.py / wal-from-json.py, one copy of each rule) and ONE template
    render into `$STAGE/out`. It was five processes rendering every template twice.
    Exit 10 = every slot held. Its output is pinned byte-identical to the old CLI
    pipeline. The commit keeps the rendered set as `$STAGE/committed`; the fan-out
    `install_templates` (one cp + one mv, atomic per file, only if it IS the live
    palette — cmp) instead of re-running `wal --theme`, then `wal_env` does what
    `wal --theme` did besides rendering (escape sequences to every pty, pywal's
    reloads), in the background.
  - **Palette prefetch** (`scripts/palette-prefetch.py`, the user's yes): after every
    library scan and light/dark switch, `Wallpaper` extracts palettes for uncached
    library images — exactly `wal -i`'s cache entry, full-res, nice 19 + ionice idle +
    `MAGICK_THREAD_LIMIT=1`, never during a change. A test pins the entry to the CLI's.
  - **The fan-out is parallel** (`bg`, then `wait`): bounded by the GTK flip's 0.25s
    sleep, not the sum. Restart checks are one `ps` read.
  - **No `hyprctl reload` per change**: `hypr/scripts/wal-reload.sh --live` (the REPO
    copy, run by reload-theme.sh where the installed one exists; `QS_OVERRIDES` for
    its placeholder) writes palette.lua and sets the three colours it feeds by
    `hyprctl eval` (~5ms vs ~100ms + a configreloaded that re-applied the cursor, the
    cursor plugin and the wave's layer rule). One jq, hex-validated; a refused eval
    falls back to the reload.
  - **Cursor regeneration waits for the wave to settle** (`Cursor._afterWave`) and runs
    `nice -n 10` — it forked a pool over every core inside the 1.15s spread.
  - **A pick made during a run is queued** (`Wallpaper._queued`, newest wins) instead
    of silently dropped. `qs ipc -c ~/.config/quicktest call wallpaper apply <path> |
    status`.
  - **Every phase logs its time**: WallWave's lines end `(+N ms)` since prepare
    (freeze, palette read, go, landed, done); the scripts log each step's ms and
    `[fan-out] N ms, run total N ms`.
- **The infection replaces pixels, it doesn't overlay them.** `infect.frag` draws the
  snapshot with `blending: false` (+ discard where the front has passed), so a
  translucent surface (barOpacity, widget glass) can't leak the new colour through
  before the front arrives. `infectglow.frag` blends the AA edge, rim and burn over
  it. Colours: `glow` = `Colors.primary`, the hot line lifts toward `Colors.fg`, the
  water's foam toward `Colors.fg` — no white in any shader.
- **The snapshot is taken in FRAMES, not ms**: on freeze the Infection enters the
  scene drawing nothing (cover 0), `FrameAnimation` counts 3 frames, then covers.
  Covering before the capture records the cover — a blank window standing in.
- **windowX/windowY** place a window that doesn't fill its screen. Zone-respecting
  surfaces (WidgetLayer, DesktopClock: `exclusiveZone: 0`) add
  `Hypr.reservedOf(...)`; floating toplevels (Settings, Lyrics) are assumed centred.
  A NEW shell window: add an `Infection` last, or it snaps colour ahead of the front.
- **The widgets' glass sees the wallpaper as drawn** (2026-11-08): `shaders/liquidglass.src.frag` samples
  `components/WallBackdrop`, which rebuilds this screen's picture from `services/WallFrame` — each
  WallpaperView registers itself there under its screen name, and the backdrop reads its `zoom`,
  `glideTx/Ty` (the planes' own pan, snapped and gliding once) and `drawn` (the picture on the settled
  plane, so a change's water holds it; the workspace's own wallpaper follows). Before this the glass
  sampled the raw file, unzoomed, so with parallax on it refracted the wrong part of the wallpaper and slid
  against it. The Material Wallpaper is still sampled from its own held drawing (not panned). The same
  shader strokes the tile's border (the Surface's `border.color`/`Tokens.borderChrome`, lit upper-left)
  and reads the backdrop's brightness per pixel for the dim and the rim.
- **The water is WallpaperView's own** (it owns the parallax framing, so no jump):
  two slots = WallWave's two channels. `keep` says what happens at settle — the shell
  draws the picture next → `cur` adopts it (pixmap-cache hit, instant); awww or a scene
  draws it → the water fades off. Over awww/a scene it maps see-through for the
  change alone (zoom 1 when the shell isn't the renderer, to match awww's crop). A
  running scene under a change to a still is stopped only when the water LANDS
  (`Wallpaper._stopSceneOnLanding`) — stopped first, the old still flashed through.
- **Scenes get a CROSSFADE, not water** (2026-10-03, the user: the scene's still sat on
  screen for the seconds the renderer took to load, then the live scene replaced it and
  "adjusted"). `WallpaperEngine._applyNow` starts the new renderer ALONGSIDE the one
  playing (`snapProc` records the old pids first), the old keeps animating while the new
  loads, and the new maps over it — Hyprland's own layer fade (`fade`, speed 10, ~1s) is
  the crossfade. `_checked` (a 1s `pgrep` + `hyprctl layers -j`, matched on pid) sees it
  map; `fadeTimer` then `_retireOld` kills ONLY the recorded old pids (`pkill -f` would
  take the new one too). A failed new renderer leaves the old scene playing (and the
  particles retry runs alongside). The palette rides the wave (`_startColours`, `image: ""`) timed to the MAP: asked
  for at the map, the scene is already up before the front leaves (the wave takes
  `WallWave.leadMs`, measured, to get going), so a scene seen before starts its colours
  `loadMs - leadMs` after launch (`colourTimer`; per-scene load time smoothed into
  `statePath("wpe-load-times.json")`, the map timestamped from Hyprland's `openlayer`), and a
  new one at the map (`_gotMapped`). Started at the apply, colours changed seconds ahead of
  the scene and a failed scene left the old one in them. The new stream is muted by
  `application.process.id` until the old is gone (`_muteIncoming`; undone on every exit,
  PipeWire may remember a mute). `running` stays false while a scene loads over NOTHING
  (`_loadingBare`), or WallpaperView would hide the shell's wallpaper for the load.
  **Measured, not assumed** (throwaway probes under `/tmp`, 2026-10-03): a layer rule's
  `order = 1` sinks a surface BELOW an earlier one (`-1` does nothing); a rule on a
  namespace re-sorts surfaces already mapped, so it can't hold one of two same-namespace
  renderers under the other; layer rules take `namespace` and no `pid`. That is why the
  fade is Hyprland's, not a reveal. The wpe-stills / `--screenshot` machinery is now
  unused (flagged, not removed). Stills (images) still arrive as water.
- **Apps change under a CURTAIN** (the user, after the first cut: "the apps are
  slightly delayed, which breaks the whole illusion"). Flipping each app as the front
  touched its window was late — Hyprland's `border` leaf is a 640ms linear fade, a
  browser or Spotify repaints in hundreds of ms — and a near-full-screen window
  flipped WHOLE when the front touched its bottom edge. Now: at the freeze
  `Contagion` asks `hyprctl clients -j` (Quickshell only refreshes toplevels when told
  and never says when it's done — stale places would leave frozen copies where
  windows aren't) and `modules/desktop/WaveCurtain` (Top layer, per screen, mapped only
  for the wave) covers every looked-at window with its piece of ONE `ScreencopyView`
  of the output, through the SAME infect/infectglow shaders (`burn` 0.35 over apps).
  At `WallWave.paletteRead` every app is told at once, underneath — borders
  (`hl.dsp.window.set_prop`, blend.lua's slots, hex-validated addresses), kitty
  (SIGUSR1 per process; `commit_stage` wrote its theme), Discord/browsers/Spotify
  (`reload-theme.sh --app …`) — and the front reveals them already recoloured, pixel
  by pixel. `contagion.js` `plan()` (covers + where the front meets each window,
  inverting OutCubic — keep in step with `Motion.travel`/wavefront.glsl) and
  `decide()` (the flips, and how long the spread waits). No curtain on a screen (no
  capture) → timed flips from the LEADS estimates, as before.
- **The slow apps are STAGED before the freeze** (`scripts/apps-lib.sh`, sourced via
  wave-lib): `commit_stage` → `stage_apps` starts, in the background, Discord's
  script on a private copy of its theme (`--css`/`--colors` from the script's own
  `--css` default, then `/* pywal */` runs collapsed — the script appends three per
  variable per run and its theme had grown to 6 MB; 22 KB clean) and Spotify's pwspice
  + `spicetify refresh` from the STAGED palette (only when the extension is
  listening). Markers `$STAGE/apps/<app>.pending` → `.ready`. Contagion shows them the
  moment every window of that app is under an up curtain or off-screen
  (`_tryEarly`, `reload-theme.sh --app X --staged`: a rename for Discord, a POST for
  Spotify; exit 3 = nothing staged → the palette path), holding the spread from the
  FREEZE (WallWave holds are per token, valid from freeze). So the apps' own work
  overlaps the commit and settle. `unless_done` compares stamps against PREPARED_AT.
- **The spread waits for the slow apps, MEASURED.** Borders and kitty are small and
  steady: a fixed lead (`WallWave.delayGo`). Discord, browsers and Spotify are not —
  fixed leads were wrong both ways (the user: "works for most apps… fix it with
  discord and spotify"): Vencord re-reads a changed theme only after a 300ms debounce
  (`function ft(t,e=300)` in its patcher.js; QuickCSS gets 50). So each runs as a
  tracked Process and HOLDS the spread (`WallWave.holdGo`/`releaseGo`) until its
  script has exited plus `contagion.js AFTER[app]` (what the app does after), less
  the front's head start to its nearest covered window; `appWaitMs` (2.5s) is only the
  net for a hang. Each app's time is logged ("Contagion: discord recoloured in N ms")
  — tune AFTER from that. Only apps `reload-theme.sh --probe` says this machine can
  reach may hold (Zen without Pywalfox is just a border).
- **Spotify SAYS when it has repainted** — no AFTER. `recolor.sh`'s own live step
  needs a DevTools port the stock launcher never opens (its `spotify-spiced` wrapper is
  gone), so a running Spotify was never recoloured live. Now `reload-theme.sh`'s
  Spotify step POSTs the bridge's `/restyle`; the extension holds a poll open on
  `/events`, clones each theme sheet with a fresh `?v=`, drops the old one once the new
  has LOADED (no unstyled frame), waits two frames and POSTs `restyled`.
  `SpotifyBridge.restyled` → Contagion releases. Nobody listening (`restyle` line,
  `listening: false`) → no wait; `--probe` lists Spotify only while one is (`GET /`).
  Tests: `python3 scripts/test-spotify-bridge.py` (private bridge, free port). Measured
  live: request → painted in ~0.3s. What it took, all invisible from outside Spotify:
  - **The extension's startup threw in EVERY Spotify, for months.** `post("init")` read
    `Spicetify.Player.getProgress()` before the player existed; the throw ended the IIFE
    after the listeners were registered, so playback anchors still arrived and nothing
    looked wrong — but the 5s heartbeat and all later code never ran (the "heartbeat"
    anchors were `onprogress`'s). `post`/`trackInfo` are now total. Tell: no page ever
    sent an `init`.
  - **Only a no-cors POST with `keepalive` reaches loopback from Spotify's page.** A cors
    GET and a non-keepalive POST never arrived (traced at the bridge). The poll is that
    shape; its reply is opaque, so an event is told from a timeout by TIME (hold 25s).
  - **A request is pending until the extension ACKs it** (`restyled`), not until some
    poll is answered: a restarted Spotify's poll stays held at the bridge, and it used to
    swallow the next request. Pending expires after 10s.
  - The heartbeat restarts a poll that's been out longer than the hold; the hello
    (`ext` … `start`) and poll failures are reported through the anchor path and printed
    by SpotifyBridge.
  - **`spicetify apply` restarts Spotify while it's still writing**, so the restarted
    page can load the PREVIOUS extension. Deploy = `apply`, then `spicetify restart`.
  - Spotify's console is off (`--log-severity=disable`, chrome_debug.log empty). The
    bridge's opt-in trace is the witness: `touch "$XDG_RUNTIME_DIR/quickshell-spotify-
    bridge.trace"`, read `….trace.log` (method, path, size, fetch-mode headers, code —
    never a body). And run the extension under bun with a fake `Spicetify`/`document`
    (a Player that throws until ready reproduces the startup bug).
  Changing the extension: copy it to `$(spicetify path userdata)/Extensions/`, `spicetify
  apply`, `spicetify restart`. Changing the bridge: kill it and the shell starts it again
  (`SpotifyBridge.lockWatch`: a `flock -s` on its lock returns the moment it dies;
  capped at five relaunches without a "ready").
  The extension never stops waiting for Spicetify (150ms × 200, then every 2s).
- **Decisions wait for the curtain.** A cached palette or a colours-only change reads
  its palette before the curtain's screencopy has a frame; with no curtain counted,
  Discord fell back to its guessed lead and flipped late. `Contagion._act` now holds
  the spread until every planned curtain is up (≤ `curtainWait`, 400ms, logged as
  "Contagion: curtain up after N ms"), and `WallWave.delayGo` accepts a LATE delay by
  re-arming the settle from `readAt`.
- **The freeze and the settle wait for facts, not margins** (2026-10-03, "it takes quite some
  time to apply"): `WAVE=ready` used to cost a fixed `freezeMs` sleep (120ms, "three frames
  with margin"), and the palette read a fixed `Motion.standard` (150ms) for colour animations
  to finish under the snapshots. Now each `Infection` holds `WallWave.snapHold` from its
  `froze` until its snapshot is drawn and covering, the last release says `snapped`, and
  ThemeRunner touches `QS_WAVE_FROZEN` (`quickshell-quicktest-wave-<token>.frozen`, same
  validation as `.landed`) which `wave-lib.sh wait_frozen` polls for — `freezeMs` is only the
  base of its timeout (3×; no flag = the old sleep). And `Motion.snap` (raised by `WallWave`
  alone, from `commit` to `go`, with a 3s net) makes every `_d()` duration 0 under the
  snapshots, so the colours change instantly and the settle is `settleMs` (50, the frames it
  takes to DRAW them). **`Motion.wave` is deliberately NOT through `_d()`**: the front keeps its
  own 1150ms through the snap, and `Contagion` takes `WallWave.settleMs`, not
  `Motion.standard`. Expected saving ~150–200ms of a ~2s apply; measured nowhere yet.
- **The script waits for the shell's word, not a worst case**: ThemeRunner passes
  `QS_WAVE_LANDED` (`$XDG_RUNTIME_DIR/quickshell-quicktest-wave-<token>.landed`) and
  touches it on `WallWave.landed`; `wave-lib.sh wait_landed` polls for it (`landMs`
  is the timeout) before the wallpaper daemon and the fan-out. The path is validated
  (it's `rm`'d) and a stale one cleared at start.
- **Hyprland's border fade is off for the wave**: the `border` leaf is read from
  `hyprctl animations -j` (at start and after every `configreloaded`, which also
  restores it), switched off by `hyprctl eval` at the freeze, put back exactly at
  settled. A leaf that only inherits can't be restored exactly → left alone, and
  borders get its length as lead.
- **Hyprland must not animate the wave's surfaces**: it eases every freshly mapped
  layer (`fadeLayersIn` inherits `fade`, 1s here), which faded the scene water in and
  would half-show what the curtain hides. `WallWave` puts in a runtime
  `hl.layer_rule({ name = "quickshell-wave", namespace ^quickshell-(wave|wallpaper)$,
  no_anim })` at start and on `configreloaded`.
- **The fan-out skips what the wave already did**: `--app` stamps
  `$STAGE/.app-<name>` (ns); `commit_stage` exports `COMMITTED_AT`; the fan-out skips an
  app stamped since (`unless_done`) — a second Spotify recolour re-fetches its
  stylesheets, visibly. kitty's net SIGUSR1 stays (re-reading the same theme is free).
- Unwatched workspaces are told at once; a watched FULLSCREEN window (above the Top
  layer, likely a game) is left alone. `qs ipc -c ~/.config/quicktest call contagion
  status` (counts only). Trade-off: set_prop outranks window rules for the window's
  life — a per-app border colour rule loses to the palette on windows open during a
  wave. Window shadows (palette.lua, `color0`, 4px) still change with the fan-out:
  Hyprland has no per-window shadow colour.


## Panel polish (2026-10-05)

Detail pass on the ORIGINAL layout (620×394, same sections) — no redesign. Tiles: "showing
now" = full-strength ring + tick; workspace owners = faint ring + number chips (first three,
`+n`), scenes carry a play mark; Thumbnails fade in over
a sweep placeholder. The hero has a blurred copy of the current picture as its backdrop. The
header's two parallax buttons are one button opening a popover (Pictures / Scenes switches).
The grid fades at an edge only while there is more to scroll that way; the empty state has an
icon. Built from static checks only — not loaded.


## Wallpaper panel round (2026-11-05; built, never loaded)

The user: bring the panel to the shell's M3E look and motion, and improve its features, behaviour and code;
"apply all" of the list below. Stage 1 kept the layout; the user then reloaded, saw little visual difference and
some unthemed / clipped bits, and asked for "quite a bit" of redesign. Asked (three options each, 2026-11-06) they
chose **bento gallery**, **image-card tiles**, **floating toolbar**: see "The redesign" at the end of this section.
(The clipping seen was the library popover, taller than the 394px pin; it now scrolls inside its card.)

- **Split.** `WallpaperPanel.qml` went from 3,986 to ~1,900 lines; the rest lives in `modules/panels/wallpaper/`
  (own `qmldir`, `import "wallpaper"`): `WallpaperTile`, `WallpaperRow`, `WallpaperBrowse`, `WallpaperMaterial`,
  `WallpaperRendererSettings`, `WallpaperSceneProps`, plus `WallpaperPopover`, `WallpaperSubBar`,
  `WallpaperOptionRow` (a `SettingRow` + `Toggle`; was a copy of SettingRow's layout). They are real files, so the
  hot-reload trap with new inline components doesn't apply. Each takes `required property var panel` (the panel
  root) where it read `root.`; the files carry no `pragma ComponentBehavior: Bound`, so a delegate inside one
  reaches `panel` by name.
- **`WallpaperEntry`** (non-visual) is what the tile and the row used to carry a copy each of (and drifted: one
  latch was `removeLatch`, the other `removeRowLatch`): the normalised entry, `isCurrent`, `applied`, `busy`,
  `isFav`, `selected`, `doApply` / `doChoose` / `doRemove` and the remove `ArmLatch`. The panel keeps one for the
  keyboard cursor (`kbEntry`), so Enter does exactly what a click does. Tile and row now take `modelData` /
  `index` as required properties of their own, so a delegate is `WallpaperTile { panel: root; width; height }`.
- **Library logic is `services/wallpaperlib.js`** (`bun scripts/test-wallpaperlib.js`, 33 cases): search, kind
  filter, favourites-only, sort, favourites floated to the front, the `find -printf` row parser and `dropPaths`.
  `Wallpaper.mtimes` is read by the same `find` (`-printf "%T@\t%p\n"`: time, a tab, the path — the time has no tab in it, so the first
  tab splits it however odd the file name). "Newest" is the file time for pictures and the Workshop id for scenes (ids only grow).
- **Motion.** Tile entrance, lean, the remove/star/apply pops, the remove chip's width and the hero dots' entrance
  moved from `SpringAnimation` (16 ms steps; stair-steps on the 165 Hz monitor) to `SpringValue` with
  `Motion.springSpatial*`. A tile's picture corner morphs on a spring (`picRadius`: `radiusCard` + `spacingSm` under
  the pointer or ticked), the frame concentric with it; hover is a `StateLayer` (with the press ripple); the
  wallpaper on show and a ticked tile sit in a `primaryContainer` frame, not a 2px ring. Rows are tonal the same way.
  The body's tab and view changes are one move (`body._enter(dir)`: from the right going deeper, from the left coming
  back); the sub-view toolbars (`WallpaperSubBar`) slide and fade in. **`body.opacity` and `scale` are products of
  `chooseK` / `fadeK` / `enterK`, never assigned**: the old handler assigned `opacity = 0`, which broke the
  `root.choosing ? 0 : 1` binding at the first tab switch.
- **Popovers** (`WallpaperPopover`, spring from the top-right corner; one at a time, `root.popover`): Parallax, and
  the new Library one (the `tune` button in the search pill, with a dot while the sort or a filter is changing the
  view): Sort (Name / Newest, `Config.wallSort`), Show (kind chips + favourites only; both reset with the source),
  Shuffle (timer toggle + 15/30/60/120 min, and `Config.wallShuffleFavs` — the draw is the starred ones, the whole
  library while none is starred), and the apply log's switch (it was a header chip; a setting is not an action).
- **Header.** Every chip has a `HoverTip`; list/grid is ONE chip showing the layout it switches to; a new `undo`
  chip (`Wallpaper.undo()`) when there is something to go back to.
- **Undo** (`Wallpaper.previous` / `canUndo` / `previousName` / `undo()`): the picture, scene or Material wallpaper
  on screen before the last change made from `apply` / `pickScene` / `applyMaterial`. In memory only, and undoing
  is itself a change, so it swaps. It restores the SHARED wallpaper; the workspace pictures a left click forgot
  are not brought back.
- **Keyboard.** `BarPanelDock` hands a panel the keys the search box didn't take (`handleKey`) and Escape
  (`handleEscape`). Arrows / Home / End / PageUp / PageDown move a cursor (`kbIndex`, drawn as a `focus` outline;
  the first press shows it, the pointer moving hides it — a panel-level `HoverHandler`, because a per-tile one
  would also fire when the grid scrolls under a still pointer), Enter applies, Space ticks in select mode, F stars,
  S select mode, L list/grid, `/` focuses the search. Escape closes the nearest thing first: popover, the
  workspace picker, monitor picking, select mode, a sub-view, the search text, the cursor, then the panel. There is
  no type-to-search (the letters are shortcuts); `/` is the way in.
- **Drop to import.** A `DropArea` over the panel takes `text/uri-list`, `Lib.dropPaths` keeps the local
  .jpg/.jpeg/.png/.gif files (decoded, absolute, de-duplicated; anything else is dropped) and
  `Wallpaper.addPaths` copies them with `cp -n`. **Unverified:** that a file manager's drag reaches a layer-shell
  surface at all.
- **Layout history — the user's call, 2026-11-06: "return to the first version and just polish it."** The layout is
  the ORIGINAL one: header with two chip trays, tabs + search row, the 74px hero strip, then the grid with
  "Add images" / "Browse the Workshop" as its first tile, and select mode's bar over the foot of the grid. Three
  redesigns were built, looked at live and rejected, in this order; do not rebuild them:
  1. *Bento*: hero + action card as the grid's header, image-card tiles, a floating toolbar. Too little grid at 394px
     (the hero took ~150px of ~250), the toolbar floated over the tiles.
  2. *Four bands*: header, tabs/search/`+ tune ⋯` tray, grid, a pinned "Now bar" (a 660×560 try was reverted — the
     user said not to change the dimensions much). Judged too simple and boring; the user preferred the old add tile.
  3. *Four bands + the old add tile + colour* (tinted scrims, a header wash): still "not satisfied"; the user
     preferred the hero card on top.
  The polish that stayed (all in the first layout): tabs 336px wide so every one keeps its name and count (306px
  truncated "Images…"); the library popover scrolls inside its card (it was taller than the pin and clipped);
  hover tips on every header chip; one list/grid chip showing the layout it switches TO; an `undo` chip; the apply
  log's switch moved into the library popover; the framed tile on springs with a rounding picture corner, a
  `StateLayer`, and a tonal `primaryContainer` frame for the wallpaper on show or ticked.
  - **Second polish round (same day, the user: "add all of those, improve the top buttons, change how favourite and
    delete are shown"):**
    - *Header buttons* regrouped by what they act on: the left tray is the WALLPAPER (restart apps, cancel pick,
      undo, **Shuffle** / **Stop** — the two you reach for most carry their name — and the Material lock); the right
      tray is the LIBRARY (rescan, parallax, renderer options, select, list/grid).
    - *Favourite and delete moved off the picture* into the tile's CAPTION (name on the left): a lit star
      (warning gold, filled) is always shown, an unlit one is an outline on hover; the bin appears on hover and ARMS
      on the first press, stretching into a red "Remove?" pill with a draining bar (the sentence over the picture still
      says what the second press does). The picture is left bare; the old top-corner discs fought the apply pill. In
      the list view the star is a filled / outline `star` symbol and the armed bin reads "Remove?".
    - *Hero strip*: one even inset all round with the thumbnail's corner concentric with the card's (it sat 2px
      from the edge with a 4px corner inside a 23px one, which read as clipped); a `StateLayer` under the pointer, and
      a click calls `revealCurrent()` (cursor on the applied wallpaper, grid scrolled to it).
    - *Calmer tile entrance*: an effects spring (ζ = 1, no overshoot) from 0.94, stagger capped at 8 tiles.
  - **Third round (2026-11-06, the user: "still not a big fan… suggest changes", then "apply all"):**
    - *Gutter gone*: `contentPad` (a 20px strip reserved for the scrollbar) is deleted — the scrollbar is a 4px overlay
      that shows only while scrolling, so the strip just made the margins lopsided. Grid, list, tabs row and hero now
      span the full width.
    - *One header tray*: the wallpaper's own actions (restart, cancel pick, undo, Shuffle/Stop) moved onto the HERO
      strip, beside the picture they act on; the header keeps one tray of library tools (+ the Material lock).
    - *Hero as a showcase*: backdrop blurred less, brighter and slightly desaturated, under a left-to-right scrim for
      the text; thumbnail at true 16:9; bigger palette dots; the kind pill and its text are neutral (accent is kept for
      the wallpaper on show, the hovered tile, and the chips that are on).
    - *The Add tile* is an empty slot: the picture's own shape, a dashed outline (`Shape` + `PathRectangle`) and a
      faint fill, with a left-aligned muted caption like every other tile.
    - *Rows*: `cellHeight = 0.64 × cellWidth` (was 0.68), about 1.6 rows visible at 620×394. Two full rows is NOT
      reachable here without shrinking the pictures below usefulness; the header, tabs and hero take ~half the pin.
      Seen live after the first four changes; the 0.64 tweak loaded clean but was not seen (a game took the screen).
  - **Seen live on 2026-11-06** (screenshots with `grim`, panel opened with `qs ipc -p shell.qml call panel toggle
    wallpaper`): the final layout's header, tabs, search, hero and the first rows. **Not seen:** the popovers, the
    Scenes and Material tabs, list view, select mode, the sub-views, the drop overlay.
  - **A tooling lesson:** `hyprctl dispatch movecursor` did not move the cursor here (it stayed at its last
    position), `wtype` sends to whatever window is focused (the browser, not the panel — the panel has no keyboard
    focus when opened over IPC), and a uinput click lands wherever the cursor is. A click meant for the panel
    opened a video in the user's browser. Do not drive the UI blind; ask the user to open a state and screenshot it.
- **Music effects in the panel (2026-11-08; built, never loaded).** A `music_note` chip in the header tray (gallery
  view only — the effects never draw over the Material wallpaper; lit while `Config.wallFx` is on) opens
  `view === "effects"` (`wallpaper/WallpaperEffects.qml`, a sub-view like the renderer options: `WallpaperSubBar` with
  Back + what the beat clock hears). Switches, Intensity, Sync and the sound map, with the tuning dead (and a reason
  said) while the effects are off or the shell isn't drawing the wallpaper. The sound row is ONE component,
  `components/WallFxSoundRow`, used here and by Settings' Effects tab. Settings keeps its tab. New files: ALT+Q.
- **Material tab clarity pass (2026-11-08; built, never loaded).** The preview's Shuffle is **Rearrange** (the hero's
  Shuffle is the wallpaper timer); a caption under the preview says whether it is a preview (and what Apply replaces)
  or live; the header's lock chip is gone (the Looks page's card is the one lock) and Looks reads presets, Save, Lock;
  Mirror moved to Shapes; "Bursts" is **Background**, and `MaterialWallpaper.highlightSlot` dims every shape but the
  slot the Shapes page is choosing for (`layout()` boxes now carry `slot`); the fallback row reads "Keep it if the
  shell closes".
- **Open:** `WallpaperPage` (Settings) still has its own copy of the tile / row / filter / selection logic; moving
  it onto `WallpaperEntry` and `wallpaperlib.js` is the next step, not done.
- **Checked:** the static checkers, the syntax idiom on every file, `bun` tests. **Not run:** a load of the shell
  (CLAUDE.md: propose, the user reloads). Needs a full restart (ALT+Q), not a hot reload: new files, a new qmldir
  and a new `Config` property.

## Open apps that repaint without a restart (2026-10-06)

What each app does when a theme run lands, and what stands in the way. Everything here was
read out of the INSTALLED builds (Zen's `omni.ja`, Millennium's theme folder), not assumed —
each one failed silently the first time, looking exactly like "live reload doesn't work".

- **Zen — live through Pywalfox, two prerequisites.** `update-zen-colors.sh` writes
  `userChrome.css` in one of two modes. *Live* (Pywalfox installed): Zen's own variables and
  rules are `var()` references to the theme variables Pywalfox sets
  (`--lwt-accent-color`, `--toolbar-background-color`, `--toolbarbutton-icon-fill`…), each with
  the palette's hex as its fallback. *Static* (no Pywalfox): literals, restart to change.
  - `zen.theme.disable-lightweight` ships `true`, and Zen's theme consumer then swaps the
    default theme in for whatever was applied — Pywalfox's theme never reaches the window.
    Live mode writes it `false` into `user.js` (first time: one restart).
  - Check a variable name against the installed `omni.ja` before using it: this Zen has no
    `--toolbar-bgcolor` (0 hits; it is `--toolbar-background-color`), and a `var()` on a name
    that doesn't exist silently shows its fallback — indistinguishable from "not live".
  - Zen's `userChrome.css` is still read at STARTUP only; what's live is the theme underneath
    it. Run a theme change, THEN restart Zen, or the restart loads the previous file.
- **Discord (Vencord's `pywal-midnight.py`) — two bugs, fixed 2026-10-06** ("Discord doesn't
  follow the album colours"). Both were silent: the theme file WAS rewritten and Vencord DID
  reload it, every time.
  - *A race without a wave.* `stage_apps` starts the preps in the background and
    `commit_stage` ends by moving `$STAGE/out` away. A wave's freeze hid the gap; the album
    scheme's system-wide run (`reload-theme.sh`, no shell watching) committed within ms, the
    script found no palette, and — treating that as "use my defaults" — staged its built-in
    theme every track (accent `#5bc6fb`, ground `#0b0710` in the log). Spotify's prep timed
    out on the same missing file (the 10s fan-out). The preps now read a snapshot
    (`apps_palette`, `$STAGE/apps/colors.json`). `test-apply-wallpaper.py discord_no_wave`
    reproduces it (it fails against the old code).
  - *It never read a palette colour.* It wants `colors` as a list or color0..15 at the top
    level; pywal's `colors` is an object. Only background/foreground got through and every
    accent was the foreground grey. The script is the user's and isn't edited:
    `discord_palette` hands it a copy with color0..15 lifted to the top level, so the accent
    is color4 (the user's call: follow the palette).
- **GTK4 / libadwaita — live with `scripts/gtk-live` (optional).** GTK reads `gtk.css` once,
  libadwaita ignores the gtk-theme key (so step 7's gsettings flip only reaches GTK3), and GTK4
  dropped `GTK_MODULES`. `livetheme.c` is a GIO module — GTK4 apps still scan
  `GIO_EXTRA_MODULES` — that watches the `gtk.css` the shell writes and reloads it into a style
  provider one step above the user stylesheet. Needs `build.sh`, then the env in place at app
  START: `shell-env.sh` (what the shell launches) and `hypr/env.lua` (what Hyprland launches;
  re-login). `reload-theme.sh` no longer asks to restart an app whose `/proc/<pid>/maps` shows
  the module, and `write_gtk4_css` (wave-lib.sh) writes `gtk.css` by rename so a loaded app never
  reads it half-written.
  - **When it is written is what makes it go with the wave.** A watching app repaints the
    instant the file changes, so the file must change WITH THE COMMIT (`commit_stage`, next to
    kitty's theme): under the curtain, and the front reveals the app already recoloured. First
    version wrote it in the fan-out, after the wave — Nautilus visibly changed after the front
    had passed it ("slow, and it didn't go with the wave"). `test-apply-wallpaper.py`
    (`gtk4_staged`) pins it: old sheet at `WAVE=ready`, new by `WAVE=go`. Step 6b is now a
    byte-compare fallback. The same logic applies to anything else that watches its own file.
  - The module reloads at once on an atomic replace (10ms), and only debounces (80ms) an
    in-place writer. `LIVETHEME_DEBUG=1 nautilus` logs `reloaded in N ms` — the cost of the
    reload itself, if it ever needs tuning.
  - **Every GTK surface stands on `background`, not `color0`** (fixed 2026-10-06: "GTK colors not
    sharing the same bg as the rest"). The shell, kitty, Discord and qt6ct all use pywal's
    special.background; GTK4's sheet used color0 for every surface and GTK3's for its header
    bars, cards, popovers and sidebars — a different, lighter ground (#2F231D vs #251912).
    GTK4's `headerbar_backdrop_color` (an UNFOCUSED window's title bar) was the accent; now the
    background too. `test-apply-wallpaper.py gtk_*` pins all of it with a background ≠ color0.
  - **GTK3 goes with the commit too.** `write_gtk3_css` and `gtk3_refresh` (the gsettings
    gtk-theme flip, run in the background) are called from `commit_stage`, only when the GTK3
    sheet really changed. `gtk3_refresh` stamps `$STAGE/.app-gtk3` and step 7's fan-out call goes
    through `unless_done`, so a run flips once — twice would repaint every GTK3 app again after
    the wave. (`scripts/generate-gtk4-css`, an old hardcoded duplicate nothing referenced, is gone.)
  - Not yet seen working in a real libadwaita app — only syntax-checked. Verify with
    `grep -c livetheme /proc/$(pgrep -x nautilus)/maps` and a wallpaper change.
  - It is loaded into every GLib process that sees the variable, so it returns without pinning
    itself in anything that isn't GTK4, and polls for a display with a cap (the first version's
    idle source pinned a core in a GTK4 process that never opened one).
- **Steam / Millennium (Material) — live, no restart.** Rewritten 2026-11-09. The theme is
  kuska1's Material (MIT), fetched by `theme-setup.sh steam` at a pinned commit and used
  UNMODIFIED; setup activates it and sets its "Color" condition to `Matugen`, leaving the user's
  other Material settings alone. Matugen mode reads `css/main/colors/matugen.css` and
  `js/main/colors/matugen.js` re-reads it every 1.5 s in every window, so `scripts/steam-colors.py`
  only has to write that file (atomically, and not at all when nothing changed): an open Steam
  repainted 0.86 s after a palette change in a live test. The file is a full Material 3 role
  set (`--md-sys-color-*`, ~60 roles) built from the pywal palette with PaletteRoles' own blends:
  primary/secondary/tertiary are color1/4/5 pulled to 4.5:1 (pwspice's `_legible`), surfaces are
  `surface`/`surfaceContainer`/`surfaceHigh` blends, `error` is Material's fixed red (the shell's
  `danger` is color1, usually the accent). It also writes the theme's light/dark switches
  (`--scheme-*`, `color-scheme`) from the background's lightness, so a light wallpaper turns the
  theme light without touching its Appearance setting, and `--hue-rotate` (tints Steam's bitmap
  art) interpolated through the hues of the theme's own presets. `test-steam-colors.py` guards it,
  and checks every role the installed Material reads is defined.
  - **What it replaced, and why** (measured 2026-11-09, Millennium 3.6.3-beta.1): a pipeline that
    baked 1641 variables into `config.json` (rewritten + five `.bak` copies per wallpaper change,
    lost if Steam was open on exit) and a 956 KB `quick.css` of 1559 hashed `--qs-*` variables
    and 8424 selectors scanned from a running Steam. Quick CSS is injected into EVERY window
    whichever theme is active: 954 KB × ~10 windows = 5.7 MB of inline CSS. Cold start to a
    rendered main window was ~80 s (81, 79, 80) with it and 7–10 s without. Material with
    Matugen: 9.0 s (3 runs), 24 KB of inline CSS across all windows. Live recolouring used to
    need the unauthenticated CEF debug port on 8080 plus a flag file recreated before every
    launch: gone. The Matugen poll costs nothing measurable (rewriting the style tag with the
    same text is ~0 ms), so the theme's own `matugen.js` is not patched.
  - **Not ours to maintain:** Material's own selectors. An upstream update can change them; the
    pin only moves when someone bumps it. A user who already had Material keeps their copy.
  - **Verification trick:** `steam -cef-enable-debugging` opens the debug port for one session
    (never needed in normal use), and CDP `Emulation.setDeviceMetricsOverride` renders a tiled
    (441 px) window at full size without touching Hyprland. Don't judge "ready" by window width.
  - **Only the main window was seen rendered** (nav, tabs, buttons, bottom bar). Dialogs, the
    Library and the friends list were not opened.

## Light mode's palette (2026-10-07)

`stage-palette.py lightfix()` (also what per-workspace palettes go through) was rewritten
after "background too white" and "accents sometimes inaccurate". pywal's `-l` lightens the
background 95% toward white and — a pywal bug — never assigns the accents it darkens, so
they arrive as the dark extraction's. The old fix worked in HLS: every accent clamped to
L <= 0.45 / S >= 0.35 (lavender #9863EC → #5e19cd; greys of the Arch logo turned purple,
teal and olive — HLS's phantom chroma), and the page only ever raised to L 0.90.

Now in CIELAB via album-colors.py's helpers: the page is L* 91 tinted with the accents'
mean a/b vector (its length shrinks when they disagree or are grey, so a grey wallpaper
gives a grey page), ink L* 20 / color15 30 / color8 56 in the same hue, and an accent is
left EXACTLY as extracted when it reaches 3:1 on that page; otherwise only its L* is
bisected down, hue and chroma kept. Text-carrying roles get palette.js's legible() floor
at runtime as before. `qs ipc … call wallpaper theme light|dark` switches the mode.
