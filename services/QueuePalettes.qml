pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// ── QueuePalettes ─────────────────────────────────────────────────────────────
// Each queued song's own cover palette (bg, accent, fg), so every row of the queue wears its album's colour scheme.
// AlbumArt holds ONE cover at a time (the playing one); a queue has many, so this extracts each distinct cover once with
// the same script (scripts/album-colors.py) and keeps the answer for the session.
//
//   of(url)   the palette for a cover, or null while it is being read. Asking enqueues it; the answer lands in `cache`,
//             which bindings read, so the row repaints when its colours arrive.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    property var cache: ({})          // url → { bg, accent, fg }
    property var _waiting: []
    property string _running: ""

    readonly property string scriptPath:
        Qt.resolvedUrl("../scripts/album-colors.py").toString().replace("file://", "")

    function of(url) {
        const u = String(url || "")
        if (u === "") return null
        if (root.cache[u]) return root.cache[u]
        if (root._running !== u && root._waiting.indexOf(u) < 0) {
            root._waiting = root._waiting.concat([u])
            root._next()
        }
        return null
    }

    function _next() {
        if (proc.running || root._waiting.length === 0) return
        root._running = root._waiting[0]
        root._waiting = root._waiting.slice(1)
        proc.command = ["python3", root.scriptPath, root._running]
        proc.running = true
    }

    property Process _proc: Process {
        id: proc
        property string out: ""
        stdout: SplitParser {
            onRead: function (line) { proc.out += line }
        }
        onExited: {
            const url = root._running
            const text = proc.out
            proc.out = ""
            root._running = ""
            try {
                const d = JSON.parse(text)
                if (d.ok) {
                    const c = Object.assign({}, root.cache)
                    c[url] = { bg: d.bg, accent: d.accent, fg: d.fg }
                    root.cache = c
                }
            } catch (e) {
                console.warn("QueuePalettes: could not read a cover's palette —", e)
            }
            root._next()
        }
    }
}
