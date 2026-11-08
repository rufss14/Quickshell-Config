pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "lyricsmotion.js" as LyricMotion
import "mediasource.js" as MediaSource

// ── Lyrics ────────────────────────────────────────────────────────────────────
// Time-synced lyrics, preferring WORD-level timing.
//
// The fetching, provider fan-out, matching and caching all live in scripts/lyrics.py.
// This is the QML face of it: hand it a track, get back lines.
//
//   kind = "word"          per-word start AND duration — the real thing
//        | "line"          per-line only; the card interpolates the words
//        | "plain"         lyrics, but no timing at all
//        | "instrumental" | "none" | "error"
//
// ── Two providers, because one of them can't do the job ───────────────────────
// LRCLIB only has line-level LRC. NetEase's `yrc` carries a start and a duration for
// every word, which is what the voice actually does. The script queries both at once and
// keeps the better answer — see there for why it does NOT wait for both.
//
// ── This makes a network request. Say so out loud. ────────────────────────────
// Looking up lyrics sends the current track's title/artist/album to a third party. That
// is inherent to any lyrics viewer — there is no local source — but it IS an outbound
// request, on every new track. `enabled` turns it off and the card says "Lyrics off".
//
// ── Nothing here fires on a position tick ─────────────────────────────────────
// A lyrics view updates ~30×/second as a song plays. Requests are keyed to the TRACK,
// deduplicated in memory here and on disk in the script, so a song played start to finish
// costs exactly one lookup and replaying it costs none.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property bool enabled: true

    // "idle" | "loading" | "synced" | "plain" | "instrumental" | "none" | "error"
    property string state: "idle"

    // "word" | "line" | "" — whether `lines[].words` carries real timings.
    property string kind: ""

    // [{ t, dur, text?, words?: [{ t, d, text }] }]
    property var    lines: []
    property string plain: ""
    property string source: ""

    // ── Who provided them ─────────────────────────────────────────────────────
    // Only the bridge fills these: its payload names its own upstream, and a good share of
    // that is community-uploaded rather than licensed — which is exactly why its coverage
    // is better, and exactly the kind of thing worth crediting rather than hiding.
    // The shell's own NetEase/LRCLIB path leaves them blank and is reported as a fallback.
    property string provider: ""
    property bool   community: false

    // Did these come from inside Spotify, with real syllable timings?
    readonly property bool viaBridge: root.provider !== ""

    readonly property bool hasSynced:  root.state === "synced" && root.lines.length > 0
    readonly property bool hasWordTiming: root.kind === "word"

    // ── Is the CURRENT track even one the bridge could ever answer for? ───────
    // Set by the caller, not inferred here — OverviewLyrics knows whether the playing
    // MPRIS player's `desktopEntry` is "spotify"; this service only sees whatever
    // artist/title/album it was handed. Needed so a Firefox or Chromium tab's track
    // never reads "Connecting to Spotify…" for a bridge that was never going to answer
    // for it in the first place.
    readonly property bool _isSpotifyTrack: (root._lastReq && root._lastReq.isSpotify) ?? false

    // ── Has the bridge had its SAY for this exact track, one way or the other? ─
    // `hasLyrics`/`lastLyricsError` alone can't tell "hasn't answered yet" from "answered
    // no" — a fetch failing for track A leaves `lastLyricsError` sitting there looking
    // exactly like an answer for track B, which hasn't been asked about at all. Compares
    // against SpotifyBridge's own record of the uri its last verdict was actually about.
    readonly property bool _bridgeSettled:
        SpotifyBridge.trackUri !== "" && SpotifyBridge.lyricsTriedUri === SpotifyBridge.trackUri

    // ── Why is there nothing to show? ─────────────────────────────────────────
    // Worked out HERE, not in the card. Two surfaces draw these lyrics and the settings
    // page asks the same question, and "no lyrics for this track" is the wrong answer to
    // give when the real one is "the bridge hasn't had a chance to answer yet".
    //
    // Only meaningful while there is nothing synced — the loading, instrumental and error
    // states already say enough for themselves.
    //
    // ── NOT gated on Config.lyricsFallback any more ───────────────────────────
    // It used to short-circuit to "" whenever the fallback was allowed to look, on the
    // theory that its own answer was the whole story. But the fallback (NetEase/LRCLIB,
    // a fast local-network lookup) and the bridge (a round trip through Spotify's own
    // renderer, a Spicetify extension, and a listener) race, and the fallback settling
    // first on "nothing here" does not mean the bridge is done trying — it means the
    // fallback is FASTER. Reporting "No lyrics for this track" in that gap was simply
    // wrong: the better, syllable-timed answer was still in flight. So this now reports
    // the bridge's own progress regardless of the fallback setting; the card only shows
    // it while `state === "none"` anyway, which means neither source has anything yet.
    //
    //   ""            nothing to explain: not a Spotify track, no bridge installed, or
    //                  something is already on the way to being shown
    //   "connecting"  the listener is not up yet
    //   "waiting"     listener up, but Spotify has not spoken to it (not running, or
    //                 the Spicetify extension is not installed)
    //   "connecting"  (again) listener IS live, but hasn't settled an answer for THIS
    //                 track yet — the extension's own fetch is still in flight
    //   "unanswered"  bridge is live, settled, and simply has no lyrics for this track
    readonly property string _rawBlocked: {
        if (!root._isSpotifyTrack)        return ""
        if (!SpotifyBridge.setupComplete) return ""
        if (!SpotifyBridge.listening)     return "connecting"
        if (!SpotifyBridge.available)     return "waiting"
        if (!root._bridgeSettled)         return "connecting"
        return Config.lyricsFallback ? "" : "unanswered"
    }

    // ── "Connecting…" is not a place to stay ──────────────────────────────────
    // The bridge only counts as having had its say once it has recorded a verdict for THIS
    // track's uri — and for some tracks (an instrumental, a track with no uri, an extension
    // that never replies to this one) it never does. "Connecting to Spotify…" then stood on
    // the card for the whole song, claiming progress that was not happening and hiding the
    // truth: that nothing has lyrics for it. So the two WAITING reasons are given a while
    // (`_waitExpired`, started with each request) and then dropped, leaving the honest state
    // underneath — "instrumental" if a provider said so, "none" if not. "unanswered" (the
    // bridge DID answer, with nothing) is a verdict, not a wait, and stays.
    property bool _waitExpired: false
    Timer {
        id: waitTimer
        interval: 8000
        onTriggered: root._waitExpired = true
    }

    readonly property string blockedReason:
        root._waitExpired && (root._rawBlocked === "connecting" || root._rawBlocked === "waiting")
            ? "" : root._rawBlocked

    // ── Spotify gets the first say ────────────────────────────────────────────
    // The shell's own lookup (NetEase/LRCLIB) used to start the instant a track did, racing the
    // bridge — and its answer, being faster, was what showed, with Spotify's better one
    // arriving behind it to replace it. It is a lookup that sends the track to a third party,
    // so for a Spotify track the bridge could answer it now waits its turn: the fallback runs
    // when Spotify has said it has NOTHING, or has said nothing at all for `bridgeWaitMs`.
    //
    //   ""          nothing special: not waiting on Spotify, and not running its fallback
    //   "bridge"    waiting on Spotify — "Connecting to Spotify…"
    //   "fallback"  Spotify had nothing or didn't answer, and the fallback is looking —
    //               "Using fallback service" — until its lyrics show (or it finds none)
    //
    // A track that is not Spotify's, or a machine with no bridge set up, never waits: nothing
    // is coming to wait for.
    property string phase: ""
    readonly property int bridgeWaitMs: 6000
    property bool _pendingFallback: false

    // What the card says while it looks, by phase (state "loading").
    readonly property string loadingText:
        root.phase === "bridge"   ? "Connecting to Spotify…"
      : root.phase === "fallback" ? "Using fallback service"
      :                             "Looking for lyrics…"
    readonly property string loadingSub:
        root.phase === "fallback" ? "Spotify didn't have these in time" : ""

    // `uri` is this request's own, when it has one. Not `_bridgeSettled`: on a track change the
    // bridge's record of "which track" can still be the PREVIOUS one for a beat (its anchor
    // lands after MPRIS's metadata), and a verdict about that one is no answer for this.
    function _waitsForBridge(uri) {
        return root._isSpotifyTrack && SpotifyBridge.setupComplete
            && !(uri && SpotifyBridge.lyricsTriedUri === uri)
    }

    Timer {
        id: fallbackTimer
        interval: root.bridgeWaitMs
        onTriggered: root._fallbackNow()
    }

    // Spotify answered "no lyrics" for this track: no point waiting out the clock.
    Connections {
        target: SpotifyBridge
        function onLyricsTriedUriChanged() {
            if (root._pendingFallback && root._bridgeSettled && !SpotifyBridge.hasLyrics)
                root._fallbackNow()
        }
    }

    function _fallbackNow() {
        fallbackTimer.stop()
        if (!root._pendingFallback || !root._lastReq) return
        root._pendingFallback = false
        if (!Config.lyricsFallback) { root._clear("none"); return }
        const r = root._lastReq
        root.phase = "fallback"
        root._runFallback(r.artist, r.title, r.album, r.duration)
    }

    // ── One lookup at a time, each tagged with its own track ──────────────────
    // The answer is filed under the key it was ASKED for (`proc.forKey`), never the key that
    // is current when it lands. It used to read `_key` on exit, and a skip during a lookup
    // put the previous song's lyrics on the new one (2026-10-31, the user: "it grabs the past
    // lyrics and plays them on the current song") — while the new song's own lookup never
    // ran, because `running = true` on a process already running starts nothing. Now a
    // request made mid-lookup waits as `_next` and starts when the one in flight exits;
    // the old answer is still cached under the old song.
    property var _next: null
    function _runFallback(artist, title, album, duration) {
        const req = { key: root._key,
                      command: ["python3", root.scriptPath,
                                "--artist",   artist || "",
                                "--title",    title,
                                "--album",    album || "",
                                "--duration", String(Math.round(duration || 0))] }
        if (proc.running) { root._next = req; return }
        root._start(req)
    }
    function _start(req) {
        root._next = null
        proc.out = ""
        proc.forKey = req.key
        proc.command = req.command
        proc.running = true
    }

    // ── Sync offset ───────────────────────────────────────────────────────────
    // Seconds added to the player's reported position before a line or word is resolved.
    // Positive = the lyrics run EARLIER (use it when they lag the vocal).
    //
    // This exists because no amount of matching can close the gap. Even with the right
    // recording, the player reports its position with latency, the audio path adds more,
    // and NetEase's timings are keyed to *their* master, not the one you're streaming.
    // Every serious lyrics app has this control for exactly that reason.
    property real offset: 0

    function nudge(delta) {
        root.offset = Math.round((root.offset + delta) * 10) / 10   // keep it to 0.1s
    }
    function resetOffset() { root.offset = 0 }

    // Was a PersistentProperties block: no disk I/O, so a nudged offset survived a hot
    // reload but never a restart — you re-tuned the same track every session.
    JsonStore {
        id: store
        path: Quickshell.statePath("lyrics.json")
        onLoaded: {
            root._loading = true
            root.offset = (store.value ?? {}).offset ?? root.offset
            root._loading = false
        }
    }

    property bool _loading: false

    onOffsetChanged: {
        if (root._loading || !store.ready) return
        store.value = { offset: root.offset }
    }

    property string _key: ""
    property var    _cache: ({})
    property var    _lastReq: null

    // Switching the fallback ON has to reach the track that is playing, not only the next
    // one. Only re-asks when there is nothing to lose: state "none" means the bridge had
    // no answer and we declined to look further, which is exactly the case the setting
    // just changed. A track that already HAS lyrics is left alone.
    Connections {
        target: Config
        function onLyricsFallbackChanged() {
            if (!Config.lyricsFallback || root.state !== "none" || !root._lastReq) return
            const r = root._lastReq
            root._key = ""                     // defeat the dedupe, then ask properly
            root.load(r.artist, r.title, r.album, r.duration, r.uri)
        }
    }

    readonly property string scriptPath:
        Qt.resolvedUrl("../scripts/lyrics.py").toString().replace("file://", "")

    function trackKey(artist, title, album, duration) {
        return [artist || "", title || "", album || "", Math.round(duration || 0)].join("::")
    }

    // Which line is live at `pos` (seconds). -1 before the first one.
    //
    // Binary search, not a scan: this runs on every position tick, and walking a few
    // hundred lines 30 times a second is real work to avoid for free. (Verified against a
    // real 114-line track: 0 mismatches over 3000 random probes.)
    function lineAt(pos) {
        const n = root.lines.length
        if (n === 0 || pos < root.lines[0].t) return -1

        let lo = 0
        let hi = n - 1
        while (lo < hi) {
            const mid = Math.ceil((lo + hi) / 2)
            if (root.lines[mid].t <= pos) lo = mid
            else                          hi = mid - 1
        }
        return lo
    }

    function _stateFor(kind) {
        switch (kind) {
            case "syllable":
            case "word":
            case "line":         return "synced"
            case "plain":        return "plain"
            case "instrumental": return "instrumental"
            default:             return "none"
        }
    }

    function _apply(key, d) {
        root._cache[key] = d
        if (key !== root._key) return      // the track moved on while we were in flight
        // Lyrics are here: whatever was waiting or looking is over.
        root._pendingFallback = false
        fallbackTimer.stop()
        root.phase = ""

        // ── `state` is settled BEFORE `lines`, and that order is load-bearing ──
        // Consumers react on onLinesChanged — the lines are the thing they draw — and the
        // first thing they ask is `hasSynced`, which reads `state`. With state assigned
        // last it was still "loading" at that moment, so every one of them concluded there
        // was nothing to show.
        //
        // That is exactly what stopped translations working on a track change: the card
        // requests one from onLinesChanged, saw hasSynced false, cleared the request and
        // was never called again — because nothing else changes afterwards. It appeared to
        // work only when _apply ran WITHOUT a preceding _clear (a cache hit, or the bridge
        // upgrading mid-song), where `state` happened to still be "synced" from the
        // previous track. Hence "it works after a reload" and not otherwise.
        //
        // Same rule, same reason, as LyricsTranslate.onExited — see the note there.
        root.kind   = (d.kind === "syllable" || d.kind === "word" || d.kind === "line")
                    ? d.kind : ""
        root.state  = root._stateFor(d.kind)
        root.plain  = d.plain ?? ""
        root.source = d.source ?? ""
        root.provider  = d.provider ?? ""
        root.community = d.community ?? false
        // Long silences become rows of their own (the three dots) — see lyricsmotion.js. A new
        // list, so the cached payload stays as the provider gave it.
        root.lines  = LyricMotion.withInterludes(d.lines ?? [])
    }

    function _clear(state) {
        if (state !== "loading") { root.phase = ""; root._pendingFallback = false; fallbackTimer.stop() }
        root.state  = state
        root.kind   = ""
        root.lines  = []
        root.plain  = ""
        root.source = ""
        root.provider  = ""
        root.community = false
    }

    // ── The request a PLAYER asks for ─────────────────────────────────────────
    // What a lyrics view does when its player or its track changes, in the one place, so a
    // second consumer (the karaoke module, with no card on screen) asks EXACTLY as the card
    // does instead of keeping a second copy that drifts. It was OverviewLyrics._reload.
    //
    // No lookup at all for a source whose metadata can't be trusted — not a lookup that is
    // then ignored: it would send a video title to a third party and cache a wrong match.
    // Clearing the service also drops whatever the PREVIOUS track left on screen.
    //
    // Spotify's own metadata where the bridge has it: MPRIS carries whatever the app chose
    // to publish, the bridge carries the fields Spotify itself holds, and the URI makes the
    // request's identity exact. "Is Spotify" is structural (which APP is playing), not "is
    // the bridge caught up right now" — see load()'s note on why.
    function loadFor(player) {
        if (!player) return
        if (!MediaSource.lyricsTrusted(player)) {
            root.load("", "", "", 0, undefined, false)
            return
        }
        const isSpotify = (player.desktopEntry ?? "") === "spotify"
        if (isSpotify && SpotifyBridge.available) {
            root.load(SpotifyBridge.artist, SpotifyBridge.title, SpotifyBridge.album,
                      SpotifyBridge.duration, SpotifyBridge.trackUri, true)
            return
        }
        root.load(player.trackArtist ?? "", player.trackTitle ?? "", player.trackAlbum ?? "",
                  player.length ?? 0, undefined, isSpotify)
    }

    // What identifies the track a player is on, for a caller that reloads when it changes:
    // the SOURCE is part of it — a tab can go from a song to a video without the player
    // object changing.
    function trackIdFor(player) {
        return (player?.trackTitle ?? "") + "::" + (player?.trackArtist ?? "") + "::"
             + (player?.trackAlbum ?? "") + "::" + SpotifyBridge.trackUri + "::" + MediaSource.idOf(player)
    }


    // ── Request. Call on TRACK CHANGE only. ───────────────────────────────────
    // `uri` is optional and, when given, becomes the identity of the request instead of
    // the artist/title/album/duration tuple. SpotifyBridge supplies `spotify:track:…`,
    // which is exact — where the tuple is a guess that two different recordings of the
    // same song can both satisfy.
    //
    // `isSpotify` is separate from `uri` on purpose. The caller knows this from the
    // player's `desktopEntry`, which is a structural fact about WHICH APP is playing —
    // true the instant a Spotify track starts, whether or not the bridge itself has
    // caught up yet. `uri` only arrives once it has (`_bridged` in OverviewLyrics
    // requires `SpotifyBridge.available`), so gating "is this worth waiting on the
    // bridge for" on `uri` instead would say no for every Spotify track played right
    // after a reload, for exactly as long as the bridge takes to reconnect.
    function load(artist, title, album, duration, uri, isSpotify) {
        if (!root.enabled) { root._clear("idle"); return }
        // ── "Nothing to look up" must forget the LAST request too ─────────────
        // A caller that declines to ask — the lyrics card on a YouTube video, whose title
        // is not a song's — arrives here with no title. Clearing the state was not
        // enough: `_lastReq` still described the previous (Spotify) track, and the two
        // things that read it kept acting on it — the bridge handler below re-applied
        // Spotify's lyrics the next time the bridge said anything (Spotify is still
        // running, just paused), and the fallback switch re-asked for them. Lyrics for a
        // song that was not playing, back on screen over the video that was.
        if (!title)        { root._key = ""; root._lastReq = null; waitTimer.stop(); root._waitExpired = false; root._clear("idle"); return }

        // Kept so the CURRENT track can be re-asked when the fallback is switched on.
        // Without it, turning the setting on would only affect the next song — `_key` is
        // already recorded, so every later signal deduplicates against it and returns.
        root._lastReq = { artist: artist, title: title, album: album,
                          duration: duration, uri: uri, isSpotify: !!isSpotify }

        const key = uri || root.trackKey(artist, title, album, duration)
        if (key === root._key) return          // same track — nothing to do
        root._key = key
        // A new track gets a fresh allowance of waiting on the bridge (see `blockedReason`).
        root._waitExpired = false
        waitTimer.restart()

        // ── Already have them, from inside Spotify ────────────────────────────
        // The bridge's extension fetches with the client's own access token, which the
        // shell has no way to obtain, and returns SYLLABLE timings rather than word ones.
        // When that arrived for this exact track there is nothing left to look up — so no
        // process is spawned and no request leaves the machine a second time.
        if (uri && SpotifyBridge.hasLyrics && SpotifyBridge.lyricsUri === uri) {
            root._apply(key, SpotifyBridge.lyrics)
            return
        }

        // ── An in-memory hit is not exempt ────────────────────────────────────
        // The cache holds both origins, and this check sat AFTER it — so a track looked up
        // earlier in the session came straight back from memory with the fallback switched
        // off, and the setting appeared to work only on songs you had not already played.
        //
        // `provider` is what distinguishes them: the bridge names its upstream, the shell's
        // own lookup leaves it blank. The entry stays cached either way, so switching the
        // fallback back on shows it again without a second request.
        const hit = root._cache[key]
        if (hit && (Config.lyricsFallback || (hit.provider ?? "") !== "")) {
            root._apply(key, hit)
            return
        }

        // ── The fallback, when it is allowed ──────────────────────────────────
        // Everything above this line is free: already in hand, or already fetched. THIS
        // is the part that spawns a process and sends artist/title/album to a third party,
        // and it is the part `Config.lyricsFallback` governs.
        //
        // Reported as "none" rather than "error" — nothing failed. The bridge had nothing
        // for this track and looking further was declined, which is a legitimate state and
        // the card already knows how to say so.
        if (!Config.lyricsFallback) { root._clear("none"); return }

        root._clear("loading")

        // A Spotify track the bridge could still answer waits for it (see "Spotify gets the
        // first say"); anything else asks the fallback at once.
        if (root._waitsForBridge(uri)) {
            root.phase = "bridge"
            root._pendingFallback = true
            fallbackTimer.restart()
            return
        }
        root.phase = ""
        root._runFallback(artist, title, album, duration)
    }

    // ── Bridge lyrics landing late ────────────────────────────────────────────
    // load() runs the moment the track changes; the extension's fetch takes a network
    // round trip and lands a beat later. Without this the better data would arrive and
    // simply be ignored until the next song — the shell would already have shown whatever
    // its own lookup returned and never revisited it.
    //
    // Guarded on the uri matching the CURRENT request, so a payload for the previous track
    // arriving after a fast skip cannot overwrite the new one.
    Connections {
        target: SpotifyBridge
        function onLyricsChanged() {
            if (!root.enabled) return
            if (!SpotifyBridge.hasLyrics) return

            // Only while the track being shown IS a Spotify one. The bridge's lyrics are
            // for whatever Spotify has loaded, which says nothing about what the card is
            // showing: with Spotify paused and a video playing elsewhere, they are not
            // wanted. (`_isSpotifyTrack` is false once load() has been told there is
            // nothing to look up.)
            if (!root._isSpotifyTrack) return

            // Only upgrade. If we already hold syllable data there is nothing to gain, and
            // re-applying mid-song resets the view.
            if (root.kind === "syllable") return

            // ── Do NOT require the key to already be the uri ──────────────────
            // It usually is not, and that was a real bug: load() is handed a uri only when
            // SpotifyBridge is `available` at that instant, and on a track change the
            // anchor lands a beat after the MPRIS metadata does. So the first load() of
            // almost every song keyed on the artist/title tuple, this guard compared that
            // tuple against a uri, failed, and the song stayed on the NetEase fallback for
            // its whole duration — while the bridge sat holding better lyrics for the
            // exact same track.
            //
            // `available` is the guard that matters instead: it means Spotify is live and
            // this uri is what is playing right now. Re-key so later load() calls for the
            // same track dedupe against the uri rather than re-fetching.
            if (!SpotifyBridge.available) return

            root._key = SpotifyBridge.lyricsUri
            root._apply(root._key, SpotifyBridge.lyrics)
        }
    }

    // ── What this service actually holds ──────────────────────────────────────
    // There was no way to ask, which is why "the lyrics do not show up" took several
    // rounds: the card being empty and the service being empty look identical from
    // outside, and they have completely different causes.
    //
    // Counts and states only — never a line of text. The words are the one thing that has
    // no business in a diagnostic.
    IpcHandler {
        target: "lyrics"

        function status(): string {
            return "state=" + root.state
                 + "  kind=" + (root.kind || "-")
                 + "  lines=" + root.lines.length
                 + "  synced=" + root.hasSynced
                 + "  source=" + (root.source || "-")
                 + (root.provider ? "  provider=" + root.provider : "")
                 + "  offset=" + root.offset.toFixed(1) + "s"
        }

        // Are the lines shaped the way the card expects? A line with no words and no text
        // renders as nothing at all, which is indistinguishable from having no lyrics.
        function shape(): string {
            const n = root.lines.length
            if (n === 0) return "no lines"

            let withWords = 0, withText = 0, empty = 0, units = 0, dots = 0
            for (const l of root.lines) {
                if (l.words && l.words.length > 0) { withWords++; units += l.words.length }
                else if (l.text && l.text !== "")  withText++
                else if (l.interlude)              dots++
                else empty++
            }
            return n + " lines: " + withWords + " with words (" + units + " units), "
                 + withText + " text-only, " + dots + " interludes, " + empty + " empty"
        }
    }

    Process {
        id: proc

        property string out: ""
        // The track this lookup is for (see _runFallback).
        property string forKey: ""

        // The payload is one long JSON line; SplitParser hands it over a line at a time,
        // so it's reassembled rather than assumed to arrive whole.
        stdout: SplitParser {
            onRead: function(line) { proc.out += line }
        }

        onExited: {
            const text = proc.out
            const key  = proc.forKey
            proc.out = ""

            // A failure only speaks for the track it was about.
            try {
                const d = JSON.parse(text)
                if (!d.ok) { if (key === root._key) root._clear("error") }
                else root._apply(key, d)
            } catch (e) {
                console.warn("Lyrics: could not parse lyrics.py output —", e)
                if (key === root._key) root._clear("error")
            }
            // A request made while this one ran — still wanted only if it is still the track.
            if (root._next) {
                if (root._next.key === root._key) root._start(root._next)
                else root._next = null
            }
        }
    }
}
