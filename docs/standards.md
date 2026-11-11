# Visual and palette standards

Read before editing `modules/`, `components/` or `shell.qml`. Moved out of CLAUDE.md verbatim.

## Standards

- **Colours only from the `Colors` singleton** (Material You, wallpaper-extracted),
  never a hardcoded hex. **Each screen can wear its own palette** (2026-10-04: a
  workspace's own wallpaper colours the shell on the monitor showing it), so a VISUAL
  file (modules/, components/, shell.qml) reads its screen's roles:
  `Colors.of(QsWindow.window).primary` — `QsWindow.window` is Quickshell's reactive
  attached window lookup, and `of()` falls back to the shared palette when there's no
  window/screen. Plain `Colors.primary` is the SHARED palette: right in services/,
  config/, state/, wrong in a visual file (`python3 scripts/check-qml-palette.py`). The
  roles live in `config/PaletteRoles.qml` (one per screen + the shared one); `Colors`
  forwards the shared one's. Spacing, type scale, radii, and motion
  durations/easing come from `Tokens` / `Motion`. Widgets consume them; they don't
  invent their own.
  - There are exactly four kinds of sanctioned hardcoded colour. Anything outside
    this list is drift. Don't extend the list, and don't "fix" what's on it back to
    the palette — each is hardcoded *because* the palette would be wrong there.
    - **Semantic pass/fail** — `config/Verdict.qml` (`pass` / `fail`, and `tint()`,
      which carries the `Config.colorizeIcons` opt-out). A wallpaper palette is free
      to land on red, and then the "it worked" tick renders red and states the
      opposite of what it means. Deliberately NOT in `Colors`, so reaching for it is
      an explicit import. It's a singleton because there were two copies of the two
      constants (VisualizerPill and OverviewNowPlaying draw the same
      `Lyrics.viaBridge` fact, and the bar sits above an open overview).
    - **Someone else's brand** — `discordRed` / `discordGreen` / `discordRedFg` in
      `modules/discord/DiscordCallBar.qml`, `claudeOrange` in
      `components/ClaudeGlyph.qml` (the mark's own declared fill), and the per-service
      grounds in `services/AlbumArt.qml` (Spotify, YouTube, SoundCloud, Bandcamp).
      Named constants with comments, scoped to the one thing wearing the brand.
    - **The palette's own fallbacks** — the monochrome ramp (`_mono`) and `shadow` inside
      `config/PaletteRoles.qml`. That file IS the palette; it can't resolve against itself.
      Monochrome on purpose (2026-10-06): the shell never wears a built-in colour scheme.
      No `colors.json` → `Wallpaper._bootstrapPalette()` runs pywal on the current
      wallpaper; black/white/grey is only for when it can't.
    - **A colour picker's input** — the hue wheel and the black/white alpha ramps in
      `components/SpectrumPicker.qml`, and NightLightPage's kelvin swatch
      (`services/kelvin.js`). These are the gamut you pick FROM, not themed
      chrome; theming them would make the picker unable to show colours it doesn't
      already wear. (The text ON the swatch is `Colors.shadow`, the palette's
      constant black — not a fifth exception.)
- **Text contrast is guarded, not just authored.** `fgMuted` and `fgDim` are an alpha of the palette's text colour, so
  their contrast follows the wallpaper. `PaletteRoles` treats the authored alphas (0.72, 0.66 / 0.68 light) as FLOORS and
  lifts either to the least alpha that reaches 4.5:1 (muted) / 4.0:1 (dim) over `surfaceHigh`, the worst-case ground
  (`services/contrast.js`; `bun scripts/test-contrast.js`; `python3 scripts/check-contrast.py` models it per bundled scheme).
  Palettes that already pass are untouched. `fgFaint` is meant to recede and isn't guarded.
- The bar, launcher, notifications, OSD, and lockscreen share one corner language,
  one elevation logic, and one motion personality.
- Separate presentation (QML) from logic (JS) from system integration (IPC,
  D-Bus). Theme and the Hyprland connection are singletons/services, never
  reimplemented per widget.
  - A *protocol* is logic, not presentation. The `:: [n/N]` update-phase markers
    were parsed inside `UpdatePanel`, so `UpdatesPage` — the richer view — had no
    progress display. Parsing now lives in `Updates` and both views bind to it.
  - Real algorithms go in a `.js` beside the service (`services/palette.js`,
    `services/calc.js`), because that can be tested. `bun scripts/test-calc.js`
    runs the launcher's expression parser against many cases; a QML expression
    buried in a panel cannot be tested at all.

- **Accent and state colours are one vocabulary, in visual files.** `accent` defaults to
  `Colors.of(QsWindow.window).primary` everywhere (2026-10-25; it was split focus/primary, and
  that split was the "inconsistent buttons" complaint). `focus` is for outlines, selection rings
  and `outlineFocus` only. At rest: `stateIdleFg`. Hover bg: `stateHoverBg`. Motion uses the
  `Motion` curve names (`travel`, `exitCurve`, `respondCurve`, `ambient`, `inOut`, `overshoot`,
  `expressive`), never raw `Easing.*`. Literal radii of 1–3.5 (hairlines) and half-size dots
  are deliberate.
- **Panels follow one recipe.** The bar's panels — wallpaper
  (`WallpaperPanel`), colours (`ColorSchemePanel`), the audio mixer
  (`EqualizerPanel`), updates (`UpdatePanel`) — were all rebuilt to it:
  - `PanelHeader` at the top (icon/glyph, two-word title with the second word in
    the panel's accent, subtitle, an action row on the right).
    `visible: Config.panelHeader("<module id>")` where the header is identity only (the module is then listed in
    `PANELS`, config/modules.js); a header that holds the panel's controls is not switchable.
  - Under it a `PanelHero` (what is going on, and the main switch or action), then `PanelRow`s / pages; an empty
    panel shows `PanelEmpty`. Outer padding `Tokens.spacingXl`, column spacing `Tokens.spacingSm`, cards
    `Tokens.radiusCard` on `section`, no outlines.
  - Header actions grouped in `ActionGroup` — the bar-style tray of
    `PanelButton`s.
  - Every spacing, radius, font size, and duration from `Tokens`/`Motion`. No
    literals.
  - Content-hugging: bind `implicitHeight` to the active view's content (capped),
    so `BarPanelDock` grows and shrinks the surface with the panel. The wallpaper
    gallery is the exception — it's a fixed pin (620×394) because a thumbnail grid
    self-sizing to content read worse.
  - Reuse the shared widgets (below), never a bespoke slider/meter/field.
  - All real work in the service; the panel shows things and calls functions.

- **Reach for these before writing your own.** Each replaced several drifted
  copies:
  - `Clock` (service) — the wall clock. Ticks once a MINUTE, aligned to the real
    boundary. `acquireSeconds()` / `releaseSeconds()` for a face that shows
    seconds. Never write `Timer { interval: 1000 }` + `new Date()` in a widget:
    twelve of those disagreed by up to a second, so the bar clock and the desktop
    clock changed minute at visibly different moments.
  - `SudoProcess` (services) — a root job fed a typed password on stdin, once, with the
    sudo-lockout guard (a rejected password isn't sent twice; nothing while `SudoLock` says
    locked). Setup and Storage use it; never write a password to a bare `Process`.
  - `InputField` (component) — the single-line text field. `committed` (Enter +
    focus loss) or `edited` (per keystroke); both always fire.
  - `ArmLatch` (component) — click once to arm, again to confirm, self-disarming.
    Non-visual on purpose. `armWhen: false` fires immediately, for a control that
    is only sometimes destructive. `HoldButton` is the press-and-hold sibling.
    `LockScreen` / `GreetScreen` keep a *keyed* variant (`armed` holds WHICH key
    is armed, one-of-N) — that's genuinely different; don't force it into
    `ArmLatch`.
  - `ActionGroup` (component) — the rounded tray of `PanelButton`s used in every
    panel header. `groupShown` hides it; children control their own `visible`.
  - `ValueSlider` (component) — rail, fill, handle, for volume/brightness/mixer.
    `thickness` (default 3) fattens the rail; the handle and unity notch scale off
    it. The audio mixer asks for a thick fader; the bar pill and brightness keep
    the hairline.
  - `ScreenOwner` (component) — which screen shows a one-screen overlay: the
    focused monitor, captured when it opens (so an open overlay doesn't hop
    screens as focus follows the mouse). Non-visual; bind `visible` to `owns`.
    Replaced five copies of an `UiState.activeScreen` rule that was stale for
    anything a keypress opens.
  - `SpringValue` (component) — a number on a physical spring: `target` in, `value` out, velocity
    kept when the target changes mid-flight. Presets are `Motion.springSpatialFast/springSpatial/
    springSpatialSlow` (position, size, shape, scale; overshoot) and `springEffects*` (opacity,
    colour; none) — Material 3 Expressive's own stiffness/damping-ratio numbers. Closed form
    (`components/spring.js`, `bun scripts/test-spring.js`), frame-exact at 165 Hz, unlike Qt's
    `SpringAnimation`, which steps at 16 ms. State-layer alphas are `Tokens.stateHover/Focus/
    Press/Drag` (8/10/10/16%), StateLayer's defaults.
  - `MorphShape` (component) — a Material 3 Expressive shape (`circle`, `cookieN`, `sunny`, `burst`,
    `clover`, `squircle`, `pentagon`, `hexagon`) that morphs on a spring when `shape` changes. Every shape
    is polar on the same 192 angles (`components/shapes.js`, `bun scripts/test-shapes.js`), so any pair
    morphs cleanly, from mid-morph too. Static geometry at rest. `RadialGauge { wavy: true }` is the
    wavy indicator: the wave is fixed to the ring, so nothing redraws while the value rests.
  - `ImagePicker` (component) — the in-shell picture/folder browser, as a page overlay: `show(path)`,
    `picked(path)` / `pickedFolder(path)` (`folders: true`). LockPage's avatar picker predates it.
  - A hover/press plate inside an inner pill is CONCENTRIC with it: the pill's radius less the gap, one
    even gap all round, growing along the bar only (`IconButton`, `CellFeedback` — use them rather than
    a Rectangle of your own; the tray's own plate is what the user called "doesn't match the inner
    pills"). `docs/bar-and-blob.md` has the numbers. In a pill, hover is ONE plate that slides
    between the buttons (`HoverTrack`): a new host of buttons offers `hoverTrack`, and a new kind of
    button claims and releases it as those two do.
  - `BarLabel` (component) — the bar's one label style (medium, bar font scale, tabular digits). A primary
    label on the bar is one; a secondary line under it stays a StyledText.
  - `LiveShape` (component) — a cell's live state as a tonal M3E shape behind its glyph (`SideCell.liveShape`);
    `SidePeek` + `EventPeek` — an event's card beside a sidebar module, under the clips peek's rules. Use them
    rather than a new dot, badge or popup for a sidebar state.
  - `MonoIconEffect` (component) — what `Config.colorizeIcons` means for a full-colour app icon: the icon
    in grey (saturation -1, brightness +0.15 — the user's pick over a scheme-tinted version), as a
    `layer.effect` gated on the setting. Not a MultiEffect colorize at 1.0, which sinks a logo on a disc
    into a blob. (`ThemedAppIcon`, a glyph cut out onto a plate, replaced for a day and dropped: blank and
    colour icons.)
  - `MusicRim` (component) — a pill's rim lit by the music (`Config.barMusicReact`): a thin `vivid` line, as
    bright as `MusicPulse` is loud, on a spring. Nothing scales, nothing fills (the user's call). Anything
    else that moves with the music reads `services/MusicPulse` (acquire/release, paired) — never its own
    cava.
  - Desktop tiles: `WidgetHeader` (glyph on an M3E shape, `shape` per widget), `TileRow` (a tonal list
    row with the state layer), `TileChip` (tonal icon button; `filled` for a tile's main action, `box`
    for size), `TilePill`, `WidgetEmpty`. A tile's hero sits on `primaryContainer`.
  - `PanelHero`, `PanelRow`, `PanelEmpty` (components) — a panel's subject card (an M3E shape, a headline, the line of
    what is true now, the main action; `footer` for controls inside the card), a tonal list row (`active`, `clickable`,
    `below` for content under it) and the "nothing here" face. Use them rather than a Rectangle of your own; the Game
    Mode and Screen time panels' heroes predate them and are bespoke.
  - `HelpTip` + `TipBubble` — a control's explanation as a tooltip. The bubble belongs to the SURFACE (the settings card
    has one, the bar window has one for its pills and panels); a new window that wants tips hosts a `TipBubble`.
    `HelpTip.provide` is a function asked on hover, for words that cost a service read (`ModuleGlance.tip(id)`).
  - `Meter` (component) — one ratio against its limit, as a track + fill. Use
    `fillDuration: Motion.track` when it follows a live signal (an audio peak),
    not the default.

- **Icons are Material Symbols, from the shell's OWN fonts** — no icon font is installed or read.
  `assets/fonts/QuicktestSymbols.ttf` (the Material Symbols the tree names) and
  `QuicktestGlyphs.otf` (every Nerd Font codepoint it spells) are cut out of the system fonts by
  `python3 scripts/material-symbols-map.py --emit`, which writes `services/icons.js` in the same run;
  `Tokens` loads them (`fontSymbols`, `fontGlyphs`). Why (2026-10-06): a Nerd Font upgrade shifted
  every glyph ID under the running shell and drew every icon as a different one. Generated files,
  never hand-edited; `assets/fonts/README.md` has the sources and licences.
  - `components/MaterialIcon` draws by `name: "search"` (looked up in `SYMBOL`, drawn as a codepoint —
    no ligatures) or by `glyph:`, the Nerd Font character the shell used to spell, translated through
    `NAME` (codepoint → name), so a ternary of two glyphs or a field in a service's table is an icon
    without anyone resolving it. A StyledText that shows an icon is a MaterialIcon (converted
    shell-wide, 2026-10-03). Do not add new Nerd Font literals to a plain StyledText; the few Text
    elements that show a `glyph` straight (IconButton's glyph path, ContextMenu) set
    `font.family: Tokens.glyphFamily(text)`.
  - **A new icon name or glyph needs a regeneration.** The fonts carry only what the tree used when
    they were cut; anything new is a help-circle (a name) or a Qt-fallback glyph until `--emit` runs
    again. `bun scripts/test-icons.js` fails on both, and on fonts and `icons.js` that weren't
    generated together. After regenerating, restart the shell (ALT+Q) — not a hot reload.
  - **Brand marks stay Nerd glyphs** (Discord, Steam, Spotify, Arch, the distro logos in AboutPage):
    Material Symbols has none, so they draw from `QuicktestGlyphs` as they always looked. `NO_SYMBOL`
    in the map script lists them; they are not a backlog.
  - The filled/outline pair is the FILL axis (`symbolFill`), not two names: a pin is `keep`, filled
    when pinned. FILL and wght are live axes in the cut font; GRAD/opsz are pinned into it.
- **A surface that fades out must keep its own copy of what it shows.** Bind a
  disappearing surface's content straight to the service and it blanks the instant
  the state clears, then spends the whole fade-out empty. Keep a plain local copy,
  set on the way in and never cleared. `UpdatesPage` (`showLog`) documents it;
  `ScreenshotToast` (`held`) re-learned it the hard way — it read as "the picture
  sometimes doesn't appear".

- Prefer event-driven Hyprland integration over polling.
- Lazy-load anything not always visible (popups, overlays) rather than
  always-mounted-but-hidden. Watch for expensive bindings and per-frame work.
  - A standalone overlay is its own `PanelWindow` with content behind a
    `Loader { active: … }`, so a closed one costs nothing (`CheatsheetPopup` gates
    the HyprConfig parse and its file watches that way).
  - **Two `PanelWindow`s sharing a layer-shell namespace fight over keyboard
    focus.** Give each its own namespace. This bit the cheatsheet and emoji
    popups.
  - Before adding a subprocess, check whether the shell already knows the answer.
    The emoji picker once spawned `hyprctl activewindow` every 30ms to poll for
    focus — a question the compositor was already pushing over the event socket.
- Flag dead code before removing it, in case it's load-bearing.

## Comments

A comment says why the code is the way it is NOW. History goes in the commit message: no dates,
no "used to", "previously", "until 2026-…", "the old version". A measured fact stays without its
diary ("measured on Qt 6.12: …"), and so does a rejected alternative stated as a reason ("not X:
X does Y"). Docs under `docs/` may keep history; code comments may not.
`python3 scripts/check-comment-history.py FILE…` lists a file's findings: clean the ones in a file
you edit. Not gated (hundreds remain); `check-all.sh` prints the count so it only goes down.

## Accessibility

Started 2026-11-08: the shared interactive components expose themselves to screen readers
(AT-SPI) — `IconButton`, `ChipButton`, `PanelButton`, `HoldButton` (Button), `Toggle`,
`ToggleChip` (CheckBox), `QuickToggleTile`, `ChipRow` / `SegmentSwitch` / `TabStrip` choices
(RadioButton, checked = current), the sliders (Slider), `InputField` (EditableText, named by its
placeholder) — with a name from their own label and a press action that does what a click does.
`Toggle` and the sliders have no text of their own: `accessibleName`, which `SettingRow` fills
from its label when the caller leaves it empty.

- New interactive components set `Accessible.role`, `Accessible.name` and
  `Accessible.onPressAction` the same way. Prefer the shared ones and it's free.
- **Reduced motion** (2026-11-08): `Config.motionReduced`, between full and off (Settings › Appearance ›
  Type & shape › Motion). `Motion.reduced` / `Motion.ambientOn` are the two reads. Central, no call-site
  change: spatial springs go critically damped, the `spring` curve and `overshoot` lose their overshoot.
  Gated on `Motion.ambientOn`: cookie/shape drift, the colour-change wave, wallpaper parallax, widget and
  HUD card tilt, overview pointer drift, lock/greet Ken Burns and scene video, the voice orb's idle turn,
  the watermark, beat-spun shapes. Gated on `!Motion.reduced` (so "off" behaves as it always did): wallpaper
  music effects, the material wallpaper's drift/spin. A NEW decorative loop or parallax gates on
  `Motion.ambientOn`; a busy spinner does not (Motion.qml category 3). Not in a bar preset or look bundle.
  Also the onboarding wizard's and setup cookie's turns, the overview's badge/cell/feed turns, Game
  Mode's hero and the photo tile's shape turn. A busy spinner turns at `Motion.spin` (exempt, like
  `pulse`). **Not covered:** panel/bar morph travel and slide-ins still move (only their overshoot is
  gone), loading shimmers.
- **High contrast**: `Config.highContrast` (Settings › Appearance › Type & shape › Shape). Central, no
  call-site change for anything that already reads roles and tokens: PaletteRoles raises the accent and
  text floors from 4.5 to 7:1 (`_textFloor`), lifts fgMuted/fgDim to 7 / 4.5 and fgFaint to 0.55, and
  draws the outline ladder solid; `Tokens.borderWidth` goes to 2; `Tokens.surfaceOpacity` and
  `Tokens.sectionAlpha` go to 1. **Draw the bar's and the sidebar's fill with `Tokens.barOpacity` /
  `Tokens.sideOpacity`, never `Config.barOpacity` / `Config.sideOpacity`** (those are what the sliders
  edit, and stay as set). A desktop tile's is `WidgetFrame.effOpacity`. Not in a bar preset or look
  bundle. **Not covered:** a translucent fill a file computes with its own `alpha()` (a hover wash, a
  dim) stays translucent; wallpaper effects and the HUD over a game are untouched.
- Bar and sidebar modules are named for screen readers by their catalogue label (2026-11-10): `IconButton.accessibleName`
  (`BarIconPill` fills it from `ModuleGlance.label`), and `SideCell` is a Button named the same way.
- Not done yet: keyboard focus order (`activeFocusOnTab` / `KeyNavigation`) across panels — the
  layer-shell keyboard-focus rules in `docs/qml-api-caution.md` make it its own job — and
  bespoke clickable `MouseArea`s outside these components.
- Untested with a real screen reader (Orca).
