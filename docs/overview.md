# Overview

Moved from CLAUDE.md; the project rules there still apply.

## Overview

A full-screen overlay on the focused monitor (`modules/overview/Overview`): window search
(top left), PowerPanel (top right), the workspace grid (`WorkspaceGrid`) with Alt+Tab and
search working INSIDE it, volume + brightness (`OverviewControls`, bottom centre). Everything
in it is built on open and destroyed on close — see "Open the overlay" under Checking your
work. A `TypeError` in a row delegate isn't a load failure; the surface just renders blank.

- **Redesigned 2026-10-04** (the user's calls): no second page, no dock, no media/lyrics
  cards, no clock, and no canvas — the old frame band/strips and the tinted gradient well
  are gone; the islands stand on an even dim (`dimAlpha` 0.5). The Discord call bar moved
  to `modules/discord/DiscordCallBar` (kept for later; the lock screen still uses it).
  The bar's bell now opens `NotificationsPanel` as a bar panel ("notifications", right).
  Now unused, flagged not deleted: `OverviewDock`, `OverviewClipboard`.
- **No "recent windows" row.** One was built (a row of live cards over the grid) and
  dropped the same day — the user: "it feels like the same feature". Alt+Tab and search
  pick a window IN the grid instead: lifted, ringed in `focus`, its label always shown with
  "2 min ago" (`Switcher.agoText`, from when it last lost focus), every other window
  receding (0.55) and a search's non-matches fading (0.22). The grid turns to the pick's
  page (`pickedWorkspace`). Don't bring back a second list of the same windows.
- **Blur only behind the cards**: `hypr/rules.lua` gives the namespace `ignore_alpha = 0.6`,
  so the dim (under it) isn't blurred and the cards (surfaceOpacity) are. Raise the dim
  past 0.6 and the whole screen blurs. The live `~/.config/hypr` needs this by hand.
- **Search** is the shared `InputField` (it grew `icon` and `keyPressed`: a caller can
  take a key before the field acts on it). Focus stays in the field; `Overview.steer`
  takes ←/→/↑/↓ on an empty field (SPATIAL since 2026-10-20: the window that way on the grid,
  switcher.js `nearest`), Tab/Shift+Tab (recently-used order; ↑/↓ too while typing), Escape (clears the text, then the
  pick, then closes) and digits on an empty field (1–0 = that workspace). Matching is the
  launcher's scorer (`switcher.js filter`).
- **Alt+Tab** (`services/Switcher` + `switcher.js`, `bun scripts/test-switcher.js`):
  hypr/binds.lua posts CUSTOM EVENTS (`qs-switch:next|prev:<addr,…>` carrying Hyprland's
  focus history, and `qs-switch:up` from a non-consuming release bind on ALT_L/ALT_R) — no
  `qs ipc` spawn per Tab. A flick shorter than `revealDelay` (150ms) switches without
  drawing anything; held longer, the overview opens with the pick lit, Tab walks it,
  letting go of Alt goes there (`Hypr.focusWindow` — the window's own workspace and
  monitor, NOT the grid's bring-it-here click rule). Escape cancels. Switcher is eager
  (shell.qml `Connections`) so it follows focus from launch. The live `~/.config/hypr`
  needs the binds by hand. `qs ipc … call switcher status|next|prev|commit|cancel`.


## The redesign (2026-10-17): the panels' look, and a window inspector

The user asked for the overview in the panels' new style (wallpaper, colour, now-playing; Caelestia's
dashboard as the reference — look only, it is GPL-3), with new animations and useful features, "surprise
me". Kept from 2026-10-04: no second page, no dock, no media/lyrics/clock cards, no canvas, and NO second
list of the same windows — the search and Alt+Tab still pick IN the grid.

- **One composition, centred** (`Overview.qml`): a `PanelHeader` ("Your *workspaces*", live counts or the
  key hints as subtitle; the search pill and `PowerPanel` as its actions) squared to the grid card's edges,
  the grid in ONE container `Surface` with a `DriftShapes` cookie field behind it, and the island below in a
  FIXED slot (`stage.islandSlot`, the inspector's height) so a pick grows it downward and nothing above
  moves. The cells are a little see-through (`fade(…, 0.62)` empty, 0.9 occupied) so an empty workspace
  shows the field.
- **The island** (`OverviewIsland`): volume + brightness (`OverviewControls`, its own surface turned off)
  until a window is picked, then one `Surface` springs (`Motion.spring`) to the inspector's size; the
  controls sink out, the inspector rises a beat behind. The inspector is a `Loader` held `_hold` for its
  fade (a `active: … item.opacity` binding was a loop) and keeps its own copy of the window (`held`).
- **The inspector** (`WindowInspector`): live `ScreencopyView` at the window's aspect, the app's icon on a
  cookie, title, facts (app, workspace, size, "ago", floating/pinned/fullscreen lit), a `ChipTray` (float,
  pin, fullscreen, centre — centre only while floating), the page's 10 workspaces as chips (where it is,
  filled), and a close `CookieButton` behind an `ArmLatch` (twice). Every action is `ActiveWindow`'s.
  Keys (`Overview.steer`, before the search field sees them): Ctrl+F float, Ctrl+P pin, Ctrl+Enter
  fullscreen, Ctrl+W close (twice), Ctrl+1…0 send it to that workspace of the page.
- **Picking with the mouse**: right-click a window in the grid (`Switcher.selectAddress`; again on the pick
  lets it go). The press is not accepted, so no drag starts.
- **Motion**: the grid card springs out of 0.94; the cells ripple OUT from the focused workspace (delay by
  distance, 38ms a cell, capped 220); a window dropped (or sent from the inspector) rings the cell it lands
  in (`WorkspaceGrid.land`); the focused workspace's number sits on a cookie on its cell's corner — ONE
  badge over the window layer (in-cell, a maximised window hid it), gliding on a spring when the workspace
  changes and turning with a `RotationAnimator` (render thread).
- Verified on the live shell (2026-10-17): open, and Alt+Tab-picked with the inspector loaded, log clean;
  screenshots looked at. Not exercised: the Ctrl keys, right-click picking, the landing ring, a drag.


## The HUD corners (2026-10-20)

The HUD moved INTO the overview (the user: no separate keybind/overlay to edit it). Its four cards
sit in the CORNERS round the grid, so the workspaces stay dead centre (the user's call, replacing a
rail beside the grid, then full-width strips, the same day): Clips + Voice above with the
header and search BETWEEN them (the header left its full-width row then), Performance + Input below
with the island between them (Clips and Performance swapped at the user's ask, same day). Every card is one fixed size (`HudCard.bodyHeight`, `stage.sideW`), so the
grid's room (`middle.roomH`) never depends on a card's width — which follows the grid's. The bottom
cards' width is `stage.flankW`: they give way to the island's ANIMATED width
(`OverviewIsland.boxWidth`) as it springs. The island gained a third face, `HudInspector`; a window
pick and a HUD pick clear each other; Escape lets go of a HUD pick before closing. ARRANGING
(`Hud.arranging`) fades the whole stage out and lifts the dim so the widgets can be dragged on the
real screen (`HudArrange`, its own full-screen Loader on the window, not inside the stage). The
cookie field runs over the WHOLE overview (a full-screen DriftShapes on the dim, under every card's
own window onto the same field). The 10-04 rule "no media/clock cards" is about the overview's own
furniture; the HUD cards are the user's explicit call. Details: docs/hud.md.

## Now playing, the peek, and the second motion pass (2026-10-20)

The user picked these from a list of proposals; the motion pass was their ask ("more cool and
smooth animations across the whole overview, at the same quality as the rest of the shell").

- **Now playing in the island** (`OverviewControls`): cover, title/artist, a playhead hairline with
  the times, prev / play-pause / next — a ROW ABOVE volume and brightness, never beside them: the
  bottom strip has height to spare and no width (a wider island squeezes the bottom cards via
  `flankW`). `MediaPosition` picks the player; a new track swaps in through `SwapFade`; no player,
  no row. The playhead's per-frame work runs only while the island shows the controls (`live`).
- **Workspace peek** (`WorkspaceGrid`): 400 ms on an OCCUPIED cell and one card hangs off its OUTER
  edge (above the top row, below the bottom one) listing its windows (icon + title, four, "and N
  more"); it glides between cells while you move, lingers a beat off them, never during a drag.
  The overview raises the grid card (`z`) while it shows, since it overhangs the strips.
- **Entrance / exit**: the cookie field swells in (0.85 → 1); the top strip drops in, the bottom one
  a beat later; each HUD card flies in from its own corner; the cells ripple out from the focused
  workspace and their WINDOWS now follow them a beat behind (they used to pop in with the stage).
  Leaving runs it backwards at `exit` speed — it used to cut the strips in one frame.
- **Under the pointer**: the cards lean and light up (HudCard); the cookie field glides against the
  pointer, up to `spacingXl` px, eased over `glide` — every DriftShapes here takes the same
  `shift` (`UiState.overviewDrift`), so a cookie crossing into a card is still one cookie. A
  Translate on the field's container would do NOTHING: DriftShapes maps the field through its
  window's transform and puts every shape back where it was on the screen.
- **Arranging** arrives as a cascade: the hint drops in, the widgets spring up one after another,
  each tag a beat after its widget.

## Sharper previews (2026-10-20)

The grid's windows and the inspector draw through `components/SharpCapture`, not a bare
`ScreencopyView`: that samples its buffer linearly with NO mipmaps (`view.cpp`
`setFiltering(Linear)`), so a 1920 px window at 330 px read one pixel in six and its text
shimmered. SharpCapture renders the capture into a layer up to 3× its drawn size (capped at the
buffer's) with `layer.mipmap`, then draws that down. One texture per live capture is the cost.
The dock's previews use it too; WindowPeek keeps the bare view (it draws windows at their real
size, so there is nothing to sharpen).

## Round 4 picks (2026-10-20)

- **Search** is a plain field's height (`Tokens.fieldHeight`), not the power tray's.
- **The peek shows today's screen time** while `Config.screenTime` records: per app on the first
  window of each app (ScreenTime counts apps, not windows or workspaces — `todayFor(appId)`),
  and the header sums them ("2.4h today"). Nothing extra when screen time is off.

## The big round (2026-10-20): everything from the review

The user asked for an ambitious review and then "build all of that". What changed, by area:

- **The grid only draws busy workspaces** (`WorkspaceGrid.slots`): the ones with windows, the
  one you're on, the pick's. Their cells share the room (`lay`: the column count giving the
  biggest cell, at the monitor's aspect, capped at 45% of its width), so the grid's size is the
  room's and only the cells inside move. Empty ones are chips in a STRIP under the cells, with
  the scratchpads (`Hypr.specials`, toggled with `hl.dsp.workspace.toggle_special("name")` —
  the form the binary's own example config binds), reopen chips (`ClosedWindows`) and Sessions.
  **While a window is held the grid opens out to all ten** (the user's call, mid-build) and folds
  back when you let go; each cell keeps its own workspace, so busy cells glide and empty ones
  fade in. The cells' FIXED 340×192 rule is gone with it.
- **Windows keep their preview for life**: the window layer is a ListModel keyed by address
  (`winModel`, `_syncWins`), not an index count — a window opening or closing no longer hands
  previews to other windows. A new one pops in; a closed one shrinks away before its row goes.
- **Zoom in and out** (`OverviewZoom`): every "go there" (a cell, a window, Enter, Alt let go,
  a digit) is `UiState.leaveOverview(ws)`; the cell grows to the screen while live stand-ins of
  its windows fly from their previews to their real places, then the overview closes. Opening
  runs the other way for the workspace you're on. The stand-ins read the preview's scene rect
  every frame, so they land on it through the entrance's own transforms. A workspace on another
  monitor just closes.
- **Fullscreen previews** stay inside their cell (`Hypr.previewRect`, shared by the previews
  and the drop maths): a fullscreen window also covers the bar, so its raw size spilled over.
- **Keys**: arrows move spatially; Shift+click a cell or chip sends the window you were in;
  hold Space for the pick (or your window) big and live; the cell's right-click MENU became the inspector's workspace page in round 10 (below) —
  name and icon (`WorkspaceLabels`, `Config.workspaceLabels`; the icon also replaces the
  number in the bar's WorkspacesPill), swap with another workspace, bring its windows here,
  close them all (twice). Escape closes the sessions card first.
- **The inspector's second row**: snap zones (`Snap.snapWindow`, the drag-to-edge rectangles;
  floats it first), the app's sound (`Audio.streamsFor` — the APP's, not the window's), a
  picture / a copy (its own buffer grabbed offscreen at its real size, through Screenshot's
  toast), record it (`Clips.recordWindowSoon`: goes there, then records its area), and its cost
  (`ProcCost` → `scripts/proc-cost.py`, the whole process tree; `test-proc-cost.py`) with force
  quit (`ActiveWindow.kill`, twice). The island's slot grew for it.
- **The search reaches past windows** (`OverviewBeyond`, under the field): a sum or conversion,
  the launcher's apps/actions/settings, recent files. Windows still come first; with none
  matching, Enter runs the first row; Shift+Enter always does.
- **The island**: the playing cover's colour (AlbumArt) on the island, the play button and the
  playhead; play/pause is a cookie; a row of quick switches (Wi-Fi, Bluetooth, DND, night light,
  mic, Game mode). **The header**: live chips — a running timer, reminders due, unseen
  notifications — each opening its own panel.
- **Sessions** (`WorkspaceSessions`): save what's open as a name; restore starts each app on its
  workspace ONE AT A TIME (focus it, launch, wait for its window, up to 8 s) — Hyprland's
  exec-with-rules form isn't documented for 0.56, so this uses only known dispatches.
- **HUD cards**: shorter (2.2 units), bigger titles, each fact said once, live status lines
  (Performance: VRAM/disk/swap; Input: on screen or not), chips only on hover.
- **Not built**: the touchpad gesture (no touchpad here, and the Lua gesture callbacks'
  arguments are undocumented); a fix for the cookie field's tone shift at card edges (the
  field is drawn twice inside a translucent card — needs masking, wants a look first);
  keyboard reach into the HUD cards.

## Follow-ups (2026-10-20, after the big round)

- **The island's now playing is the Now Playing panel's player**: CookieCover (turning cookie +
  level ring), title / artist / album, the wavy seek and the cookie transport — the last two now
  SHARED components (`components/MediaSeek`, `components/MediaTransport`) that MediaPanel uses
  too, so the two can't drift — and the player's own volume (ThickSlider, Audio.playerLevel).
  The system levels and the quick switches sit in a column beside it.
- **Album colours follow Settings › Appearance › "Tint media cards"** (`Config.albumCardColors`)
  for the island as for every other media card. The user didn't like the tint; it's that switch.
- **Dragging is smooth again**: the board is the whole room and never moves (the cells' block is
  centred inside it: `originX`/`originY`); a board hugging the block re-centred as the grid
  opened out for a drag and slid the window layer — and the window in your hand — under the
  pointer. The held window keeps its size until dropped (`_heldW`/`_heldH`), and the rest
  glide without overshoot while a drag is live (`calm`). Cells decelerate, never spring.
- **Notifications open IN the overview**: the bell (always in the header now) turns the middle
  card into the bar's NotificationsPanel, loaded by URL (modules/panels imports this directory,
  so no import back). The card springs to the centre's size inside a fixed slot (`cardSlot` —
  what the corner cards and the island anchor to), the grid sinks out, the centre rises a beat
  behind. Escape, the bell again, or typing go back.
- Sessions and the cell menu stay as built (the user, asked).

## Round 7 (2026-10-20)

- **Labels belong to apps** (`Config.appLabels`, keyed by Taskbar.keyFor): a workspace wears its
  biggest labelled window's app's name/icon (`WorkspaceLabels.labelOf`), so moving the app moves
  the label — the user's call; per-workspace labels went stale on a rearrange. The cell menu names
  one of the workspace's apps (the biggest by default; tap another's icon). `workspaceLabels` is gone.
- **Every close zooms**: Escape, the keybind/bar toggle and `ipc overview close` go through
  `UiState.leaveOverview(focused)`, so leaving plays the same zoom as choosing a workspace. No cell
  for the workspace (off the page): no backdrop, only the windows fly.
- **Shift held** (empty search) opens the grid to all ten like a drag does (`grid.showAll`); with it
  Shift+click sends your window to any of them, empty ones included.
- **Frames on the way in**: three of the four HUD cards build asynchronously (Clips stays sync — its
  height IS the strips'); the zoom's stand-ins are plain ScreencopyViews; SharpCapture oversamples
  2×, not 3×. Not measured: compare by eye.
- **The Now Playing panel's language**: a Workspaces | Notifications SegmentSwitch in the header
  drives the morph (the bell chip is gone); the header's live chips sit in a ChipTray; the strip's
  empty workspaces are cookies that wind and swell on springs (CookieButton's) and pop in.
- **The tooltip clip**: the window layer is z 5, over the strip — a bottom-row tooltip opens down
  onto the chips and was drawn under them.

## Round 8 (2026-10-20)

- **Notifications beside the workspaces**, not a tab: in the collapsed grid, when the cells keep
  ~2/3 of their size with room taken off BOTH sides (they stay centred — the user's call), the
  history sits right of them (`WorkspaceGrid.notesOn`). Hidden while the grid is opened out.
  The tabs and the card-morph are gone. Since 2026-10-21 it is `NotificationCentre` (compact: no
  ground of its own, it blends into the grid card; a HUD-card-shaped header (no PanelHeader — 6.5 units won't hold one))
  in a Loader, so it is the SAME body and tiles as the bar's panel (see docs/sidebar.md, "Retheme
  2026-10-21"). `NotificationRow`/`Groups` lost `flat` — a row is a tile, not a line.
- **Ctrl while dragging**: dropped on another window, the two trade workspaces (`swapMode`;
  the ghost outlines the window under the pointer with a swap mark).
- **Opening waits for frames** (`Overview.revealed`): the dim, field, stage and entrances start
  when the opening zoom's stand-ins have their first captures (≤150 ms, never later than 220);
  stand-ins are hidden until then, previews fade in on their first frame (SharpCapture).
  **Closing ends empty**: (the dim now holds through the flight and lifts with its tail — see "The zoom, seamless" below) the overview closes 40 ms
  after the stand-ins clear, so Hyprland's layer-out animates a blank frame, not them.
- **The strip is gone** (empty-workspace chips, scratchpads, reopen chips; ClosedWindows and
  Hypr.specials removed). Empty workspaces are reached with Shift or a drag. **Sessions** moved to
  a header chip; its card (`OverviewSessions`) hangs under the header.
- **The search finds windows only** (OverviewBeyond removed — the user didn't want a launcher there).
- **The workspace card** (peek): a winding cookie with the number or the app label's icon, the
  label or "Workspace N", counts and today's time; windows as icon tiles with title over app
  name; keycap hints for what a cell does.
- **The Clips card** is the Clips panel's tiles: the buffer ring + switch; Clip it + lengths +
  Record — beside the clip deck. The timeline card is gone.

## Round 9 (2026-10-22): selection, undo, operators, screens

The user asked for features and visual improvements without naming them; they picked all four features
and all four visuals from a list, and OK'd a screenshot of the live overview first. Built in stages.

- **Header at screen scale**: `PanelHeader` gained `chipSize`, `titleVariant`, `subtitleVariant` (defaults =
  the old panel size, so its 70 other users are unchanged); the overview asks for a 44 px chip, a headline
  title and a label subtitle. The subtitle must stay short — the header column is narrow and elides.
- **Window previews**: the app's icon sits big in the middle only until the capture has a frame (or for a
  window under 90 px); after that it rides a round badge on the bottom-left corner, since a centred icon over
  live content just covered the window's own text. A hovered preview lifts (1.025).
- **Search operators** (`services/switcher.js` `parseQuery` / `filter`, tests in `scripts/test-switcher.js`):
  `ws:3`, `ws:1,2`, `app:kit`, `is:floating|tiled|pinned|fullscreen|audio` (flags by prefix, so `is:fl` works as
  it is typed). All operators AND together, then the plain words are scored as ever. A word that only LOOKS like
  one (`is:xyz`, `ws:abc`, a title's `http:`) stays a plain word; a key with no value yet is dropped, so typing
  never blanks the grid. Window records carry no live state: `filter` takes a `factsOf(win)` resolver
  (`Switcher._facts`: geometry, `pinned`, `Audio.streamsFor`) and only calls it when a flag is asked for —
  reading `lastIpcObject` in the records themselves would rebuild the whole list on every refresh.
  `OverviewFilters` is the chip row under the field (Floating, Pinned, Fullscreen, Audio): a chip writes
  `is:…` into the field and lights when the word is there, so the field stays the one source of truth.
- **Selection** (`Switcher.marks` / `marked`): Ctrl+click a preview marks it (primary ring + a tick on the
  bottom-right corner); Ctrl+A marks everything the search shows, or with nothing typed the workspace you are
  on, and again lets them go. A pick and a selection clear each other (so do a HUD pick and a selection). The
  island turns to `BulkInspector`: icons, "N windows", where they are, float/tile (one switch for the lot: if
  all have it they lose it, else the ones without get it), pin, Clear, send-to-workspace chips, close (twice).
  Dragging ANY marked window moves them all (no split hint), Shift+click a cell sends the selection. Keys with
  a selection: Ctrl+F / P / W / 1–0, Esc clears (before the pick, before closing). Marks reset when the
  overview closes.
- **Undo** (`Hypr.moveLog`, `undoMove()`): every move through `Hypr.moveWindowToWorkspace`, `moveAll` and
  `swapWorkspaces` is logged with where each window WAS; moves within 250 ms are one step (a selection, a swap).
  Ctrl+Z or the header's Undo chip sends them back and rings the cells. A tiled window returns to its
  workspace, not its slot; a CLOSE cannot be undone (the process is gone — closing keeps its two-step latch);
  windows on special workspaces are not logged. Cleared each time the overview opens.
- **"+ New workspace" cell** (`WorkspaceGrid.newWs`): while the grid is sparse (≤ `sparseUpTo` = 5 cells) and
  no empty cell is showing, the page's first empty workspace gets a cell labelled "+ New workspace" — click to
  go, drop a window to give it a workspace of its own. An ordinary cell of an ordinary workspace; this is also
  what stops a one- or two-workspace grid being a lone box in a big card. When the workspace you are on is
  empty there is already an empty cell and none is added.
- **Screens**: with more than one monitor a cell whose workspace lives on ANOTHER monitor hangs a small tab with
  that monitor's name on its lower edge (in the gap, so a window can't cover it), and the inspector gets one
  "send to <monitor>" chip per other screen (to that screen's showing workspace). All workspaces were already
  in the grid whichever monitor they are on, so a separate strip would have duplicated cells.
- **Declined**: the cookie field's tone shift at card edges. Looked at on a real screenshot: a cookie crossing a
  card's edge reads as one cookie on this palette. The fix would mask the full-screen field around every card —
  an offscreen full-screen layer redrawn every frame the field drifts, which is the cost the 10-17 perf pass
  removed. Revisit only if it shows on a palette where it matters.
- **Verified**: static checkers, `bun scripts/test-switcher.js` (71), `test-icons.js`; the live shell
  hot-reloaded each stage clean; screenshots of the header, chips, the "+ New" cell, the bulk face (Ctrl+A) and
  the monitor tab. NOT exercised (they act on real windows): Ctrl+click, dragging a marked window, Shift+click
  with a selection, Ctrl+Z / the Undo chip, the send-to-screen chips, the filter chips' clicks.

## Round 10 (2026-10-24)

The user's calls, in one message: Shift a toggle, no grid expansion on a drag, the cell menu gone and its contents
in the inspector, the app icon back in the middle of each preview, and "don't let the island be this big".

- **Shift is a TAP-toggle** (`Overview.steer` + the stage's `Keys.onReleased`): Shift down on an empty field arms
  `_shiftTap`, its release flips `grid.showAll`. Another key (a capital letter) or a Shift+click (`grid.sent`)
  disarms it, so Shift+click-to-send never toggles. It used to be held. `showAll` still resets on close.
- **A drag does not open the grid out any more**: `slots` is the busy cells (+ the "+ New workspace" one) unless
  `showAll`. The notification card and the "+ New" label stay through a drag too (no `ghosting` in `notesOn` /
  `offersNew`). `ghosting` remains for the drop ghost and `calm`.
- **The cell menu is deleted** (`menuWs`, the `menu` Surface, right-click on a cell). Its contents are the
  inspector's second page: the chip that carries the workspace's number in the tools row flips it to the
  WORKSPACE page (`WindowInspector.spaceOpen`; the same chip, lit, flips back): the app's name + icon
  (WorkspaceLabels, per app), Swap with, Bring here, Close all (ArmLatch `allLatch`). A page, not a third row — the
  first try (a third row always shown) took the island from ~1000 to ~1250 wide and squeezed the Performance and
  Input cards beside it, which the user called out. The default face is the size it was; the workspace page is
  ~36px taller than the tools row while open. `Overview.islandSlot` is unchanged.
- **`WorkspaceChips`** (new): the ten numbered chips, one copy for "send it to", "swap with" and the bulk face.
- **The app icon is centred on every preview again** (round 9's corner badge and "big icon only until the capture
  has a frame" are gone — the user preferred it). The selection tick stays bottom-right.
- **Not exercised** (needs clicks on real windows): the workspace page itself (opening it, naming, icons, swap,
  bring, close all), the Shift tap toggle, a drag with the folded grid. Seen: the default face's size, the
  centred icons, the folded grid with a window picked.

### Round 10, second pass (2026-10-24)

- **Shift and Ctrl are on screen and both are toggles** (`OverviewModifiers`, bottom left of the workspaces' card):
  two `ChipButton`s in a `ChipTray`, lit when toggled OR held, with a line under each lit one saying what it does.
  Tap the key or click the chip. State lives in `Overview` (`modPress`/`modRelease`, `ctrlOn`, `grid.showAll`);
  a tap is a press and release with nothing between, and a Shift/Ctrl that was for a click (`grid.modUsed`) or came
  with another key is not one. **Shift on**: all ten cells, and a click on a cell SENDS your window there
  (`sendHere` returns false when there is nothing to send, and the click then goes to the workspace as before).
  **Ctrl on**: a click on a window selects it, a drag onto another swaps (`OverviewWindow.ctrlMode`). Both reset
  when the overview closes. Held keys behave as before. `wtype -M shift` does NOT test this (it sets the modifier
  state, not a key event); `wtype -k Shift_L` / `-k Control_L` do.
- **Spacing**: the pick grew 6% — on a preview as big as its cell that is ~15px a side, more than the 12px gap, so
  it touched its neighbour. The lift is now capped to a few px (`OverviewWindow.lift`) and the grid's `gap` is
  `spacingXl`.
- **The "+ New workspace" cell** is an invitation, not a hollow box: the cell tints toward `focus`, its edge
  lights up, and in the middle a slowly turning cookie with a plus, "New workspace" and (when tall enough)
  "Workspace N · drop a window here". `cell.offered`.
- **The name tag on a cell's top right is gone** (WorkspaceLabels names/icons are still set from the inspector's
  workspace page and still show in the bar's WorkspacesPill and as a cell's big icon).

### Round 10, third pass (2026-10-24)

- **The Shift/Ctrl chips say nothing on the board any more**: each has a "?" beside it (`OverviewHelpDot`) that opens
  a styled card above it on hover — the key's title and three lines with icons (tap/click toggles, what it does,
  how it ends). `OverviewModifiers` is one `ChipTray` now (chip, ?, chip, ?).
- **The "+ New workspace" cell carries the workspace pill** instead of the "Workspace N · drop a window here" line:
  round chips for every empty workspace of the page that has no cell (`WorkspaceGrid.freeSlots`), the cell's own
  ringed. Click one to go there (focus + `UiState.leaveOverview`); drag a window onto one to send it there — each chip has
  its own `DropArea` setting `dropTarget` (it has no cell, so no ghost; `clearDrop()` so no stale split hint
  rides along). The face is declared after the cell's MouseArea/DropArea so the chips get the click and the drop.
  Hidden on a cell under 100px tall; chips shrink (min 20px) in a narrow one.
- **Not exercised**: the "?" popup (needs a hover), clicking or dropping on a chip.

### Round 11 (2026-10-24)

- **The pill's chips SELECT, they don't go** (the user). A click rings the chip (`WorkspaceGrid.newChoice`) and the
  "+ New workspace" cell then stands for that workspace (`newTarget`, `cell.goesTo`): clicking the cell goes there,
  dropping on the cell sends there, Shift-mode sends there. A drop onto a chip still sends to that chip. The pick is
  forgotten on close, and falls back to the cell's own workspace if it stops being free.
- **One "?" for both keys, opened by a click** (the user: not on hover). `OverviewHelpDot` takes `sections`
  (a keycap heading + icon lines each). A click outside closes it without eating the click (a full-window catcher with
  `mouse.accepted = false`); Escape closes it first (`Overview`, `mods.helpOpen`); it resets on close.
- **Typing elsewhere is not a Shift tap**: a capital letter in a field other than the search (the AI box) used to
  toggle the all-ten grid, because the letter's press was taken by that field and never cancelled the tap
  (`Overview._typingElsewhere`).
- **The left face (`OverviewFeed`)**: the notification centre's mirror, left of the busy cells, on the same terms
  (`notesOn`). Both side faces now start below the watermark and end above the Shift/Ctrl chips
  (`WorkspaceGrid.sideTop`/`sideBottom`, passed by `Overview`), so their headers line up. Pages swiped like a
  short-video feed:
  - the wheel scrolls the page's own list first, and past its end the page gives (a rubber band) then turns, one page
    per push with a cool-down. A `WheelHandler` OVER the pages takes the wheel and scrolls the page's Flickable itself
    (each page exposes `flick`); otherwise the Flickable eats every event. Drag the header strip to swipe (follows the
    pointer, turns past a fifth or on a flick). The rail on the outer edge: a stop per page, the near one swells.
  - pages build only while in view or passing; the page you were on is `Config.overviewFeedPage` (default 1, Ask:
    the one page that sends nothing until you type).
  - **What's changed** (`FeedChanges`): the version on a turning cookie, ShellUpdate's notes when a newer release is
    out, and an honest "patch notes, soon" card. The real thing (notes since the version you last had) is for later
    — the user's call.
  - **Ask** (`FeedAssistant` + `services/Assistant` + `services/assistant.js`): a chat through `ai-ask.py` with the
    launcher's provider and keys (`Ai`), but its own thread, its own Claude Pro session (`session: "Overview"`) and
    its own system prompt, which lists what may change and its current value. A reply may end in ```action blocks —
    a colour scheme (16 colours, pywal layout → `ColorScheme.applyPalette`) or a setting from a fixed list (22 keys,
    clamped to Config's own ranges). Each becomes a card: Apply, then Undo (the replaced value/palette is kept).
    Nothing applies itself. Anything off the list or malformed is an "invalid" card that says why.
    `bun scripts/test-assistant.js` (36). No key: the page takes one in place (`Ai.saveKey`, stdin → 0600); the tune
    chip picks the provider (switching clears `aiModel` to the provider's default).
  - **A local model**: `ai-ask.py` gained an `ollama` provider (OpenAI-shaped, no key, `Config.aiLocalUrl`, default
    `http://localhost:11434/v1`, 180 s timeout); it shows in `Ai.providers` (so in Settings › Launcher too). The URL
    has no settings field yet.
  - **News** (`FeedNews` + `services/News` + `scripts/news-fetch.py`): Google News RSS, an edition per country in its
    language. "Near you" = the country of the weather location (`Config.weatherCountry`), else the locale; never an IP
    lookup; `Config.newsCountry` overrides. Topics: Near you, World, Tech, Science, Sport (`Config.newsTopic`). Fetched
    only when the page is in view, cached 20 min in `$XDG_CACHE_HOME/quicktest/news/`; offline shows the cache marked
    stale. The first story is a tinted hero; source icons come from Google's favicon service. A click opens the story
    and leaves the overview. `python3 scripts/news-fetch.py --selftest`.
- **Not exercised**: everything that needs the pointer — the "?" card, the chip selection, swiping/wheel turning,
  the rail, News at all (its page was never on screen; the script was run by hand against PT/US), a real AI turn
  (parser tested offline; `claude -p --append-system-prompt` and the model's compliance with the action format are
  unverified), Apply/Undo on a scheme.

### Round 11, second pass (2026-10-24)

- **The face swipes SIDEWAYS** (the user: the listing horizontal, changed by a press-and-drag). Pages sit side by side
  (`x: d * step`); the rail is a row UNDER the pages, the stop you're on stretching to carry its name. Press and drag
  anywhere on a page: the page follows, past a fifth (or a flick) it turns, rubber band at the ends. A sideways wheel
  (touchpad two-finger, tilt) turns too; the vertical wheel only scrolls. The pages' lists are `interactive: false`
  (a vertical Flickable grabs the press before a sideways drag could), scrolled by the face's own `WheelHandler`;
  the `DragHandler` has no `CanTakeOverFromItems`, so dragging in a text field still selects text.
- **News has pictures**: `news-fetch.py --images 12` unwraps the top stories' Google links (article page →
  signature/timestamp → Google News' undocumented batchexecute → the publisher URL → its `og:image`), six at a time,
  cached by article id in `news/images.json` for good (600 newest). Measured: 11 of 12 PT stories, ~2 s cold, instant
  warm. `News.pictures` is a map BESIDE `items` (reassigning `items` rebuilt the list and jumped it to the top);
  the publisher URL is kept too, so a story opens there directly. The hero becomes a photo card (picture full-bleed,
  a gradient into `base`, the headline over it); rows get a thumbnail on the right; a slow zoom under the pointer.
  `Config.newsImages` (default on) turns the pass off — each publisher sees one page fetch, like a browser preview.
  If Google changes the endpoint, lookups fail quietly and the page is text-only.

### Round 12 (2026-10-24)

- **Scrolling**: a wheel notch is ~150 px and GLIDES (`OverviewFeed.scroll`, notches add onto where the glide is
  going); a touchpad scrolls 1:1 (×1.2). **Press and drag up/down** scrolls the page (it follows the pointer and
  coasts on release, `coast`); left/right still swipes — the first 6 px decide the axis (`swipe.axis`).
- **Room**: the side faces span the card's whole height (`sideY = sideTop`, `sideH = boardH − sideBottom − sideTop`;
  they used to stop where the cells did) and grow into the width beside the cells, up to 1.4 × `notesW` (`sideW`).
  Both sides, so the notification centre too.
- **`SlidingTabs`**: a tray of stops with a lit pill that slides between them, following a REAL position mid-swipe.
  The face's rail and the News topics both use it; a stop can carry a `badge` dot (the rail's "What's changed" while
  there are unseen notes).
- **Patch notes** — `assets/changelog.json` (data, newest first; `bun scripts/test-changelog.js` checks shape,
  order, newest = `Config.version`, every icon known), `services/Changelog` (FileView, `unseen`, `markSeen`,
  `dateLabel`), `FeedChanges` + `FeedNoteSection`. The page: a hero (version on a turning cookie, name, date, "New",
  summary, a sheen crossing once), highlight rows, section cards showing 3 lines with "+N more" (grows on a curve,
  the new lines rise in), older releases folded under "Earlier". Everything cascades in (ViewEnter) each time the page
  comes into view. Seen after 2 s on the page (`Config.changelogSeen`); "New" stays for that look (`seenAtOpen`).
  **`Config.version` is 0.4.** The v0.4 notes were written from the README's "What's new since v0.3", the feature
  docs and the memory of each round; v0.3's from its GitHub release.
- **Local AI is the default** (`Config.aiProvider: "ollama"`, `aiModel: ""`; a saved choice is kept).
  `scripts/local-ai.py` (status / serve / pull, `--selftest`) + `services/LocalAi` + `LocalAiSetup` + `LocalModelList`.
  The Ask page opens with a three-step card: **Install** (`ollama`, plus `ollama-vulkan` when /sys shows a GPU — 5 MB,
  any vendor; through `Updates.installPackages`, so the update panel's own password prompt and progress, and the
  overview steps aside), **Start** (`ollama serve` as a detached user process, `OLLAMA_VULKAN=1` with a GPU; then it
  starts with the shell, `Config.aiLocalAutostart`), **Pick a model** (catalogue: qwen3:4b recommended, llama3.2:3b,
  gemma3:4b, qwen3:8b; download progress from Ollama's streamed `/api/pull`; the first becomes the one in use).
  `Ai.ready`/`blocker()` follow LocalAi, so the launcher's `?` falls back to a web search until it's set up.
  `ai-ask.py`: `aiLocalUrl` is the server root (a `/v1` is tolerated), an empty or non-local model name means the first
  pulled, qwen3 gets `/no_think`, and `<think>…</think>` is stripped from replies.
- **Not exercised**: the install (needs your password), serve, a pull, a local answer, the drag-scroll and glide, the
  sliding pills, opening a notes section.

### Round 12, fixes (2026-10-24)

- **The Ask page's box couldn't be clicked into.** A `DragHandler` on an item stacked OVER a `TextInput` keeps the
  field from taking focus on a click — reproduced offscreen with `qmltestrunner` (a field under such an overlay never
  got `activeFocus`; the same handler on the PARENT of the pages passes, and sideways/vertical drags still reach it).
  The swipe handler now sits on `viewport` itself; only the `WheelHandler` stays on the layer over the pages.
- **The local AI answered nothing after ~25 s.** qwen3 is a thinking model: through Ollama's OpenAI-shaped endpoint it
  ignored `/no_think`, spent all 1500 tokens reasoning (`finish_reason: length`) and returned empty content.
  `ai-ask.py` now uses the NATIVE `/api/chat` with `think: false`, and for the Ask page (`structured`) a JSON schema as
  `format` ({reply, actions}, `ACTION_SCHEMA`) that `blocks_from` turns back into text + an ```action block. Measured
  on qwen3:4b (RX 6700, Vulkan, 100% GPU): 0.6–4.7 s, real actions, refuses off-topic asks.
- **Claude Pro failed on every new Ask thread** (and the launcher's first `?` of a boot): the CLI now answers a resume
  of a missing session with a result line `is_error` ("No conversation found") instead of nothing, which was passed on as
  the answer and skipped the create-retry. An error before any other event is now held and the retry runs. Measured 4 s.
- **It just flips settings** (the user): actions are applied the moment a reply lands (`Assistant._land`), the card
  says what changed and offers Undo (Redo after). The prompt is settings-only — one sentence, never code, scripts or
  how-tos — and `maxTokens` is 700.
- **No lighting effects** (the user): the patch notes hero's sheen and accent glow, and the setup card's glow, are gone.
- **Shift/Ctrl moved to the top right**, in the watermark's row; the help card opens downward (`OverviewHelpDot.below`).
  The side faces run from under that row to the bottom of the card (`sideBottom: 0`).

### Round 13 (2026-10-24)

- **The AI reaches the shell, behind three layers** (`services/assistant.js` `SHELL`, `validate(a, ctx)`; the user:
  "access to the shell, but not be able to delete stuff — apply safety measures"). New verbs: `action` (a
  ShellActions entry from an allowlist — night light, DND, game mode, stay awake, clipping, Wi-Fi, mute, mic, sidebar,
  record, save a clip, shuffle, Lens, colour picker, clips library, the wallpaper/scheme/Bluetooth/notifications/update
  panels, Settings, lock, power menu, reload; toggles take `on`), `volume`, `brightness`, `wallpaper` (a library picture
  by name, or random), `preset` (a saved scheme), `media`, `workspace`, `launch` (an installed app via Launcher.search,
  apps only), `timer`. Layer 1: nothing else can be expressed — no command, no file, nothing that deletes or closes.
  Layer 2: values clamped, names matched against what exists here (`Assistant._names()`: wallpapers, presets, action
  names/states) — a path can't be invented. Layer 3: `confirm` (lock, reload, power menu, recording, Settings) waits on
  the card for Do it / Skip. Undo where there's something to put back (toggle again, previous volume/brightness/
  wallpaper/palette, stop the timer). Actions that need the screen close the overview once after all of them run.
  `bun scripts/test-assistant.js` (68, the refusals included). The JSON shape the local model answers in
  (`ai-ask.py ACTION_SCHEMA`) lists the same verbs.
- **Light/dark from the AI applies**: `themeMode` goes through `ColorScheme.switchMode` (it re-derives the palette); if
  the mode already matches — an earlier direct write left it flipped without colours — `Wallpaper.reapplyPalette()`.
- **The conversation, redesigned**: a ListView over a ListModel appended to from Assistant.messages (`sync`), so only a
  new turn is built — it rises and settles (`add`), the rest move aside (`displaced`), and the list glides to the end.
  `ChatMessage`: your bubble in the accent on the right, the AI's beside its cookie avatar, the corner nearest the
  speaker tucked (per-corner radii); a fresh reply types itself out (≤1.2 s; the full text sizes the bubble so it never
  jumps) and its cards deal in after. `ChatActionCard`: swatches or an icon tile, the state line (done with a popping
  tick / waiting for your OK / couldn't / undone / skipped / not allowed) and the state's buttons. `ChatComposer`:
  the send button inside the pill (quiet when empty, fills and lifts with text, a stop with a winding arc while a reply
  comes; `InputField.trailingSpace`). `ChatIdeas`: the empty state, six idea tiles in two columns that rise in. The
  reply on its way: three dots that hop, then the streamed words.
- Gotcha met: registering a new type in `qmldir` AFTER saving the file that uses it leaves the live shell on a failed
  reload ("X is not a type") — a qmldir edit alone doesn't reload; re-saving any .qml does. Register first.

### Round 14 (2026-10-24)

- **Ideas**: back to the slim rows (the user found the tiles too big), now four drawn at random from a pool of 23
  each time a conversation starts (`ChatIdeas.draw`, on completion and whenever it's shown again).
- **Smarter AI**: the prompt carries rules (light/dark is `themeMode`, never a scheme; exact names from the lists;
  several requests → several actions; never claim what wasn't an action) and six worked examples in the form the
  provider answers in; the local model runs at temperature 0.3 (`ai-ask.py`); only the last 10 turns are sent.
  Measured on qwen3:4b: light mode, play a song, open a site + volume, a sunset scheme, a scene — all right, 0.9–3.5 s.
- **New verbs** (`assistant.js`, 81 tests): `scene` (a Wallpaper Engine scene by title — `WallpaperEngine.scenes`,
  `Wallpaper.pickScene`; Undo puts back the scene or picture before), `play` (Spotify, `scripts/music-play.py`),
  `open` (http/https only — no file:, javascript: or custom schemes), `search` (Config.webSearchUrl).
- **Playing on Spotify** (`scripts/music-play.py`, `--selftest`), three tries in order: the Spotify bridge's new
  `POST /play` (the Spicetify extension now hands the bridge the client's own access token every 5 min — kept in the
  bridge's memory only, never emitted, loopback only — and the bridge searches Spotify's Web API and starts the hit via
  MPRIS OpenUri: exact and instant); else a DuckDuckGo `site:open.spotify.com/<kind>` search → OpenUri (or `xdg-open`
  when Spotify is closed); else Spotify's own search page. DuckDuckGo blocks a burst of scripted queries (202
  "anomaly", measured) and Bing/Brave/Mojeek don't serve `site:` results to scripts, which is why the bridge route
  exists. **Needs the extension re-applied and the bridge restarted** to get the first route.
  The card says "working" (its icon sways) until the helper answers.

### Round 15 (2026-10-24)

- **Ten more things the AI does** (`assistant.js`, 117 tests; executors in `services/Assistant`): `remind` (in N
  minutes, or at HH:MM today/tomorrow/a date → `Reminders.addDue`), `todo` (`Tasks.add`), `alarm` (HH:MM + once/daily/
  weekdays/weekends/days → the Timers bitmask), `window` (an open app: move to a workspace, float, fullscreen, focus —
  fullscreen only toggled when Hyprland's own record says it differs), `output` (default sink by name), `appvolume`
  (`Audio.streamsMatching`, new), `bluetooth` (connect/disconnect a paired device), `clip` (save the replay buffer),
  `screenshot` (the snip tool, after the overview has gone), `look` (a workspace's own wallpaper and/or saved scheme —
  `Wallpaper.assign` / `ColorScheme.assign`; Undo restores both maps), `discord` (mute/deafen), `findsetting`
  (`SettingsIndex.search` → `UiState.openSettingsTo`), `remember`/`forget` (`Config.aiMemory`, ≤20 notes, sent every turn).
  Undo for each where there's something to restore.
- **It answers from the shell's state**: every turn carries a "Right now" block (`Assistant._nowLines`): time, weather,
  CPU/GPU/RAM, battery, what's playing, volume and output, the newest notifications, open windows by workspace, a Discord
  call, reminders, to-dos, alarms — read off the services, nothing fetched.
- **Smarter local model**: rules for the common confusions (alarm vs reminder, side by side = tiled, questions get no
  actions, "what did I miss" = notifications), the worked examples sent as real earlier TURNS for the JSON form
  (`exampleTurns`; as text in the prompt qwen3:4b copied one word for word) with an end-of-examples turn, `num_ctx` 8192.
  Measured on qwen3:4b: alarm, GPU temp (from state), notifications summary, daily alarm, Daft Punk, an autumn scheme, a
  45-minute reminder, side by side, Discord mute — all right, 0.6–4 s. Known slip: with no real history, "what did I just
  ask you?" can still echo an example.
- **Spotify actually plays — via a mailbox** (`spotify-bridge.py`, the extension `mailbox-9`): the token route answered
  429 every time (Spotify throttles its desktop token outside the app) and is gone. POST /play queues the words and wakes
  the extension's long poll; the extension loads `/mailbox.css` (`#qs-mailbox::after { content: "<base64 JSON>" }`) and
  reads it with getComputedStyle — a renderer that can only send opaque no-cors requests can still READ a stylesheet's
  effect — then searches with Spicetify's GraphQL `searchDesktop` (CosmosAsync Web API as fallback) and `Player.playUri`,
  and POSTs `played`/`play-failed`, which /play has waited for (8 s). Round trip tested offline on a spare port
  (woken in 0.5 s). The search-page fallback is GONE: it went through OpenUri, which stopped the music and played nothing
  (the user). Not found → said so, music untouched.
  **Needs**: the extension copied and `spicetify apply`, and the bridge restarted.
- **Follow-up, "Spotify found nothing"** (2026-10-24): the mailbox worked; the search didn't. `searchDesktop` is
  registered by `xpui-routes-search.js`, a chunk Spotify loads only after its search page is opened — until then
  `Spicetify.GraphQL.Definitions.searchDesktop` is undefined — and the CosmosAsync fallback answers "Resolver not
  found!" on Spicetify 2.45. The extension (`mailbox-10`) now searches with `searchSuggestions` (the top bar's
  type-ahead, registered by `xpui-modules.js` at start; variables copied from Spotify 1.3.4's own call), then
  `searchDesktop` if loaded, and reports WHY on failure; the bridge returns 404 only for a search that found nothing
  and 502 with the reason otherwise. Verified from Spotify's own bundle in /opt/spotify/Apps/xpui, not live.

### Round 16 (2026-10-24)

- **Per-app volume past 100%**: `appvolume` takes 0–130 (`Audio.boostCeiling`); a media player (Spotify) goes
  through `Audio.setPlayerLevel` — its own volume, plus the stream's boost past 100%, the volume profiles' path, so it
  lasts the song — anything else through its stream (`Audio.streamsMatching`). "Right now" lists each app's level.
- **More Discord**: `discord` leave / camera / screenshare (camera and screen share by the configured keys,
  `pressBlocker`), `discordvolume` (mic 0–100, output and each person 0–200), `discorduser` (mute someone for you),
  `discordsetting` (noise / echo / agc / push to talk). "Right now" names who's in the call and your levels.
- **One JSON shape per verb** (`ai-ask.py _VERBS` → `anyOf` with each verb's required fields): with one loose object a
  4B model filled the wrong fields and skipped `value`/`on` (measured: three of six failed); per verb, all right.
  `--selftest` checks the verbs equal assistant.js's.
- **"Hey Claude"** — `scripts/voice-listen.py` (`--selftest`), `services/VoiceAssistant`, `modules/voice/VoiceOrb`,
  `VoiceSetupRow` (the Ask page's tune panel). Vosk (karaoke.py's helpers, loaded by path): a GRAMMAR recogniser of the
  wake phrases idles on the mic (cheap, and random speech can't wake it); the wake starts a free recogniser fed the last
  2 s (one breath: "hey claude play odo by ado"), ended by Vosk's endpoint or 9 s. The words go to `Assistant.ask` —
  the same thread, actions and safety as typing. The overlay: bottom centre on the focused screen, a cookie breathing
  with the mic level, the words as heard, then the reply and a chip per action (state live); tap → the Ask page.
  `qs ipc call voice listen` skips the wake phrase (for a key). Off by default (`Config.aiVoice`): the mic is open the
  whole time it's on; audio never leaves the listener's memory. The English model (~40 MB) comes from
  `karaoke-model.sh en-us` behind a button. Not tested live (no English model here yet); Vosk-small may mishear
  names ("Odo", "Ado") — Whisper would be the upgrade.
- **Follow-up, "Hey Claude doesn't trigger"** (2026-10-24): the English model had never been fetched (and voice was off),
  and the service only looked for it at startup — `VoiceAssistant.recheck()` now runs whenever the voice row is shown.
  Fetched with `karaoke-model.sh en-us` (68 MB unpacked); "hey", "claude", "okay" are in its vocabulary ("odo" isn't).
  The listener needs ~5 s to load the model. Its first live run reported a wake with nobody speaking: deciding on the
  grammar recogniser's PARTIALS let any sound pass for the only words it knows. It now wakes on a finished result with
  every wake word ≥ 0.8 confident (`WAKE_CONF`), and keeps 8 s of audio so a one-breath request still arrives whole.
  25 s of a quiet room after the fix: 0 false wakes (not yet measured with music playing). Typing just "hey claude"
  opens the voice row instead of asking the model; the Ask header says "say “hey claude”" while it's waiting.

### The zoom, seamless (2026-10-24)

The user: "seamless and very smooth, in n out". Found by reading, NOT yet seen running — compare by eye.

- **Do NOT put `no_anim` on the overview's layer rule** (tried, reverted the same day — the user: "the blur is
  sudden and not gradual"). Hyprland eases every layer surface (`fadeLayersIn` inherits `fade`, 1 s here, front-
  loaded), which does leave the opening's stand-ins briefly translucent over the real windows — but the compositor's
  blur has no strength of its own, it follows that layer alpha, so with the fade off the blur snapped to full in one
  frame (the live rules.lua has no `ignore_alpha`, so the dim alone blurs the whole screen). Known limit: blur-OUT
  at the end of a leave can still step, since the overview closes blank (see "Closing ends empty").
- **Rate**: the zoom is geometric (`OverviewZoom.k`: the lerp weight of s^x, s = 1/previewScale) on
  `Motion.zoomCurve` (ease in AND out; emphasizedDecel did half the distance in two frames), `Motion.zoom` 440 /
  `zoomOut` 380 ms. Taste knobs: those three tokens.
- **The compositor's workspace slide** (500 ms, `wind`) is under a leave. The board and the dim now HOLD until the
  last third of the flight (`tail`, timed on a linear `u`, not the curve), then dissolve together with the
  stand-ins: the real window's border/shadow/rounding arrive as a crossfade. Stage fades over the first half
  (`Motion.zoomOut / 2`, InOutSine) instead of vanishing in two frames; the cookie field's own fade is off while
  leaving (it would outlive the window).
- **Round 2 (same day, the user: "it still flashes when opening and closing", "weird on an empty workspace", "make
  the bar/sidebar/frame collapse when opening and surge when closing")**:
  - The board was a 0.9 sheet in the CELL's colour across the whole screen, both ways — a flash (worst on a light
    theme) and over the compositor's blur threshold. It is now the DIM's colour at 0.5 (`boardAlpha`, under
    `ignore_alpha` 0.6), on a leave only (opening has no workspace switch to hide).
  - **A workspace with no windows** gets no board, a 0.6× flight and a tail that starts at 15% (`OverviewZoom.empty`):
    nothing to land, nothing sliding, so it is a plain fade.
  - **The bar/sidebar/frame folding away on open and surging on leave was built (Intro.collapse/surge) and REVERTED
    the same day — the user didn't like it. Don't bring it back.**
  - **Blur**: `ignore_alpha = 0.6` (the repo's rule: blur only behind the cards) gave NO blur at all on the user's screen
    (the cards' own alpha sits under it), so the live `~/.config/hypr/rules.lua` is back to `blur = true`, whole-screen
    — the user's standing choice ("Overview blur back on by request"). The repo's rule still has the threshold.
- **Round 3 — the flash on ARRIVING (leave → real workspace)**: with whole-screen blur, the compositor blur follows the
  layer's alpha, so while any dim is left the real windows under it are blurred and the stand-ins fade over BLURRED
  windows, and when the overlay went (blank, 40 ms after the flight) the blur and the dim dropped in one frame. Now a
  leave closes ON ITS LAST FULL FRAME (`Overview.landed`, no `closeSoon`; dim and stand-ins held to the end, only the
  board steps back over the last third) and Hyprland's layer fade-out takes dim, stand-ins and blur away together —
  the one gradual blur-out there is. `visible` ignores the scrim once landed; the scrim cuts to 0 instantly (Behavior
  off while leaving). **A bet**: the old code blanked first because closing on a full frame "flashed" (2026-10-20) —
  that was with square, misplaced stand-ins and a fading dim; if it comes back, look at the stand-ins' hand-off to the
  real window (border/shadow/translucency of the real one) before reverting. The fade speed is Hyprland's
  (`fadeLayersOut` inherits `fade`, speed 10, `wind`); a gentler one is a `hl.animation` leaf in animation.lua, which
  would slow EVERY layer's fade-out.
- **Not done / guessed**: Hyprland's 2px border may mean the real surface is inset from the box the stand-in lands
  on (a possible ~2 px settle at the hand-off; not measured). The next step if this isn't enough is a true camera
  zoom (the whole stage scaling about the cell, neighbours and HUD cards going with it) — a design call, not built.


## M3E pass (2026-11-03)

The overview in the language of the desktop widgets, bar and sidebar (docs/standards.md: `SpringValue`,
`MorphShape`, tonal `primaryContainer`). Built in four stages at the user's ask ("clean UI, fluid animation,
consistent with the rest of the shell"); written from the code, **never loaded**.

- **Header / chips**: `ChipButton`'s lean and disc fill run on `SpringValue` (shared: every ChipTray in the
  shell, ~327 chips). `PanelHeader.morph` (opt-in, default `""`): the chip is a `MorphShape` on
  `primaryContainer`; the overview's goes `cookie9` → `sunny` while searching. The filter / modifier / header
  chips no longer pass `tint: focus` (`focus` is for rings). `PowerPanel`'s confirm tail opens on one spring
  factor; the surface follows the row, so it has no width animation of its own.
- **Cells / previews**: focused cell on `primaryContainer`; the where-you-are badge is a `MorphShape` that
  wears the next of five shapes per workspace and glides on `springSpatial` (re-seated on open); the
  "+ New" cookie morphs `cookie9` → `sunny` under the pointer; the workspace chips and the peek's cookie are
  tonal; a preview's pick / hover / grab scale is a spring (grab uses `springEffectsFast`, no overshoot); the
  selection tick is a `cookie9`. **Not changed on purpose**: cell and preview x / y / size glides stay on
  their bezier curves — the drag / drop / `calm` maths and "cells decelerate, never spring" depend on them.
- **Island**: the box springs to its face's size (`springSpatial`; `flankW` follows `boxWidth`, so the HUD
  cards beside it move with the spring — go to `springSpatialSlow` if they breathe too much). The inspector
  and bulk faces rise on a spring. `WindowInspector`: preview width on a spring, `cookie9` icon badge, lit
  facts on `primaryContainer`, snap chips lean on springs. Structure and size of the controls unchanged (the
  island must not grow, round 10).
- **Side faces / HUD**: `ScallopChip` (shared, ~20 files) winds on ONE 0→1 spring that drives the turn, swell,
  petals and fill, and defaults to `primary`; `SlidingTabs`' lit pill is the tonal container and its slide is a
  spring; the "?" help card, Sessions card, composer send button, ideas, news stories, action-card tick,
  local-AI steps and the HUD speaking avatar lean / pop on springs.
- **Left as is**: `OverviewFeed.pos` (written directly by the swipe / wheel logic, so a `Behavior` stays),
  the entrance stagger, `OverviewGlow` (the user dislikes lighting effects; no new ones).
- **Check**: static checkers + syntax idiom clean. Not exercised: everything that needs the pointer or real
  windows (drag, pick, bulk, tick, badge re-seat on open), and the springs' feel.

### Review rig and the first patches (2026-11-03)

- **`scripts/overview-shots.sh [outdir]`** photographs every state of the running overview (idle, search, pick, bulk,
  all ten, Ctrl, sessions, help, the three feed pages, the peek) with `grim`, through
  `qs ipc -c <repo> call overviewdebug go <state> [arg]` (`Overview.qml`, view state only: it never moves, closes or
  sends a window; only the focused monitor's overview answers). `STATES="idle pick"` picks some; it closes the overview
  and restores the feed page. The IPC function is `go`, NOT `show` (that collides with the `qs ipc show` subcommand).
  Opened from the script, so it needs the shell running THIS config; check the log after a save before trusting a shot
  (a reload can fail and leave the old config running, e.g. a missing `import Quickshell.Io`).
- **Patched from the first 1:1 review**: a small number chip on every other busy cell (the big faded number sat behind
  the windows, so only the focused cell said which workspace it was); idle cell edges are a hairline (card, cell and
  preview each had a heavy one); the search field has no focus trace and a quiet primary rim (`InputField.trace`); the
  power tray's glyphs are plain foreground at rest (the semantic tints are near-grey and read as disabled);
  the island is as tall as the corner cards (`OverviewIsland.minH`, pad `spacingMd`) so the three share a bottom
  edge, and the inspector's title column is narrower (230 / 300) so a pick squeezes the corner cards less; the player
  volume's `%` is gone and the transport smaller, so the slider has room; the corner cards sit back (`HudCard`: 0.86×
  fill, a quieter edge) and the workspaces card is denser; the peek's key hints are `caption`, not `micro`; the Ask
  page's ideas centre in the room; the feed pages dissolve at the bottom in a gradient in the card's colour (a
  `MultiEffect` alpha mask on the viewport's layer drew NOTHING here; `OverviewLyrics` does it with an overlay gradient,
  and so does this). `HudClipsCard`'s ring read `parent.radius` inside a ClippingRectangle (10 binding errors per open;
  now `card.radius`).
- **Not a bug**: the notification filter chips' right edge fading ("dis…") is the strip's designed "more this way" fade.
- **Not done (proposed, awaiting the user)**: the workspace's own wallpaper behind its cell, search operators as chips
  inside the field, the inspector regroup (segmented toggles, mini-map, overflow), the contextual keycap hint bar
  replacing the header subtitle, an audio / attention badge on previews, frozen thumbnails off the hovered workspace,
  one named-beats choreography for open / close.

### Stage 1 of the proposals (2026-11-03)

- **Search operators are chips inside the field.** `ws:2`, `app:kitty`, `is:floating` become removable chips once complete
  (typed with a space after, or from the filter chips); the field then holds only the words still being typed.
  `services/switcher.js splitOps` does the split (pure, `bun scripts/test-switcher.js`, 78); Switcher still gets ONE query
  string (`Overview.applyQuery`: chips + text), so `parseQuery` / `filter` are untouched. Backspace in an empty field takes
  the last chip off, Escape clears the text then the chips, the filter chips toggle `ops` (`toggleOp`), a flag typed by hand
  is taken out of the text instead. `InputField.leadingSpace` reserves the room.
- **`OverviewHints`** (beside the filter chips) replaces the header's long subtitle: the keys that act now, by mode
  (idle / search / pick / marks). The subtitle is counts, or the picked window's name.
- **Cell wallpapers** (`WorkspaceGrid`): a workspace with its OWN wallpaper wears it behind its windows (0.45); a busy
  cell on the shared one wears it faintly (0.26); empty cells on the shared one wear none (ten copies of one picture was
  noise). Inside a `ClippingRectangle` the child's `parent` is the content item: it needs an id (`cellWall`) — `parent.pic`
  was `file://undefined`.
- **Audio badge** on a preview (bottom-left, a tonal speaker) when the app has a playback stream.
- **Frozen previews**: `OverviewWindow`'s capture is live only while hovered, picked, selected, dragged, on the workspace
  you are on, or until its first frame; the rest hold their last frame.
- **Not built**: an "attention" badge (no urgent flag in `Hypr`; notifications aren't tied to a window), the one-timeline
  choreography (the open / close beats — `revealed`, `arrive`, `landed`, the zoom hand-off — are interlocked with the
  compositor's layer fade; a rewrite risks the seamless zoom the user asked for), the inspector regroup.

### The inspector regrouped (2026-11-03)

`WindowInspector` was two rows of everything (about 830 px, squeezing the corner cards) plus the workspace page. Now:

- **Row 1, identity and state**: the live preview, title and facts, the state toggles (float, pin, fullscreen) and the close
  cookie. The ten numbered chips and the centre chip are gone from it.
- **Row 2, placing it**: `WorkspaceMap` (new: the page's ten workspaces as ONE row — here is filled, a workspace with windows is
  tonal, an empty one is quiet; click to send), the snap zones (a touch smaller) and centre, its CPU and memory as plain text,
  and ⋯.
- **The ⋯ page** replaces row 2 (like the workspace page does, so the island's height holds): its sound (mute + volume), a
  picture, a copy, record, the other screens, its workspace's page (name / icon / swap / bring / close all — it used to be the
  chip with the number on row 2) and force quit (twice).
- **One width for every page** (`implicitWidth: max(col, tools)`): the corner cards follow the island's width (`flankW`), so a
  page turn must not move them. A pick is now ~715 px wide (was ~827).
- The keys are unchanged (Ctrl+F float, Ctrl+P pin, Ctrl+Enter fullscreen, Ctrl+W close, Ctrl+1…0 send). Debug states `more` and
  `space` in the rig photograph the two pages. New icons need a regeneration, so only symbols already in the cut font were used
  (`drive_file_move`, `vertical_split`, `more_horiz`, `arrow_back`; `bun scripts/test-icons.js` 23/23).

### Performance card and the notification centre (2026-11-03)

The user: the overview is overwhelming and hard for a normal user to understand; the notification centre looks outdated.

- **Performance** (`HudPerfCard`): the status line is a SENTENCE now — `services/hud.js perfVerdict` (pure, `bun scripts/test-hud.js`,
  106): Running smoothly / Getting warm / Processor is busy / Graphics are busy / Memory is filling up / Running hot / Memory
  almost full, coloured by how much it matters (`HudCard.statusLevel`, mixed toward the foreground: the palette's warning and
  the fail red alone are dim on this ground). The VRAM / disk figures it used to carry are on each ring's hover tip (the part's
  name and facts). "Frame cap" is "Max FPS" with its explanation (and, when MangoHud has no preset, why it is off) in a tip; the
  presets are 30 / 60 / 120 / ∞ (four labelled segments — five elided every label to "..."); a cap outside them still gets its own.
  Game mode has a one-sentence tip.
- **`components/HoverTip`** (new): a floating label after a rest, parented to the item it explains, for anywhere that is NOT a
  settings page (`HelpTip`'s tip is only drawn by `SettingsCard` — in the overview it shows nothing). Declare it inside an item,
  never directly in a Layout. NOT yet seen on screen (needs a hover).
- **Notification centre** (`NotificationCentre`, shared by the bar's panel and the overview's face): the bell / stopwatch / bin trio
  and the search + layout + select row are one toolbar in WORDS — `Quiet` (Do Not Disturb; opens "Quiet for 30 min / 1 hour / till
  morning / until I stop it / turn off") and `Clear all` on the left, a search icon and `⋯` on the right. The search field and
  the `By app / By time / Select` row open from those two icons instead of always being there. The empty state is a tonal shape
  and "All caught up". Groups: the app's name is a real label with its count in a tonal pill; a notification's time is plain
  text, not a grey capsule.

### Calm by default, plain words, the Clips card (2026-11-03)

The user: "do 1 and 2 together" — fold the extras away, and say things in plain language.

- **`Config.overviewMore`** (default false, persisted): the four corner HUD cards and the side faces (Ask / News / Changes,
  the notification centre) are NOT built until it is on — a first look is the header, the search, the workspaces and the island
  (a performance win too: nothing in those cards runs). A **More / Less** chip leads the Shift / Ctrl tray top right. Folded, the
  cells use the whole card (`WorkspaceGrid.notesOn` needs it) and sit below the tray (`maxHeight − sideTop`, centre offset).
  The rig has `calm` / `full` states and puts back what it found.
- **Plain names**: the HUD cards are Performance / Replay clips / Voice chat / Key display, with blurbs that say what they are
  (`hud.js CATALOG`; translations keyed by the old English fall back to English until re-extracted). Shift / Ctrl are
  "All spaces" / "Select" (the key stays in the "?" card, its title says what each does). Icon-only controls have a `HoverTip`:
  the power tray, the island's six quick switches, the inspector's toggles, the map and the snap zones.
- **Clips**: "Clipping" is **Instant replay** ("On · remembering the last 1:12" / "Off · turn on to keep the last 3 min"), the
  scissors row is **Save last** (+ the lengths) and **Record**, each cookie and the gallery have a tip saying what they do and, for
  Save, why it can't yet.
- Not exercised: every `HoverTip` (needs a hover), the More chip's click.

### The More bind, Voice and Key display (2026-11-03)

- **Binds for "More"**: `Ctrl+M` inside the overview (`Overview.steer`, before the search field sees it) and
  `qs ipc -c <repo> call overview more` for a Hyprland bind (`UiState._overviewIpc.more`, toggles `Config.overviewMore`,
  open or not). The More chip's tip names the key.
- **Voice chat**: a call with no channel name yet reads "Voice call" instead of a bare ping; the buttons say their state
  ("Mic on / Mic off", "Speakers on / Speakers off" — it was "Sound"/"Deafened"), each with a tip (deafen also mutes); the mic
  slider's icon explains it (and that clicking a person sets how loud THEY are for you).
- **Key display** (was Input): the status is "Hidden / Showing on screen / Shows while you play"; the card's one action is a
  labelled **Show on screen** switch (it was "pin it to show it", behind a chip that only appears on hover), with an
  "Always / Games only" chip once it is on; the description moved into the switch's tip.

### Left-face pages (2026-11-03)

"What's changed" is **What's new** (rail and page header); every stop of a `SlidingTabs` (the rail, the News topics) has a `HoverTip`
with its name, since all but the current one are icons. The Key display card gained a Customise chip (see docs/hud.md).
