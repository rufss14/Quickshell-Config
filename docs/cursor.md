# Cursor

Moved from CLAUDE.md; the project rules there still apply.

## Cursor

`scripts/generate-cursor-theme` → `services/Cursor.qml` → `modules/settings/pages/
CursorPage.qml`, with the motion effects beside it: `services/cursoreffects.js` →
`services/CursorEffects.qml`. Tests: `python3 scripts/test-cursor-theme.py` (temp dirs
only; never passes `--apply`) and `bun scripts/test-cursoreffects.js` (pure). Saved looks
live in `presets/cursor.json`.

- **The compositor draws the cursor**, so "a cursor in the shell's colours" is a THEME
  regenerated when the palette moves. The shell passes `Colors.primary` as `--fill` and
  `Colors.base` as `--edge`; the script never parses a palette file, so it can't disagree
  about what "the accent" is, and the album scheme reaches it even in shell-only mode.
  Pillow (already a dependency) draws the shapes on a 32-unit grid and writes the
  XCursor container by hand — no librsvg, no xcursorgen.
- **One solid arrow, on purpose.** `default`, `pointer` and every hand name (`hand2`…)
  are the same file, so nothing changes shape over a link. A hand for hover and a
  hollow-at-rest arrow were both tried and rejected; don't reintroduce them.
- **Sixteen drawn shapes, sixty-odd names.** Arrow, text, grab, grabbing, wait, progress,
  crosshair, the four resize axes, four-way move, not-allowed, help, zoom in/out. Every
  other name is a symlink to one of them (`ALIASES`): the CSS names a compositor asks
  for (cursor-shape-v1) and the legacy X names a toolkit asks for, grouped as Adwaita
  groups them except `move`, which is the four-way arrow. This is what "it goes back to
  the default on window edges" was: resize and move weren't drawn, so Hyprland took them
  from Adwaita (`Inherits=`, still the net for anything missing). A new shape is one draw
  function, a `SHAPES` row and an `ALIASES` row; the test pins that no alias is claimed
  twice or shadows a drawn shape.
- **Fast on purpose — it runs on every palette change.** Each (shape, size, frame) is
  independent, so `build_all` fans them over a forked pool (fork, not spawn: no threads
  held, no re-import of Pillow), spinner frames are 8 not 12, supersampling drops with
  size, and a `.stamp` (the script's own hash + the two colours) skips the drawing when
  nothing changed — dragging the size slider or re-applying after a reload costs a
  symlink check. 1.9s → ~0.5s, and `Cursor.qml`'s debounce fell 600 → 150ms with it.
  `test-cursor-theme.py` pins that pooled output is byte-identical to serial.
- **Other apps read `XCURSOR_THEME` when THEY start** — Qt, GTK, Electron and XWayland
  clients each load their own cursor, and nothing told them which theme, so they showed
  the default. `scripts/shell-env.sh` and `hypr/env.lua` export it, but ONLY once the
  theme exists on disk: a name that points at nothing gives a client no cursor at all,
  which is worse than the default (the Lua is `pcall`'d for the same reason — a config
  error there would take the whole config down). Windows already open keep what they
  loaded; GTK apps follow live through gsettings (Hyprland writes the applied name there,
  which is why the two-name trick also recolours them). The live `~/.config/hypr` is an
  installed copy, so `hypr/env.lua`'s block has to be added there by hand.
- **Hyprland won't re-read a theme it thinks it already has.** Its XCursor loader
  remembers the last name, size and scale (`m_themeName`, `m_lastLoadSize`,
  `m_lastLoadScale` in `XCursorManager.hpp`), so `hyprctl setcursor quicktest 24` again,
  with the files rewritten underneath, changed nothing on screen. Regenerating was never
  the bug; showing it was. The theme is therefore reachable under TWO names — the
  directory and a `quicktest-b` symlink — and `Cursor._flip` alternates them on every
  apply. (Inferred from the header, not from Hyprland's source; the observed symptom was
  "files always fresh, pointer stale".) Quick check: Hyprland syncs the applied name into
  `gsettings get org.gnome.desktop.interface cursor-theme`, so it flips between the two.
- **A Hyprland reload undoes it.** `reload-theme.sh` → `wal-reload.sh` runs
  `hyprctl reload` right AFTER the service has applied the new cursor. So it applies
  again on `configreloaded` (`Hyprland.onRawEvent`, `event.name`), from the theme
  already on disk — no regeneration, no polling. `CursorEffects` does the same for the
  plugin, whose values a reload also resets.
- **Ask it, don't theorise:** `qs ipc -c ~/.config/quicktest call cursor status` and
  `… call cursoreffects status` (read-only) report enabled / applied / colours / busy /
  `lastError`, and both services `console.log` each run and `console.warn` each failure,
  because a run that fails with the settings page closed used to be invisible. If the
  target is missing, the singleton was never created — see Eager singleton references.
- **Inert while off** (`Config.cursorTheme` defaults false — enabling writes to
  `~/.local/share/icons` and replaces the user's cursor, which a published config must
  not do on first launch). Turning it off hands the cursor back with `--revert`, but
  only if THIS session applied it, so a reload on a machine that never used the feature
  can't reset someone's own cursor theme.
- **Presets** (`Config.cursorPresets`, same `{ name, config }` shape and built-in
  "Default" as the bar's) hold colour, custom colour, size, effect mode, sensitivity and
  shake — NOT the two master switches, so loading "Calm" never replaces your cursor or
  loads a plugin. The file is hand-editable, so `loadCursorPreset` validates every field
  against its range before assigning. Every `cursor*` key is in `_persisted`.
- **Motion effects are the hypr-dynamic-cursors plugin** — optional, third-party C++
  that hyprpm builds against the installed Hyprland. The namespace is `dynamic_cursors`
  (underscore) with `activation` keys, and its table doesn't exist until the plugin is
  loaded, hence `if hl.plugin.dynamic_cursors then … end`. Configuration goes in at
  RUNTIME with `hyprctl eval`, so no Hyprland config file is edited (the live
  `~/.config/hypr` is an installed copy and drifts); verify with
  `hyprctl getoption plugin:dynamic_cursors:mode`. The Lua is built by
  `cursoreffects.js` from a mode whitelist and clamped integers — `hyprctl eval` runs
  whatever it is given inside the compositor, and the values come from a hand-editable
  JSON file. A missing plugin or missing hyprpm DISABLES the controls with a reason
  (`CursorEffects.blocker()`); an installed-but-unloaded plugin gets one `hyprpm reload`
  per enable, not a loop. `hyprpm` is named in `install-dependencies.sh` as an opt-in and
  deliberately not installed: it compiles third-party code.
- **Limits worth knowing.** Clients that already loaded the theme (GTK, Qt, XWayland)
  keep the old colours until they next ask for a cursor. The plugin wants SVG hyprcursor
  themes for sharp shake-magnification; ours is bitmap up to 96px, so a large magnify
  looks soft. It forces software cursors on Nvidia.

