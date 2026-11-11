# Discord integration

Moved from CLAUDE.md; the project rules there still apply.

## Discord integration

`scripts/discord-rpc.py` (binary IPC framing + OAuth) → `services/Discord.qml` →
`modules/discord/DiscordCallBar.qml`, configured from
`modules/settings/pages/DiscordPage.qml`. Tests: `scripts/test-discord-rpc.py` is
fully mocked and safe; `scripts/test-discord-press.py` touches live Discord and
toggles real mute — ask first.

- Credentials are read/written ONLY through `scripts/discord-credentials.py`,
  never from QML. Quickshell can't create a file `0600`, and a secret in argv is
  visible in `ps` to every process — so it goes over stdin. `discord-rpc.json` is
  that `0600` file, in `$XDG_STATE_HOME/quicktest/secrets/` (outside the repo;
  `scripts/qspaths.py`, which also moves an old copy out of the repo dir). The client secret is write-only from QML's
  side: `Discord.hasSecret` is a boolean, and a save that omits `clientSecret`
  keeps the stored one.
- **No application needed (zero-setup sign-in).** The `rpc.*` scopes are whitelist-gated: only an
  application's owner (plus ≤50 testers) can grant them, so a client id shipped in this repo would
  be rejected for everyone else, and its client secret can't be published. With no
  `clientId`/`clientSecret` configured, `discord-rpc.py` therefore authenticates as **Discord's own
  StreamKit app** (`SHARED_CLIENT_ID`) and swaps the auth code at StreamKit's public proxy
  (`SHARED_TOKEN_URL`, JSON `{"code"}` → `{"access_token"}`, no secret on our side) — the route
  trigg/Discover uses. Requests only the plain `rpc` scope.
  - **Borrowed and undocumented.** Discord can change or close the proxy, and borrowing its
    identity is a terms-of-service grey area. An application of your own in `discord-rpc.json`
    always wins; `"sharedApp": false` (the Settings › Discord toggle) switches the fallback off, and
    only then does the helper report `no-credentials`.
  - **Unverified live as of 2026-10-07:** that mute/deafen, volumes, devices and per-user
    volume/mute/pan all work with only the `rpc` scope. Discover Overlay sends `SET_VOICE_SETTINGS`
    with it; nobody was seen using `SET_USER_VOICE_SETTINGS`. `scripts/test-discord-shared.py` is
    mocked and covers only which identity wins and the exchange's shape.
  - No refresh token comes back, so a week-old token means one new consent dialog. The token cache
    is stamped with its `client_id` so switching between the shared and your own app never replays
    one app's token to the other.
- Discord's RPC has **no command for screen share or camera**. Those work by
  focusing Discord and injecting its keybind, quarantined in
  `scripts/discord-press.py`. Everything else on the panel is real RPC.
- `wtype` against an XWayland client exits 0 and delivers nothing. XWayland needs
  `xdotool` (XTEST); native Wayland needs `wtype`. The choice comes from
  `Hypr.windows[].xwayland` — never assume.

### Call log and the scoreboard (2026-11-08)

`services/calllog.js` (pure, `bun scripts/test-calllog.js`) → `services/CallLog.qml` (eager in shell.qml, `Config.callLog`,
default ON — the user chose "keep until I forget") → the **Board** tab of `modules/panels/VoicePanel` (`voice/VoiceBoardView`),
and a "Call log" card on Settings › Discord (toggle, count, Forget everyone behind an ArmLatch).

- **Counts** everyone in your current channel who isn't you and isn't a bot (`Discord.users`, from the helper's VOICE_STATE_*
  events — no helper change). Time together is credited every 30 s and whenever the set of people changes (a speaking flicker
  changes `Discord.users` but not the ids, and is ignored); a span over two ticks is clipped like Screen time's. Each arrival is
  one more call together. A call that ends is saved at once, else once a minute.
- **No friends list.** Discord's RPC doesn't expose one (only the channel), so the board ranks everyone who shared a call —
  the user accepted that over a "mark as friend" star. The eye on a row HIDES a person (still recorded, so they don't come
  back); with the hidden shown a row can be restored or deleted for good (two taps). Forget everyone is in Settings.
- **Kept** in `statePath("call-log.json")`: `{ version, people: { id: { name, avatar, seconds, calls, last, hidden } } }` — names
  and numbers only: no channel or server name, no time of any call. Until forgotten (the user's choice). Not a secret file
  (not in `secrets/`), but personal: don't commit it, it lives under XDG_STATE_HOME outside the repo.
- **Validated at the door** (`calllog.js`): an id must be 5–25 digits; a display name is whatever a stranger typed, so control
  and bidi characters are stripped and it's cut at 64 and only ever drawn as plain text; an avatar is kept only if it's
  `https://cdn.discordapp.com/…`. A hand-edited file goes through the same `clean` (2000 people at most, the biggest kept).
- **Unverified live:** nothing here has seen a real call. The helper's `isSelf`/`bot` flags and `avatar` URL are what the
  People tab already relies on. `qs ipc -c ~/.config/quicktest call calllog status` answers with counts only.

### Rich presence (two separate cards, two separate daemons)

Both follow `claude-presence.py`'s design exactly — a `setsid`-detached daemon the
shell reload can't touch, a state FILE watched by QML, an options FILE polled by the
daemon, coalesced 5s-rate-limited `SET_ACTIVITY`, SIGTERM-unwinds-to-clear. Each needs
its own Discord *application* because the card's bold first line is the application's
name, so each is its own connection and its own helper.

- **Claude Code** — `scripts/claude-presence.py` → `services/ClaudePresence.qml` →
  the "Claude Code presence" card in `DiscordPage.qml`. `presenceClientId` in
  discord-rpc.json, an app you register.
- **Counter-Strike 2** — `scripts/cs2-presence.py` → `services/Cs2Presence.qml` →
  the "Counter-Strike 2 presence" card. Tests: `python3 scripts/test-cs2-presence.py`,
  fully mocked. It exists because **Discord's detectables database has no Linux
  executable for CS2** (`games-v1.json` lists only `win64/cs2.exe`), so native-Linux
  CS2 shows as the bare word "cs2" with no art and CS2 ships no presence of its own.
  - **No app to register.** The daemon handshakes as Valve's own registered
    "Counter-Strike 2" application (`1158877933042143272`, the `DEFAULT_CLIENT_ID`),
    which was measured to work without owning it — the RPC handshake accepts any valid
    id and `SET_ACTIVITY` needs no OAuth. `cs2PresenceClientId` in discord-rpc.json
    overrides it for someone who wants their own art.
  - **Match data is Game State Integration**, not RPC. `scripts/install-cs2-gsi.sh`
    writes `gamestate_integration_quickshell.cfg` into CS2's `csgo/cfg/` and records
    the port + auth token in `cs2-gsi.json` (gitignored, 0600) so the daemon and the
    game agree. GSI is official, read-only and VAC-safe. CS2 reads the .cfg only at
    launch — a fresh install needs a game restart, which the script and the card both
    say.
  - The daemon runs a stdlib `http.server` on a **daemon thread** (127.0.0.1:3000 by
    default) because the main loop is a selectors loop; a self-pipe byte wakes it.
    "CS2 quit" is a 30s feed-silence timeout, not a process check.
  - `player` in the feed follows your spectator target once you're dead, so
    `player.match_stats` is only yours while `player.steamid == provider.steamid` —
    `normalise()` drops it otherwise and the Runner carries the last real K/D forward.


## The Quicktest theme (Vencord / Vesktop)

`vencord/quicktest.theme.css` → copied by `scripts/theme-setup.sh discord` (Settings → Setup) into every
Vencord-family client's `themes/` and enabled there; `scripts/themes/discord/quicktest-theme.py` rewrites
its palette block on every colour change (`apps-lib.sh`, same staged-then-renamed publish as before).
Tests: `python3 scripts/test-discord-theme.py` (palette script + the file's own rules; `--hashes` lists the
hashed Discord classes it depends on), and `bash scripts/test-theme-setup.sh` for the install path.

It replaces Midnight, which Setup used to download and recolour with `pywal-midnight.py`. Setup now un-enables
Midnight and leaves its file alone; a client that has only Midnight is still recoloured (`discord_themes`),
and `pywal-midnight.py` stays until the user says to remove it.

- **Same translation as the shell.** The Tokens block (radii, spacing, curves, shadow dp) and the role
  mixes (`surface`, `container`, `high`, the state ladder) are copied from `Tokens.qml` / `PaletteRoles.qml`
  (they were first copied from the Spotify theme QuickSpice, which the shell no longer ships: QuickZiro replaced it).
  Copies of ~60 lines; if the shell's change, change this.
- **It follows Settings → Type & Shape (2026-10-24).** `services/DiscordTheme.qml` reads the RESOLVED
  `Tokens`/`Motion` values (spacing, the five radii — so roundness, square corners and the "Rounder" ladder
  are already applied — the text/numerals faces after the installed-font check, the six durations, the card
  and popup shadows; `Config.shadowScale` 0 = none) and hands them, as JSON on argv, to
  `scripts/themes/discord/apply-shape.sh`, which finds every client's `quicktest.theme.css` and calls
  `quicktest-theme.py --shape`. Same shape as `Cursor.qml`: the shell passes values, the script never
  re-derives them. They land in a second generated block (`qs-shape:begin/end`) that the CSS reads through
  `--qs-sp-*`, `--qs-r-*`, `--qs-font*`, `--qs-t-*`, `--qs-shadow-*`; the committed block is the defaults
  (a test checks it), so an untouched install's launch-time push writes nothing. 400ms debounce, `nice 10`.
  One lock covers both blocks, because the wave's recolour and a shape push both rewrite the whole file.
  Validated at the argv boundary (a font name is refused if it could end a CSS string; numbers are ranged).
  Setup's "current" check ignores both blocks, and a Setup re-copy resets shape to the defaults until the shell
  next starts (it pushes at launch). **Not reaching Discord:** Opacity (Discord's cards sit on a solid frame, so
  it would only dull them) and Text scale (measured over CDP, 2026-10-24: Discord's text is a mix of fixed px
  and rem that does not follow `<html>`'s font size — setting it to 118% changed nothing on screen — so only its
  own Appearance → Chat Font Scaling can move it). Icon shape reaches the sidebar entries' holders and the
  single icon buttons, not the guild icons (below).
- **Embraced from the shell, checked against screenshots of the live page over CDP** (inject the CSS as a
  `<style>`, `Page.captureScreenshot`, look; it is the only way these were verified): the sidebar entries'
  icons (Friends, Nitro Home, Shop, Quests) sit in a ShapeBox holder — a tinted cookie by default, whatever
  Icon shape says otherwise, deepening on hover (`--qs-clip-holder`); the user panel's single icon buttons and the
  Spotify plugin's transport buttons take the shape on hover (`--qs-clip-button`; mute/deafen are split pairs with
  a chevron and keep theirs; scoped narrowly because a cookie over a wide button stretches into an oval);
  every Discord slider is WaveSlider's sine up to a thin playhead and a flat rail after it — it travels only
  while the Spotify plugin's pause icon is showing (`#vc-spotify-player:has(.vc-spotify-pause)`, plugin classes,
  stable) and is a flat line when paused; and the title bar's two clusters are capsule trays like the bar's. The cookie
  and clover outlines are generated (`scallop_polygon`, the shell's Scallop outline).
- **Five inputs, one block.** `--qs-base/text/primary/focus/on-primary` sit between `qs-palette:begin/end`
  markers; the script imports `pwspice.py` for `_mix`/`_legible`, so primary and focus are the colours the bar
  wears (floored at 4.5:1). It writes nothing when the block is unchanged — Vencord re-parses the theme on
  any write. Light palettes (base luminance ≥ 0.5) get the shell's light-mode alphas; the shell reads
  `Config.themeMode` for that, a theme has no config, so luminance stands in.
- **Discord's own tokens are the mechanism.** The `--background-*`, `--text-*`, `--control-*` … remap recolours
  everything the file never mentions. Presence dots, the red mute/deafen/delete buttons and the notification
  badge are deliberately NOT remapped (a wallpaper palette can land on green for "do not disturb").
- **Selectors.** ARIA / `data-list-item-id` / the name half of a class where it is distinctive; a hashed class
  only where the name is generic. All 75 hashed classes were checked (2026-10-24) against the stylesheets
  Discord had fetched that day (Midnight, HSL, SettingsModal) — they are those authors' selectors, not
  independently measured. A panel that stops being a card after a Discord update is one of them.
- **The rail is built in.** `--qs-rail: top` (default) is HorizontalServerList's geometry copied rule for rule
  (the first port "adapted" it with the card gap, dropped its `.base .content` ×2 offset and broke the server
  list's clicks; 2026-10-24) — change those numbers only with a screenshot; `side` is Discord's column; override with `:root { --qs-rail: side; }` in Vencord's QuickCSS. Settings-as-a-modal is
  SettingsModal's technique. **Both must be disabled in Vencord while Quicktest is on** — HSL's rotation on top
  of this file's is a double turn.
- **BetterFolders' sidebar breaks the top rail** (measured over CDP on 2026-10-24). With the plugin's default
  `sidebar: true`, opening a folder adds a SECOND server list as its own grid item (`grid-area:
  betterFoldersSidebar`) — a clone of the whole nav, so the rail's rotate and `100vw` rules hit it too, its grid
  column grows to the window's width, and the channel list, chat and user-panel buttons are pushed off-screen
  (it looked like "the page scrolls", but nothing scrolled: an `overflow: clip` on the page changed nothing and was removed).
  Turn BetterFolders → "Display servers from folder on a sidebar" OFF and a folder expands inside the one
  rail. The theme does not try to handle the clone: it is a plugin's DOM, and hiding it would hide the folder.
- **Not done, on purpose.** Cookie-clipped server icons (as QuickSpice did, with a `clip-path`): Discord masks guild icons
  with an SVG `foreignObject` that animates its own squircle, so a `clip-path` would fight it. List-item
  stagger and message fade-in: both replay on every virtualised mount, which reads as flicker while scrolling.
- **Unverified (nothing here has rendered in Discord):** the geometry of the top rail and the Settings modal
  (both ports of other authors' CSS adapted to this file's gap), every panel actually becoming a card, the
  `qs-pop` menu entrance, and light palettes (Discord's own icon assets follow `.theme-dark`, not the palette).

### M3 Expressive pass (2026-11-01) — never rendered

Three additions, in the shell's own M3E vocabulary (`docs/standards.md`'s spring/state-layer section), all
either new CSS custom properties or a remap of a Discord variable the file already owned — no new selector,
so none of it touches the fragile top-rail/BetterFolders geometry above.

- **Baked springs.** `--qs-spring-fast` / `--qs-spring` are `linear()` easings sampling the exact closed-form
  step response of `Motion.springSpatialFast` (800/0.6) and `Motion.springSpatial` (380/0.8) —
  `components/spring.js`'s math, not a cubic-bezier approximation, so they genuinely overshoot and settle back
  the way the shell's own hover/press springs do. Same category as `--qs-travel` (a curve shape transcribed
  once, not re-derived every push); their paired durations, `--qs-t-spring-fast` (322ms) / `--qs-t-spring`
  (371ms), are new keys in the Type & Shape JSON (`Motion.springSettleFast`/`springSettle`, added for exactly
  this consumer — nothing in QML needed a spring's "duration" before), so they honour `Config.motionEnabled`/
  `motionScale` like every other timing here. Applied to: the guild-icon hover grow, the title-bar window-dot
  hover grow, the sidebar icon-holder/button clip-path hover morph, and (new) every button's press-release —
  pressing is still the instant `respond` snap, but releasing springs back out with a hair of overshoot instead
  of easing back symmetrically. Needs Chromium 113+ for `linear()`; older ones silently lose that one
  transition's easing (not a crash — the declaration is just invalid) and keep the previous behaviour.
- **The ripple decay.** `Motion.ripple` (500ms) is now threaded through the same JSON as `--qs-t-ripple`. A
  menu row (`[role="menuitem"]`) and a reaction pill (`[class*="reaction_"]`) each get an asymmetric
  transition: entering hover/focus answers in `--qs-t-respond` (the more specific `:hover`/`:focus-visible`
  rule), leaving decays over `--qs-t-ripple` on `--qs-decel` (the LESS specific rest rule, which is what CSS
  takes a transition's timing from) — fast snap-in, slow wave-like fade-out, exactly Motion.qml's own comment
  on why `ripple` is deliberately much longer than `standard`. Channel/member/DM rows were deliberately left
  alone: modern Discord may paint their hover via a floating highlight element rather than the row's own
  background, and that can't be told apart from reading the CSS alone — ask for the CDP session before
  touching those.
- **Tonal containers.** New `--qs-primary-container` / `--qs-fg-on-primary-container` (`PaletteRoles.
  primaryContainer`/`fgOnPrimaryContainer`, approximated — `color-mix()` can't run `legible()`, so these are
  good for a chip's fill, not for anything that must clear 4.5:1 on its own). Replaces the flat `--qs-active`
  wash on: `--mention-background`/`-foreground`, `--message-reacted-background/-text-default`,
  `--reaction-background/-text-reacted-default`, and `--interactive-background-selected` (a selected channel/
  member/menu row). All five are Discord variables this file already owned; nothing new to guess at.

Settings modal: gained the same `qs-pop` entrance (`--qs-t-emphasized`/`--qs-decel`) the context menu already
used — reusing a verified keyframe on an already-verified selector, so the only new risk is whether the modal
even runs its `animation` while `#app-mount .baseLayer__960e4` is being forced visible (untested).

Tests: `scripts/test-discord-theme.py` passes (the "committed shape block IS the defaults" check covers the
three new motion keys). `DEFAULT_MOTION` in the test file grew the same three keys.

### Cookie shape on the composer toolbar (2026-11-01) — CDP-verified

User asked for more of the shell's cookie shapes and pill hover motion. Checked live over CDP (DOM +
CSS domains, `CSS.createStyleSheet`/`setStyleSheetText` — NOT a page `<style>` tag, which Discord's CSP
silently no-ops; `CSS.forcePseudoState` to see `:hover` without moving a real cursor; every screenshot
`clip`-cropped to a single UI element so no message text ever entered a capture) on a real server channel:

- **Avatars are off-limits everywhere, not just guild icons** — confirmed: the user's own panel avatar and
  every friend-list row use the identical `svg.mask__xxxxx` + `<foreignObject mask="url(#svg-mask-avatar-
  status-round-32)">` technique already documented for guild icons. Still correctly left alone.
- **The composer's icon row IS safe and now wired**: `.attachButton__74017` (the +/attach button) and
  `.buttons__74017 [role="button"]` (timestamp, gift, GIF, sticker, emoji, and whatever a client plugin adds
  beside them) are `<div role="button">`, confirmed square (32px) over CDP, added to the same selector group
  as the user-panel's single buttons and `.vc-spotify-button` — same `--qs-clip-button`/`-hot` + spring-fast
  hover transition, so cookie or clover (Settings → Type & Shape → Icon shape) now reaches this row too.
- **Reaction pills confirmed non-square** (52×30) — correctly NOT given the clip (would stretch into an
  oval), stay a plain rounded pill. No change.
- **A false alarm, corrected**: forcing `:hover` on these and reading `clip-path` back first showed
  `inset(0px round 10px)`, which looked like Discord overriding the rule and needing `!important`. It
  wasn't — that IS `--qs-clip-rounded` (the shape `icon: "default"` maps a BUTTON to; only HOLDERS get the
  cookie by default). Re-tested with the shape JSON's `icon` explicitly `"cookie"`: the scalloped polygon
  landed cleanly on both the emoji and attach buttons, no `!important` needed, confirmed by cropped
  screenshots of the rendered (not just computed) style. Don't add `!important` here — it isn't needed and
  would mask the next real regression.
- **To see it**: Settings → Type & Shape → Icon shape → Cookie (or Clover). Already wired end to end
  (`DiscordTheme.qml` → `apply-shape.sh` → `quicktest-theme.py --shape`); no code change needed to turn it
  on, this round only widened which Discord elements the existing toggle reaches.

### Mica rewrite (2026-11-01)

User asked to base the theme's LOOK on a third-party "Discord Mica" theme
(github.com/PL7963/Discord-Mica) while keeping only four things from Quicktest: colours, hover
animations, the settings-modal fix, and the progress-bar wave. Fetched Mica's actual CSS first
(web-fetch agent, not the live `@import` in their installed file — that file does
`@import url("https://discord-mica.pages.dev/...")`, which this project's own test explicitly
forbids: "no @import and no remote url(): nothing third-party is fetched at runtime"). Mica's CSS
turned out to be ~280 lines, no license header, and genuinely nothing to port literally: no
sliders, no animations, no settings-modal technique — just a long list of panels set to
`background: transparent !important`, relying on the OS compositor (Windows' Mica / DWM) to blur
behind the now-transparent window. Ported the CONCEPT, wrote fresh CSS: nothing of theirs is in
this file.

**Why it actually works here**: confirmed `~/.config/hypr/appearance.lua` has `decoration.blur` on
shell-wide (blend.lua-driven, shared with Quickshell) with no `no_blur` rule for Discord — so a
transparent Discord panel genuinely shows Hyprland's own blur, not a blank hole.

**What changed**: new `--qs-mica-base/-panel/-popup` fills (translucent versions of the existing
surface/container/high roles, not palette-generated — plain `color-mix()` same as everything else
in the Tokens section) replace the old opaque "Cards" treatment; new `--qs-outline-bar` (85% —
PaletteRoles' own `outlineBar` number) because a translucent surface needs its border to do more
work, the fill alone no longer defines the shape. Shadows dropped from panels (nothing solid for a
shadow to read as lifted off); kept on popups/the settings modal, which stay denser
(`--qs-mica-popup`, 55%) since they float over arbitrary content and need to stay legible. Trays
(title-bar clusters, the server rail's border) stay at the old opaque `--qs-container` — too small
for translucency to read as anything but muddy.

**Rail: side only now.** The top-rail -90° rotation hack caused every layout bug traced this
session (the third-party "Read All" button's sideways text, the guild home icon rendering at
0×0, cramped/overlapping icons at some window widths) — user's call to drop it rather than keep
chasing the same class of bug. `--qs-rail`, the `@container qs` switching, and the whole rotation
block are gone; `scripts/test-discord-theme.py` now asserts they DON'T exist (guards against
reintroducing it) instead of asserting both modes are styled.

**Still open, not this round:**
- Settings modal selectors (`.layer__960e4`, `.standardSidebarView__23e6b`, etc.) are CONFIRMED
  STALE — checked live over CDP, none matched. Settings currently renders unthemed, at whatever
  position Discord's own layer system gives it; this is very likely the real "box covering my
  DMs" the user kept reporting (a devtools-overlay screenshot earlier in the session turned out to
  be a red herring for a *different* instance of the same underlying complaint). Left the old
  selectors in (inert, not harmful) rather than delete them. Needs a fresh CDP pass: open Settings,
  find the current class names, rewrite the whole block.
- Home/Discord-logo icon on the guild rail still paints blank sometimes, despite every computed
  style checking out (white fill, opacity 1, the mask's blob path resolving to real geometry).
  Update, 2026-11-01: forcing the wrapping `foreignObject`'s `mask` off via a stylesheet rule
  (present from first paint, not a live DOM poke — a poke on the already-rendered element proved
  nothing either way, since Chromium silently failed to repaint it) fixed the glyph once on
  reload, then did NOT reproduce on a second, otherwise-identical reload with the same rule in
  place and matching per `getComputedStyle` — so that "fix" was a one-off repaint coincidence, not
  the actual cause. Reverted (not shipped). Whatever's wrong, it's intermittent and isn't
  something `mask` alone controls — likely a genuine Chromium compositor quirk around a nested
  `<svg>` glyph inside an HTML `foreignObject` under an animated SVG `mask`, outside anything this
  theme's CSS can reliably fix. Next step, if picked up again: watch it across several reloads to
  see whether it correlates with anything observable (cold load vs warm, window focus state,
  timing relative to the guild list's own mount) rather than assuming the first CSS lever that
  moves it once is the fix.
- Spotify-triggered "section grows a lot": user confirmed via their own A/B (theme disabled = it
  stops) that it IS theme-related, but 4 seconds of sampling `panels__5e434`'s height during steady
  playback showed zero change — not continuous growth. Likely tied to a specific moment (track
  change, widget first appearing) not yet isolated. Also unanswered when this rewrite landed.

### Font fix, wave restart, hover-track stacking (2026-11-01)

- **The font remap was a no-op.** `--font-primary`/`-display`/`-headline`/`-code` (the type block)
  are not real Discord custom properties — grepped the actual installed `_app.asar` (1.0.168): the
  only one Discord reads is `--font-family` (consumed as `var(--font-family)`, default `system-ui,
  'Helvetica Neue', Arial, sans-serif`). Fixed to set `--font-family: var(--qs-font);` directly.
  There is no `--font-code`/mono equivalent in this build, so code blocks stay on Discord's own
  default — same "not reaching Discord" bucket as text scale, above.
- **The wave restarted every second, twice tried.** First fix: `animation: qs-wave …` was only
  added by `#vc-spotify-player:has(.vc-spotify-pause) …`; Vencord's unmemoized 1s re-render (the
  same one that jumps `width`, measured above) remounts the pause/play icon on each tick, so the
  `:has()` match drops and re-matches, restarting the keyframe from frame 0. Scoping the animation
  to always run on `#vc-spotify-player`'s own bar and only toggling `animation-play-state` for
  paused vs playing (so it's never restarted, only paused in place) did NOT fix it — user confirmed
  still laggy, so the bar itself, not just the icon, is plausibly what's being remounted. Replaced
  the CSS `@keyframes` entirely: `quicktestMotion`'s new `wave.ts` writes a `--qs-wave-x` custom
  property from the wall clock (`Date.now() % 2513`), the same way `components/WaveSlider.qml`
  phases its own wave (`Date.now() / 400`, not an animation's own elapsed-since-start clock) — a
  remount can't desync a wall-clock phase, there's no "frame 0" to snap back to. `mask-position-x:
  var(--qs-wave-x, 0px)` reads it; CSS has no `animation` left for this at all. Still unverified
  live (no CDP session this round) — tell me if it's still off.
- **qs-hover-track-plate removed outright** (user's call, didn't like it) — `hoverTrack.ts`,
  `spring.ts` and the plugin's `style.css` are deleted, `index.tsx` now only wires up the wave.
  While it existed, it had a real stacking bug worth recording in case this kind of plate comes
  back: it was `position: fixed`, appended as a plain sibling of Discord's whole app root, and a
  positioned sibling paints above a non-positioned one regardless of z-index — so it rendered over
  the settings modal, context menus, popouts, no matter how that layer's own z-index was set
  *inside* the app root. The real fix would need knowing the app root's own `position`, which
  wasn't findable by grepping the bundle (it's a thin loader `_app.asar`; the real renderer code
  streams in at runtime) or checked live over CDP. The workaround tried (hide the plate whenever
  `[role="dialog"]`/`[role="alertdialog"]`/`[role="menu"]` is open, ARIA over a hashed class, same
  rule this file already follows) is moot now — gone with the file.
- `quicktestMotion` is NOT synced automatically: its canonical copy is
  `vencord/userplugins/quicktestMotion/` in this repo, but what Vencord actually builds is
  `~/.local/share/vencord-src/src/userplugins/quicktestMotion/`, a separate checkout with no sync
  script between them (checked this round — there isn't one). Both copies were hand-edited to
  match this round; `quicktest.theme.css` doesn't have this problem (Vencord re-parses it on every
  write, so the live `~/.config/Vencord/themes/quicktest.theme.css` was patched directly) but the
  plugin's `.ts` needs a Vencord rebuild (`cd ~/.local/share/vencord-src && pnpm build`) and a
  Discord restart to actually take effect — the wave fix doesn't do anything in Discord until then.
