# System-integration gotchas

Moved from CLAUDE.md › API caution; the rules there still apply.

- On `Image`, `sourceSize` is applied to the whole file BEFORE `sourceClipRect`
  cuts it. Setting both scales the image down first and then takes a full-size
  rectangle out of the result — a two-pixel sliver, not a crop. With a clip in
  play, reset `sourceSize` to `Qt.size(0, 0)`. `PanelHeader.iconClip` is the one
  user, taking Wallpaper Engine's mark out of its logo.

- **`Process.stdinEnabled: true` is only the INITIAL value, and false closes stdin
  BEFORE the next start.** The idiom writes a secret in `onStarted` and then sets
  `stdinEnabled = false` so the child sees EOF; Quickshell then closes the write channel
  before starting that Process again (`process.cpp` startProcessIfReady). So every run
  after the first got an empty stdin unless the caller set `stdinEnabled = true` again
  before `running = true`. It bit Setup (the setup page's installs: `sudo -S` read EOF →
  "no password was provided"), Storage (its sudo jobs) and the since-removed OBS service (a second
  credential save sent nothing). Re-arm it next to every `running = true`, as Updates' fifoWriter,
  Clipboard and LyricsTranslate always did.
- **pam_faillock locks sudo after 3 failures in 15 min, for 10 min — and while locked,
  the RIGHT password fails too**, with nothing but "incorrect password attempt". One
  wrong password through `sudo -S` costs TWO strikes (it re-prompts and reads EOF off the
  one-line stdin). `services/SudoLock` reads the user's own tally (`faillock --user`, no
  root; `sudolock.js`, `bun scripts/test-sudolock.js`) so a password box can say "locked
  until 20:23" instead of "failed". Setup refuses to resend a password sudo just rejected
  (by hash) and sends nothing while locked. Updates and Storage don't use it yet.
- **`Quickshell.Io.Socket` logs EVERY error as a warning — a peer hang-up
  included.** A server that closes after each reply (Hyprland's request socket)
  costs one `PeerClosedError` warning per request, so a poll floods the log.
  Disconnect from your side as soon as the reply's last line is parsed. And after
  a failed CONNECT it keeps its dead QLocalSocket and ignores every later
  `connected = true`: build it from a `Component` and discard it on that error
  (`connected` still reads true inside `onError` for a peer close, false for a
  failed connect). Both measured; `services/Pointer.qml` does both.
- **Hyprland configs this repo ships are `.lua`, not hyprlang.** 0.56 ships a full
  Lua config manager and a Lua default at `/usr/share/hypr/hyprland.lua`; hyprlang
  is being retired. Selection is by FILE EXTENSION, not a flag — the log line is
  `[cfg] Config is lua, loading lua mgr`.
  - **File layout** (`hyprland.lua` require()s them in order): `autostart` (start
    hook), `env` (aliases + `hl.env`), `hardware` (monitors/input/devices/layout),
    `palette` (generated wal colours), `appearance` (shape/opacity/blur/shadow),
    `animation` (curves + timing), `binds`, `rules`.
  - **`blend.lua`** is the source of truth this shell and the hypr config SHARE:
    `rounding`, `border_size`, gaps, opacity, blur, and the window ease. hypr's
    `appearance.lua`/`animation.lua` `require` it; `config/Blend.qml` regex-parses
    it and feeds `Defaults`/`Tokens`/`Motion`. Editing a number there moves the
    window AND the matching shell surface. `scripts/hypr-config.py` writes geometry
    edits here (the Hyprland settings page's sliders); `lua5.4
    ~/.config/hypr/scripts/check-blend.lua` and `bun scripts/test-blend.js` guard it.
  - **`scripts/hypr-config.py`** parses `binds/blend/appearance/animation/hardware/env`
    into JSON with file+line spans; `services/HyprConfig.qml` watches those six.
    Rename a hypr file → update both.
  - The API reference is the LSP stub `/usr/share/hypr/stubs/hl.meta.lua`. Read it
    rather than guessing: `hl.config({ general = { gaps_in = 0 } })`,
    `hl.bind("SUPER + Q", hl.dsp.exit())`, `hl.env(k, v)`,
    `hl.on("hyprland.start", function() hl.exec_cmd("…") end)`.
  - There is a static validator: `Hyprland --verify-config -c f.lua` prints
    `config ok` and exits 0 without starting a compositor.
  - **This extends to `hyprctl dispatch`, and the legacy spelling silently does
    nothing.** `hyprctl dispatch focuswindow address:0x…` is a *Lua syntax error*
    here (`')' expected`); the dispatch is discarded and hyprctl still answers
    "ok" because "ok" only means it was queued. The Lua form works and reports
    honestly: `hyprctl dispatch 'hl.dsp.focus({ window = "address:0x…" })'` →
    `warning: hl.focus: window not found` for a bad address. This cost a whole
    debug cycle on the emoji picker. From QML use `Hypr.focusWindow()` /
    `Hyprland.dispatch()`; from a script, copy `scripts/discord-press.py`.
    A BARE word (`hyprctl dispatch exit`) parses but then fails at dispatch time
    with `hl.dispatch: expected a dispatcher` unless the word resolves to one, and
    the stub declares no global `exit`. Both logout buttons used that spelling;
    they now call `Hypr.exitSession()` (`hl.dsp.exit()`, which passes
    `--verify-config`), and `scripts/greet-run.sh` dispatches the same.
  - **Focusing a window WARPS THE CURSOR** (Hyprland's `cursor:no_warps` governs
    it, default warps). A shell surface that dispatches focus to hand control back
    teleports the pointer. Prefer waiting for focus to return on its own when a
    layer surface closes; only dispatch as a fallback if it demonstrably doesn't.
  - Keep `hl.exec_cmd` inside an `hl.on("hyprland.start", …)` callback, never at
    the top level — top-level Lua runs during `--verify-config` too, so a
    top-level exec launches the thing you were only trying to check.
  - `scripts/greet-preview.lua` is the worked example.
