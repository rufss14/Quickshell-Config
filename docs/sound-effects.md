# Sound effects

Moved from CLAUDE.md; the project rules there still apply.

## Sound effects

`scripts/gen-sfx.py` (synthesised WAVs into `$XDG_CACHE_HOME/quickshell-quicktest/sfx/`, stamped
by its own hash, no recordings so no licence) → `pw-play`, one detached process per cue (`Sfx._spawn`, `--latency=20ms`; probed with
`command -v`, a missing one disables the control with a reason). NOT QtMultimedia: a `SoundEffect`
per file stalled PipeWire when 17 were created at once (every reload froze) and, with Qt
Multimedia's `QAudioContext` thread alive, SEGFAULTED the shell when the headset was unplugged,
inside libpipewire (both measured 2026-10-06, sound effects off = neither) → `services/Sfx` (decisions in `services/sfx.js`, `bun scripts/test-sfx.js`,
`python3 scripts/test-gen-sfx.py`) → `modules/settings/pages/SoundEffectsPage` (Devices ›
Sound effects). `qs ipc -c ~/.config/quicktest call sfx status | test <cue>`.

- **Off by default** (`Config.sfxEnabled`, a published shell mustn't make noise on first start),
  with six groups under it (`sfx.js GROUPS`: panels, typing, switches, notify, alerts, capture), each its own
  switch (`sfxPanels`…) AND level (`sfxPanelsVolume`…). Nothing is generated or loaded until
  sound is on (or the page calls `Sfx.warm()` so its Play buttons work).
- **Loudness**: master and group levels are each SQUARED and multiply, under a 0.6 `CEILING`
  (`volumeFor`) — a linear slider spends its lower half on "quiet" and its top on "too loud".
- **The sounds are tuned by ear and by measurement** (the user's calls, 2026-10-03): keys are
  band-passed NOISE (an actuation tick, then a clack and a low thud), never ringing sines —
  the first version was one 227 Hz tone and read as "a bamboo stick"; `test-gen-sfx.py` pins
  that no single frequency holds the energy. Only the "tactile" keyboard is kept. The swoosh is
  a band-pass SWEEP, slow (~540 ms), low and softened (a low-pass after it), never a swept
  low-pass of white noise ("something dragging across the ground") and never above ~1 kHz
  ("too high pitched"). Audition by rendering candidates to a scratch dir and `pw-play
  --volume 0.3`; don't tune blind.
- **Panels are heard from `UiState`'s slots** (left/right/center/side, overview, launcher, power
  menu) by one `Connections` in `Sfx` — no per-panel code. A panel replacing another is ONE
  `open` (`sfx.js panelCue`). A cue has a minimum gap (`MIN_GAP`) so the launcher's two flags
  can't double-fire.
- **Typing has two scopes** (`Config.sfxTypingScope`, "shell" default | "all"):
  - **Shell**: `InputField` and `LauncherField` call `Sfx.typed(key, text, modifiers)` from
    `Keys.onPressed` without accepting. The lock screen's password field deliberately doesn't.
  - **Everywhere** (`services/SfxKeys`, `sfxkeys.js`, `bun scripts/test-sfxkeys.js`): Wayland
    shows the shell only its own keys, so a small Lua hook is put into Hyprland at RUNTIME
    (`hyprctl eval`, no config file edited; `input.keyboard.key`) that posts a CUSTOM EVENT per key
    with `hl.dsp.event(...)`, heard on the event socket the shell already reads (rawEvent name
    `custom`). No file, no spawn, no `io`. It sends ONE state letter + ONE class letter (key /
    space / enter / backspace) — **never the key**: the event socket is readable by every process
    the user runs. Non-typing keys (modifiers, arrows, F-keys, escape) are class "" and not sent.
    The hook exists only while `SfxKeys.wanted` (sfx + typing + scope "all" + not
    `Gamemode.silencesKeys` + not `Lock.locked`) and is removed otherwise; a Hyprland config reload
    drops runtime Lua, so it is re-installed on `configreloaded`. While it is live, the fields'
    own `typed()` calls stand down (they'd click twice). The Lua is pcall'd throughout: it runs in
    the compositor on the input path.
  - **Hyprland's key-event payload was MEASURED, not documented**: the stub doesn't say; on 0.56.2
    the callback gets THREE BARE NUMBERS (`shapes` = `number|number|number`) — most likely
    `IKeyboard::SKeyEvent`'s (timeMs, keycode, state 0/1), placed by magnitude in `numeric()` so the
    order needn't be right. When it can't place them (or a Hyprland sends a table or a name) the
    hook falls back to tables and names, and if state can't be read at all every event sounds
    — the press AND its release, "I hear it twice" (what the first build did). It reports the first
    `SHAPE_REPORTS` payloads' SHAPE — field names and types, state values, never key / keycode /
    text — to `qs ipc … call sfxkeys status` (`shapes`). MEASURED: three bare numbers (time, keycode, state), now handled by magnitude (`numeric()`); the shape report is bucketed. Read it, then tighten `classOf` /
    `stateOf` in `sfxkeys.js`; don't guess again. (`scripts/test-sfxkeys.js` runs the Lua under
    lua5.4 on a stub `hl` against every shape.)
  - **Game Mode** has `Config.gamemodeKeys` (default on, "Mute typing sounds" in the Gaming panel):
    `Gamemode.silencesKeys` removes the hook entirely, so a game's WASD rides nothing.
- **Switch and notification cues** (two groups, so each can go on its own): `Toggle` plays on/off from its own click; a NEW,
  non-transient toast (`Notifications.showPopup`, not a replacement of one already up) chimes.
- **Timer / alarm / capture cues are played by the service that knows**, not hooked from
  outside: `Timers` (`timer` when a countdown ends, `alarm` in `_fireAlarm`), `Screenshot.present`
  (`shutter`), `Clips._announce` (`clipsaved`) each call `Sfx.play`. Calling it doesn't start the
  caller; a `Connections` on Clips from Sfx would have created a dormant singleton. Those
  events also send a notification, so a cue that `announces` (alerts, capture) ducks the
  notification chime for `NOTIFY_HOLD_MS` rather than chiming twice.
- The settings page is the Appearance page's shape: a hero with a MIXER (one bar per group,
  as tall as the group is actually loud) and one card per group, all from ONE `groups` table
  naming the Config properties.
- Adding a cue = a row in `sfx.js CUES` + a sound in `gen-sfx.py` (the tests pin that every file
  name exists in both). The shell's own volume scales from the generator's per-sound levels.

