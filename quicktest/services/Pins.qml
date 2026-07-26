pragma Singleton
import Quickshell
import Quickshell.Io
import Qt.labs.platform
import QtQuick

// ── Pins ──────────────────────────────────────────────────────────────────────
// Pinned apps, by desktop-entry id. Shared by the launcher's pin strip and the
// overview's dock — one list, one file, one source of truth.
//
// This lived inside AppLauncherPanel, which meant the overview dock would have
// needed its own copy of both the list and the persistence. It also read and wrote
// the file with subprocesses:
//
//     Process { command: ["cat", pinFile] }                       // read
//     Process { command: ["sh", "-c", "mkdir -p … && echo … > …"] }  // write
//
// FileView does both natively, with no process at all, and watches the file so an
// edit from anywhere is picked up.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property var ids: []

    readonly property string path:
        StandardPaths.writableLocation(StandardPaths.CacheLocation) + "/qs-launcher-pins"

    FileView {
        id: file
        path: root.path

        // REQUIRED: FileView is lazy. Without preload it never reads, `onLoaded`
        // never fires, and the pins silently come back empty every session.
        preload: true
        watchChanges: true
        onFileChanged: reload()

        // No pins file yet is the FIRST-RUN state, not a failure. Without this,
        // every fresh install logs a scary "File does not exist" on startup.
        printErrors: false

        onLoaded: {
            try {
                const parsed = JSON.parse(file.text())
                if (Array.isArray(parsed)) root.ids = parsed
            } catch (e) {
                console.warn("Pins: could not parse", root.path, "—", e)
            }
        }
        // No pins file yet is the normal first-run state, not an error.
        onLoadFailed: root.ids = []
    }

    function isPinned(id) { return id && root.ids.indexOf(id) >= 0 }

    function toggle(id) {
        if (!id) return
        const next = root.ids.slice()
        const i = next.indexOf(id)
        if (i >= 0) next.splice(i, 1)
        else        next.push(id)
        root.ids = next
        root.save()
    }

    function pin(id) {
        if (!id || root.isPinned(id)) return
        root.ids = root.ids.concat([id])
        root.save()
    }

    function unpin(id) {
        if (!root.isPinned(id)) return
        const next = root.ids.slice()
        next.splice(next.indexOf(id), 1)
        root.ids = next
        root.save()
    }

    // Reorder — the dock drags pins around. The list IS the order, so a move is a
    // splice-out then a splice-in.
    //
    // Note the removal happens BEFORE the insert, and `to` is interpreted against
    // the already-shortened list. Computing `to` against the original list and then
    // splicing is the classic off-by-one here: dragging an item rightward lands it
    // one slot short of where it was dropped, every time.
    function move(from, to) {
        const n = root.ids.length
        if (from < 0 || from >= n) return
        const dest = Math.max(0, Math.min(n - 1, to))
        if (dest === from) return

        const next = root.ids.slice()
        const [item] = next.splice(from, 1)
        next.splice(dest, 0, item)
        root.ids = next
        root.save()
    }

    function save() {
        // setText writes through FileView — no `sh -c`, no mkdir dance.
        file.setText(JSON.stringify(root.ids))
    }
}
