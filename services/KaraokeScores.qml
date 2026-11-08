pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "karaoke.js" as KJ

// ── KaraokeScores ─────────────────────────────────────────────────────────────
// The karaoke game's results, kept per song: the best run, the last, how many times it was
// played, a short history — and the song's album cover, saved locally so the list still has it
// after a player's cache has gone. The rules (what beats what, what a hand-edited file may say)
// are services/karaoke.js (`bun scripts/test-karaoke.js`); this holds the file and the covers.
//
//   record(result, meta)  a finished run into the table → { newBest, previousBest, entry }
//   songs                 the table as a list (most recently played first)
//   summary               songs, plays, and how many songs sit at each rank
//   coverUrl(entry)       where to draw its cover from: the saved copy, else the player's URL
//   remove(key) / clear() forget one song, or all
//
// ── The file ──────────────────────────────────────────────────────────────────
// `statePath("karaoke-scores.json")` and `statePath("karaoke-covers/")`: state, not config, and not
// the repo — these are one person's scores. The document is read back through KJ.sanitize every time
// (a hand-editable file is a trust boundary: numbers are clamped, a rank is re-derived from its
// accuracy and never believed, a URL must be http(s) or a local file).
//
// ── The covers ────────────────────────────────────────────────────────────────
// `curl`, a declared dependency already used by Weather and the news feed, one at a time. Its
// argv is built here with no shell, restricted to http, https and file URLs (a player's art is
// either a CDN address or a local cache file) and never follows a redirect to anything else. A cover
// is named by the song's key (KJ.coverName) and only recorded once curl has succeeded; until then
// the list draws the player's own URL. One that failed is tried again the next time the shell
// starts, never in a loop.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property JsonStore _store: JsonStore {
        id: store
        path: Quickshell.statePath("karaoke-scores.json")
        defaults: ({ songs: ({}) })
        onLoaded: root._refetch()
    }

    // The lines the user marked as not to be sung (right-click on a lyric), per song:
    // statePath("karaoke-skips.json") = { songs: { "artist::title": ["index:words of the line", …] } }, read back
    // through KJ.sanitizeSkips like the scores (a hand-editable file).
    property JsonStore _skipStore: JsonStore {
        path: Quickshell.statePath("karaoke-skips.json")
        defaults: ({ songs: ({}) })
    }
    readonly property var skipDb: KJ.sanitizeSkips(root._skipStore.value)
    function skipsFor(key) { return key !== "" && root.skipDb[key] ? root.skipDb[key] : [] }
    function toggleSkip(key, mark) {
        if (key === "" || mark === "") return
        const marks = KJ.skipToggle(root.skipsFor(key), mark)
        const songs = Object.assign({}, root.skipDb)
        if (marks.length > 0) songs[key] = marks
        else delete songs[key]
        root._skipStore.value = { songs: songs }
    }
    function clearSkips(key) {
        if (key === "" || !root.skipDb[key]) return
        const songs = Object.assign({}, root.skipDb)
        delete songs[key]
        root._skipStore.value = { songs: songs }
    }

    readonly property string coversDir: Quickshell.statePath("karaoke-covers")

    // Every read goes through sanitize; every write is a new document (JsonStore: assign, never mutate).
    readonly property var db: KJ.sanitize(store.value)
    readonly property var songs: KJ.list(root.db, "recent")
    readonly property var summary: KJ.summary(root.db)

    function record(res, meta) {
        const r = KJ.record(root.db, res, meta, Date.now() / 1000)
        if (r.entry === null) return r
        store.value = r.db
        root._want(r.entry)
        return r
    }

    function coverUrl(entry) {
        if (!entry) return ""
        return entry.cover !== "" ? "file://" + root.coversDir + "/" + entry.cover : entry.art
    }

    function remove(key) {
        const e = root.db.songs[key]
        if (!e) return
        store.value = KJ.removeSong(root.db, key)
        root._unlink(e.cover)
    }

    function clear() {
        for (const k of Object.keys(root.db.songs)) root._unlink(root.db.songs[k].cover)
        store.value = KJ.dbNew()
    }

    // ══ Covers ════════════════════════════════════════════════════════════════
    property var _queue: []                // [{ key, name, url }]
    property var _job: null

    function _want(entry) {
        if (entry.art === "" || entry.cover !== "") return
        const name = KJ.coverName(entry.key)
        if (root._queue.some(j => j.key === entry.key) || (root._job && root._job.key === entry.key)) return
        root._queue = root._queue.concat([{ key: entry.key, name: name, url: entry.art }])
        root._pump()
    }

    // Songs on file whose cover never arrived (offline at the time, say): once, at start, a few.
    function _refetch() {
        let n = 0
        for (const k of Object.keys(root.db.songs)) {
            if (n >= 20) break
            const e = root.db.songs[k]
            if (e.art !== "" && e.cover === "") { root._want(e); n++ }
        }
    }

    function _pump() {
        if (fetch.running || root._queue.length === 0) return
        root._job = root._queue[0]
        root._queue = root._queue.slice(1)
        fetch.command = ["curl", "-fsSL", "--max-time", "20",
                         "--proto", "=http,https,file", "--proto-redir", "=http,https",
                         "--create-dirs", "-o", root.coversDir + "/" + root._job.name, root._job.url]
        fetch.running = true
    }

    Process {
        id: fetch
        onExited: function (code) {
            const job = root._job
            root._job = null
            // Recorded only on success, and re-read: the song may have been removed meanwhile.
            if (code === 0 && job) store.value = KJ.withCover(root.db, job.key, job.name)
            root._pump()
        }
    }

    // A forgotten song's cover goes too. The name is only ever one KJ.coverName could have made
    // (sanitize guarantees it), so this cannot be pointed at another file.
    function _unlink(name) {
        if (!/^[0-9a-f]{8}\.img$/.test(name || "")) return
        eraser.command = ["rm", "-f", root.coversDir + "/" + name]
        eraser.running = true
    }
    Process { id: eraser }

    IpcHandler {
        target: "karaokescores"
        function status(): string {
            const s = root.summary
            return "songs=" + s.songs + " plays=" + s.plays + " ranks=" + JSON.stringify(s.ranks)
                 + " queue=" + root._queue.length + " covers=" + root.coversDir
        }
        function clear(): void { root.clear() }
    }
}
