pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "romanize.js" as Rom

// ── LyricsRomanize ────────────────────────────────────────────────────────────
// A lyric written in another script, in Latin letters — "konnichiwa" where "こんにちは" was.
// It REPLACES the lyric on the card, lit syllable by syllable on the original's timing
// (services/romajialign.js, wired up in OverviewLyrics.romanUnitsFor).
//
// scripts/lyrics-romanize.py → here → the lead line of each row in OverviewLyrics. Modelled on
// LyricsTranslate (which it sits beside on the card) and deliberately smaller: no backend
// editor, no probe, no history — one request per track, one retry.
//
// ── Google first, a local library as the fallback ─────────────────────────────
// The script tries Google's public endpoint and then a local library (pykakasi, pypinyin,
// korean-romanizer, unidecode), `Config.lyricsRomanizeOnline` off dropping Google. **With it on,
// each lyric line that has non-Latin letters is sent to Google**, and only while
// `Config.lyricsRomanize` is on — off by default, because this config is published.
//
// ── The toggle exists only on a song that has something to romanize ───────────
// `romanizable` is asked of the lyrics (romanize.js: which writing system, no network). A song in
// English has nothing to show, so the Now Playing panel shows no switch for it — and once the
// script has answered "nothing to romanize" for a track the Python side disagreed with the cheap
// check about, `romanizable` goes false again rather than leaving a switch that does nothing.
//
// ── Keyed to the TRACK, never to the position ─────────────────────────────────
// One request per track, deduplicated here and cached on disk for a month by the script.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property bool enabled: Config.lyricsRomanize

    // The lyrics' own text, one string per row (an interlude row is ""), index-aligned with
    // Lyrics.lines.
    readonly property var texts: Lyrics.lines.map(l =>
        l.text || (l.words ? l.words.map(w => w.text).join("") : ""))

    // The writing system worth romanizing in the current lyrics, or "".
    readonly property string script: Lyrics.hasSynced ? Rom.scriptOf(root.texts) : ""

    // "idle" | "loading" | "ready" | "none" | "error"
    property string state: "idle"

    // Romanized lines, index-aligned with Lyrics.lines. "" where a row has nothing.
    property var    lines: []
    property string backend: ""
    property string lastError: ""
    property string installHint: ""

    readonly property var backendNames: ({ "google": "Google", "local": "On-device" })
    readonly property string backendUsed: root.backendNames[root.backend] || root.backend

    // Does this song have something to romanize? The script says no → there is nothing to
    // switch on; the request said "nothing to romanize" → likewise.
    readonly property bool romanizable: root.script !== "" && root.state !== "none"

    readonly property bool hasLines:
        root.state === "ready" && root.lines.length > 0

    // What the switch's line under it should say while it works or when it can't.
    readonly property string status: {
        if (!root.enabled || !root.romanizable) return ""
        if (root.state === "loading") return "Romanizing…"
        if (root.state === "error")
            return root.lastError + (root.installHint !== "" ? " — install " + root.installHint : "")
        if (root.state === "ready" && root.backendUsed !== "")
            return "Romanized by " + root.backendUsed + (root.lastCached ? " · from cache" : "")
                 + (root.googleLimited && root.backend === "local" ? " (Google is refusing requests)" : "")
        return ""
    }

    property string _key: ""
    property bool   _retried: false
    property var    _memo: ({})

    // ── Google says no, so stop asking ────────────────────────────────────────
    // A 429 is Google refusing THIS connection (the translate button shares it), and asking
    // again every few seconds is how that lasts. After one, only the local library is asked for
    // `limitMs`; the script reports it (`google: "limited"`) even when the library then answered.
    readonly property int limitMs: 15 * 60 * 1000
    property bool googleLimited: false
    // A timer rather than a time stamp compared in a binding: nothing would re-evaluate that
    // when the minutes pass, and Google would stay ruled out for the rest of the session.
    Timer { id: limitTimer; interval: root.limitMs; onTriggered: root.googleLimited = false }

    readonly property bool failed: root.state === "error"

    // Did what is on screen come off the disk cache (the script says so), or the in-memory one?
    property bool lastCached: false
    readonly property bool cacheEnabled: Config.lyricsRomanizeCache

    function clear() {
        root.lastCached = false
        root.state = "idle"
        root.lines = []
        root.backend = ""
        root.lastError = ""
    }

    // Called by the card with the lyrics' texts and a key for them. Same contract as
    // LyricsTranslate.load.
    function load(key, texts) {
        if (!root.enabled || !key || !texts || texts.length === 0) { root._key = ""; root.clear(); return }
        if (key === root._key) return

        root._key = key
        root._retried = false
        retryTimer.stop()

        // Answered this session already: no process, no loading state — the card goes straight
        // from one track to the other. Skipped when caching is off (that switch means "romanize
        // every play"); this layer is a cache like the disk one.
        const m = root.cacheEnabled ? root._memo[key] : undefined
        if (m !== undefined) {
            root.backend = m.backend
            root.lastCached = true
            root.state = m.lines.length > 0 ? "ready" : "none"
            root.lines = m.lines
            return
        }

        root.clear()
        root._send(texts)
    }

    // The request itself. The retry comes here and NOT through load(): load() resets
    // `_retried`, so a retry that re-entered it re-armed itself and ran every few seconds for
    // ever — which, against a service that was refusing, kept it refusing.
    function _send(texts) {
        root.state = "loading"

        proc.gotFinal = false
        proc.pending = JSON.stringify({
            lines: texts, key: root._key,
            backends: Config.lyricsRomanizeOnline && !root.googleLimited ? ["google", "local"] : ["local"],
            cache: root.cacheEnabled
        })
        // Re-armed before every run: `stdinEnabled: true` is only the INITIAL value and
        // onStarted sets it false, so every run after the first would read EOF
        // (docs/gotchas-system.md).
        proc.stdinEnabled = true
        proc.running = true
    }

    onEnabledChanged: if (!root.enabled) { root._key = ""; root.clear() }
    // Which backends are allowed changed under a finished request: ask again, the disk cache
    // answers what it can. (This one IS a new request, so it goes through load().)
    Connections {
        target: Config
        function onLyricsRomanizeOnlineChanged() {
            if (!root.enabled || root._key === "") return
            const k = root._key
            root._key = ""
            root._memo = ({})
            root.load(k, root.texts)
        }
    }

    Timer {
        id: retryTimer
        interval: 6000
        property string forKey: ""
        onTriggered: {
            if (root._key !== retryTimer.forKey || !root.enabled) return
            root._send(root.texts)
        }
    }

    property Process proc: Process {
        property string pending: ""

        command: ["python3", Quickshell.shellPath("scripts/lyrics-romanize.py")]
        stdinEnabled: true

        // One JSON object per line, and possibly two: a quick local answer first (`final: false`)
        // and Google's better one after it. Each is handled as it arrives, so the first shows
        // while the second is still on its way.
        property bool gotFinal: false
        stdout: SplitParser { onRead: function (line) { proc.handle(line) } }

        onStarted: {
            write(proc.pending)
            stdinEnabled = false
        }

        function handle(line) {
            let d
            try { d = JSON.parse(line) } catch (e) {
                console.warn("LyricsRomanize: could not parse output —", e)
                return
            }
            // Google refused: leave it alone for a while, whoever then answers.
            if (d.google === "limited") { root.googleLimited = true; limitTimer.restart() }

            if (d.final !== false) proc.gotFinal = true

            if (!d.ok) {
                // Nothing to romanize is an answer, not a failure: no retry, no message.
                if (d.none === true) { root.lines = []; root.state = "none"; return }
                root.lastError = d.error || "romanization failed"
                root.installHint = d.install || ""
                root.state = "error"
                // One retry, and only for something a retry can fix — a moment without
                // network. A missing library, or Google refusing us, will not be different
                // in six seconds.
                if (!root._retried && root.installHint === "" && d.google !== "limited") {
                    root._retried = true
                    retryTimer.forKey = root._key
                    retryTimer.restart()
                }
                return
            }

            root._retried = false
            root.backend = d.backend || ""
            root.lastCached = d.cached === true
            // Only the FINAL answer is remembered: a quick one that Google is about to replace
            // would otherwise be what a replay of the track shows.
            if (d.final !== false && root.cacheEnabled)
                root._memo[root._key] = { backend: root.backend, lines: d.lines || [] }

            // State settled BEFORE lines, so a consumer reading hasLines on onLinesChanged does
            // not see "loading" (the same order every lyrics service keeps).
            root.state = (d.lines || []).length > 0 ? "ready" : "none"
            root.lines = d.lines || []
        }

        onExited: {
            // The script ended without a final answer (it died): a provisional one on screen
            // stands, and with nothing on screen that is a failure to say so.
            if (!proc.gotFinal && root.state === "loading") {
                root.lastError = "the romanizer stopped without answering"
                root.state = "error"
            }
        }
    }

    // Counts and states only — never a lyric.
    IpcHandler {
        target: "lyricsromanize"
        function status(): string {
            return "enabled=" + root.enabled + "  script=" + (root.script || "-")
                 + "  romanizable=" + root.romanizable + "  state=" + root.state
                 + "  lines=" + root.lines.length + "  backend=" + (root.backend || "-")
                 + (root.lastError !== "" ? "  error=" + root.lastError : "")
        }
    }
}
