# QML API caution

Read before editing any QML. Moved out of CLAUDE.md verbatim.

## API caution

Quickshell is young and evolving; so is Hyprland. Don't assume API shape from
training data — check actual usage in this repo and what's installed on disk, and
flag uncertainty rather than asserting. The installed build's own C++ source is on
disk here, at `/usr/src/debug/quickshell-git/quickshell/src/` — the ground truth for
behaviour the qmltypes can't show (when a signal fires, what gets logged).

Things that bit us and are cheap to re-check:

- **Never redeclare a property the base component already has.** `PrivacyPill` did
  `property color accent: …` on an `IconButton`, which already declares `accent` —
  and then assigned `accent:` too. That's `Property value set multiple times`: a
  hard load failure of the whole file, which cascades (`Bar` unavailable →
  `shell.qml` unavailable → nothing starts). Invisible to the syntax check;
  `check-qml-duplicates.py` catches it. Before subclassing, list what the base
  already declares — its own default is usually what you wanted, with the caller
  passing the value in.
- **…and redeclaring a C++ base property SHADOWS it, silently.**
  `required property var screen` on a `PanelWindow` declares a second, QML-side
  `screen`; `screen: modelData` then lands on the shadow and the layer surface never
  learns its output. Measured with a C++ `Timer.interval` redeclared in QML: the
  timer kept its default. Seven overlays did this and landed on the focused monitor
  only by luck; all are fixed, and the one-screen ones decide WHICH screen with
  `ScreenOwner` (below). Anything mapped on EVERY screen at once must assign the
  base `screen` (as `Bar` and `DockReserve` do) — the old dock didn't, and both
  copies landed on one monitor.
- **A `Loader` with an explicit size RESIZES ITS ITEM to match.** So
  `Loader { width: item ? item.width : 0 }` freezes the item at whatever size it
  loaded with: load while empty and it's pinned at 0 forever, however many children
  arrive later (`implicitWidth` grows, `width` doesn't). That was "the dock shows no
  apps" — reproduced offscreen with `/usr/lib/qt6/bin/qml`. Let a Loader auto-size
  (no width/height at all), or bind the item's IMPLICIT size.
- **A `Loader`'s `implicitWidth` / `implicitHeight` are READ-ONLY** — they follow the loaded item.
  `Loader { implicitHeight: item ? item.implicitHeight : 0 }` is `Invalid property assignment:
  "implicitHeight" is a read-only property`, a hard load failure that cascades (HoverCard →
  SidePanelDock → Bar → shell.qml, 2026-10-17). Passes the syntax sweep and every static checker.
  Read `loader.item ? loader.item.implicitHeight : 0` from the parent instead.
- **`Keys.*` is an attached property that only works on an `Item`.** `PanelWindow`
  is not one. Attaching there logs `Could not attach Keys property … is not an
  Item` and then does nothing — so Escape silently stops closing a panel. Put the
  handler on an `Item` inside (a `Surface` is a `Rectangle`, so it qualifies) that
  is an ancestor of whatever has focus. `TextInput` doesn't consume Escape, so it
  bubbles up. Bit `EmojiPopup`.
- **`PanelButton` has `activated()`, not `clicked()`.** `onClicked:` on one is `Cannot assign to non-existent
  property "onClicked"` — and it blanks the WHOLE page it sits in (WallpaperPage, 2026-10-29), not just the button.
  Passes the syntax sweep and every static checker; only the log of a running shell says so
  (`strings /run/user/$UID/quickshell/by-id/*/log.qslog | grep "Cannot assign"`).
- Every `.qml` must be registered in its directory's `qmldir`, or it's "not a
  type" at runtime with no static warning.
- **A HOT reload cannot introduce a new inline-component name that is used.** Add (or rename)
  `component Foo: Item { … }` and use it, save, and the running shell's reload fails with
  `@File.qml[n:5]: Foo is not a type` — on every later save too, until a restart. A cold start
  loads the identical file; editing an EXISTING inline component's body hot-reloads fine, and an
  added-but-unused one does too. Measured in an isolated scratch config (2026-10-10), so it is
  Quickshell/Qt, not the code: ALT+Q after adding or renaming an inline component, and when
  testing from a terminal use a fresh `quickshell -p …` rather than trusting the live reload. It
  looked like a naming bug twice before it was understood (`LeadButton`, `KeyCap`).
- **A new `Config` property does NOT persist by itself.** A preference survives a
  reload only if `Config._persisted` names it; forget and the setting works in the
  session you set it in, then resets on the next reload — including the hot reloads
  your own saves trigger, so it reads as "the toggle turns itself off", never as "I
  missed a list". The runtime audit (`_auditPrefs`) only catches the OPPOSITE mistake
  (a name with no property). The cursor's toggle did this, and the audit that found it
  turned up eleven older ones (night light, the wallpaper paths, the screenshot
  options). `scripts/check-config-persisted.py` is the static guard; a property
  that is deliberately stored elsewhere goes in its EXEMPT table with the reason.
  The saved document is `Quickshell.statePath("config.json")`; to see what a running
  shell actually persisted, read that file (never edit it — see Guardrails).
- A layer-shell surface opened from a *different* surface (a panel opened by a bar
  pill) needs `WlrKeyboardFocus.Exclusive`. `OnDemand` only grants focus on a
  click INTO the surface, so text inputs silently ignore typing and
  `Keys.onEscapePressed` never fires. Don't hold `Exclusive` across long-running
  work — it locks the rest of the desktop out of the keyboard.
- Don't bind a property to a *function call* that walks `Hyprland.monitors` or
  another lazy model. They notify mid-evaluation and re-enter the binding — a real
  binding loop (`CavaBG.suppressed`). Have the service compute a plain notifying
  property and bind to that.
- **`QsWindow.window` on an object with no Item above it** (a window's own root, a
  QtObject in a singleton) gives no attached object; Qt's attached lookup then falls
  through to `undefined` rather than throwing, and `Colors.of(undefined)` is the shared
  palette. Inferred from how the lookup is written (`windowinterface.cpp` walks QObject
  parents to the nearest Item), not measured — a `TypeError` naming QsWindow in the log
  would mean otherwise.
- **A property named like an Item property that's FINAL is a hard load failure.**
  `property real left` ("time left") on a Shape: `Cannot override FINAL property`, and
  PowerMenu → shell.qml was unavailable. `check-qml-final.py` catches it. (`state` isn't
  FINAL, but redeclaring it breaks States — don't either.)
- **An inline `component` in a PanelWindow-rooted file failed to load** (measured 2026-10-31, Qt 6.12,
  CavaBG): "X is not a type" at the component's own declaration, with or without outer-id
  references. A separate file worked. Every other inline component here lives in an Item-rooted file.
- **Inside a `ClippingRectangle`, a child's `parent` is the content item**, not the rectangle:
  `parent.someProp` reads `undefined` ("Unable to assign [undefined] to QUrl"). Use an id.
- **`signal set(…)` makes the file unparseable, silently.** `qmlformat` prints nothing
  and outputs 0 bytes — the syntax idiom's only tell. `set`/`get` are contextual
  keywords; name the signal something else (VoicePanel's `Level.chosen`). `check-qml-final.py`
  catches it.
- **An `id` may not shadow a JavaScript global.** `id: gc` (inside an inline
  `component`, even) is `ID illegally masks global JavaScript property` — a hard load
  failure that cascades to `Bar` unavailable, and passes the syntax sweep
  (`check-qml-final.py` lists it as `illegal-names`). `gc`, `print`, `escape`, `isNaN`, `console`, `Math`… are all
  taken. Bit BluetoothPanel's `GlyphChip`.
- **`Quickshell.env()` returns a QVariant, so an unset variable is `undefined` —
  not `""`.** Never test with `!== ""`: `undefined !== ""` is TRUE, so the check
  passes for exactly the variable that isn't there. Use the `||` idiom the repo
  already uses (`Clipboard.qml`, `Updates.qml`, `Storage.qml`, `LockScreen.qml`):
  `(Quickshell.env("X") || "")`, or
  `Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")`. It
  bit `Greet.underGreetd` (inverted — decided it WAS running under greetd exactly
  when `GREETD_SOCK` was unset) and `Greet.bundlePath` (built
  `"undefined/quickshell-greet/greet.json"` and silently loaded nothing). Neither
  produced a warning. Verified against the qmltypes:
  `grep -n 'name: "env"' -A 3 /usr/lib/qt6/qml/Quickshell/quickshell-core.qmltypes`
  → `type: "QVariant"`.
- **Never load an `image://icon/…` URL asynchronously.** Quickshell's icon provider is a
  QPixmap provider, and on Wayland (ThreadedPixmaps) Qt runs an asynchronous load of it on
  its image-reader thread, where `QIcon::fromTheme` races the GUI thread's lookups. A segfault
  in `IconImageProvider::requestPixmap` under `QThread::exec` in the crash report is this.
  `Canvas.loadImage` is ALWAYS asynchronous: `ThemedAppIcon`'s cut of every dock icon
  crashed every launch (2026-10-31) until it stopped cutting `image://` sources (it has since been replaced
  by `MonoIconEffect`, a layer effect, which loads nothing itself). An `Image`
  with `asynchronous: true` takes the same path (SideWindow and WindowPill still do, one
  icon at a time, and have survived); keep new ones synchronous.
- **`MultiEffect` desaturates AFTER it colorizes** (measured, Qt 6.12, 2026-10-31): `saturation: -1` with
  `colorization: 0.75` drew pure grey (151,151,151) — the tint was taken back out. Colorize alone; it is a multiply
  onto the source's luminance (TintedIcon), so it replaces the hue by its own amount.
- **A layer's effect item can't find its window**: `Colors.of(QsWindow.window)` inside a `layer.effect` answers with the
  shared `Colors` singleton, not the screen's palette. Resolve the colour on the HOST (a property of the
  layered item's file) and pass it into the effect. The singleton also seemed to survive hot reloads (a role newly forwarded
  through `Colors` read `undefined` until a restart, while the per-screen palettes had it) — restart after adding one.
- **System-integration gotchas** (`Image.sourceSize`/`sourceClipRect`, `Process.stdinEnabled`,
  pam_faillock, `Io.Socket` warnings, Hyprland `.lua` config and `hyprctl dispatch`) are in
  `docs/gotchas-system.md`. Read it before touching a `Process`, a socket, or Hyprland config.
- **Inside a hidden layer, `visible` is false — even while it's on screen.** A mask stencil (`visible:
  false; layer.enabled: true`, read by a MultiEffect) renders its children, but each child's `visible`
  reports false. A component that skips work `if (!visible)` draws nothing there: CavaBG's Waveform was
  blank for that (2026-10-31). Gate on a property the host can override (`WaveformSpectrum.drawing`).
