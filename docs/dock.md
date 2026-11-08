# The dock

Moved from CLAUDE.md; the project rules there still apply.

## The dock

`services/Taskbar.qml` (logic in `services/dock.js`, `bun scripts/test-dock.js`) →
`components/DockIconStrip.qml` → `modules/bar/DockHost.qml` (persistent, welded) with a
`components/DockPreview.qml` beside it (`modules/overview/OverviewDock.qml` was the
overview's own copy; the overview dropped it 2026-10-04 — unused, flagged). Settings › Dock (`DockPage`) configures it.

- **Windows' rules.** One list — pins in pin order, then unpinned running apps in
  first-seen order. Click: launch / most recently focused window / (already focused)
  next window — Hyprland has no minimize to copy. Shift-click: new window. Middle-click:
  close the most recent window, one per click (the user's mapping, 2026-09-29).
  Right-click: jump list (the entry's own `actions`, launch, pin, close). Drag
  reorders pins; dropping a running app among them pins it there.
- **Event-driven.** Grouping reads `wayland.appId`, `activated`, `urgent` and
  `workspace` off each `HyprlandToplevel` — all pushed over the event socket. It
  never holds `Hypr.acquire()` (the 250ms refresh loop); focus recency is tracked
  from `Hyprland.activeToplevel`.
- **One key per app: its desktop-entry id** (`Taskbar.keyFor`). Windows report a
  class, the launcher pins entry ids; the old dock pinned classes into the same
  file. `_migratePins` rewrites legacy class pins once, after BOTH the pins file and
  the entry scan have loaded — never before (it would write `[]` over real pins).
- **`ScriptModel`, never a bare array, for anything with live state.** A JS array
  as a Repeater model rebuilds every delegate on any change (measured: one app
  appended rebuilt all four buttons) — resetting hover/press/entrance state, and in
  the preview, restarting every live capture.
- Buttons are placed by hand (`lead + i*slot`, animated), not by a `Row`: the
  neighbours of a dragged button step aside (`dock.js shift()`) and a reorder
  commits once, on release.
- **Welding** is `SettingsPanelHost`'s recipe: a `reveal` box pinned to the frame's
  inner edge grows 0 → thickness in step with the sidebar's bar, whose one lobe
  (`BlobBarLayer.sidebarRect`) the blob welds; the card rides the box's moving edge. Welded = `Colors.frameFill`, no border, no shadow;
  no plugin = squared butt-join; no frame = a floating card. Needs Morph + screen
  frame + anchored bar, and the page says which is missing.
- Everything in `DockHost` is behind a `Loader` on `Config.dockEnabled`; what
  `Bar.qml` reads is forwarded out as null/0 when unloaded (a null Region is empty).
- **Focusing a window warps the cursor** unless `cursor.no_warps` — the repo's
  `hypr/hardware.lua` now sets it. The live `~/.config/hypr` is an INSTALLED COPY
  that has drifted from `hypr/` (it lacked SUPER+D; the emoji picker and its bind are
  gone); dock keybinds (SUPER+D/T, SUPER+ALT+1–9) exist only in the repo copy
  until installed.
- **Around the icons:** notification badges (unseen since the app was last focused;
  records carry the spec's `desktop-entry`), level bars in place of the running pip
  while an app has a playback stream (never a separate badge — tried, too heavy),
  MPRIS controls in the preview, scroll = volume (identical to the bar's media
  pill: each stream stepped by `Audio.steppedLevel`, system OSD with the app's icon)
  or, for an app not playing, its windows. Streams/players/
  notifications name apps their own way; `Taskbar.keyForAny` + `dock.js
  idCandidates` map them, preferring a RUNNING key.
- **Files:** `Taskbar.openWith` builds argv from the entry's Exec (`dock.js execArgv`,
  spec field codes; refuses apps with no file code or Terminal=true). Recent files
  come from `recently-used.xbel` via `services/Recents` + `xbel.js` — match on the
  exec's binary, NOT `name` (that's the app that RECORDED the entry). Trash and
  Downloads are `services/Places` (FolderListModel-watched; `gio` for every file op;
  emptying the trash goes through an `ArmLatch`).
- **Dodge windows** uses Hypr's event tier (`acquireEvents()`: refresh on rawEvent,
  debounced, plus a 1s poll only while a floating window is visible — Hyprland emits
  nothing during a float drag). **Keyboard** (SUPER+T) needs EXCLUSIVE focus and
  lets go after 8s idle, since a click elsewhere can't reach this window.
- **Motion** (2026-09-29, "top tier" pass): ONE focus indicator travels between apps
  (`DockIconStrip` `glider`, the workspace pill's two-edge `Motion.trail` stretch) and hands
  back to the button's own pip whenever slots are in flux (drag, launcher insert) or the
  focused app's indicator says more (level bars, urgent). A closed/menu-unpinned app leaves a
  `Ghost` that sinks out while neighbours close over it (never for a drag-off — the poof —
  nor for an app a scoped dock merely stops showing). Icons swell in staggered on first
  build and rise out of the edge in turn each time the dock is revealed (`shown`,
  `Motion.stagger`/`staggerCap`). Badges pop on the spring and bump on a new count, holding
  their last label while they shrink. The preview's content fades up when it glides to
  another app. A MELTED preview has a second axis (`narrow`): it buds out of the icon at the
  button's width and widens, and closing pinches in toward the icon before the depth goes,
  its content showing only in the melt's last half.
- A looping `Animation.Infinite` over `Motion` durations must be gated on
  `Motion.slow > 0`: with motion off every step is 0ms and the loop spins a core.
- Pins live at `Quickshell.statePath("pins.json")`; the old cache file is read once
  and left in place. The dock's OWN pins — files/folders at its far end, and files
  pinned inside a jump list — are `services/FilePins` (`dock-files.json`, a
  JsonStore); a file learns its icon/folder-ness once, from `gio info`, at pin time.
- **App-reported state** (Unity LauncherEntry: counts, progress, urgency) is
  `services/LauncherEntry` — `dbus-monitor` parsed by `services/unityentry.js`
  (`bun scripts/test-unityentry.js`, fixture = a real capture). The app's own count
  beats the notification badge.
- **Scope** (`Config.dockScope`: all / monitor / workspace) filters running apps per
  dock; pins show everywhere, and a pin for an app out of scope still switches to it.
- **Magnification grows OUT of the dock**: `DockHost`'s `reveal` clip gets
  `magnifyHeadroom` inward, while `lobe` — the dock's own box — stays what the blob,
  the input mask and the wave use. Never point those at `reveal`. A dock that scrolls
  clips its strip, so there magnification stays inside the buttons. Welded, the swell
  is a smooth bell under the pointer (`dock.js magnifyBell` — stacked layers of the
  icons' own cosine, fed to a FIXED pool of BlobRects, `deformScale: 0`). One box
  per icon was tried first and read as a lumpy staircase. Preview tiles are the 16:9 box, EXCEPT a
  tiled window squeezed off its monitor's shape by neighbours (`DockPreview.squeezed`),
  which gets a tile of its own shape at the row's height (`thumbAspect`). The user
  rejected aspect-shaping every tile, so keep it to the squeezed ones. A MELTED
  preview (`dockPreviewFuse`) stays INSIDE the dock's length (`spanLo`/`spanHi`), and its
  ends stay `endInset` (blob smoothing + a corner) clear of the dock's ENDS; the melted
  menu does the same. An end landing on the dock's end put two rounded corners on one
  line, and the blob blended them into a bump (apps at either end of the dock). Do NOT
  stretch the preview to the dock's full length and fold it into the dock's lobe: that
  was tried, and the user rejected the whole dock merging into the preview. It
  sits flush on the dock's face (`standOff` 0) and the swell relaxes under it
  (`flatUnderPreview`) — a gap bridged by the blob, or a swell poking into the join, both
  read as a bump. The floating preview
  stands off the swell's full height (`dockInner` minus the headroom) and wears the
  dock's own outline (`strokeColor`/`strokeWidth`), never the accent. Strength
  eases 0↔1 (`magnifyAmount`) around the last pointer position; peak is
  `Config.dockMagnifyScale`.
- **Melted menu**: with the same setting, the right-click menu is `ContextMenu`'s
  opt-in `pinned` + `fused` mode, flush on the face beside the clicked icon and inside the
  dock's length. It and the preview are never open together (opening the menu closes and
  blocks the preview, so the menu has priority), so the menu borrows the preview's blob slot.
- **Peek** (`Config.dockPeek`): resting on a window in a preview sets `UiState.dockPeek`
  after 300ms. `modules/bar/WindowPeek`, declared FIRST in Bar.qml (under the frame, bar
  and dock, over normal windows), then draws that window's workspace live with it lit (97%
  opacity; the user wants it only slightly see-through) and the rest faded. Every window
  is drawn at its real place and size (a shrink-and-centre for full-size tiled windows was
  tried and reverted). Nothing is focused or moved. The overview's dock
  doesn't peek. Right-click on a preview window runs `Taskbar.bringHere`, which moves it
  to the workspace showing on the dock's monitor and focuses it.
- The settings page's Pinned section is the real strip in `editMode` (drags only).
- **Inner pill** (`Config.dockInnerPill`): the bar's nested surface behind running
  apps, one per run of neighbours (`workspaces.js runs()` → a start→length map).
  One `RunPill` delegate per SLOT over the buttons' ScriptModel — never the runs
  array as a model (WorkspacesPill's lesson: that rebuilds every pill per change).


## The ii style (`Config.dockStyle`, 2026-10-10)

`"frame"` (default) is everything above; `"ii"` is End-4's dock, **buttons only** — the card
around the strip stays whatever the host makes it (welded or floating). Picked in Settings ›
Dock › Behaviour › Style. All in `DockIconStrip` behind `root.ii`:

- **Flat** (`root.flat` = `barFeedback || ii`): no hover swell, press shrink or lift; the bar's
  `CellFeedback` ladder (primary tint + ripple); `Tokens.radiusPill` corners; no quiet fill
  behind the focused app. **No magnification** — `root.magnifyOn` is `Config.dockMagnify &&
  !ii`, and that (not `Config.dockMagnify`) is what the strip reads. The settings page greys
  Magnify/Zoom out.
- **Dots, not pip + glider:** one dot per window up to three (wide pills; small circles past
  three), focus colour for the focused app, warning for attention, one pulsing dot while a
  launch waits for its first window. The glider is off (`gliding` is false), the pip is hidden,
  the level bars still replace the dots while an app is playing.
- **Hairlines and end buttons:** a keep button (`keep` — toggles `UiState.dockRevealed`, the
  SUPER+D latch; only drawn when `Config.sidebarAutoHide` is on, otherwise it would be a dead
  control), then the start button, a hairline, the apps, the existing tail divider, and an
  **overview button** as the last tail key (`__overview`; right-click does nothing, a file
  dropped on it is refused). `lead` grows by a `divider` gap after the start group.
  Hover labels for `__keep` / `__overview` are in `DockPreview`.
- **Not in keyboard mode:** the keep button isn't a stop for SUPER+T (the overview button is,
  as part of the tail).
- **The `StartCell` component** is the old `LauncherButton` generalised (key, glyph/symbol,
  open, slot). While writing it the live shell's hot reload failed with `LeadButton is not a type`.
  The name was innocent: **a hot reload cannot introduce a new inline-component name that is
  used** (a first inline component in a file, or a rename) — reproduced in a scratch config; a cold
  start loads the same file fine, and editing an existing inline component hot-reloads fine. After
  adding or renaming one, restart the shell (ALT+Q).

## Colourised dock icons

`Config.colorizeIcons` (Settings › Appearance) now also tints the dock: app icons, pinned-file
icons and a leaving app's ghost become single-colour silhouettes in the screen's `primary`
(`MultiEffect { colorization: 1.0 }`, the tray pill's rule), in BOTH styles. `layer.enabled` is
`root.tinted`, so it costs nothing while the setting is off. The icon glyphs (Trash, Downloads,
the start button) were already palette-coloured. Not done: the preview card's header icon and
the window-list icons in `DockPreview`.
