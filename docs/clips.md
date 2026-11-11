# Clips

Moved from CLAUDE.md; the project rules there still apply.

## Clips (replay buffer + recorder)

`scripts/clips-run.py` (detached runner) + `scripts/clips-lib.py` (library) →
`services/Clips.qml` (logic in `services/clips.js`) → `modules/bar/SideClips` (the sidebar
button) and its panels `modules/panels/ClipsPanel` (clipping, save lengths, recording,
capture target, the latest clips), `ClipsTargetPanel` and `ClipsPeek`,
`modules/panels/ClipsGallery` + `ClipsGalleryPanel` (the library),
`modules/settings/pages/ClipsPage`. Medal/ShadowPlay-style, on **gpu-screen-recorder**.
Tests (all safe): `bun scripts/test-clips.js` (pure), `python3 scripts/test-clips-run.py`
(a FAKE recorder on a temp PATH), `python3 scripts/test-clips-lib.py` (generated clips).
Diagnose with `qs ipc -c ~/.config/quicktest call clips status` (states and counts only).

- **Two switches, both off by default, neither flipped by anything but the user** (no
  auto-start on games): `Config.clips` shows the pill; **Clipping** (`Config.clipsBuffer`,
  persisted) KEEPS the buffer running — `_reconcile()` starts it once the run dir, the probe
  and the runner's state are all known (a buffer surviving a reload is found, not doubled),
  and restarts it if it dies: 5s apart, and after three failures in a row it stops
  (`gaveUp`, one notification) until the switch is flipped. With the feature off, `_launch`
  refuses — a keybind must not start a screen recording nobody can see.
- **Region recording pauses clipping**: the recorder captures one thing at a time, so a
  running buffer is stopped for it (`_pendingRegion`; its contents go) and clipping picks
  back up when the recording ends. A plain recording during the buffer is SIGRTMIN and
  costs nothing.
- **The runner is detached** (`setsid`, update-run.sh's rule): a reload never drops the
  buffer. It talks through files in `$XDG_RUNTIME_DIR/quickshell-quicktest-clips`:
  `state.json` (atomic), `events.jsonl` (one line per saved file), `recorder.log`, and a
  `lock` flock (a second start exits 75). `check` reconciles a state file whose daemon
  died and creates both files — FileView only sees a file CREATED if its directory existed
  when the watch was set up, so QML mkdirs + checks first and only then sets the paths.
- **Signals, not the `-ipc` socket.** SIGUSR1 saves the buffer, SIGRTMIN+1..6 the last
  10s/30s/60s/5m/10m/30m, SIGRTMIN toggles a regular recording during the buffer (needs
  `-ro`), SIGUSR2 pauses, SIGINT stops (a recording is written out). Every build since 5.x
  shares them; `-ipc` is newer. The pid is checked against `/proc/<pid>/comm`
  (`gpu-screen-reco`, 15-char truncation) before every signal.
- **Saved files are learned from the recorder's `-sc` hook** (`scripts/clips-saved.sh` →
  `clips-run.py saved`), so a save nobody asked QML for still peeks. QML reads events by
  TIME, not line count (the hook trims the file).
- **`clips.js recorderArgv` is the trust boundary** for the hand-editable config: every
  value whitelisted or clamped; the runner re-checks the argv's shape (the recorder first,
  no `-sc` of its own). Verified against the installed 6.1.3 (`--help`, the man page):
  `-k auto`, `-bm auto|cbr`, `-replay-storage`, `-restore-portal-session`.
- **No QtMultimedia** (not installed; a missing module would take down every importing
  file). Thumbnails and the trimmer's filmstrip are ffmpeg frames, cached by a hash of
  path+size+mtime; playback is the gallery's own player (see "The library, the player and the file manager" below; `gio open` only if qt6-multimedia is missing). A trim is `-c copy` to `<name>-trim` beside the
  original (keyframe-snapped start, and the card says so); a rename is link+unlink so it
  can't replace a file. Deletion is `gio trash` through an `ArmLatch`.
- **Copy** puts a `text/uri-list` on the clipboard (`Clipboard.copyText(text, mime)`), the
  way a file manager copies — a paste into a chat attaches the file.
- **The button** (user's picks): click = the Clips panel beside it, middle = clip it
  (`Clips.saveClip(0)`, which says why when it can't), HOLD = the target picker, right =
  its settings. At rest the ring fills with the buffer, turns red and full while
  recording, with a red dot breathing on `Motion.pulse` (a channel: it has to keep saying
  "recording" with motion off). Hovering while it counts shows the time. Clipping off is
  an empty ring at FULL strength (dimmed, it read as broken); only unavailable dims.
- **The save lengths** are `clips.js saveLengths(buffer)` — the ones gpu-screen-recorder
  has a signal for, shorter than the buffer (each round-trips to `save:N`; tested).
- **The peek**: a save opens `ClipsPeek` beside the button for 2.6s (`autoCloseMs`, longer
  while hovered) on the focused monitor, only when the side slot is free
  (`Config.clipsPeek`). It keeps a COPY of `Clips.lastSaved` (the fade rule).
- **Keys** (`hypr/binds.lua` and the live copy): ALT+F10 save, ALT+F9 record,
  ALT+SHIFT+F10 clipping on/off, ALT+SHIFT+F9 region (slurp). ShadowPlay's own keys.
  ALT+F10 with nothing to save says WHY in a notification (clipping off, still starting,
  the recorder failing) rather than doing nothing. Autoreload picks up a live binds.lua
  edit; to confirm, `hyprctl binds` shows Lua binds as `dispatcher: __lua` with a callback
  index (grep the `key:`, never the command text — it isn't printed).
- `gsr-kms-server` needs `cap_sys_admin` to capture a monitor without a prompt; Arch's
  package sets it. `-w portal` is the fallback (`Config.clipsTarget = "portal"`).
- **Hold the button to pick a target** (`SideClips`): a dwell (so a click never flickers),
  then a charge arc — drawn with its own `Shape`, because RadialGauge EASES its sweep and a
  hold must track the finger — while the ring coils and glows; at full charge two ripples
  and an elastic pop, then `ClipsTargetPanel` beside the button ("Clip from" retargets the
  buffer, "Record" records it now; the Clips panel's Change opens it too). The list is
  `Clips.targetChoices()`, CALLED on open and on `Hypr.windowsChanged`, never bound — the
  window list reads visible workspaces, which walks `Hyprland.monitors` (a binding over it
  re-enters) — with `Hypr.acquireEvents()` held while it's up. Keys (`Clips.retarget` / `recordTarget`):
  `focused`, `mon:<name>`, `portal` persist in `Config.clipsTarget`; `win:<address>` and
  `region` are `sessionTarget` — a RECTANGLE (`clips.js windowGeom`), which doesn't follow a
  moved window; the portal is the capture that does. Wayland has no other window capture
  in gpu-screen-recorder (`-w focused`/window ids are X11-only).
- **Recording something other than the buffer's target** stops the buffer for it
  (`_pendingRecord`; the recorder captures one thing) and clipping resumes after. The same
  target records beside the buffer with SIGRTMIN, losing nothing.
- **The editor** (`modules/panels/ClipEditor`, the gallery's second view): player,
  transport (frame step, speed, volume, loop the cut), filmstrip timeline with playhead and
  in/out handles (I/O keys), save frame, and `clips-lib.py export` — fast copy vs precise,
  10/25/50 MB targets, downscale, "No mic" (first audio track), mute, GIF. Streams
  `progress`; cancel kills the runner, whose SIGTERM handler kills ffmpeg and removes the
  partial file (tested). `export_plan()` is pure and pinned by the test.
- **The player is optional**: `components/media/ClipPlayer.qml` is the ONLY file that may
  `import QtMultimedia` (not installed by default; a missing module makes the importer fail
  to EXIST; the sound effects used to be a second one and now go through `pw-play` instead — see
  `docs/sound-effects.md`). `state/Media` probes it with `Qt.createComponent` (Morph's pattern); the editor
  loads it by URL only when available, and otherwise shows the poster and still cuts and
  exports. Needs `qt6-multimedia qt6-multimedia-ffmpeg` (in install-dependencies.sh).
- **"Separate tracks" (`clipsSplitAudio`) records the mic but hides it**: players,
  browsers and Discord's embed play only the FIRST audio track, so a split clip sounds
  mic-less everywhere but an editor. Measured on a real clip: the voice was on track 2
  (peaks −13 dB) and "missing". The page says so; the export defaults to `mix` (`amix …
  normalize=0`, one track — without normalize the voice comes out quieter); "Separate"
  is opt-in. Discord's own mute is unrelated: it never mutes the PipeWire source.
- **Favourites** are `Quickshell.statePath("clip-favourites.json")` (a JsonStore, never
  config.json), filtered to absolute paths on read; renames move the star, trash removes it.
  The library filters/sorts through `clips.js libraryView` / `clipKind`.


### The panel, revamped (2026-10-18)

`ClipsPanel` brought to the look of the media / colours / clock panels (user: "a revamp, use the style from the recent
panels"). Same `Clips` calls, same two columns; only what you see changed:
- Header actions are a `ChipTray` of `ChipButton`s (gallery, folder, settings), in one accent: `focus`, `danger` while a
  recording runs. (`ActionGroup` is what the older panels still wear.)
- **Clipping** card: the buffer as a `RadialGauge` (held time in the hole; `sampleInterval: 1000`, so it settles each second
  instead of redrawing all day), the switch, then **Clip it** as a primary `CookieButton` and the lengths the recorder can
  cut (`saveLengths`) as one tray of labelled chips. Dimmed together while clipping is off.
- **Recording** card: a `CookieButton` (record → stop through its own squash), the running clock with a breathing dot
  (`Motion.pulse`, a channel — it keeps saying "recording" with motion off), pause and region as chips.
- **Capture** card: the target and an edit chip, with the video and audio settings as two pills.
- **Latest**: three thumbnails, each arriving on a spring (`PopIn`); hover lifts the frame, shows a play disc and a copy chip.
  An empty state instead of a bare "Nothing saved yet".
- Cards are flat `section` fills on `radiusCard` (no outline), washed with the accent while the buffer / a recording runs,
  and arrive one after another (`PopIn`). `Tile` is still the one inline component (new `tone` / `popIndex`).
- Unverified by eye: the card heights against the slot's `maxHeight`, and the lengths tray's width with six chips.

### Eight additions (2026-10-18)

The user asked for the suggestions after the revamp: all but the lock-screen replay. Logic is pure and tested in `clips.js`
(`bun scripts/test-clips.js`, 171 cases), the runner and library carry the file work (`test-clips-run.py`, `test-clips-lib.py`).

1. **Clip it + N more seconds** (`Config.clipsAhead` 0/10/20/30; the panel's timer chip cycles it, Settings › Clips › Clip & record
   sets it). `Clips.clipIt` — what the BUTTONS mean — waits, then asks the recorder for the next signal length up that covers
   `before + after` (`aheadPlan`) and cuts the saved file down to size (`clips-lib.py headtrim`, a stream copy swapped over the original:
   the ONE in-place edit in the library, only on a file we asked for seconds ago; keyframe-snapped, so a touch long, never short). The
   keybind and `clips save` stay plain "now"; `clips saveAhead <before> <after>` is the IPC form. The whole buffer + N is the last
   `buffer` seconds ending N from now — a buffer can't hold more than its length. While it waits: "Saving in 7s…", **Now** and **Cancel**.
2. **Clips named after the window.** The recorder's `-sc` hook (`clips-run.py saved`) renames the file to `<Game>_Replay_<stamp>` using
   `hyprctl activewindow -j` (`window_label`: the TITLE for Steam / Proton / Wine / gamescope windows, the class for anything else; only
   letters, digits, `.`, `-` — never `_`, which the library splits on). A plain recording gets the label put into its `-o` path at start,
   a recording during the buffer stores it in state when toggled on (you are elsewhere by the time it ends). `Config.clipsNameByWindow`
   reaches the hook through state.json (`clips-run.py set … naming window|plain`), because the daemon is started once. `clipKind` finds
   `_Recording_` / `_Video_` mid-name; `gameOf` / `gamesOf` feed the gallery.
3. **Quick actions.** The save peek is a chip tray: copy, **edit** (`Clips.editClip` → the gallery opens its editor on that file; it
   consumes `Clips.editRequest`), **send to Discord** (copies it as a file and brings Discord forward — a paste attaches it), play, library.
   The panel's latest clips get edit + copy.
4. **"Why isn't it clipping?"** `clips.js diagnose` turns facts into sentences: the recorder isn't installed, the capture monitor is gone,
   the recorder's own words explained (`explainError`: permission → use the portal, portal, monitor, codec), a buffer that won't fit in
   RAM, a low disk. The panel shows the worst one in a card with a button for the fix (`Clips.fixLabel` / `applyFix`: portal, Auto codec,
   keep it on disk; "target" and "folder" open the picker / settings). A warning (disk) takes the warning tone.
5. **Presets** (`PRESETS`: Game, Tutorial, Light, Max): one pill sets fps, quality, bitrate mode, codec, resolution, buffer length and audio.
   Lit while the settings are EXACTLY that preset (`matchPreset`); none lit = tuned by hand. A running buffer keeps its old settings until it
   restarts, so `Clips.stale` (what it was started with ≠ what is set) shows "Apply settings". The capture target, folder and container are
   not part of a preset.
6. **RAM and disk.** `Clips.health` — free RAM and disk, the recorder's resident memory (the buffer lives in it) and whether
   `gsr-kms-server` has `cap_sys_admin` — from ONE shell script, probed only while something holds `acquireHealth()` (the panel, every 5s) and
   once when clipping gives up. Nothing runs in the background. The buffer card shows "Holding 0:45 of 2:00 · 412 MB".
7. **Stop after…** (`Config.clipsRecordLimit`: 5 / 10 / 30 min, 1 / 2 / 4 GB; the schedule chip on the record card cycles it). Checked every
   3s while recording; a size asks `clips-lib.py size` (a plain recording by its path, one during the buffer by the newest `Video_*` since it
   began). Wall-clock, so a pause counts. Stopping says so in a notification. Enforced from the shell: a reload mid-recording drops the limit.
8. **Gallery.** Opens on **Today** when anything is from today (once, never over your pick), a game filter appears with two or more games,
   **multi-select** (Ctrl-click, the tick on a tile, Shift-click a range, Ctrl+A; Escape clears) with a bulk pane: star all, copy as files,
   shrink each to 10 / 25 / 50 MB one after another (`Clips.exportMany`, the editor's export, cancelable), delete (asks; to the trash).
   **Drag a clip out** by the handle on its thumbnail (Qt's drag, `text/uri-list`, the whole selection if it is part of one); only from the
   handle so dragging a tile still scrolls the grid. Search by name already existed.
- Unverified live: none of this has been loaded. In particular the drag into another app (Wayland), the hook's rename racing the recorder,
  how a head-trim lands on a real clip, the panel's heights, and Discord coming forward.

### The library, the player and the file manager (2026-10-18)

User: the revamp's look on everything the clips panel links to ("like the library"), Play in the shell not in mpv ("it's annoying"), the
folder in a file manager like Nautilus instead of a terminal `cd`, the library easier to reach, and "a bigger clear button".
- **Restyled to the media / colours look**: the library (ChipTray header and toolbars, a `SegmentSwitch` filter, flat `section` cards, tiles
  and cards on `PopIn`, a `CookieButton` for play), the editor/player, the target picker (segmented mode, pills under Monitors / Windows /
  Other headings) and the peek (the frame is a play button, one chip tray). Settings › Clips keeps the settings pages' own style.
- **Play is in the shell.** `Clips.playClip(path)` (the peek, the panel's latest clips, the library's Play and double-click) opens the gallery
  on `ClipEditor` with `viewOnly`: it autoplays (`ClipPlayer.autoplay`), has the transport and a seek strip, no cut handles and no export;
  **Edit** (or E) flips the same component to the editor, so the clip is where you left it. `Clips.playRequest` is consumed by the gallery like
  `editRequest`. Only when qt6-multimedia is missing does it hand the file to the system's video app (`openClip`, which the editor's
  "open in default app" chip still calls on purpose).
- **Folders open in a file manager.** `gio open <dir>` opens whatever handles `inode/directory`, which here was a terminal. Now `clips.js
  pickFileManager` / `fileManagerArgv`: `Config.clipsFileManager` ("" = auto) if installed, else the first installed of Nautilus, Dolphin,
  Thunar, Nemo, PCManFM-Qt, PCManFM, Caja (probed once at start into `Clips.fileManagers`); "show in folder" SELECTS the file in Nautilus and
  Dolphin (the others open the folder). The folder is made first. Settings › Clips › Files has the choice. `gio open` is the last resort.
- **The library is easier to reach**: a labelled **Library** chip on the panel's Latest card, **Alt+F8** (repo `hypr/binds.lua`; the LIVE
  `~/.config/hypr/binds.lua` needs the line by hand), "Clips library" in the launcher (`ShellActions` `clipsLibrary`), `clips gallery` over IPC,
  and the panel's header chip as before.
- **The clear buttons are big.** A disc as tall as the search field clears the search (there was none); a selection (one clip or many) shows a
  banner with a full-size "Clear selection" pill (Escape clears too). Interpretation: the user said "a bigger clear button" without saying
  which — these are the two clears the library has.
- Double-click on a tile now PLAYS (it opened the editor); Edit is its own chip.
- Unverified live: none of it has been loaded — the player's autoplay, Nautilus selecting the file, the view-only layout, every restyled
  surface's heights.

### The library, reworked (2026-10-18, same day)

User, with a screenshot: "I don't like how it looks, doesn't feel good enough and it's quite clunky to use — make it look better and be
easier and more pleasant to use." What was clunky, and what replaced it (this supersedes the library bullets above):
- **Three rows of chrome before any clip** (search + sort, a full-width filter bar, the games row) → ONE toolbar: search (with a clear disc as
  tall as the field), the filter as a compact `SegmentSwitch`, and the sort as a single chip that says how it is sorted and cycles on a click.
- **Raw file names** (`Replay_2026-10-11_02-22-38-trim`) → `clips.js prettyName`: "Elden Ring · 21:41", "Replay · 02:22", a "Trimmed" /
  "Edited" / "GIF" tag on the frame, your own names kept. Display only — the file's name is never changed.
- **One endless grid** → grouped by DAY ("Today", "Yesterday", "Monday", "11 October"; `groupByDay`) while sorted newest/oldest, one unlabelled
  group when sorted by length or size (a day heading over a list not in day order would lie).
- **Click selected, a side pane then reflowed the whole grid** (four columns became three on every click) → **a click PLAYS**; pointing at a clip
  shows a play disc and star / edit / copy on the frame; the tick (or Ctrl / Shift-click, Ctrl+A) selects. Once anything is selected a click
  toggles instead, as a photo library does. The pane is gone: a **selection bar floats up from the foot** (one clip: Play, Edit, star, copy,
  send, folder, delete; several: star all, copy, shrink to 10/25/50 MB, delete) with a big **Clear** at its end. Nothing reflows. Escape lets go
  of a selection before it closes the library. Delete still asks twice and goes to the trash.
- A clip you just made, renamed or exported is selected, so it is easy to find. Empty states say what to do and offer "Clear filters".
- Not changed: the player / editor, the target picker, the panel and the peek (restyled earlier today).
- Unverified live: never loaded — the hover states, the bar's rise, the day groups against a real library, and the tile size at your width.
- The library's click-away backdrop closed on ANY tap inside the card once its buttons were TapHandler-based (ChipButton/CookieButton/SegmentSwitch; PanelButton's MouseArea used to block it). Fixed 2026-10-18: ClipsGallery closes only for a tap outside the card. Other click-away backdrops checked: none host those controls.

### Panels reworked, plus sharing and housekeeping (2026-11-09)

User: "add and alter everything about it for the better … could also use the bridge scripts we already have for Discord and
Spotify". Supersedes the Latest / Capture bullets of "The panel, revamped".
- **Stage 1 — fixes.** `Clips.clips` was replaced with a NEW array on every index refresh, so `Clips.clips.slice(0, 3)` rebuilt the
  latest row (delegates, thumbnails, pop-ins) whenever anything refreshed. Now: an index whose text is identical to the last is
  dropped (`_indexText`; a local trash clears it), and the panel replaces its row only when `clips.js listSig` of what it shows
  differs. The target picker did the same on every `Hypr.windowsChanged`; it now compares the list (JSON) before replacing it.
  The preset pills (Rectangle + MouseArea, no accessibility, no state layer) are `ChipButton`s; literals → tokens; strings →
  `Translation.tr`; the panels' own history comments gone.
- **Layout.** Left: Clipping, Recording. Right: Capture, **Library**. Full width under both: **Latest**, one row of up to six
  (three on a short edge) with a duration badge, the pretty name, the song/people line (or "time · age"), a dot for clips saved
  since the panel was last open (`Config.clipsSeenAt`, set when the panel closes), hover play disc + edit/copy.
- **Keys while a panel is open** (`SidePanelDock` → `handleKey`): panel — C clip it, 1–6 a length, R record, P pause, L library;
  target picker — Up/Down/Enter, Tab flips Clip from / Record. Window rows in the picker carry the app's icon (`Icons.pathForAppId`,
  read synchronously).
- **Capture card**: mic and desktop-sound switches beside the video summary. They are settings, so a running buffer shows
  "Apply settings" as for any other.
- **Library card**: library size and free disk as one `Meter`; a clean-up chip appears only when `Clips.prunePreview` (clips.js
  `prunePlan`) is non-empty and takes two taps (`ArmLatch`). Limits: `Config.clipsPruneDays` / `clipsPruneGB`, 0 = none, set in
  Settings › Clips › Share & keep. Never a favourite, never a file written in the last 15 minutes; to the trash. Nothing automatic.
- **Send to Discord shrinks first.** Over `Config.clipsDiscordMB` (10/25/50/500) the clip goes through the editor's export with
  `sizeMB` (the lib's own 8% container headroom), then the SHRUNK file is copied and Discord comes forward. Too long to fit at the
  export's floor bitrate (150 + 128 kbps, `discordPlan.fits`) → copied as is, with the reason in the notification. Everything that
  sends (peek, editor, library bar) calls `Clips.sendToDiscord`. Paste is still the user's: no key injection, nothing is sent.
- **Context stamp** (the Spotify/Discord bridge use). `Clips._stamp` at save time: the song of the playing MPRIS player (Spotify
  through its bridge or not — `trackArtist` / `trackTitle`) and, only with `clipsStampCall`, the non-self non-bot names in
  `Discord.users`. Kept in `statePath("clip-context.json")` (a JsonStore like the favourites): `{ paths: { "/abs": { artist, title,
  with } } }`, cleaned on read AND write through CallLog's `cleanName` / `people` (control + bidi characters out, 64 chars, ≤8
  people, ≤5000 entries, absolute paths only). Shown in the peek, the panel's row and the library tile; the library search matches
  it. A rename moves the entry, a trash drops it. Music defaults ON, the call OFF (it writes other people's names down); Settings ›
  Clips › Share & keep has both switches and an armed "Forget". Personal — not in the repo, not a secret.
- **Peek**: a rail runs down with the time left (restarted when the pointer leaves, as the dock's timer is), a star replaces the
  play chip (the frame already plays), the stamp is a line under the name.
- Tests: `bun scripts/test-clips.js` (269: `discordPlan`, `prunePlan`, `contextOf` / `cleanBook`, `listSig`, search by stamp).
  `clips.js` now imports `calllog.js`; the test inlines both, the second in its own scope.
- **Not done**: the Alt+F10 / Alt+F9 hints are still typed into the labels (no service maps a bind to its label; the shipped
  `hypr/binds.lua` has them); undo after a library delete (`gio trash` has no restore CLI here); keyboard navigation inside the
  main panel beyond the keys above.
- **Unverified live — none of it has been loaded**: every height against the slot's `maxHeight` (the full-width Latest row adds
  one tile row to the panel), six thumbnails at 95 px, the rail, the keys reaching the panel through the dock, the window icons in
  the picker, a real Discord shrink and paste, a real MPRIS stamp, a clean-up of a real library, hot reload of the edited inline
  `Tile` (no new inline component was added, so it should).

### The library, third pass (2026-11-09)

User: "change the clip gallery … everything" (speed, look and layout, features — in that order).
- **Speed.** The list was a ListView of DAY groups, each a `Grid` + `Repeater` of every tile, and every tile carried its hover
  chrome (tick, three ChipButtons with their springs, drag handle, play disc) all the time: a day of a hundred clips built a few
  hundred buttons. Now the model is `clips.js layoutRows(groups, cols)` — headings and rows, keyed — so only the rows near the
  screen exist, and the hover chrome is a `Loader` active while the pointer is on the tile, anything is selected, or for
  `Motion.standard + Motion.respond` after it leaves (so it still fades). A tile at rest is a picture and a caption. Row heights vary
  (a stamp or tag line adds one), which a ListView allows.
- **Look.** A heading per day carries `groupLine` (clips · size · footage). **Hover scrub**: rest 450 ms on a ready clip and the
  pointer's x walks through ten frames of `Clips.loadStrip` (the editor's filmstrip, cached on disk by `key_of`; the first time is one
  `clips-lib.py strip` run at `nice 10`); a rail shows where. It shares the single `Clips.strip` slot with the editor, which reloads its
  own on open. The header's subtitle adds the free disk (`Clips.refreshHealth()` once on open — nothing holds the probe).
- **Features.** Facet row: games, **With music** / **In a call** (clips whose stamp has a song / people; shown only when some clip has
  one), and a row of **your tags**. **Tags**: `Clips.tags` in `statePath("clip-tags.json")` (`{ paths: { "/abs": ["tag"] } }`), cleaned
  like a name (CallLog's `cleanName`, runs of spaces collapse, 24 chars, six a clip, "Clutch" = "clutch", the first spelling kept; all in
  `clips.js`, tested). The selection bar adds a tag to everything selected (a field) and shows the first two tags the selection carries
  as chips — a tap takes that tag off all of them. A rename moves a clip's tags and stamp, a trash drops them. Search matches tags. The
  header gets the clean-up chip when `Clips.prunePreview` is non-empty (two taps, to the trash).
- **Not done**: compare two clips side by side (a second player; the editor's `ClipPlayer` is the only QtMultimedia file and a second
  instance doubles the decoders — ask if it is wanted); sort/filter are not remembered between opens; bulk "send to Discord" (several
  files can't be pasted into one chat reliably — the shrink chips stay).
- **Unverified live — never loaded**: that a `Loader`'s `sourceComponent` finds the tile's ids under `ComponentBehavior: Bound`
  (the same file's other delegates do), the scrub's first-run delay, row heights with the tag/stamp lines, scrolling across many rows,
  the selection bar's width with the tag chips on a narrow library, and the facet rows' height against the toolbar (the user once
  called the old chrome "three rows before any clip": this adds up to two more rows, each only when it has something to offer).
