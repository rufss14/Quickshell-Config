# Checks

Run these before reporting a QML change as done. Moved out of CLAUDE.md verbatim.

## Checking your work

Do these in order. Each catches what the one before it misses.

1. **The static checkers.** They catch hard, silent load failures that
   `qmlformat` cannot:
   - `python3 scripts/check-qml-aliases.py` — `property alias x: someId.y` where
     `someId` isn't declared in the file. An invalid alias is a hard load failure
     of the whole component, and it cascades — every consumer then reports "Type
     unavailable" and names the *consumer*, not the file with the mistake. Caused
     by exactly one edit: deleting or renaming an object an alias still points at.
   - `python3 scripts/check-qml-duplicates.py` — a property (or an attached handler
     like `Component.onDestruction`) assigned twice in one scope (`Property value set
     multiple times`), a hard failure invisible to a syntax check. **Until 2026-10-04 it
     and check-qml-aliases.py checked ONLY the files given as arguments, so the bare
     command below checked nothing and printed 0.** No arguments now = the whole repo.
     It skips multi-line JS template literals (embedded Python read as QML).
     It reads every statement on a line (`Row { x: 1; y: 2; x: 3 }`), and a declaration with a value
     (`property color accent: …`) counts as setting it: until 2026-11-10 it matched neither, so the
     redeclared-and-assigned case the API caution credits it with went through.
   - `python3 scripts/check-qml-readonly-anim.py` — a `Behavior on X` (or an
     `…Animation on X`) where X is `readonly` in the same object. An animation
     writes what it animates, so this is `Invalid property assignment: "X" is a
     read-only property` — a hard load failure that took down Bar via DockHost via
     DockIconStrip. Scoped per object: a parent's readonly X of the same name is
     a different property.
   - `python3 scripts/check-qml-fillheight.py <files…>` (it checks only the files it's
     given; no arguments = nothing checked, exit 0) — a layout nested in a
     `ColumnLayout` with no `Layout.fillHeight` stated. Qt defaults it to TRUE for
     layout children, which silently steals surplus vertical space. `check-all.sh`
     gates it against `scripts/fillheight-baseline.txt` (known, untriaged findings per
     file): a file that gains one fails. Triage one → lower its count.
   - `python3 scripts/check-qml-hotpaths.py` — an animation or fast Timer with nothing to
     stop it. Gated at zero.
   - `python3 scripts/check-qml-final.py` — a property declared with the name of one of
     Item's FINAL properties (`left`, `right`, `top`, `transform`, `layer`, `x`…, read
     from the installed qmltypes): `Cannot override FINAL property`, a hard load failure
     that cascades (PowerMenu's drain ring's `property real left` took out shell.qml,
     2026-10-03). Skips QtObject/Singleton/Timer/… scopes, where any name is legal.
     Also (`illegal-names`): an `id` that is a JavaScript global (`gc`, `print`, `escape`…) and
     `signal set(…)` / `signal get(…)`.
   - `python3 scripts/check-qml-palette.py` — a visual file reading `Colors.primary`
     (the shared palette) instead of `Colors.of(QsWindow.window).primary` (its screen's).
     It renders, in the wrong screen's colours, only while a workspace has its own
     wallpaper — so nothing else would ever notice.
   - `python3 scripts/check-qml-imports.py` — a file naming `QsWindow` without `import Quickshell`:
     `ReferenceError: QsWindow is not defined`, logged per binding while every colour it feeds is
     undefined. Not a load failure, so nothing else notices. Also: a `Scrollbar` must be a SIBLING of
     the Flickable it serves (it anchors to it) inside a plain `Item` — as a child of the Flickable it logs
     "Cannot anchor to an item that isn't a parent or sibling", and as a child of a layout "Detected
     anchors on an item that is managed by a layout", at every start. And `GridLayout` has `uniformCellWidths`/`uniformCellHeights`;
     only Row/ColumnLayout have `uniformCellSizes` (a hard load failure otherwise, invisible to every checker).
   - `python3 scripts/check-qml-singletons.py` — a singleton (`PowerSaver`, `Config`, `UiState`…, read from
     the qmldirs) used in a file that doesn't import its directory: `ReferenceError … is not defined` per
     binding, not a load failure, and invisible to the smoke test when the file is never built (a settings
     page hidden on this machine). Caught BatteryPage's `PowerSaver` on 2026-11-08.
   - `python3 scripts/check-qml-qmldir.py` — a new sibling file used by type name (`BarDockPopups {`) in a
     directory whose qmldir doesn't list it: `… is not a type`, and every file above it fails to exist —
     the whole shell, from Bar.qml. The parse sweep passes it. Caught on 2026-11-08.
   - `python3 scripts/check-glyphs.py` — a Nerd Font glyph that is neither mapped in
     `services/icons.js` nor present in the bundled `QuicktestGlyphs.otf`: it draws
     nothing, with no warning anywhere. Needs fontTools.
   - `python3 scripts/test-checkers.py` — the checkers themselves, each fed the mistake it exists to
     catch (a checker that stops matching still prints `name=0`). Add a case when a checker learns one.
   - `python3 scripts/check-config-persisted.py` — a `Config` property that isn't
     in `_persisted`. It works until the next shell reload and then quietly resets;
     see API caution. Run it whenever `Config.qml` gains a property. (Until 2026-09-26 it
     matched `property bool x` with ONE space only, so every column-aligned declaration
     went unchecked.)

2. **The syntax idiom.** `qmllint` is useless here. To check a file parses:
   ```
   sed -E 's/\?\.(\[|\()/\1/g; s/\?\./\./g' f.qml > /tmp/c.qml \
     && /usr/lib/qt6/bin/qmlformat /tmp/c.qml | wc -c
   ```
   `>0` bytes = parses. **Two expressions, and the order matters.** The old
   one-liner `sed 's/?\./\./g'` is correct for `x?.y` but WRONG for `x?.["k"]` and
   `x?.()` — it rewrites those into syntax errors. The bracket and call forms need
   `?.` DELETED (first expression); the ordinary case is replaced (second). It
   cost a false alarm on `services/Audio.qml` and
   `modules/overview/OverviewNowPlaying.qml`, the only two files using that form.
   A clean sweep is `find . -name '*.qml' -not -path './config/settings/*' -not -path './plugin/build/*'`
   over the above (what `scripts/check-all.sh` runs).

   **This is SYNTAX ONLY — weaker evidence than it feels.** A file that parses can
   still fail to load, hard, at runtime. All of these pass a clean sweep while the
   shell refuses to start:
   - a property redeclared *and* assigned (see API caution)
   - an unresolved type from a missing `import` / `qmldir` line
   - `Keys` attached to something that isn't an `Item`
   - `y`, `width`, or another property assigned twice

3. **The transient load.** Actually try to start it:
   ```
   timeout 12 quickshell -p ~/.config/quicktest/shell.qml >/tmp/qs.log 2>&1 &
   sleep 9
   grep -iE 'unavailable|cannot assign|set multiple|not a type|is not defined' /tmp/qs.log
   ```
   `Configuration Loaded` and no matches means it will start. This caught four
   hard failures in one session that the syntax sweep passed clean:
   `verticalItemAlignment` on a `Row`, `width` assigned twice, `y` assigned twice,
   an undeclared identifier.

4. **Open the overlay.** Nothing inside the overview exists until it's opened — a
   shell that loads clean can still be broken in every delegate it hasn't built.
   ```
   qs ipc -c ~/.config/quicktest call overview open
   sleep 5
   grep -cE 'TypeError|Binding loop|QTextCursor' /tmp/qs.log
   qs ipc -c ~/.config/quicktest call overview close
   ```
   A `TypeError` in a binding is not a load failure — the binding resolves to
   `undefined` and the surface renders blank — so grep for it deliberately.

Steps 3 and 4 as one command: `bash scripts/smoke.sh` (refuses while a shell is
running). It also opens every bar panel (`panel toggle`), the Clips gallery and every settings page over IPC and
scans the log, since all of them are only built when shown. `bash scripts/smoke-headless.sh` runs the same checks inside a sandbox
(temp HOME/XDG dirs, private session bus, no system bus, no Hyprland socket) under a
headless sway, so it is safe beside a live shell and is what CI's `smoke` job runs.
It has no Hyprland, so it proves "everything loads", nothing Hyprland-specific. The sandbox is
seeded so more gets built: two wallpapers (gallery tiles), three generated clips (the Clips gallery's tiles and day headings; needs ffmpeg), one pinned app and the dock's
Downloads/Trash tail (dock buttons), and a first-run `config.json` (the welcome flow). It renders
only with lavapipe (`vulkan-swrast`); without it the run says so ("the scene graph didn't start")
and checks the QML alone.

A stray instance from a manual run holds the notification server and port 47821.
`bind failed: Address already in use` means kill the leftover shell (and its
`spotify-bridge.py` child) before trusting anything else in the log.

**A green check means "no typos", not "it works". Say so when reporting it. A
reload by me is the actual test.**
