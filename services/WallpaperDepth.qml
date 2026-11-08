pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "depthink.js" as DepthInk

// ── WallpaperDepth ────────────────────────────────────────────────────────────
// The depth clock's data: for a wallpaper, the cutout that goes in front of the clock, and where
// the clock goes. WallpaperView draws it (wallpaper → clock → cutout); this only produces and
// remembers it.
//
// The work is scripts/wallpaper-depth.py, run in a private Python environment (scripts/
// wallpaper-depth-setup.sh builds it — Python 3.13, rembg + onnxruntime, two models, ~1 GB, nothing
// system-wide). A wallpaper takes ~30 s on the CPU the first time and is instant after: results
// are cached in the cache dir by path and by the screen's shape. One job at a time, so a wallpaper
// browse doesn't run the models in parallel.
//
//   entryFor(path, aspect)   null until known, then { state: "ready"|"none"|"failed", cutout, x, y,
//                            luma } — reading it asks for the job, so a binding is all a view needs.
//                            "none" still has x, y and luma: the clock is drawn, with nothing over it.
//   waiting(path, aspect)    asked for and not answered yet (the "analysing" state)
//   place(path, x, y) / unplace(path)   the clock somewhere of the user's choosing / back to automatic
//   blocker()                why it can't run, or ""   (the pattern Discord.pressBlocker set)
//   install()                build the environment; progress in `installNote`
//
// ── Where things live ─────────────────────────────────────────────────────────
// $XDG_DATA_HOME/quicktest/depth   the environment and models (kept — they are big)
// $XDG_CACHE_HOME/quickshell-quicktest/depth   the cutouts (can be wiped; they are rebuilt)
//
// ── Remembered across restarts ────────────────────────────────────────────────
// Every answer is also written to `index.json` in the cache dir (a moment after it changes), and
// read back at start. Without it each reload began with the clock in its "analysing" state — a
// python process per wallpaper to be told what the last run already knew — and the clock waited,
// breathing, for ~25 ms to ~1 s before it rose. With it the clock rises at once from the index.
// What the index cannot know is that a wallpaper was edited in place under the same path: its mask
// is then stale until the cache dir is cleared (the script notices by mtime, but nothing asks it).
// A mask whose FILE is gone is caught — `stale()` — so a wiped cache dir heals itself.
//
// ── The whole library ─────────────────────────────────────────────────────────
// With Config.wallDepthPrepare the wallpapers are analysed ahead, one at a time, at the lowest CPU
// priority and only when nothing the user is looking at is waiting. A cached wallpaper answers in
// ~25 ms, so after the first pass this is a quick walk, and a pick finds its cutout waiting.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string dataDir:
        (Quickshell.env("XDG_DATA_HOME") || ((Quickshell.env("HOME") || "") + "/.local/share")) + "/quicktest/depth"
    readonly property string cacheDir:
        (Quickshell.env("XDG_CACHE_HOME") || ((Quickshell.env("HOME") || "") + "/.cache")) + "/quickshell-quicktest/depth"

    // ── Is it set up, and can it be? ──────────────────────────────────────────
    // `checked` keeps "not looked yet" from reading as "not installed" in the first second.
    property bool checked: false
    property bool ready: false
    property bool hasUv: true
    function recheck() { probe.running = true }
    Component.onCompleted: root.recheck()
    Process {
        id: probe
        command: ["sh", "-c", "test -f \"$1/ready\" && echo ready; command -v uv >/dev/null && echo uv", "sh", root.dataDir]
        stdout: StdioCollector {
            onStreamFinished: {
                root.ready = text.indexOf("ready") >= 0
                root.hasUv = text.indexOf("uv") >= 0
                root.checked = true
            }
        }
    }

    // For the control that turns this on: "" when it can work, else why not.
    function blocker() {
        if (!root.checked) return "Checking…"
        if (root.installing) return "Setting up…"
        if (!root.ready) return root.hasUv ? "Tap to set up (one-time download, about 1 GB)" : "Needs uv (pacman -S uv)"
        return ""
    }

    // ── Setup ─────────────────────────────────────────────────────────────────
    property bool installing: false
    property string installNote: ""
    function install() {
        if (root.installing || !root.hasUv) return
        root.installing = true
        root.installNote = "Starting…"
        setup.running = true
    }
    Process {
        id: setup
        command: ["bash", Quickshell.shellPath("scripts/wallpaper-depth-setup.sh"), root.dataDir]
        stdout: SplitParser {
            onRead: function (line) { if (line.indexOf(":: ") === 0) root.installNote = line.slice(3) }
        }
        stderr: StdioCollector { id: setupErr }
        onExited: function (code) {
            root.installing = false
            if (code === 0) {
                root.installNote = ""
            } else {
                const said = setupErr.text.split(/[\r\n]+/).filter(s => s.trim() !== "")
                root.installNote = "Setup failed" + (said.length ? ": " + said[said.length - 1] : "")
                console.warn("WallpaperDepth: setup exited", code, said.slice(-3).join(" | "))
            }
            root.recheck()
        }
    }

    // ── The cutouts ───────────────────────────────────────────────────────────
    // path|aspect|clock → entry. Replaced whole on a change so a binding that read it re-runs.
    property var entries: ({})
    property var _queue: []          // jobs waiting, each { key, path, aspect, clock, bg }
    property var _wanted: ({})

    // The clock as the script is asked for it: "" for the automatic spot, else "x,y".
    function _clockOf(path) {
        const p = Config.wallDepthPlaces[path]
        return (p && p.length === 2) ? Number(p[0]).toFixed(3) + "," + Number(p[1]).toFixed(3) : ""
    }
    function _key(path, aspect, clock) { return path + "|" + Number(aspect).toFixed(3) + "|" + clock }
    function _set(key, entry) {
        const next = Object.assign({}, root.entries)
        next[key] = entry
        root.entries = next
        root._dirty()
    }

    // ── The index ─────────────────────────────────────────────────────────────
    // Only answers worth keeping: a "failed" or a wait is not. `fmt` guards against an index
    // written by another version of the entries' shape.
    readonly property int _indexVersion: 2
    // The mask format the script writes now (FORMAT in scripts/wallpaper-depth.py; test-wallpaper-depth.py
    // fails if the two drift). An entry made under another format is not trusted: its mask is of the old
    // quality, and nothing would ever ask the script again.
    readonly property int formatWanted: 5
    property bool _indexLoaded: false
    function _dirty() { saveIndex.restart() }
    Timer {
        id: saveIndex
        interval: 2000
        onTriggered: {
            if (!root._indexLoaded || !root._dirReady) return
            const keep = {}
            for (const k of Object.keys(root.entries)) {
                const e = root.entries[k]
                if (e && (e.state === "ready" || e.state === "none")) keep[k] = e
            }
            indexFile.setText(JSON.stringify({ v: root._indexVersion, entries: keep }))
        }
    }
    // The cache dir may not exist yet (the script makes it on its first run).
    property bool _dirReady: false
    Process {
        running: true
        command: ["mkdir", "-p", root.cacheDir]
        onExited: function (code) { root._dirReady = code === 0 }
    }
    FileView {
        id: indexFile
        path: root.cacheDir + "/index.json"
        preload: true
        atomicWrites: true
        printErrors: false      // absent on the first run
        onLoaded: {
            try {
                const doc = JSON.parse(indexFile.text())
                if (doc && doc.v === root._indexVersion && doc.entries) root._adopt(doc.entries)
            } catch (e) { console.warn("WallpaperDepth: the index is unreadable, starting empty") }
            root._indexLoaded = true
        }
        onLoadFailed: root._indexLoaded = true
    }
    // What was remembered fills in only what this run has not already been told.
    function _adopt(saved) {
        const next = Object.assign({}, root.entries)
        for (const k of Object.keys(saved)) {
            if (next[k]) continue
            if (saved[k] && saved[k].fmt !== root.formatWanted) continue
            next[k] = saved[k]
            root._wanted[k] = true
        }
        root.entries = next
    }

    function entryFor(path, aspect) {
        if (path === "" || !(aspect > 0)) return null
        const clock = root._clockOf(path)
        const key = root._key(path, aspect, clock)
        const e = root.entries[key]
        if (e) return e
        // Not asked for yet. Queued from a binding's evaluation, so deferred — a binding must not write.
        if (root.ready && Config.wallDepth && !root._wanted[key]) {
            root._wanted[key] = true
            Qt.callLater(root._enqueue, { key: key, path: path, aspect: aspect, clock: clock, bg: false })
        }
        return null
    }
    // An answer whose mask turned out to be missing (the cache was cleaned under a running shell):
    // forgotten, so the next ask makes it again. Once per answer — a file that never comes must not loop.
    property var _retried: ({})
    function stale(path, aspect) {
        const key = root._key(path, aspect, root._clockOf(path))
        if (root._retried[key]) return
        root._retried[key] = true
        const next = Object.assign({}, root.entries)
        delete next[key]
        root.entries = next
        delete root._wanted[key]
        root._dirty()
    }

    // Asked for, and no answer yet. Reads `entries`, so a binding follows the answer.
    function waiting(path, aspect) {
        if (!root.ready || !Config.wallDepth || path === "" || !(aspect > 0)) return false
        return root.entries[root._key(path, aspect, root._clockOf(path))] === undefined
    }

    function _enqueue(job) {
        // A job the user is waiting for goes before the background ones. A placement that is
        // superseded before it ran (the clock was dropped twice) is not worth a second of CPU.
        const stale = j => !j.bg && !job.bg && j.path === job.path && j.aspect === job.aspect
        // Forgotten as asked-for, or placing the clock back there later would wait for ever.
        for (const j of root._queue) if (stale(j)) delete root._wanted[j.key]
        const q = root._queue.filter(j => !stale(j))
        if (job.bg) q.push(job)
        else        q.splice(q.findIndex(j => j.bg) < 0 ? q.length : q.findIndex(j => j.bg), 0, job)
        root._queue = q
        root._next()
    }

    // ── The text colour ───────────────────────────────────────────────────────
    // `luma` is how light the picture is behind the clock. The palette gives a PREFERENCE: "auto"
    // is its darker end for a pale picture and its lighter end for a dark one, whichever way the
    // scheme runs (a dark scheme over a pale wallpaper needs dark text); the other two are the
    // user's pick of one role. What comes back is the first of those that reaches `target`:1 over the
    // picture's measured brightness, else the best of them pushed toward black or white by as little
    // as it takes (services/depthink.js) — so no palette and no picture can leave the time unreadable.
    // 3.5 suits the huge time (WCAG's large-text 3:1, with room), 4.5 the small date.
    // `roles` is the asking window's palette (Colors.of(QsWindow.window)): this is a service, and
    // each screen wears its own. The view and the placer's preview both ask here, so they agree.
    function ink(roles, luma, target) {
        let list
        if (Config.wallDepthInk === "primary")   list = [roles.primary]
        else if (Config.wallDepthInk === "text") list = [roles.fg]
        else {
            const baseDarker = roles.base.hslLightness < roles.fg.hslLightness
            list = ((luma > 0.5) === baseDarker) ? [roles.base, roles.fg] : [roles.fg, roles.base]
        }
        const c = DepthInk.pick(list, luma, target ?? 3.5)
        // Handed back as it came when the palette's own colour reads (a QML color, exactly).
        for (const own of list) if (own === c) return own
        return Qt.rgba(c.r, c.g, c.b, 1)
    }

    // ── Placing it ────────────────────────────────────────────────────────────
    function place(path, x, y) {
        const next = Object.assign({}, Config.wallDepthPlaces)
        next[path] = [Math.round(x * 1000) / 1000, Math.round(y * 1000) / 1000]
        Config.wallDepthPlaces = next
    }
    function unplace(path) {
        if (Config.wallDepthPlaces[path] === undefined) return
        const next = Object.assign({}, Config.wallDepthPlaces)
        delete next[path]
        Config.wallDepthPlaces = next
    }

    // ── The library, ahead of time ────────────────────────────────────────────
    readonly property bool _prepareWanted: Config.wallDepth && Config.wallDepthPrepare && root.ready
    property int bgTotal: 0
    property int bgDone: 0
    readonly property bool preparing: root.bgTotal > root.bgDone
    on_PrepareWantedChanged: root._planPrepare()
    Connections {
        target: Wallpaper
        function onWallpapersChanged() { if (root._prepareWanted) root._planPrepare() }
    }
    function _aspects() {
        const seen = {}
        for (const s of Quickshell.screens)
            if (s.width > 0 && s.height > 0) seen[(s.width / s.height).toFixed(3)] = true
        return Object.keys(seen).map(Number)
    }
    function _planPrepare() {
        root._queue = root._queue.filter(j => !j.bg)
        root.bgTotal = 0
        root.bgDone = 0
        if (!root._prepareWanted) return
        const aspects = root._aspects()
        const jobs = []
        for (const p of Wallpaper.wallpapers) {
            if (!/\.(png|jpe?g|webp|bmp)$/i.test(p)) continue
            // The ones already on a screen's way are the first job's business.
            for (const a of aspects) jobs.push({ key: "", path: p, aspect: a, clock: root._clockOf(p), bg: true })
        }
        root.bgTotal = jobs.length
        root._queue = root._queue.concat(jobs)
        root._next()
    }

    function _next() {
        if (run.running || root._queue.length === 0) return
        // Not while a game holds the machine.
        if (root._queue[0].bg && Gamemode.active) { gameRetry.restart(); return }
        const job = root._queue[0]
        root._queue = root._queue.slice(1)
        run.key = job.key
        run.bg = job.bg
        const cmd = [root.dataDir + "/venv/bin/python", Quickshell.shellPath("scripts/wallpaper-depth.py"),
                     job.path, "--cache", root.cacheDir, "--models", root.dataDir + "/models",
                     "--aspect", job.aspect.toFixed(3)]
        if (job.clock !== "") cmd.push("--clock", job.clock)
        run.command = job.bg ? ["nice", "-n", "19"].concat(cmd) : cmd
        run.running = true
    }
    Timer { id: gameRetry; interval: 60000; onTriggered: root._next() }

    Process {
        id: run
        property string key: ""      // the job that is running, for a run that said nothing
        property bool bg: false
        // The answer names its own job (the stream can close after the exit, when `key` already
        // belongs to the next one).
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null
                try { r = JSON.parse(text.trim().split("\n").pop()) } catch (e) { r = null }
                if (!r || r.image === undefined) return
                const key = root._key(r.image, r.aspect, r.clock ?? "")
                // The library pass only warms the cache: what a screen shows it asks for itself.
                if (root._wanted[key] !== true) return
                if (r.state === "ready" && r.cutout) root._set(key, { state: "ready", fmt: r.fmt, cutout: r.cutout, x: r.x, y: r.y, luma: r.luma ?? 0.5 })
                else if (r.state === "none")         root._set(key, { state: "none", fmt: r.fmt, x: r.x, y: r.y, luma: r.luma ?? 0.5 })
            }
        }
        stderr: StdioCollector { id: runErr }
        onExited: function (code) {
            if (run.bg) root.bgDone = Math.min(root.bgTotal, root.bgDone + 1)
            if (code !== 0) {
                console.warn("WallpaperDepth: wallpaper-depth.py exited", code, runErr.text.trim().split("\n").slice(-2).join(" | "))
                // Settled as failed, so it isn't asked for again on every binding.
                if (!run.bg) root._set(run.key, { state: "failed" })
            }
            root._next()
        }
    }
}
