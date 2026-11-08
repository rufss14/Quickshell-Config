# The sidebar

Moved from CLAUDE.md; the project rules there still apply.

## The sidebar (dock edge)

Settings › Sidebar groups everything on the edge the bar doesn't own: Dock
(`DockPage`), Stats (`SidebarStatsPage`) and Clips (`ClipsPage`).

- **What's on the edge is `Config.sidebarLayout`** — the top bar's `layout` shape (region →
  groups → ids) and the same `layout.js` algebra, over `start` / `centre` / `end` along the
  edge, over the shell's ONE module catalogue (`config/modules.js`; `sidebarModuleList` is its
  `forSurface("side")`, the bar's `moduleList` its `forSurface("bar")`). Reversed 2026-10-07 at
  the user's ask: top-bar modules used to never move here; now every module is one pool, a module
  is offered on a surface if it has a form (`bar` / `side`) for it, and it has ONE place — placing
  it on one surface takes it off the other (`Config._leaveBar` / `_leaveSidebar`, in every
  inserting mutator). Staged: the catalogue is merged; most modules still have one form
  (`bun scripts/test-modules.js`). Membership IS visibility:
  `dockEnabled` / `sidebarStats` / `clips` are READONLY, derived from it, and still written
  to config.json (save-only entries) so the file reads as before. Toggle with
  `Config.sidebarToggle(id)`, never an assignment. `_loadSidebarLayout` migrates a document
  that has only the three old switches (clips start, dock centre, stats end) and leaves the
  layout alone when a document mentions neither (an older shell preset). A saved layout
  is reconciled with an EMPTY priorKnown, so an upgrade never adds a sidebar module: new
  ones wait in the pool. Adding a SMALL module joins its home region's last group when that
  group is all small (`layout.js addModule`'s `canJoin`; the user's call, 2026-10-02: one
  pill per region, like the top bar's groups — one pill per module read as loose buttons).
  The top bar's add still starts a group of its own.
  `qs ipc … call sidebar status | place <id> <region> | remove <id>`.
- **Arranging it is the top bar's arrange mode, on the edge** (the user's ask, 2026-09-29):
  Sidebar › Layout open IS `UiState.sidebarArrange` (on construction, off on destruction;
  its header button toggles it). `modules/bar/SideArrange` (behind a Loader in Bar.qml, z
  60, over the modules) puts a handle over every module — drag it along the edge, onto
  another (which HALF: before/after, into that group), into a gap between groups (a
  group of its own; a hollow outline, vs the insertion bar), onto an empty region's
  outline, or out into the room beside the sidebar to take it off — with one line saying
  what the drop will do (`SideDrag.description`). `state/SideDrag` is BarDrag's twin with
  its OWN mime (`application/x-quickshell-sidemodule`), so neither surface's targets light
  up for the other's modules; commits happen in `onDropped` only. Targets come from the
  rail and the layout (`rail.at`, `allLengths`, `Config.sidebarLayout`), never from the
  module items; the drag image IS the module, grabbed on press from `rail.items` (the
  hosts register theirs). Modules are disabled and the dragged one dims while arranging.
  The dock never shares a group: `Config.sidebarMoveIntoGroup` turns such a drop into a
  group of its own beside it. The settings side is `modules/settings/SideModuleTray` (the
  unplaced modules as glyph+label chips — not live copies, which would sample — drag out,
  click to add, drop one back to take it off). Arranging keeps the sidebar out, even
  empty (`SideBarHost.live`), and closes its panel. `layout.js moveToOwnGroup` names gaps
  in the layout as it WAS, and adjusts for a lone module's own group vanishing (this used
  to move it one group too far, on the top bar too; tested).
- **`modules/bar/SideRail`** is the ONE layout for that edge. It places every module per
  `sidebarLayout` (`dock.js sideRail()`, `bun scripts/test-dock.js`): `start` packs from the
  NEAR corner (welded into the bar's underside on a side, the left strip at the bottom —
  `SideRail.near`), `end` packs back from the far corner (`corner`), `centre` is one block
  centred between them. Hosts report `lengths` (by id) and read `at` (by id) and, for the
  dock, `room` (its ceiling at rest). The centre steps down past any open panel card
  the sidebar isn't holding that crosses the edge's band (`railAvoid()`). The start region DOESN'T
  step: a panel card over the near corner (the band plus `apart`) COLLAPSES whatever stands
  there into the frame (`SideRail.startCollapsed` / `isCollapsed(id)`) until it closes —
  stepping it down pushed the dock into the stats, the user's "running out of space". Card
  heights are animated, so the rail follows a panel smoothly. No host computes its own
  position along the edge. `SideRail.apart` (`Morph.smoothing` + a margin) keeps welded
  lobes from bridging.
- **It wears the top bar's style** (the user's call, "match it exactly"). Bar › Style drives
  both: `modules/bar/SidePill` draws every sidebar surface in the top bar's own recipe —
  `"bar"` (Bar.qml's unified surface), `"inner"` (BarGroup's inner pill,
  `Config.barInnerPill`) — welded (frame fill, the blob draws the outline),
  flush (anchored, nothing to weld: square where it meets a strip, `bleed` with no frame)
  or floating (`barAnchored` off: outlined, shadowed, `barInset` off the strip). Its SIZE is the dock's, not the
  top bar's (the user's call after trying the bar's: "it needs to fit the dock"). Every
  module stands in a cell of the dock's icon plus `sidebarCellPad` (spacingSm) a side
  (`sidebarCell`, from `dockIconSize` — Dock › Icon size and Sidebar › Layout › Size are that
  one setting; NOT `dockButtonSize`, which the overview's dock keeps — its spacingMd pad made
  the sidebar 68px at 32px icons, "too thick", 2026-10-02), in the
  top bar's inner pill (`sidebarPillCross`, spacingXs a side) with the top bar's margin
  either side (`sidebarDepth`), corners `sidebarRadius` (the blob's sidebar lobes too).
  The inner pills are the TOP BAR's own, exactly (the user's call, 2026-10-17, replacing the
  2026-10-02 "softer" mix): `SidePill` gives them the nested elevation, borderless, at the bar's
  roundness and opacity, as BarGroup does. Briefly they wore the sidebar's own material (frame
  fill, outline, concentric corner) and read as "nothing like the top bar"; don't tint or outline them. The sidebar's
  dock wears its indicators on the edge toward the WINDOWS (`DockIconStrip.indicatorsInward`,
  `barFeedback` only — the overview's dock keeps the outward side): the focus glider an
  accent bar, a running app a dot, the level bars there too, and no fill behind the focused
  app.
  **Hover cards** (2026-10-17): `components/SideHover` on a cell opens `modules/panels/HoverCard` (the side panel
  "hover", `sidePanelArg` = its kind; `window` first) after a 450ms dwell and closes it 140ms after the pointer
  leaves. A guest in the panel slot: only when the slot is FREE (a panel the user opened is never pushed aside),
  never over the bar's own panel column on this side (opening a side panel shuts it), not while arranging or hidden.
  Information only — the pointer is on the cell, so the cell's own click still opens its real panel. Like every
  fading surface it keeps its own copy of what it shows. Side panels ask for `OnDemand` focus, which only takes it
  on a click into the surface, so a card never steals typing.
  **The active indicator** (2026-10-17, replacing a plate-and-flood try the user rejected: "the dimensions are
  improper"): `CellFeedback.active` draws IconButton's mark — a short accent bar, a glyph long, settling in on its
  length — on the sidebar's edge toward the WINDOWS (the dock's rule), as the top bar puts it under the content.
  A module sets `feedback.active` to its open/on state; `markMax` lets a long module (the window's title) span it.
  Hover/press is IconButton's ladder via `components/CellFeedback` (a tint, a ripple, no
  bounce). `DockIconStrip` takes `buttonSize`/`iconPx`/`barFeedback` from its host (the
  overview's dock keeps the house wash). The sidebar's panels are sized in
  `Tokens.sideCardUnit`, never the cell. Across the edge, `dock.js sideSurface()` says where
  the surface lies (welded: from the screen edge, strip inside it; flush: on the strip;
  floating: off it by `barInset`) — SideRail draws from it (`surfaceLo`/`surfaceHi`/
  `depth`, hosts pin at `rail.edgePos()`) and DockReserve reserves from it. Along the edge,
  `pad` is the inner pill's margin.
- **Unified only — top bar and sidebar** (the user's call, 2026-09-29: "a full bar, no stuff
  with gaps in between"). The pills shapes (`pills`/`pillsAnchored`, `barMode`,
  `barSpacing`, `barUnified`, `sidebarUnified`) are gone; `barLayout` is `unified`
  (floating) or `unifiedAnchored` (on the frame), and `layout.js unifiedLayout()` maps an old
  pills name to its unified twin (config.json and presets). Don't bring a per-group pill
  back. `modules/bar/SideBarHost`
  draws ONE bar strip to strip along the edge (`SideRail.barStart`/`barEnd`), and what
  stands on it is inner pills (`SideRail.inset` in from its ends, centred across the
  band). Welded, the bar is ONE lobe (`BlobBarLayer.sidebarRect`) and nothing on it has a
  lobe of its own — pill lobes laid on the bar would bulge wherever their faces coincide
  with its face; only what reaches PAST its face (a panel, the dock's preview) does.
- **The whole sidebar hides as ONE** (`sidebarAutoHide`/`sidebarDodge`;
  the dock's, stats' and clips' own switches are gone — `_persisted` migrates a pills-mode
  document's `dockAutoHide`/`dockDodge` into them once). `SideBarHost` runs whenever
  anything is placed (`Config.sidebarAnyPlaced`), draws the bar, and owns
  the one reveal, the edge zone (file drags too) and dodge. Each host exports `engaged` (its
  `held`), Bar ORs them with `SideRail.smallHovered` and SUPER+D's `UiState.dockRevealed`,
  the big hosts slide on `rail.barShown` with the same curve, and the small groups ride its
  `cross` itself. `dockTakesSpace` reserves for the whole edge whichever module is on.
- **Small modules** (`sidebarModuleList` `small: true`: Stats = `SideStats`, Clips =
  `SideClips`, Shell tools = `SideTools`, Power = `SidePower`, Voice = `SideVoice`, Colour
  picker = `SideColour`, Notifications = `SideNotifications`, Clipboard = `SideClipboard`, Timer = `SideTimer`,
  Lens = `SideLens`, Claude Code = `SideClaude`, Screen time = `SideScreenTime`)
  are a few cells each — mostly `SideCell`s
  (a glyph at `sidebarGlyphPx` = 0.9 × the icon, weight `sidebarGlyphWeight` (400 + 100), FILLED
  while the cell is `active` — any cell, `glyph` resolves to a name too. It was 0.75 in the
  Nerd Font days, when a glyph's line box ran half again taller than its ink and at the icon's
  size it read far too big; at ~42% of the old roomy cell every small module read as a dot in
  an empty box beside the dock (2026-10-02). Material Symbols draws to its box, so 2026-10-17
  ("glyphs too small/thin") moved it up and made the stroke sturdier. The clips arc is the cell less spacingXs a side and a
  hairline thick, its glyph the cell's own size (`SideClips.innerGlyphPx`, 2026-10-17: a ring with a half-size
  glyph in it was a different language from the rest of the edge); recording is the accent, not red, with a pulsing dot — CellFeedback, an optional ArmLatch
  `armed` state, `glyphAngle`/`glyphScale` for a module that animates its glyph),
  `sidebarCellGap` apart (the dock's button gap; lengths via `Config.sidebarRun(n)`). A static count is the row's
  `cells`; one that changes (Voice's faces, the picker's swatches) comes from
  `services/sidemodules.js` (`bun scripts/test-sidemodules.js`), which the rail
  (`SideRail.cellsFor`) and the module both call. Voice meters the mic only in a call or
  under the pointer (a monitor stream, so never the privacy pill) and rings the talker in
  `Colors.focus` — Discord's green stays the call card's. The picker is
  `services/ColorPicker` (hyprpicker, optional: its tile carries `blocker()`; picks go
  through `parseHex`, the history is `statePath("picked-colours.json")`).
  SideGroupHost loads each module BY URL (`moduleUrl`), so a broken module blanks its slot
  instead of making SideGroupHost — and Bar — fail to exist. `modules/bar/SideGroupHost` draws an inner pill per
  GROUP of them, like the top bar's groups; the dock, stats and clips always stand alone
  (`dock.js sideGroups` splits a group round them). Bar.qml builds one per
  `SideRail.smallGroups` entry (a ScriptModel keyed on the ids joined). Their lengths are
  data (cells × `sidebarCell` + 2 × pad, `SideRail.smallLengths`); they ride `rail.cross`,
  and the sidebar bar's lobe and mask cover them — no lobes or masks of their own. A new small
  module = a catalogue row + a file + one line in `SideGroupHost.moduleUrl` (+ `cellsFor`
  if its count moves) + a tile on the Sidebar page. SideGroupHost hands a module
  `vertical`, and — where it declares them — `screen`, `monitor` and `shown` (the sidebar
  out and the module not sunk: what gates sampling and clocks). **Power** is ONE cell
  (2026-10-02; five cells read as a tower): click opens the power menu, `modules/bar/PowerDock` — a
  column of four big buttons welded into the frame's right edge (see "The power menu" in
  `small-features.md`; the full-screen wlogout-style overlay it replaced is gone, 2026-10-18).
  `UiState.powerMenuOpen`, `qs ipc … call power toggle`; Exclusive keyboard; `ScreenOwner`. Tiles:
  lock, log out, restart, shut down; all but lock click twice (a keyed `armedKey`), letters L E R P,
  arrows/Tab + Enter, Escape disarms then closes. Under a fullscreen window nothing can show it
  (the bar's layer is hidden), so the request is dropped. Hibernate/firmware/suspend are no longer
  in the table (`Session.probe()` still answers CanHibernate / CanRebootToFirmwareSetup via busctl,
  and `needs` would gate a row that came back). Middle-click on the button locks. Everything
  goes through `services/Session`, which the overview's PowerPanel uses too — no inline
  `Process` in either. **Timer** (`SideTimer` → `modules/panels/TimerPanel`) is a view
  over `services/Timers`: a glyph at rest, a ring while a countdown (time left) or the
  stopwatch (its minute) runs, a full danger ring and a nudging bell when a countdown
  finishes; hover shows the time; middle-click starts/stops the panel's current face
  (`Timers.mode`) or dismisses a finished one.
  **Timer panel, revamped 2026-10-18** (the media / colours look: `SegmentSwitch`, a `RadialGauge` with the time inside, a
  `CookieButton` for start / pause, `ChipTray`s, flat `section` cards): four faces — Timer, Stopwatch, Alarms, **Focus**. New in
  `services/Timers`: a countdown **pauses / resumes** (`pauseTimer`, `resumeTimer`; the time left is banked in `timerLeftMs`) and
  **extends** (`extendTimer`, +1 / +5 min; `timerSpan` is what the ring is a fraction of, so it never reads past full); a **focus**
  (Pomodoro) cycle rides the countdown (`startPomodoro`, `pomoSkip`; phases and lengths are `services/timers.js`, tested by
  `bun scripts/test-timers.js` — focus, a short break, a long one every N sessions; stopping the countdown ends the cycle), so the
  sidebar ring follows it for free; an alarm that fires **rings** (`Timers.ringing`) until dismissed or **snoozed** (5 / 10 min,
  `snoozeAt` beside the schedule, which carries on), shown as a banner in the panel and a danger ring on the button; alarms **repeat on
  chosen weekdays** (a bitmask, `alarms.js`, which the service already supported — the panel just never offered it; a click on the repeat
  label cycles the presets); the stopwatch marks the **best / worst lap** and copies the laps; a running countdown says "Ends 14:32".
  The button: a paused ring is warning-coloured, a ringing alarm holds the full danger ring, and middle-click silences / resumes / starts
  for the current face. The clock panel's timer card and the desktop timer widget follow the pause (they use `timerSpan`, and the widget's
  play button pauses / resumes). Unverified live: never loaded.
  **Round 2 (same day, "I don't really like how it looks, it could use more imagination and animations"):** the gauge-in-a-card face was
  replaced by `components/TimerDial`, a scalloped COOKIE that IS the time left. It shrinks as the time goes (growing to full when a run
  starts), turns slowly and breathes while running (loops on `Motion.pulse`-class decoration, only while `running`, only with animations on, only
  while its face is on show — `live`), freezes and dims when paused, goes the warning colour for the last ten seconds (a bump and a ring every
  second) and danger when time is up, where fourteen small cookies burst outward and it shakes until dismissed. A star orbits the rim once a minute
  (`orbit` is unwrapped turns, so it never swings back); a ring leaves the rim each minute; the digits are `RollText`. An idle timer's cookie is
  TURNED to set minutes (drag round from 12 o'clock, a bump at each detent, `Timers.setTimerLength`; a tap that doesn't move starts it); "Exact time"
  unrolls the h·m·s steppers. The stopwatch's cookie grows over each minute and pops back at the next, hundredths beside the digits, laps drop into
  the list (`ScriptModel` + an `add` transition). Alarms: a scalloped `ClockFace` shows the time being set (hands glide), a small one sits on each
  alarm (day / night tone), "Next Tue 07:30 · in 7 h 12 min" heads the list. Faces slide in the direction of the tab picked (all four sit in one
  box, `stage`, as tall as the face shown; `enabled` — not `visible` — switches them, because a hidden layout's height is stale for a frame when it
  returns); the banner and the exact-time box unroll; trays fade in as they become possible. Unverified by eye, and the dial can be rendered offscreen
  to look at it — ask first (CLAUDE.md). **Voice**: a face (or the "+n") opens
  `modules/panels/VoicePanel` beside it — everyone in the call, mute/deafen/leave; a
  RIGHT-click opens it on that person (`UiState.sidePanelArg`, the one generic "what was
  this opened on" slot): their volume 0–200% and a real per-person mute, for you
  (`Discord.setUserVolume` — coalesced, a slider sends per frame — and `setUserMute`;
  the helper's `userMute`, and SET_USER_VOICE_SETTINGS' REPLY updates the list, no event
  follows it), presets, and their balance (`setUserPan`, -1…1 ↔ Discord's `pan {left,
  right}` gains, the helper's `pan()`). Two tabs: People and Your audio (mic + a live
  level, output, devices, voice activity / push-to-talk, noise suppression / echo / AGC —
  `Discord.processing`, `inputMode`, `in/outputDevice(s)`; the helper refuses a key, mode
  or device id Discord didn't list, and `_hold` keeps a stale snapshot from flicking a
  just-changed control back). Over them a strip: connection, ping, duration, open
  Discord, screen share / camera (keystrokes — the panel closes first; a blocker shows in
  the strip on hover). People join/leave on ListView transitions; only a TAB switch eases
  the panel's height (`switching`) — a row opening already moves it, and easing that too
  would chase. The sidebar's faces are a ScriptModel keyed by id (they pop in on join).
  **Lens** (`SideLens`, SUPER+O / SUPER+SHIFT+O, `qs ipc … call lens text|translate`):
  `services/Lens` runs slurp (`%x %y %w %h %o`) → grim into `$XDG_RUNTIME_DIR` →
  `scripts/lens.py` (tesseract TSV → lines with boxes; images under 1000px tall are 2×
  upscaled first — a 13px line misreads otherwise; only INSTALLED languages from
  `Config.lensOcrLangs`) → `modules/panels/LensOverlay` (per screen, Overlay layer,
  Exclusive keys, content behind a Loader, a held copy for the fade): the region frozen,
  each line boxed (click = copy), translate paints each line's translation over it
  (`lyrics-translate.py` with the lyrics' backend order, no cache — network backends SEND
  the text, on a click only). Geometry is `services/lens.js` (`bun scripts/test-lens.js`);
  `python3 scripts/test-lens.py` reads a generated image with the real tesseract.
  **Claude Code** (`SideClaude` → `modules/panels/ClaudePanel`): `scripts/claude-sessions.py`
  imports claude-presence.py's registry reader (`~/.claude/sessions`, pid+procStart
  checked) and merges OPTIONAL hook state from `scripts/claude-hook.py` (async Claude Code
  hook → `$XDG_RUNTIME_DIR/quickshell-quicktest-claude/<sid>.json`, 0600; records a tool's
  name and a file's BASENAME, permission prompts, the last reply's first 200 chars —
  never prompts or command lines), installed/removed ONLY by the user via
  `scripts/install-claude-hooks.py` (backup, idempotent, keeps other hooks; the panel's
  button runs it). `services/ClaudeSessions`: `needsYou` (hooks), `fresh` (busy → idle
  since the panel was opened), `focus(pid)` → the helper walks the pid's parents to a
  Hyprland client → `Hypr.focusWindow`. The cell's mark is `components/ClaudeBurst` — the
  user's animated WebP (`assets/logos/Claude.webp`) as a white-on-transparent SPRITE SHEET
  (`scripts/claude-burst.py` keys the orange plate out; Qt here has no WebP plugin, so
  `AnimatedImage` can't play the original), tinted like any glyph. While working it plays the
  loop, rests a beat and repeats; a stop lets the loop finish (a constant 25 fps would redraw
  the bar's window for the hours a session works). `python3
  scripts/test-claude-sessions.py` (fake HOME / runtime / CLAUDE_CONFIG_DIR).
  **Recent + resume + rate limit** (2026-10-03, the user's ask): the panel also lists ENDED
  sessions — the newest transcripts under `~/.claude/projects`, any project, `entrypoint` "cli"
  only (no `claude -p`/SDK runs), not held by a live pid — and a click runs `claude --resume
  <sid>` in a terminal via `Terminal.runIn(cwd, argv)` (argv + `workingDirectory`, no shell
  string). The cwd is the one RECORDED in the transcript, never decoded from the directory name
  (the munging is lossy), and `--resume` only finds a session from the directory it lives in —
  that is why a session of this repo resumes in `~/.config/quicktest`. "New in quicktest"
  starts `claude` in `Quickshell.shellDir`. The helper vets `sid` (`SID_OK`: never a flag) and
  that the cwd still exists. Live rows are keyed by PID: two registry files can carry one
  session id. A `ScriptModel` has only a `modelData` role, so `ListView.section.property` finds
  nothing — the first row of a group draws its own heading (`first`).
  **The rate limit has exactly one source: the status line.** Claude Code writes the 5-hour and
  weekly usage nowhere on disk (a transcript records a quota only when a request is REJECTED,
  as `quotaLimits` on a 429), but passes `rate_limits` {five_hour, seven_day}.{used_percentage,
  resets_at} to a status-line command. `scripts/claude-statusline.py` keeps only that block
  (`$XDG_RUNTIME_DIR/quickshell-quicktest-claude-rate.json`, 0600), prints nothing, always exits
  0, and WRAPS a status line the user already has (`ours -- theirs`, same stdin, their output);
  `install-claude-hooks.py` sets it with the hook and `--remove` puts theirs back exactly. The
  user chose this over reading `~/.claude/.credentials.json` for Anthropic's undocumented
  `/api/oauth/usage` (fresh with no session, but it sends the login token from a new place
  and the endpoint can change) — don't switch without asking. The figures are as old as the last
  reply any session made: `claudeusage.js` (`bun scripts/test-claudeusage.js`) says "as of 3h
  ago" past 30 min and reads a window past its `resetsAt` as EMPTY, never as its old
  percentage. Unverified against a live statusline payload: `resets_at`'s format (parsed as
  epoch s, ms or ISO) — the first real `rate` message is the check
  (`qs ipc … call claude status` → `rate=true`).
  The overview's call bar (now `modules/discord/DiscordCallBar`) had a right-click menu
  doing the same mute. `components/Avatar` is the round face both draw; deafened is
  `\u{F07CE}` headphones-off (F02CE, used before, is a HEADSET). **The frame's strip
  counts as bar**: welded, every surface starts at the SCREEN edge (`SideRail.surfaceLo` 0)
  with the strip inside its `sidebarDepth`, and what stands on it centres across the whole
  band (centring on the lobe alone left `inset + strip` on the strip side). Along the edge,
  welded, the pills are `inset` from the screen's own corners
  (`SideRail.pinDepth` 0). DockReserve reserves `sideSurface().reserve − strip` on top of
  the frame's zone.
- **The sidebar HOLDS its side's panels** (user's pick, 2026-09-28). They hang off
  its face (`SideRail.panelFace` = `band` = `surfaceHi`, 68 here → `BarPanelDock.leftFace`/`rightFace` →
  `BarDock.sideFace`) and melt out of the corner it makes with the bar, so nothing on the
  rail steps or collapses for them (`SideRail.obstacles` drops that side's cards). Stepping
  ran out of room past ~330–420px of panel: the dock parked above the stats with the card
  over its top and 28px of it bare. An open panel keeps an auto-hiding bar out
  (`holdingPanel`); SUPER+SHIFT+D slides the panel back to the strip with the bar
  (`BarDock.edgeInset`, eased). `panelFace` must never read `cards` or `barShown` — both
  follow the panels' x. A bottom sidebar doesn't hold panels; cards crossing it still step it.
- **Buttons with panels** (the user's picks, 2026-09-29): the stats and the clips are ONE
  bar-style button each (small modules, 1 cell, groupable like the rest — only the dock
  stands alone), with a LIVE GLANCE at rest, and their panel opens BESIDE the button:
  `modules/bar/SidePanelDock` melts it sideways out of the sidebar's face level with the
  button (not the side's bar column, which hangs from the top corner). One at a time,
  `UiState.sidePanel` / `sidePanelFrom` (the button, whose rail place anchors it) /
  `sidePanelScreen`; exclusive with the bar column on the sidebar's side (opening either
  closes the other); closed by Escape, the button again, SUPER+SHIFT+D, or the button
  leaving the layout. Motion is the melted dock preview's: `grow` out of the face, `narrow`
  from a button-wide bud; switching buttons GLIDES the card along the face while the
  content crossfades (Accordion). Its ends SNAP into a corner within `rail.apart` of one (an
  end just short of the bar or strip blends into a bump). Welded it is the
  `BlobBarLayer.sidePanel` lobe; floating, a card a gap off the face. Panels may declare
  `maxHeight` (in: the room; scroll past it) and `autoCloseMs` (out: close unless hovered).
  `qs ipc … call sidebar panel stats|clips|notifications|clipboard|timer|voice|claude|screentime` toggles one.
  **The sidebar speaks the TOP BAR's vocabulary** (the user, 2026-10-02, after a round of
  rings, thumbnails and app-initial discs read as "very weird": "make it similar to the
  topbar"): monochrome glyphs, no rings-with-numbers, thumbnails or face icons on the edge.
  A round that put readings under glyphs (`SideCell.caption`, still there, unused), stats as
  a cell per metric and a count badge on the bell did NOT survive in the code — what's left
  of it: `components/CountBadge` (UpdatePill's badge, shared) and `sidemodules.js
  statsCells` + its test (unused; SideRail doesn't call it — when it did while SideStats
  drew one cell, the stats pill ran ~150px past its button). **Notifications** shows a DOT
  (no number, the user's pick) while `Notifications.unseen` > 0 — arrivals since its panel
  was last open (`seenAt`, persisted in notifications.json; a document without it counts
  everything as seen), never the total; only the side panel marks seen. **Clipboard**
  flashes a check when a NEW newest entry lands (by `at`, so deleting the top entry
doesn't), and its panel steps aside 600ms after a pick. Both
  panels draw the overview's own lists: `components/ClipboardList` and
  `modules/notifications/NotificationGroups` (lifted out of OverviewClipboard /
  OverviewNotifications; the lock screen's centre uses the latter too, with
  `actionable: false` so nothing opens behind the lock). Since 2026-10-06 the
  notification list is flat `NotificationRow`s under a slim app header (no card-in-card
  pile; a busy app shows 2 + "N more", remembered by app name across arrivals).
  **Retheme 2026-10-21** (round 2, after "boring, doesn't fit the overview"): the body is
  `modules/notifications/NotificationCentre` (header, Undo, empty state, list), hosted by
  `NotificationsPanel` AND the overview's notification card, so they can't drift. A notification
  is a TILE (`NotificationRow`: a faint text-colour wash on whatever it sits on, no outline): the app's icon in a
  ShapeBox cookie (Config.iconShape applies), tinted by a hash of the app name from
  primary/focus/info (critical = danger, tile and all), winding under the pointer; a sender's
  avatar replaces the icon, circled inside the cookie; the time is a pill; the ✕ and an app's
  Clear are `HoverTray` chips; actions and "N more" are `ChipTray` pills. Groups are headed by a
  slim label. Compact (the overview): NO ground of its own (a tinted pill behind it read as a box on a
  box — the user, 10-21 — so it blends into the grid card), and a HUD-card-shaped header
  (ScallopChip, title over subtitle, ChipTray);
  non-compact (the panel) keeps PanelHeader. The groups PopIn once per open
  (`cascade`/`opened`/`settled` — a group made later by an arrival is just there, or each
  notification would replay the page); the lock screen's list is `cascade: false`.
  **Features (2026-10-21, round 3)** — logic in `services/notifyview.js` (`bun scripts/test-notifyview.js`),
  state in `services/Notifications`, UI in `NotificationCentre` / `Row` / `Groups` / `Strip`:
  search (words in any order over app/summary/body; the field shows once there are 5+); a
  per-app **summary strip** (a chip per app with its count — also the filter); **by app ↔ by day**
  ("Last hour / Earlier today / Yesterday / Earlier"); **select** mode (tick tiles → dismiss with
  Undo, or snooze 1 h); **timed DND** (`dndFor` / `dndUntilMorning`, `dndUntil` persisted, expiring
  on the Clock's minute tick and on load); **mute an app** (`mutedApps`: still lands in history, no
  toast or chime; critical breaks through, as for DND); **snooze** (15 min / 1 h / 3 h from a tile
  — the record leaves the history, the app is NOT told it was dismissed, and it comes back on top
  as new with a toast, unless quiet, on the minute tick: a woken record is plain data, so its
  actions are gone); **copy**; and **reply** (only while the app still holds the notification and
  `hasInlineReply`). `muted`, `snoozed` and `dndUntil` live in `notifications.json` beside `dnd`.
  A toast can now sit over a plain record (the snoozed ones): `showPopup` no longer matches on an
  absent `id`, and `closePopup` finds the record by key. Not built: pin, a rolling unread count,
  an arrival glow (PulseOnce owns `scale`, which the cookie's wind already drives). A click
  runs the default action while the app still holds the notification live, else
  focuses/starts the app (`Notifications.activate`); live action buttons show on the
  row. Clearing is instant with an `UndoBar` (`clearHistory`/`clearApp` return what they
  removed, `restore` puts it back); rows new since the panel opened keep a dot. The old StatsHost/ClipsHost pills
  and their hover cards are gone; `components/CardSection`, `sysstats.js fitSections`,
  `page`, `move` and `reorder` were theirs and are now unused (flagged, not deleted).
- **System stats**: `modules/bar/SideStats` (the button) → `modules/panels/StatsPanel`
  (`Config.sidebarStats`, off by default).
  - **On the edge**: ONE cell, a level bar for each of the first three metrics, in the
    cell's tint, gliding on `Motion.glide`. Never recoloured by value. (A cell per metric
    with its reading under the glyph was tried 2026-10-02 and didn't survive — see above.)
  - **The panel**: a tile per metric — a `RadialGauge` ring (the CPU and GPU
    temperatures are a thinner INNER arc on their part's ring, `sidebarStatsTempArcs`, not
    rings), the part and its hardware, the headline, every fact with an icon, a minute's
    trace, the CPU's threads, the devices' charge bars, and "over its threshold" — alerts
    show there (and in an optional notification) and nowhere on the button, by request.
    Click a tile: its settings page; middle: the system monitor. It scrolls past the room.
  - **Sampling**: `services/StatsSampler` (a type, not a singleton) holds SysInfo /
    NetStats / SysStats' disk / DeviceBatteries for the CONFIGURED metrics while its owner
    wants them — the button while it's on screen (devices even while auto-hidden), the
    panel while it exists. Refcounted underneath, so the two never count each other.
  - **Device batteries** (`devices` metric): `services/DeviceBatteries` merges UPower's
    peripherals (Bluetooth via BlueZ, anything with a kernel power_supply) with OpenRazer
    (`scripts/razer-batteries.py` over `busctl`, once a minute) — mainline can't read a
    Razer dongle's battery, so UPower never lists it. The ring is the LOWEST charge, the
    panel lists every device (`mergeDevices`; a wireless mouse charging on its cable shows
    up twice and is merged by base name). The panel has a charge BAR per device (`meters` in
    `readout()`, a `Meter` with the device's own low-battery point as its `limit` — never a
    red fill), and with one device, what OpenRazer reports under it (`deviceRows`: link,
    DPI · Hz, sleep timer, low threshold, firmware). Its icon is `glyphScale` 0.7: the mouse
    glyph fills its whole box and read too big beside the others. A Razer device is drawn
    as Razer's SNAKE instead (user's call): `scripts/theme-logo.py` lifts it out of the
    INSTALLED icon theme's app icon (Papirus `razercommander`; `rect`s and see-through
    layers dropped, cropped via ImageMagick) into the cache, and `TintedIcon` draws it as a
    stencil in `Colors.fg` (`readout().logo`). The logo is never shipped in the repo;
    without such a theme icon it's the mouse glyph. `python3 scripts/test-theme-logo.py`. OpenRazer answers 0% for
    a sleeping device, so 0 is dropped. The poll is gated on the SETTING, not the ring: with nothing found the
    ring drops out, and a ring-gated poll would never see the device return. OpenRazer is
    NOT in `install-dependencies.sh`, not even as a comment: most users have no Razer
    hardware (the user's call). The ring works without it. Nothing listed? Ask the
    sources, not the shell: `python3 scripts/razer-batteries.py` (`[]` → `journalctl --user
    -u openrazer-daemon`: the group is `openrazer`, and the dkms module needs the running
    kernel's headers) and `bluetoothctl info <mac> | grep -i battery` (no line → BlueZ has
    no Battery1; an HFP speaker needs BlueZ `Experimental = true` for PipeWire to report it).
  - **Logic**: `services/sysstats.js` (`bun scripts/test-sysstats.js`). `SysInfo` owns
    the counters, including disk I/O from `/proc/diskstats` and `memHistory`.
    `services/SysStats` owns which metrics there are (`metrics`, `unavailable`), ONE
    `readout(key)` per metric that the button and the panel both read (`ratio`, `inner`,
    `glyph`, `label`, `name`, `value`, `rows`, `history`, `meters`, `page`…), `df` for the
    disk, the sustained alerts (`isAlerting`), and the middle-click monitor. A
    top-processes list was built and then removed at the user's request; don't bring it
    back unasked.
  - **Unavailable rings drop out**: `statsMetrics(list, unavailable)` handles GPU on
    NVIDIA, no swap, or no battery.
  - **Fixed scales**: the network ring uses `sidebarStatsNetMbps`, never the recent
    peak, and the temperature arcs run 0–100°C.
  - **Hardware names** ("GPU — AMD Radeon RX 6700 XT"): `scripts/hw-names.sh` runs once
    (raw CPU/Vulkan/lspci/disk-model strings), and `sysstats.js` `cleanCpuName`/`gpuName`
    tidy them. Vulkan's deviceName is the marketing name; lspci only knows the chip family.
  - **The rings glide** (`RadialGauge.glide` → `Motion.glide` 700ms, InOutSine) rather
    than `Motion.settle`: the user asked for smoother. It still rests ~300ms per 1s sample;
    the 4Hz network ring retargets mid-glide. Don't opt other gauges in by default. The
    button's bars glide the same way.
  - The pill's "numbers in the rings" and "rings per page" settings went with it
    (`sidebarStatsNumbers`, `sidebarStatsPageSize`): the panel has room for everything.
- **SUPER+SHIFT+D** (`qs ipc … call sidebar toggle`, `UiState.sidebarHidden`, runtime
  only) sinks the dock and the pills into the frame. While hidden there's no edge reveal
  and no reserved space. The bind is in `hypr/binds.lua` and the live copy.
- **`services/Terminal`** is the one place the terminal is resolved (Config, then
  `$TERMINAL`, then the fallback). The launcher's `>` mode and the stats middle-click
  both use it.


## Window, layout, brightness and lock modules (2026-10-07)

Four modules with BOTH a bar form and a sidebar form (one catalogue entry each in
`config/modules.js`; a module lives in one place, so placing it on one surface takes it
off the other). Each opens the same panel in either dock (`BarPanelDock` / `SidePanelDock`
registries, `Config._defaultPanelSides`).

- **Focused window** (`window`) — on the sidebar (`SideWindow`, one cell) the app icon with the app's NAME under it
  (shrunk to fit, then elided; the icon in silhouette when `Config.colorizeIcons` is on), swapped on focus like the
  bar's pill (`SwapFade`); the title, class and state are in its HOVER CARD. A rotated title down the edge was tried
  and read badly (2026-10-17). ``services/ActiveWindow`: per monitor, the focused toplevel
  if it is on that monitor, else the most recently focused one on its active workspace.
  `WindowPanel` acts on that window BY ADDRESS (`{ window = "address:0x…" }` selectors in
  `hl.dsp.window.*` — measured: a fake address returns "ok" and leaves the active window
  alone), so a click never lands on whatever got focus meanwhile. Close goes through `ArmLatch`.
- **Window layout** (`layout`) — `services/HyprLayout`: `hyprctl eval hl.config({ general =
  { layout = … } })` live (dwindle/master/scrolling/monocle all take on 0.56.2), read back
  with `getoption`, and written to `appearance.lua`'s `layout` line through HyprConfig
  (`scripts/hypr-config.py` APPEARANCE). The id is whitelisted — it is spliced into Lua.
- **Brightness** (`brightness`) — `services/Brightness`, every display in one panel; the
  pill/cell scrolls ITS screen's display, matched on `port` (the Hyprland connector; `name`
  is the I²C bus).
- **Submap & locks** (`locks`) — `services/KeyLocks`: submap from the `submap` event; Caps/Num
  from a runtime Lua hook that posts only `custom>>qs-locks` on a 58/69 release (nothing
  about other keys leaves the compositor), then one `hyprctl devices -j` read. The hook
  exists only while a module holds `acquire()`; settings previews never acquire.

IPC: `qs ipc … call bar add <id>` / `bar remove <id>` (the sidebar's `place`/`remove` twin),
`sidebar panel brightness|window|layout`.

### Every module on either surface (2026-10-07)

Every catalogue entry now has both forms except the four that are rows of live things
(workspaces, tray, visualizer) or the sidebar itself (dock). The missing forms are two
generic files keyed by `moduleId`, not one file each:

- `modules/bar/SideBarModule.qml` — a bar module as a sidebar cell: glyph/symbol (SideCell
  gained `symbol`, filled while active), an optional reading (`caption`), and the pill's
  click. Portable bar panels (colorScheme, equalizer, wifi, bluetooth, gaming, clock) are
  registered in `SidePanelDock` and open beside the cell; wallpaper and updates keep their
  bar panels. SideGroupHost hands the id over (`m.moduleId`).
- `modules/bar/widgets/SideModulePill.qml` — a sidebar module as a bar pill. Self-contained
  panels (stats, clipboard, timer, claude, screentime, clips) are registered in
  `BarPanelDock`; voice's pill is the mute switch (its panel follows the sidebar's call
  faces). ClipsPanel's target button opens Settings › Clips when not in the sidebar.

`UiState.closePanel(name)` closes the panel in EITHER dock. **Upgrade trap, fixed:** the
bar's reconcile appends modules missing from `knownModules`, so the first load after a
sidebar module gained a bar form put it on BOTH surfaces. `Config._barKnown()` counts every
module with a sidebar form as known; such a module waits in the pool.

## Idle actions (2026-10-08)

"After N minutes without input, do X" — `inactivity` in the catalogue, a cell on the sidebar
(`SideInactivity`) and a pill on the bar (`SideModulePill`), one panel either dock holds
(`modules/panels/InactivityPanel`, `Config._defaultPanelSides`). A LIST of rules, each
`{ id, enabled, minutes, action, command }`: lock, screen off, suspend, hibernate, log out,
power off, or a command of the user's own.

- **Logic** is `services/inactivity.js` (`bun scripts/test-inactivity.js`): the trust boundary
  between a hand-editable file and the thing that powers the machine off — minutes clamped
  1–720 (a NaN must never become "idle at once"), unknown actions dropped (never defaulted),
  ids made unique, 8 rules at most, ordered by timeout. A command is parsed to an ARGV
  (quotes and backslash only; no shell, no variables), so what runs is readable off the field.
- **`services/Inactivity`** runs it: one `IdleMonitor` per rule, `respectInhibitors: true`, so
  Stay awake (`Idle`) and Gamemode pause EVERY rule. Actions go through `Session` (power verbs,
  lock) and `Hypr.setDpms` (screen off); a rule that can't run says why (`blocker()`:
  hibernate without logind support, an empty command) and is skipped at fire time.
  `qs ipc … call inactivity status|on|off`. Eager in shell.qml (`Connections`).
- **Rules live in `statePath("inactivity.json")`, not config.json**, on purpose: config.json is
  also what a Shell preset carries (`Config._dumpPrefs`), and a shared preset must not be able to
  arm a power-off or a command. `Config.lockIdleEnabled` / `lockIdleMinutes` migrate ONCE into a
  "Lock" rule (an off setting stays off).
- **Log out and power off warn first**: their monitor trips 30 s early, a critical notification
  says so, and the action runs when the window ends unless input (or switching the rule off)
  cancels it. Critical notifications never auto-dismiss in this shell, so every exit from the window
  dismisses the warning (`_clearWarning`) — a cancelled "Powering off in 30 s" must not linger.
- **Screen off wakes itself** when its monitor sees input again. Hyprland does NOT wake a blanked
  monitor on input unless `misc.mouse_move_enables_dpms` / `key_press_enables_dpms` are set
  (neither is in `hypr/`); if the shell dies while the screen is off, only those bring it back.
  The dpms dispatch's argument table (`{ action = "off" }`) is modelled on the other dispatchers,
  not yet measured on 0.56.2.
- Icon: `pause_circle` (already in the bundled font), so no regeneration.

## A quieter sidebar (2026-10-31)

The user: make the sidebar "cleaner and less busy" in the Material 3 style. Their picks:

- **One inner pill per region** (`modules/bar/SideRegionPills`): start, centre and end each draw one
  `SidePill "inner"` from their first group to their last, with a `Divider` hairline (inset
  `spacingMd` across the pill) centred in each gap the rail leaves between groups. Six pills became
  three. `SideGroupHost` and `DockHost` no longer draw a pill of their own. Geometry is
  `rail.placed` (the same pos/len the hosts stand at), the reveal is `rail.cross`, the start region
  collapses with `rail.startCollapsed`, and the blob's deform matrix applies as it does to the hosts.
  Still the top bar's inner pill (2026-10-17's call), only fewer.
- **Connected hover**: each region pill holds a `HoverTrack` (`SideRail.regionTracks`; the hosts
  hand it out as `hoverTrack`), so hover is one plate sliding between every button in that pill,
  the dock's apps included. See `docs/bar-and-blob.md` › the hover track.
- **The dock's marks are one calm line** (`DockIconStrip`, `barFeedback`): `borderChrome` thick and
  `spacingXs` in from the cell's inner edge, the same as `CellFeedback`'s active mark. The focused app's
  is the cells' length (`focusMarkLen`); running is the same line short and muted instead of a dot;
  an app making sound stretches its line toward the focused length by its loudness instead of three
  level bars (the bars' meter still runs, `bars.measuring`). The overview's dock is unchanged.
- **Call faces are one overlapping stack** (`SideVoice`): an M3 avatar group, faces at 0.75 of the
  icon size overlapping by 40%, each ringed in `surfaceContainer` so the overlap reads, and the "+n" as
  the stack's last disc. One cell for two items, half a cell for each after (`sidemodules.js
  stackCells`, fractional, which `Config.sidebarRun` takes). Right-click opens the panel on the
  face under the pointer (`faceAt`).
- **The focused-window cell is the icon alone**, at the dock's icon size, with the name left to the
  hover card. It **steps aside** (0 cells, so the rail closes the gap) when the dock on that edge
  already draws the focused app (`Config.dockEnabled && Taskbar.onDock(key)`) and on an empty
  workspace. Both of those are `sidemodules.js windowCells`, which `SideRail.cellsFor` (now told its
  `screenName`) and `SideWindow` both ask. Arranging always shows it. Hiding it on an empty workspace
  was my reading of the pick; it used to show "Desktop" there. A small module whose cells are 0
  now has length 0, not a bare pill margin.

### The dock, second pass (2026-10-31)

The user: "the dock could look better". Their picks: everything on the list, with the icons as Android's
themed icons.

- **Themed icons — DROPPED the same day.** On screen some icons drew blank (the Canvas wasn't `available` when
  the cut asked for its context: "Unable to use getContext() at this time") and every `image://icon` one stayed in
  colour (the crash fix's fallback). The user: "completely off … take a look at how end-4 shell does it". The dock
  and SideWindow now tint with `components/MonoIconEffect` (a layer gated on `Config.colorizeIcons`, rasterised at
  `iconRaster` so the hover lift stays crisp): first end-4's desaturate 0.8 + a tenth of the accent, then a colorize
  toward the palette's `vivid` ("more saturated"), and finally — the user's preference — plain grey: saturation -1,
  brightness +0.15. What follows is
  the dropped design, kept for its measured Canvas traps; its files (`ThemedAppIcon.qml`, `themedicon.js`,
  `scripts/test-themedicon.js`) were deleted on the user's go.
- **Themed icons** (`components/ThemedAppIcon` + `components/themedicon.js` — deleted).
  These are what `Config.colorizeIcons` now means in `DockIconStrip` and `SideWindow`: the glyph cut out of the app's colour icon,
  in `fgOnPrimaryContainer`, on a round `primaryContainer` plate. Colorizing the whole icon (a MultiEffect layer)
  had sunk any logo-on-a-disc icon into a flat disc. Papirus has a monochrome icon for almost no app (of
  the dock's, only GNOME Settings), so the glyph is CUT. A ring at 40% of the icon samples for a plate; on a
  plate, a pixel's ink is its colour distance from the plate's, gated to opaque pixels (or the plate's
  anti-aliased rim comes out as a ring); with no plate it is the silhouette, shrunk to Android's 2/3; a plate
  whose glyph is nearly nothing or nearly everything falls back to the icon itself, shrunk, in colour (Vesktop's
  rainbow tile). Checked on the real Papirus icons (Steam, Discord, Spotify, kitty, Settings, Zen, VS Code,
  Obsidian, VLC come out clean; Firefox weakly, as on Android).
  - **Canvas traps, measured on Qt 6.12** (headless, `qmltestrunner`): the image calls take a STRING (a `url`
    value makes `createImageData` return nothing and `drawImage` draw nothing); a `canvasSize` larger than the
    item is not scaled down but windowed (`canvasWindow`); `putImageData` of an image from `createImageData(url)`
    drew nothing, while `drawImage(imageData, …)` scales and draws. So the cut uses `createImageData(url)`
    (the icon's own pixels, no read-back), and `drawImage` puts it back at the item's size. Bare paths
    (Icons' Papirus map) are made `file://` URLs first.
  - With no source it does nothing, so an icon drawn as itself costs no cut.
- **The launcher is the dock's main button** (`StartCell.hero`, sidebar only): the glyph at 2/3 on a filled
  `primary` rounded square (corner 0.3 of its side, Material's FAB), rounding into a circle on `springSpatial`
  while the launcher is open. A divider follows it (the `lead` gap the ii style had, now also `barFeedback`).
- **Pinned | running divider** in a `divider` gap after the last pin (`pinGap`), only at rest: a drag or an
  insert closes it, so dock.js's whole-slot drag and drop arithmetic is untouched. Positions go through
  `slotPos(i)`, points back through `unGap(main)`; a run pill can cross the gap (its span is measured to its
  last button).
- **The icons lift on hover** like every other cell's glyph (`wash.lift`, as a Scale before the face's
  Translate). The start button's scale Behavior is off on the sidebar, so it doesn't chase that spring.
- The dividers here and the region pills' are one component (`Divider`).

## A livelier sidebar (2026-10-31)

The user: make the sidebar and its modules "more interesting". Their picks: all four ideas below, each calm while nothing
is happening. Also this round: the clips button's record dot became the `videocam` symbol (FILL = the buffer is running,
an outline when clipping is off, breathing while recording; the catalogue already showed that symbol).

- **Shapes for live state** (`components/LiveShape`): a tonal Material 3 Expressive shape grows out of a cell's glyph
  centre while something is happening, morphs when the state changes (MorphShape), and shrinks away keeping its last
  outline. The glyph sits on it at 0.68 in the container's ink. `beat` turns one petal (shapes.js `turnFor`) every
  `Motion.pulse * 4` on the spring, so a working state ticks rather than redraws. Warning/danger tones are
  `alpha(role, 0.22)`, the armed cell's recipe (the palette has only `primaryContainer`). `SideCell` takes `liveShape`
  / `liveTone` / `liveInk` / `liveBeat`. Wired: Claude (working = cookie9 on primaryContainer with a beat, needs you =
  burst in warning; the burst's scale onto it is a Scale transform, so its press Behavior doesn't chase the spring),
  timer (inside its ring: running countdown/focus = cookie9, stopwatch = sunny, paused = squircle in warning, ringing =
  burst in danger; no beat, the ring is the motion), clipboard (a burst behind the check for `copiedMs`).
- **Hover chips** (`modules/panels/HoverCard`, kind = module id; `components/SideHover`): the window cell's hover card,
  for every module: its catalogue name (`Config.sidebarModuleList`) and a line from its service (`valueFor`), sized
  to its text (`sideCardUnit` 2–5). `SideCell.hoverKind` opts a cell in (tasks, colour's eyedropper, inactivity,
  power, the voice mic, clipboard, timer at rest); Claude, clips (not mid-hold), stats and the running timer hold
  their own `SideHover`. SideHover now closes its card when it is disabled (the power menu opening under it).
- **Event peeks** (`modules/panels/EventPeek`, side panel "peek"; `components/SidePeek`): the clips peek's rules for
  every module — focused monitor only, a free slot (a hover chip gives way), not over the bar's panel column, not
  while arranging or sunk; a peek already up keeps its place. Kinds: timer (finished / alarm ringing; Dismiss, Snooze
  5 min; 6 s), claude (needs you / finished a turn — the newest of `fresh`; "Go to it"; 6 s; counted against the last
  count so the session list loading isn't an event), colour (swatch in the picked colour + hex; 2.6 s; the copy the
  pick makes then finds the slot taken), clipboard (an image or the first three lines in mono; 2 s; password
  managers' copies never reach the store — `clip-store.py is_secret`). Each has a switch: `Config.peekTimer /
  peekClaude / peekColour / peekClipboard` (Settings › Sidebar › Peeks).
- **Richer glances**: tasks wear a wavy done/total ring (SideTimer's geometry, the glyph fitted inside) while anything
  is open — the count badge went, the chip says it; the clipboard shows its last copy at rest when it is a picture (a
  rounded thumbnail, Avatar's mask) or a `#rrggbb` colour (a swatch), never text; dock apps carry a `CountBadge` of
  unseen notifications (`Notifications.unseenByApp` / `unseenFor(appId, name)`: since the notification panel was last
  opened, keyed by desktop entry and app name, lowercased).

### Like the top bar: islands, a hero, now playing, the music (2026-10-31)

The user: the sidebar is "boring compared to the top". Picks: all four below (Settings › Sidebar › Look).

- **Islands** (`Config.sidebarIslands`, default on): `SideRegionPills` draws a pill PER GROUP, keyed
  `"region:ids"` (SideRail.smallGroups' key, so a group that only moves keeps its pill; the keys are a joined
  string, so the Repeater rebuilds only when the set of groups changes). Each island's HoverTrack is registered
  under that key; SideGroupHost and DockHost ask for their island's first, then their region's. Off: one pill
  per region with dividers (the "quieter sidebar" pick, kept as the alternative).
- **The hero** (`Config.sidebarHero`, default `"claude"`, "" none): a `primaryContainer` chip under that module's
  cells (`rail.at` / `rail.allLengths`), `Config.sidebarCell` across, a hover plate's radius. `SideCell.hero`
  (its `hoverKind` is the module id) turns the glyph to `fgOnPrimaryContainer`; SideClaude, SideTimer's running
  view and SideNowPlaying do it themselves. A LiveShape on the hero's chip is filled `primary` with
  `fgOnPrimary` ink, or it would vanish into the chip. Picked from chips in Settings › Sidebar › Look
  (the module inspector is the top bar's).
- **Now playing** (`modules/bar/SideNowPlaying`, catalogue `nowplaying`, side-only, centre): the cover through a
  cookie (MorphShape mask, turned as a child of the layer) in a wavy progress ring in `AlbumArt.accent`, flat
  while paused; the cookie turns one petal per beat (MusicPulse.beats) or every `Motion.pulse * 4` without the
  music edge; position read once a second while playing. Click the media panel, middle play/pause, scroll
  next/previous, hover chip "title · artist". `MusicPulse.player` (the first playing non-Discord player, else
  the first non-Discord one) is its player; with none it steps aside (`SideRail.cellsFor` 0). Not placed by
  default — drag it on in Arrange.
- **With the music** (`Config.barMusicReact`, default on): `components/MusicRim` on BOTH bars' pills (BarGroup's
  chips, SideRegionPills' islands) — a `borderChrome` rim of the palette's `vivid` at `0.65 × glow`, the glow on
  `Motion.springEffectsSlow` toward `0.8·level + 0.25·kick`. Nothing scales, no fill. (First it scaled the sidebar's
  pills on the beat with a wash — the user: "messy", and "limited to sidebar".)
- The dock icons, finally: **grey** (MonoIconEffect saturation -1, brightness +0.15) — the user preferred it to
  the scheme-tinted pass.
