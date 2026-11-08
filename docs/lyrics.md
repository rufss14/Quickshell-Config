# Lyrics

Moved from CLAUDE.md; the project rules there still apply.

## Lyrics

`scripts/lyrics.py` (NetEase yrc + LRCLIB) → `services/Lyrics.qml` →
`modules/overview/OverviewLyrics.qml`. Motion lives in `services/lyricsmotion.js`
(`bun scripts/test-lyricsmotion.js`).

A SECOND source runs beside it:
`~/.config/spicetify/Extensions/quickshell-bridge.js` →
`scripts/spotify-bridge.py` → `services/SpotifyBridge.qml` (it also carries the wave's
Spotify restyle the other way — see "The wave"), decoded by
`services/spicylyrics.js` + `services/objpack.js` (`bun scripts/test-spicylyrics.js`,
`bun scripts/test-objpack.js`). Diagnose it with
`qs ipc -c ~/.config/quicktest call spotify lyrics`.

- **The bridge exists because the token does.** Spicy Lyrics' API authenticates
  with a LIVE Spotify access token, so it only works from inside the client —
  hence a Spicetify extension, not a Python provider. NetEase stays as the
  fallback and is never removed.
- `Platform.GetSpotifyAccessToken()` does **not exist** on Spicetify 2.44. The
  real one, verified in `helper/spicetifyWrapper.js`, is
  `Platform.AuthorizationAPI.getState().token.accessToken`. Check the wrapper, not
  their repo, not training data.
- **`!Spicetify` is a ReferenceError, not a falsy test.** An extension is
  `defer`red and runs before the global exists, so the readiness guard must be
  `typeof Spicetify === "undefined"`.
- **Chromium throttles `setInterval` to ~1/minute when Spotify's window is
  hidden** — its normal state behind this shell. Anything that must stay live
  rides `onprogress` (playback-driven); timers are the paused-case fallback only.
- The API answers with a **dictionary encoding, not JSON**: `[valuesList,
  opcodeStream]` (`X-mode: 2`). `objpack.js` decodes it, bounded on depth, counts
  and pointers, refuses `__proto__`, returns null rather than throwing.
- `SpicyLyrics-Version` is **validated server-side** — an unknown value is a bare
  HTTP 400. Pinned in the extension; bump it from their releases page when lyrics
  stop. **A stale pin can also fail SOFT (2026-10-10):** pinned at 6.3.15 while 6.3.153
  was current, the API still answered 200 with real lyrics but line-only (`Type=Line`,
  Apple Music) — no error anywhere, syllable sync just quietly gone. Bumping the pin
  fixed it. If `spotify lyrics` says `line` with `syllables: 0` on everything, check the
  pin first (`gh api repos/Spikerko/spicy-lyrics/releases/latest --jq .tag_name`).
  The extension lives only in `~/.config/spicetify/Extensions/`, not in this repo.
- The extension is a **long-lived child holding a port**, so it needs
  `PR_SET_PDEATHSIG` — it only noticed Quickshell had died when it next WROTE, and
  it only writes on a POST.
- **Every one of those failed invisibly.** The fix that mattered was making the
  failure REPORTABLE — `SpotifyBridge.lastLyricsError` plus a structural
  description of an unmappable payload. Build the diagnostic first.
  - When reporting a payload's shape, print **types and counts, never values**
    below the top level. That's where the lyrics are.
- Each of the three files carries its own "when this breaks" list. Start from
  `qs ipc -c ~/.config/quicktest call spotify lyrics`; it names the stage.
- The card does **not** lay out text. A `TextEdit` per line does, and every glyph
  places itself at `positionToRectangle(i)` — so wrapping, mixed scripts, font
  fallback and right-aligned duet lines are Qt's problem. `Text` has no
  `positionToRectangle`; only `TextEdit` and `TextInput` do.
  - This replaced hand-rolled measuring that was wrong differently for every
    script. Don't measure text here again.
  - `LyricGlyphs.qml` draws one line's letters and is used three times per row —
    lead, backing vocal, translation.
- **A row's height must come from ONE function, called by both sides.** The layout
  pass reserves the height; the block draws at it; a one-pixel disagreement puts
  one lyric on top of the next. `leadHeight()` and `unitsFor()` exist so the two
  sides can't diverge. Do not inline either.
- **`?? []` on a binding that should never be empty hides the bug and costs a
  day.** Deleting `row.units` produced a `TypeError` that named the fault exactly;
  guarding it turned that into an empty layout, zero height, a blank card.
- **Two things that cost nothing and flood everything:**
  - A binding that ASSIGNS `measure.text` and READS `measure.contentHeight` is a
    binding loop — 48,000 log lines in ten seconds. `layout` is a plain property
    filled by `rebuildLayout()`.
  - `positionToRectangle(i)` past the end of the text logs
    `QTextCursor::setPosition: out of range` PER GLYPH, PER FRAME. Range-check the
    index before the call.
  Both saturate the event loop, which starves the IPC, subprocesses and the frame
  clock — so the symptom appears somewhere else entirely.
- **Ask the service before theorising.** `qs ipc … call lyrics status` and
  `… call lyrics shape` distinguish "the card is broken" from "there is nothing to
  draw". Counts and states ONLY — a diagnostic that prints a line of lyric has
  leaked the one thing that must not end up in a log.

## Lyrics translation

`scripts/lyrics-translate.py` → `services/LyricsTranslate.qml` → a line under each
lyric, toggled from the media card.

- Two backends, tried in order: **argos-translate** (AUR, runs locally, nothing
  leaves the machine) then **Google's public endpoint over plain HTTP** (needs
  nothing installed). Installing argos later upgrades the privacy silently.
- **The fallback SENDS EACH LINE TO GOOGLE.** No key, no account — but the text
  leaves the machine, which is why `Config.lyricsTranslate` defaults to false and
  the probe only runs once the feature is on. This config is published; that
  default is the point.
- **One request per line, not negotiable.** The endpoint accepts repeated `q` and
  answers with a well-formed response that translated only the FIRST one, padding
  the rest with metadata. Batching would silently shift every translation onto the
  wrong lyric.
- Cached seven days on disk, keyed by a HASH of the lines. Keyed on provider once,
  which broke when the bridge upgrades a track's lyrics mid-song.
- A translation has no timings, so the line's span is interpolated across its
  words — the same guess the line-only lyrics path makes.
- `state` is settled BEFORE `lines`. Consumers read `hasLines` on the change
  signal — with `lines` first they saw state still `"loading"` and reserved no
  height.


## Now Playing panel round (2026-10-12) — built from static checks, never loaded

Everything here was written and checked with the static checkers and the pure tests, and
**never run in the shell**. `bun scripts/test-lyricsmotion.js`, `test-romanize.js`,
`test-volumeprofiles.js`, `python3 scripts/test-lyrics-romanize.py` cover the logic.

### Spotify gets the first say (`Lyrics.phase`)
- For a Spotify track with the bridge set up (`SpotifyBridge.setupComplete`), the shell's own
  lookup (NetEase/LRCLIB) no longer races the bridge. `Lyrics.load()` waits (`phase = "bridge"`,
  "Connecting to Spotify…") until the bridge answers "no lyrics" (`lyricsTriedUri`, early) or
  `bridgeWaitMs` (6 s) of silence passes, then runs the fallback (`phase = "fallback"`, "Using
  fallback service", sub "Spotify didn't have these in time") until its lyrics show. Bridge
  lyrics arriving later still upgrade them (`onLyricsChanged`). A non-Spotify track, or a
  machine with no bridge, never waits.
- `_waitsForBridge(uri)` compares against the REQUEST's uri, not `_bridgeSettled`: on a track
  change the bridge's own record can still be the previous track for a beat.
- Every card reads `Lyrics.loadingText` / `loadingSub`; `PanelLyrics` re-holds on `onPhaseChanged`.

### The dots are a row (`lyricsmotion.js withInterludes`)
- A gap of `BREAK_S` (4 s) or more — the intro included — becomes a row in `Lyrics.lines`
  (`interlude: true`, `t`, `dur`, no text), inserted in `Lyrics._apply` (the cached payload stays
  as the provider gave it; the function is idempotent). A provider's own blank row spanning a long
  gap is taken over instead of doubled. `structure()` gives the line after one its `break` entrance.
- **No height until it is the row being sung** (OverviewLyrics `dotsRow` / `dotsOpen`, eased 0 → 1;
  `relayoutInterludes` patches row tops each frame — arithmetic only, no text measured). So the
  dots are never visible in advance: the line before is sung, the dots open (the next line moves
  down), the line follows and the row closes. The dots fill across the WHOLE gap
  (`interludeAt().progress`), not the last 9 s (the old `countdown`, a bad idea for long gaps).
- The old overlay `Row` and `root.gap` are gone; `LyricMotion.interlude()` is kept (tested) but
  nothing in the card reads it any more — flag, then remove if nothing wants it.
- A track change recreates every delegate (the Repeater model is a fresh array), so a layout delta
  at an interlude is not animated per row; the strip's scroll carries it. **Unverified live.**

### Lyric type
- `LyricGlyphs.embolden` (lead line only): the lyrics face (CodeNewRoman) stops at Bold, so a
  heavier weight does nothing — every letter is drawn twice 0.5 px apart with alpha compensated
  (`1 − √(1 − α)`) so the dim lines keep their hierarchy. Glint: wider (0.38), brighter
  (`Qt.lighter(accent, 2.3)`), a larger pop. One place each to tune.

### Romanization (`LyricsRomanize`, `scripts/lyrics-romanize.py`, `services/romanize.js`)
- The Spicy Lyrics payload has NO romanization field (measured on a live Apple Music payload:
  syllables carry only `Text`, `IsPartOfWord`, `StartTime`, `EndTime`), so it is generated:
  **Google first** (`dt=rm`, one request per line, only lines with non-Latin letters), then a local
  library (pykakasi, pypinyin, korean-romanizer, unidecode). `Config.lyricsRomanize` (off) and
  `lyricsRomanizeOnline` (on; off = local only).
- The header chip (`abc`, in the mic button's old slot) and the settings rows appear only when
  `LyricsRomanize.romanizable` — the lyrics' own writing system (`romanize.js scriptOf`), no network.
- **The `dt=rm` reply shape is UNVERIFIED**: Google answered HTTP 429 to every request that day.
  Written from the documented shape (`[null, null, <of the translation>, <of the source>]`); a
  reply with no romanization is a FAILURE naming that, never silence, so the fallback runs.
- `scripts/install-dependencies.sh` lists the optional packages; `python-pykakasi` and
  `python-unidecode` are in `extra`, the Chinese and Korean package names are unverified.

### Volume profiles (`volumeprofiles.js`, `Audio.applyProfile`, `components/VolumeProfiles`)
- The speaker no longer mutes: it folds the volume bar into four named levels — Soft 35 %, Medium
  65 %, Max 100 %, Boost 130 %. The 130 % ceiling is `Audio.boostCeiling` (`VP.CEILING`) and is the
  mixer's boost ceiling too (it was 150 %, then 135 %).
- **Only the PLAYER is touched, never the output device.** Soft/Medium/Max set the player's own
  MPRIS `Volume` (Quickshell `MprisPlayer.volume`; Spotify's is `writable`, measured with
  `busctl introspect`) — the one Spotify keeps across tracks. Setting its PipeWire stream is what
  "failed to persist": Spotify rewrites the stream on a track change. Boost sets MPRIS to full and
  over-amplifies THE STREAM to 130 %, remembering what it was and putting it back on any other pick.
  A player with no MPRIS volume falls back to its stream throughout.
- A boost is **held** (`Audio._boostApp`): re-asserted ~0.8 s after a track change, a playback-state
  change or a stream appearing, and only when the stream has come back at exactly unity (Spotify's
  rewrite) — a level the user set themselves is never fought.
- The bridge extension was NOT changed: its shell→extension channel is an opaque `no-cors` reply
  (an event is told from a timeout by TIME), which cannot carry a number. If MPRIS writes turn out
  not to stick on a real Spotify, that is the next thing, and it would need a new channel.

### Follow-ups the same day
- **Romanization "didn't work at all"** — three causes, all found from `qs ipc call lyricsromanize
  status` (it sat at `loading`, then `error=python-pykakasi is not installed`, in a loop):
  Google answered HTTP 429 (the "Sorry…" block page) to every request from this connection; the
  local fallback `python-pykakasi` was not installed; and `load()` reset its own `_retried`, so the
  one-retry re-armed itself and re-asked about 40 lines every ~6 s, which keeps a block going. Now:
  the script sets a `_limited` flag on the first 429 (every other line fails without a request) and
  reports `google: "limited"`; the service stops asking Google for 15 min (`googleLimited`, a
  timer — a time stamp in a binding would never re-evaluate); the retry goes through `_send()`, and
  only for a failure a retry can fix. A failure now shows: the chip turns warning-coloured and the
  panel subtitle says why. **It still needs a source:** Google is refusing this IP, so
  `sudo pacman -S python-pykakasi python-unidecode` (both in `extra`) is what makes it work now.
  The chip's icon is `record_voice_over` (pronunciation); `abc` was the first pick.
- **Ceiling 130 %** (was 135 %): `volumeprofiles.js CEILING`, so the mixer and Boost move together.
- **Boost's gestures** (the other profiles just apply): left click UNLOCKS the volume bar to 130 %
  and shows it, changing nothing; right click unlocks it AND sets the boost; picking any other
  profile locks it again (`MediaPanel.boostUnlocked`; the bar also reads as unlocked whenever the
  level is past 100 %). Unlocked, the bar (`ThickSlider.notchAt`) draws a tick at 100 % and turns the
  warning colour past it. Past 100 % the level is the player's STREAM (MPRIS stops at 1.0), so
  `Audio.playerLevel` returns the stream's when it is lifted and `setPlayerLevel(…, boost)` sets
  MPRIS to full + the stream over-amplified, held across track changes at that level.
- The user's second "left clicking" in the request was read as RIGHT click.

### Romanization replaces the lyric, syllable-synced, and loads faster (same day)
- **In place, not under.** With it on, the lead shows the Latin letters where the script was
  (`OverviewLyrics.romanUnitsFor`, one function for the layout pass `textFor(line, i)` and the row —
  the heights must come from the string that is drawn). The separate row I had added is gone. Lines
  with no romanization (an English refrain) keep their text; the backing vocal is NOT romanized.
- **Synced to the syllables** (`services/romajialign.js`, `bun scripts/test-romajialign.js`). The
  romanizer returns one string per line; the voice has timing per syllable. For Japanese the line is
  cut into moras, every kana is an ANCHOR that takes the mora that spells it (で↔de, ん↔n, は↔wa,
  しゃ as one, っ doubling the next consonant, a long vowel's second kana taking nothing), and the
  kanji between two anchors share what lies between. A kanji read longer than guessed therefore
  costs only its own group; proportional splitting would shift everything after it. Which of two
  kanji takes an odd mora ("se·kai" / "seka·i") is not in the data — the first takes the remainder.
  Pinyin is paired syllable for character, everything else letter for character; an unplaceable line
  falls back to `retimeWords` (the words spread along the original's own timeline).
- **Faster.** A repeated line is asked once (`_unique`: a chorus is a quarter of a song); the line
  timeout is 3 s (a straggler sets the time for the whole song); and the local library and Google
  now run SIDE BY SIDE — the local answer goes out the moment it is ready (`final: false`) and
  Google's, which reads kanji in context, replaces it when it lands (`final: true`; the service
  handles one JSON line at a time, and only a final answer is memoised or cached). Google's own
  latency is the floor: with the local library installed the first answer is near-instant, without
  it the song waits on the network. A replay is instant (30-day disk cache).

### Romanization cache, like the translation one (same day)
- It already cached (`~/.cache/quickshell/lyrics-romanize`, keyed by a hash of the lines + the script),
  but invisibly and without a policy: all nine entries found on disk were on-device answers from
  while Google was refusing, kept the same 30 days as a Google one — so Google's better reading would
  not have replaced them for a month. Now:
  - `Config.lyricsRomanizeCache` (default on, persisted) and a "Cache romanizations" row beside the
    translation one; off romanizes every play and neither reads nor writes the disk or the in-memory
    layer (`LyricsRomanize._memo`).
  - **A Google answer lives 30 days, an on-device one a day** (`LOCAL_TTL`, judged by the entry's own
    `saved_at` + `backend`; an entry with no stamp predates the rule and counts as stale). Only a FINAL
    answer is written, and only when no line failed.
  - The readout says "Romanized by Google · from cache" (`LyricsRomanize.lastCached`, the script's own
    `cached` flag), as translation does.
  - `python3 scripts/test-lyrics-romanize.py` pins the policy (served at any age if Google, a day if
    on-device, `cache: false` touches nothing).

### The previous song's lyrics on the next one; the empty state (2026-10-31)
- **Fixed: a skip during a fallback lookup put the old song's lyrics on the new one.** The lookup's
  `onExited` filed its answer under `_key` — the track current when it LANDED — so a lookup still running
  for song A, finishing after a skip to B (whose bridge fetch had failed), was applied to B. B's own
  lookup never ran either: `running = true` on a running Process starts nothing, and applying A's answer
  ended B's wait. Now each lookup carries `proc.forKey` (the key it was asked for); a request made
  mid-lookup waits in `_next` and starts when the one in flight exits, if it is still the track; a
  failure only clears the state when it was about the current track. A's answer stays cached under A.
- **The card's empty state is the player's mark and why** (the user: no "second phase … with the cava
  and all"): Spotify's logo (glyph F04C7, in the card's accent) or a music note, "Instrumental", "Unable
  to fetch lyrics" (none or error), "Lyrics off", or the loading text while still looking. The spectrum,
  the track line, the seek bar and the cava stream they held are gone from OverviewLyrics; `scrubbing`
  stays for hosts and is always false.
