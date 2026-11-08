# App launcher

Moved from CLAUDE.md; the project rules there still apply.

## App launcher

`modules/panels/AppLauncherPanel` (the state, keys and anchored geometry) hosted in
`BarPanelDock`'s centre slot, composed of `LauncherField` (the pill), `LauncherAction`
(the sum / command / question band), `LauncherRow`, `LauncherQuick` (an app's quick actions),
`LauncherEmoji` (the `:` grid), `LauncherChat`, `LauncherHelp` and `LauncherHints` (the footer). The thinking is NOT in the panel: ranking, launch history and
"what does Enter mean" are `services/launcher.js` (`bun scripts/test-launcher.js`) behind the
`services/Launcher` singleton; the calculator is `calc.js`; the AI is `services/Ai`.
Settings › Launcher (`LauncherPage`) owns the AI provider/key, the `>` terminal, the web
search engine and the history. `python3 scripts/build-settings-index.py` after editing it.

- **At rest it is only the field** (the user's call, 2026-10-03: the pin strip went, and
  `Config.launcherPinsExpanded` with it). Pins are still the dock's (`Pins`); they only
  sort first among equal matches, and a row's pin button / Ctrl+P toggles one (right-click is the quick actions now).
  The empty field TYPES its prefixes (`components/TypedPlaceholder`, shared with the settings and wallpaper searches): `LauncherField` keeps "Search apps" and types one `idleHints`
  entry after it (key in the accent, then what it does), holds, erases, next — one Timer whose
  interval is the phase's delay. Only while empty, unmoded and visible; with motion off it shows
  the first hint whole. (A slide-and-fade ticker came first and was not read as an "effect".)
- **Proportions** (the user: "too tall and disproportional"): 44px rows, five at most, a 56px field
  block and a 28px footer — about 330px at the ceiling, down from 460. All from `Tokens`.
- **The height is sprung (2026-11-07), and the dock still eases after it.** The target changes
  on nearly every keystroke, and handed to `BarDock` raw each step restarts the dock's 340ms
  bezier — a velocity jump per letter, the stutter. A `SpringValue` keeps its velocity when its
  target moves, so a run of keystrokes is one continuous motion (the property the old
  `SmoothedAnimation` pair was chosen for); `Motion.springSpatial` adds the expressive overshoot
  (~1.5%: a pixel or two on a row, ~4px on the open). Three springs — card, band, footer — each
  to its own target; `implicitHeight` and `footY` are clamped at the field block, since an
  overshoot on close would otherwise take them under it. Open and close stay the dock's, so the
  blob melts as for every other panel.
  - The `SmoothedAnimation` version took a duration, never a speed limit: a velocity-based one
    made a one-row change ~40ms (2–3 frames) and read as low frame rate. A spring has no such
    mode, but if the open ever reads as too bouncy, soften the spec (`damping` toward 1), not
    the targets.
  - **Do not make the dock stop easing a panel that is "already open"** (`Behavior { enabled:
    …wanted… }`): `enabled` is read when the value is written, `wanted` flips in the same cascade
    as the height, and on close it can still hold the old value — the card snapped shut with no
    melt. This was tried and removed 2026-10-03.
  - **The footer is positioned, not anchored**: `footY` = just below the content (sprung like the
    card), the panel `clip`s to the card's edge, so the footer is revealed as the edge passes it.
    Anchored to the bottom it landed on the search field the instant the first letter was typed.
- **Ranking** scores name / generic name / keywords / exec name / comment on one tier scale
  (exact, prefix, word start, initials, substring, fuzzy). History (frecency, `launcher-history.json`
  under XDG_STATE_HOME, ids and counts only) and pins add a bonus **capped under one tier**:
  they order within a quality of match, never across it. A test pins that; keep it.
- **Focus never leaves the field.** Up/Down move the list's selection without taking focus, so
  typing always refines and there is no "back to the field" step. The field and the root both
  call `handleKey()`. Escape peels one layer: quick actions → help → text → mode chip → close.
- **Hover selects only when the pointer actually moved** (`LauncherRow`'s scene-position
  check). Results re-flow under a resting cursor as you type; Qt re-delivers hover to the new
  row, and letting that select moved Enter onto an app you never pointed at.
- **No guessing.** A miss shows two buttons (web search, ask) rather than Enter sending your
  text anywhere. `>`, `?`, `+`, `;` and `:` are the only modes and only from an EMPTY field.
- **Shell actions and settings answer too** (2026-10-04): `services/ShellActions` is a table
  (night light, DND, game mode, stay awake, lens, colour pick, clip, record, lock, power
  menu, wallpapers, random wallpaper, light/dark, Wi-Fi, mute, mic, sidebar, updates,
  settings, reload…) folded into the SAME index (`launcher.js buildIndex` `kind: "action"`,
  `penalty` 5 — under one tier, so an app matching as well lists first; history lifts a
  habit). `stateOf` gives a toggle's chip (On/Off), `blockerOf` replaces the description
  and stops Enter (the launcher stays open). Destructive power actions are ONE entry that
  opens the power menu (`PowerDock`). At most 4 actions (`capKinds`), then ≤3 settings from
  `SettingsIndex.search` (3+ letters). `Launcher.open(result)` dispatches by kind.
- **`+` installs packages** (`services/Packages` + `packages.js`, `bun scripts/test-packages.js`):
  `pacman -Ss` (local, every word regex-ESCAPED) and, only with yay/paru installed, the
  AUR RPC (`aur.archlinux.org/rpc/v5/search`, the longest word — it LEAVES the machine,
  only in `+` mode, debounced). Ranked exact name → prefix → contains → description,
  repos before the AUR. Enter → `Updates.installPackages` on the update runner (its
  flock, progress and password prompt; the update panel opens): `pacman -S --needed`
  WITHOUT `-y` (never a partial upgrade) then the helper, every name re-checked
  (`NAME_OK`) — the trust boundary is there. A request is never killed mid-run; a
  changed query re-runs when it lands.
- App names are somebody else's strings: the row's match highlight goes through
  `launcher.js highlight()` (escapes `& < >`) before `StyledText { rich: true }`.
- Results are a `ScriptModel` keyed by `id`; a retained row gets its new `modelData` via
  dataChanged, so highlights follow without rebuilding rows (read from scriptmodel.cpp).


## M3E pass and new modes (2026-11-07)

Asked for: the search bar in the shell's M3E language with fluid animation, plus useful new
features. The user picked row quick actions, clipboard + emoji prefixes and web shortcuts
(running windows were offered and NOT picked — still out, as on 2026-10-03), and for the look:
sliding plate, morphing mode shape, spring entrance, grouped results. **Written without
loading the shell; nothing here has been seen running.**

**Look**
- **One selection plate.** `AppLauncherPanel`'s `ListView` draws the selected row as a single
  `primaryContainer` rectangle (`highlight`, `highlightFollowsCurrentItem: false`) whose `y` is a
  `SpringValue` following `currentItem.y + rowTop`; it stretches a few px with its velocity.
  Rows no longer draw a fill or border of their own — `LauncherRow` only re-colours its text onto
  the container (`fgOnPrimaryContainer`) and turns its tile from a squircle into a cookie
  (`MorphShape`). Hover fill is gone: hover selects (when the pointer moved), so the plate is the hover.
- **A row is a cell.** The delegate is an `Item` holding the group header (when the row opens a
  group) and the `LauncherRow`; the plate's offset is the header height. Headers are NOT
  `ListView.section`s: where a section header sits relative to the delegate's `y` was not
  something to guess without a running Qt, and plain arithmetic is checkable.
- **Rows arrive on springs** (`LauncherRow`: opacity on `springEffects`, a rise/scale on
  `springSpatial`, staggered by `Motion.stagger`, capped). Only NEW rows animate — `ScriptModel`
  keys by id, so typing keeps the rows that still match. The start always goes through a `Timer`
  (see "Gotchas").
- **The field**: the leading mark is a `MorphShape` badge (cookie at rest; squircle run, sunburst
  ask, hexagon install, clover clipboard, burst emoji) that morphs per mode and turns accent when
  one is up; the glyph pops on a spring on a mode change and gets a tiny nudge per letter. The
  mode chip is a tonal pill whose width is a spring; its label is held so it doesn't blank
  while shrinking.
- **The band** (`LauncherAction`): tonal `primaryContainer`, cookie badge, state layer, press squash.

**Grouping** (`launcher.js groupResults`, `bodyHeight`): results keep their rank within a kind;
kinds are ordered by where each first appears, so the best match is still first and Enter still
opens it. Headers show only when two or more kinds answer. `bodyHeight` sums the first
`maxRows` rows plus their headers — the list is the body's height, so a header costs a row's
worth of scroll, not a row.

**Quick actions** (Tab, or right-click, on an APP row; `LauncherQuick`, `Launcher.quickActions`):
Open · the entry's own desktop actions (`DesktopEntry.actions`: "New private window"…) · Pin/Unpin
to dock · Forget launches (that one app's frecency, `launcher.js forget`). Open and desktop actions
close the launcher; pin and forget return to the list. **Right-click used to pin** — the pin
button, Ctrl+P and the row's `keep` button still do. It is the body of the panel, not a popup:
`ContextMenu` is scene-anchored and would clip inside the card.

**`yt cats`** (`launcher.js cleanShortcuts` / `webShortcut`, `Config.launcherWebShortcuts`,
Settings › Launcher › Site shortcuts): the first word is a key, the rest the query; the "Search
YouTube for “cats”" row goes FIRST. The key alone is not a search. **Trust boundary**: the list
ends in `xdg-open`, so only `http(s)://…%s…` addresses and `[a-z0-9]{1,12}` keys survive the
cleaning, the query is `encodeURIComponent`ed and spliced with a replacer function (`$&` in a query
stays literal). The settings page marks bad rows and the launcher ignores them.

**`;` clipboard** (`Launcher.searchClip`, `launcher.js searchClip`): every word must appear in the
entry, case-blind, newest first; empty = the newest. Enter → `Clipboard.copy` (back on the
clipboard, not typed into a window). The history is the clipboard panel's, shown here as rows.

**`:` emoji** (`services/Emoji`, `services/emoji.json`, `launcher.js searchEmoji`,
`LauncherEmoji`): a grid with a cookie plate and the name beneath; arrows move in 2D, Enter
copies. 1906 emoji, no skin-tone variants, nothing newer than Emoji 16.0, from
`python3 scripts/gen-emoji.py` (needs `unicode-emoji` only to regenerate). Read from disk the
first time `:` is up. Recents (`emoji-recent.json`, state dir, characters only) come first, and
lift within a tie. **No emoji font installed → the mode says so (`Emoji.blocker()`)**;
`noto-fonts-emoji` is in `install-dependencies.sh`. Matching is by the Unicode NAME only
("fire" finds 🔥; "happy" finds nothing) — no keyword table.

**Gotchas**
- A `SpringValue` starts AT its target when it finishes loading, and a target set from the
  owner's `Component.onCompleted` can land before that — no animation. Every "arrive" here
  starts from a `Timer` (interval 0 = the next turn of the event loop) for that reason.
- `MaterialIcon`'s fill axis is `fill`; `symbolFill` is `PanelButton`'s.
- New icons need `--emit`, which is banned without the user's say-so (memory: snip redesign).
  Only names already in the font are used: `emoji_emotions`, `language`, `chevron_right`,
  `history`, `content_paste`, `open_in_new`, `keep`. A better glyph for the emoji mode, the web
  row or a desktop action is an `--emit` away.
- New singleton (`Emoji`) and new files in qmldirs: needs a full restart (ALT+Q), not a hot reload.
