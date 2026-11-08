# Contributing to Quicktest

The rules the code holds itself to are in the README's
[Architecture notes](README.md#architecture-notes-for-contributors). This file is the
practical half: how to work on it, and how to make the changes people make most.

## Before you start

- **Arch + Hyprland 0.56 (Lua config) + Quickshell 0.3.** The shell is the repo: it runs
  from `~/.config/quicktest`, and saving a file hot-reloads a running shell. Keep a second
  checkout if you don't want every save to land on your desktop.
- **Your preferences are not in the repo.** They live in
  `$XDG_STATE_HOME/quickshell/…/config.json` (`Quickshell.statePath`). Secret files live in
  `$XDG_STATE_HOME/quicktest/secrets/`. Neither is ever committed.
- **Dev tools:** `./scripts/install-dependencies.sh --dev-install` (nodejs for the `.js`
  tests, fonttools for the glyph check). `sway` if you want the headless smoke test.

## Checking a change

In order; each catches what the previous one can't.

| Command | What a pass means |
|---|---|
| `bash scripts/check-all.sh` | No broken aliases, duplicate properties, read-only animations, FINAL overrides, wrong-screen palette reads; every QML file parses; every `scripts/test-*` passes. |
| `bash scripts/smoke-headless.sh` | The shell starts in a sealed sandbox (headless sway, temp HOME, private bus), the eager services exist, the overview and every settings page build without a load error or TypeError. Safe beside your running shell. CI runs it. |
| Reload your own shell (ALT+Q) | It works. Nothing above looks at pixels or talks to Hyprland. |

A green check means "no typos". Say which of the three you ran when you open a PR.

`docs/qml-api-caution.md` lists load failures **none of the checkers catch** — read it once.
The ones that bite first:

- Every new `.qml` needs a line in its directory's `qmldir`, or it's "not a type".
- Never redeclare a property the base type already has (`accent` on an `IconButton`).
- `PanelButton` has `activated()`, not `clicked()` — `onClicked:` blanks the whole page.
- A Loader's `implicitWidth/Height` are read-only.
- A new inline `component` needs a full restart, not a hot reload.

## Recipes

### A new setting

1. Add `property <type> name: <default>` to the `config/Config*.qml` file for its area, near its
   neighbours. `Config` is one singleton split by area into an inheritance chain — `ConfigShell`
   (bar look, appearance) ← `ConfigEdges` (dock, sidebar) ← `ConfigBarLayout` (bar layout, presets,
   module settings) ← `ConfigSystem` (motion, sound, game mode, lock, Wallpaper Engine…) ←
   `ConfigDesktop` (theme, updates, cursor, settings, widgets) ← `Config.qml` (version,
   persistence) — so `Config.name` works wherever it's declared. A file can't statically see a
   name declared further down the chain: reach it as `root.name`.
   A path's default is `""`, resolved by the service — never a literal `$HOME` path
   (it would be persisted into everyone's config).
2. Add `"name"` to `_persisted` (in `config/Config.qml`). Forget it and the setting resets on the
   next reload. `python3 scripts/check-config-persisted.py` catches this.
3. Use it in a settings page (`SettingRow`, `Toggle`, `SliderRow`, `ChipRow` — see
   `docs/settings-style.md`), then `python3 scripts/build-settings-index.py` so search finds it.

### A new service

- `services/Name.qml`, `pragma Singleton`, registered in `services/qmldir`.
- Subprocesses, sockets, D-Bus and polling live here, never in a widget. Real logic goes in
  `services/name.js` (`.pragma library`) with a `scripts/test-name.js` beside it — copy the
  `new Function(src + "return {…}")` loader from any existing test.
- A long-lived child process: start it with `setpriv --pdeathsig TERM` so it dies with the
  shell (a SIGTERM'd Quickshell runs no cleanup). Writing to a process's stdin: read
  `docs/gotchas-system.md` first (`stdinEnabled` must be re-armed before every start).
- If it has an `IpcHandler` and must run at startup, reference it from `shell.qml` with a
  `Connections { target: Name }`; a plain property reference doesn't build it.

### A new settings page

1. `modules/settings/pages/NamePage.qml`, built from `SettingsPage` + `Section`s — copy a
   small page such as `NightLightPage.qml`.
2. Register it in `services/SettingsIndex.qml` (`_catalogue`: file, label, icon, keywords).
   No page carries more than six views.
3. `build-settings-index.py`, then the smoke test opens it for you.

### A new dependency

- Needed by everything → `OFFICIAL_PKGS` in `scripts/install-dependencies.sh`, with a
  comment when the reason isn't obvious from the name.
- Needed by one feature → `PACK_PKGS` (a Setup step), and the feature must **disable itself
  with a reason** when it's missing (`Discord.pressBlocker()` is the pattern). Never a
  control that fails on click.

### Anything that holds a secret

- The file path comes from `scripts/qspaths.py` `secret_file(name)` (0600, outside the repo).
- Secrets travel over stdin, never argv — `ps` shows every process's arguments to every user.
  `scripts/wifi-hidden.py` and the `*-credentials.py` scripts are the pattern.
- Tests that touch such a script point **both** `XDG_CONFIG_HOME` and `XDG_STATE_HOME` at a
  temp dir before importing it.

### Hyprland config

The shipped config is Lua (`hypr/*.lua`); `hyprctl dispatch` takes Lua too
(`hl.dsp.focus({…})`). `Hyprland --verify-config -c hypr/hyprland.lua` checks it without
starting a compositor. Never install a bind or monitor at runtime through `hyprctl eval`
(it has segfaulted the compositor); write the file and `hyprctl reload`.

## Look and feel

Colours from `Colors.of(QsWindow.window)`, sizes from `Tokens`, timing from `Motion` — no
literals. `docs/standards.md` has the palette roles, the panel recipe and the shared widgets
to reuse before writing your own.

## About `docs/`

The files there are the project's working notes: measured gotchas, design decisions and
their reasons, written while building each area (much of it with an AI assistant, which is
why some read like a lab notebook). They are the best record of *why* something is the way
it is — read the one for the area you're touching — but they are not a user manual.

## Commits and PRs

One change per commit, a subject that says what changed, a body that says why and what was
verified. Don't commit `config.json`, secret files, `plugin/build/` or a rebuilt icon font
unless that's the change.
