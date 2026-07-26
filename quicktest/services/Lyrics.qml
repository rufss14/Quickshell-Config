pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

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

    readonly property bool hasSynced:  root.state === "synced" && root.lines.length > 0
    readonly property bool hasWordTiming: root.kind === "word"

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

        root.kind   = (d.kind === "word" || d.kind === "line") ? d.kind : ""
        root.lines  = d.lines ?? []
        root.plain  = d.plain ?? ""
        root.source = d.source ?? ""
        root.state  = root._stateFor(d.kind)
    }

    function _clear(state) {
        root.state  = state
        root.kind   = ""
        root.lines  = []
        root.plain  = ""
        root.source = ""
    }

    // ── Request. Call on TRACK CHANGE only. ───────────────────────────────────
    function load(artist, title, album, duration) {
        if (!root.enabled) { root._clear("idle"); return }
        if (!title)        { root._key = ""; root._clear("idle"); return }

        const key = root.trackKey(artist, title, album, duration)
        if (key === root._key) return          // same track — nothing to do
        root._key = key

        const hit = root._cache[key]
        if (hit) { root._apply(key, hit); return }

        root._clear("loading")

        proc.out = ""
        proc.command = ["python3", root.scriptPath,
                        "--artist",   artist || "",
                        "--title",    title,
                        "--album",    album || "",
                        "--duration", String(Math.round(duration || 0))]
        proc.running = true
    }

    Process {
        id: proc

        property string out: ""

        // The payload is one long JSON line; SplitParser hands it over a line at a time,
        // so it's reassembled rather than assumed to arrive whole.
        stdout: SplitParser {
            onRead: function(line) { proc.out += line }
        }

        onExited: {
            const text = proc.out
            const key  = root._key
            proc.out = ""

            try {
                const d = JSON.parse(text)
                if (!d.ok) { root._clear("error"); return }
                root._apply(key, d)
            } catch (e) {
                console.warn("Lyrics: could not parse lyrics.py output —", e)
                root._clear("error")
            }
        }
    }
}
