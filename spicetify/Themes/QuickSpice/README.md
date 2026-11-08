# QuickSpice

A [Spicetify](https://spicetify.app) theme that draws Spotify in the Quicktest shell's own
language, so an open player reads as one more panel of the desktop it sits on. It replaces the
Ziro-based theme earlier versions of the shell installed.

It is written from the shell's design tokens, not borrowed from another theme:

| Shell                                   | Spotify                                              |
| --------------------------------------- | ---------------------------------------------------- |
| `Surface` (outlined card, radius 16)    | library, page, side panel and player are four cards  |
| `ActionGroup` (tray of ghost buttons)   | history arrows, the player's right-hand controls     |
| `SegmentSwitch` (pill, filled indicator)| filter chips, tabs                                   |
| `CookieButton` (9-petal scallop, winds) | play / pause, prev / next, shuffle / repeat          |
| `WaveSlider` (sine up to the playhead)  | the seek bar, travelling only while a track plays    |
| `Tokens`, `Motion`                      | the same spacing, radii, durations and curves        |

## Colour

`color.ini` holds the five inputs of the shell's palette (base, text, primary, focus, on-primary)
and `user.css` mixes every other role from them with `color-mix()`, the same blends as
`config/PaletteRoles.qml` — so the surfaces are the greys the bar wears. `scripts/themes/spotify/pwspice.py`
rewrites the `[Pywal]` section from `~/.cache/wal/colors.json` whenever the shell's palette changes.
There is no hex colour in `user.css`.

## Install

**Settings → Setup → Theme your apps** installs Spicetify, copies this theme and applies it. By hand:

```sh
cp -r spicetify/Themes/QuickSpice ~/.config/spicetify/Themes/
spicetify config current_theme QuickSpice color_scheme Pywal inject_css 1 inject_theme_js 1 replace_colors 1
spicetify apply
```

Copy it, don't link it: `pwspice.py` writes `color.ini` in place, and through a link that would
write your palette into the repo.

## Files

- `user.css` — the theme.
- `theme.js` — state CSS can't see, all of it on `<html>` and never in Spotify's own DOM: `data-qs-playing`
  (the wave and the turning play cookie only move while a track plays), `data-qs-light`, `--qs-art` (the
  cover, for the fallback below), `--qs-canvas` (the relayed Canvas clip, below), and the angle the play
  cookie settles onto when playback stops.
  Changes to it need a Spotify restart; changes to `user.css` repaint live.
- `color.ini` — the palette slots, and the monochrome fallback before the shell has written one.

## Things worth knowing

- **Two nav layouts.** Spotify draws its global nav either as a left column (search collapsed to a circle)
  or as a full-width top row (search open); the theme styles both, scoped on `.searchInputCollapsed`.
  Snippets that lay the nav out themselves (some Marketplace ones do, with `!important`) are overridden
  for what is *drawn* only, never for where things sit.
- **Canvas clips, relayed.** Every Canvas clip is H.264, and Spotify's Linux build cannot decode H.264
  (its ffmpeg is linked into `libcef.so` without the proprietary codecs; there is no library to swap),
  so Spotify itself never plays one. Where `MediaSource` says so, `theme.js` looks the track's clip up
  (Spicetify's GraphQL `canvas` query) and asks the shell's bridge for it: `GET /canvas?src=<the
  canvaz.scdn.co URL>` downloads it once, re-encodes it to an animated AVIF (the whole loop, 480px
  wide: ~1.5s of encoding and ~400KB for a 7s clip; WebP if ffmpeg has no SVT-AV1) and caches it in
  `$XDG_CACHE_HOME/quickshell-spotify-canvas` (300 clips).
  It is drawn the way Spotify draws its own: the top of the side panel, full width at 9:16, behind the
  cover area, the title and the artist, fading into the panel below; the cover steps aside while it
  plays and comes back for a track with no clip. A track change holds the clip on screen until the
  next one is ready (or known not to exist, or 600ms pass), so two tracks with clips go clip to clip
  instead of flashing the cover between them. An image, not a `<video>`, so it scrolls and clips with
  the panel. The lookup retries at start-up until the restored track exists (a restored session fires
  no songchange). The bridge
  fetches nothing but `https://canvaz.scdn.co/….mp4`. A Spotify that CAN decode keeps its own video.
  Spotify's own canvas surface (an undecodable video and its scrims, 1px tall with nothing to size
  them — a hairline across the clip) is hidden while relaying.
  The bridge is a DETACHED process (`Config.spotifyBridgeDetached`): it outlives a shell reload, so new
  bridge code needs the bridge itself restarted — kill it and the shell starts a fresh one.
- **Home is a bento.** Twelve columns: the first quick pick is a two-by-two hero, each shelf is a
  section card, wide / narrow / narrow / wide. It answers the width of the page (container queries),
  not the window: shelves stop pairing up below ~1180px and the quick picks reflow below ~640px. It
  only touches `[data-testid=home-page]`. A shelf is Spotify's carousel, which sizes its cards from
  the PAGE (`--carousel-shelf-element-width`) and lets the last one run off the edge; inside a card
  that read as a card cut in half, so the theme redefines that width from the shelf's own (as many
  whole cards as fit at ≥ ~140px) and drops the carousel's edge fade.
- **One face.** Everything is the shell's font. Spotify adds `spotify-mix-non-latin` to `<html>` and
  sets its font stacks there with `!important` inside `@layer fonts`; an `!important` in a layer beats
  every unlayered rule, so the theme's remap joins that same layer. Outside it, it loses silently: the
  buttons wear the shell's face and every title and name stays Spotify Mix.
- **The playing mark.** Spotify marks what is playing with an `<img>` of its own green equaliser GIF (a
  still SVG while paused). The theme paints that img in the accent through VisualizerPill's bars — three
  3px bars, centred, square-ended — as a mask: an animated WebP at 20fps (Spotify's GIF is 33) and an
  SVG at rest. They're generated: `python3 scripts/themes/spotify/equaliser.py` prints both.
- **Shuffle and repeat.** On, a cookie takes the accent fill (as the media panel's does) AND a dot below
  it — on a low-chroma palette the accent can be darker than the off cookie's chip tint, so the fill
  alone read backwards.
- **The cover's ring.** The player's cover is a turning scallop with a ring of cava bars, like the
  media panel's. `theme.js` reads `GET /spectrum` from the shell's bridge (`scripts/spotify-bridge.py`,
  which runs cava on Spotify's own PipeWire node while something listens); without the bridge the ring
  stays a ring of dots. The bridge runs detached and survives a shell reload: to run new bridge code, kill the bridge and the shell starts a fresh one.
- **Search.** An empty field types its own hints (`artist:` `album:` `track:` `genre:` `year:`), as the
  launcher's does, while it is pointed at or focused; at rest the whole hint stands still (typing
  forever was ~40 text writes, i.e. frames, a second for as long as Spotify ran). Focus rings the pill
  and turns the magnifier. There is deliberately NO global `/`
  shortcut: moving focus during a keydown made Chromium on Wayland lose the key-up, and the `/` repeated
  forever (131 repeats in 5s, typed into the field). Spotify's own Ctrl+L does the job.
- **The cookie field.** The shell's drifting scallops, under the app, with the panels' fills under the
  shapes (`html[data-qs-field]` makes the panels' own backgrounds transparent while it runs). Nothing is
  drawn per frame: `theme.js` renders the field once as an SVG tile in the palette's colours (rebuilt when
  the palette changes), repeated over a layer one tile larger than the window, which slides one tile and
  starts over — a compositor `translate`, plus two slow sways. The fills are rounded rects kept on the
  panels by a ResizeObserver. Its first versions were a canvas redrawn 20 times a second on Spotify's
  main thread, which Spotify keeps saturated: it stuttered, and its jank guard switched it off for the
  session ("the cookies disappear"). It also kept a hidden Spotify rendering at full rate — measured
  playing off-screen: 147% renderer / 68% GPU before, ~17% / ~5% after. What a single tile cannot keep
  is each shape turning on its own.

## Performance

Measured over Chrome's debugging protocol (Spotify started with `--remote-debugging-port`, then CDP
`Performance.getMetrics` / tracing / `LayerTree`), 2026-10-19:

- **Continuous motion runs on the compositor.** The cover's turn, the play cookie's turn and the seek
  wave animate `rotate` / `translate` only. They used to animate registered custom properties and
  `mask-position`, which can only run on the main thread; every frame re-resolved the var()s under them
  (120-point polygons, a 5KB data-URI mask) and tripled the page's style cost per frame.
- **No vsync loops.** The ring waits out its interval on a timer and only then asks for a frame; the
  cookie field asks for none.
- **Nothing that ends keeps a layer.** The page-enter animation fills `backwards`, not `both`.
- Spotify under XWayland never learns it is off-screen (`document.visibilityState` stays `visible`), so
  a theme cannot rely on visibility to go quiet. Most of what is left is Spotify's own and its
  extensions' (Spicy Lyrics asks for every frame while anything plays).

## Motion

The shell's measure, not more: ghost icon buttons lift 1.06 and dip 0.94 over Motion.standard on the
spring curve and leave the press ring; nothing tilts its glyph. Cards lift 2px, library tiles 1.04.
The transport cookies keep CookieButton's wind and lean — that IS the shell's.

## When Spotify updates and something looks wrong

Spotify's class names are hashed and change every release, so this theme hangs on the ones that
don't (`.Root__*`, `.main-*`, `data-testid`, `data-encore-id`) and on the Encore design tokens it
remaps. A rule that stops matching degrades to Spotify's own look for that one element; nothing
breaks. Find the element's current hook with Spotify's devtools (`spicetify enable-devtools`) and
fix the selector in `user.css`.
