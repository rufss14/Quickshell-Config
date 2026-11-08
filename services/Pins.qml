pragma Singleton
import Quickshell
import Quickshell.Io
import Qt.labs.platform
import QtQuick

// ── Pins ──────────────────────────────────────────────────────────────────────
// Pinned apps, by desktop-entry id. Shared by the launcher's pin strip and both
// docks (through Taskbar) — one list, one file, one source of truth.
//
// "By desktop-entry id" is a rule the dock used to break: it pinned by WINDOW
// CLASS ("Spotify") while the launcher pinned by entry id ("spotify"), so the
// same app could be pinned twice under two keys and each surface failed to
// recognise the other's pins. Taskbar now writes entry ids and migrates the old
// class-keyed pins once — see Taskbar._migratePins.
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

    // True once the file has been read — or found missing, which is the normal
    // first-run state. Taskbar's pin migration waits on this: rewriting the list
    // before the file has answered would overwrite the user's pins with [].
    property bool loaded: false

    // Beside config.json, under XDG_STATE_HOME: pins are the user's own data.
    readonly property string path: Quickshell.statePath("pins.json")

    // ── Where they lived before, and the one-time move ────────────────────────
    // The CACHE dir — which cleaners (and people) are entitled to wipe, taking every
    // pin with it. When the new file doesn't exist yet, the old one is read and
    // written to the new place. The old file is left alone: if the write fails,
    // nothing has been lost, and the next start simply tries again.
    readonly property string legacyPath:
        StandardPaths.writableLocation(StandardPaths.CacheLocation) + "/qs-launcher-pins"

    // The file is hand-editable, so only non-empty strings survive a load.
    function _parse(text, from) {
        try {
            const parsed = JSON.parse(text)
            if (Array.isArray(parsed))
                return parsed.filter(x => typeof x === "string" && x !== "")
        } catch (e) {
            console.warn("Pins: could not parse", from, "—", e)
        }
        return null
    }

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
            const ids = root._parse(file.text(), root.path)
            if (ids !== null) root.ids = ids
            root.loaded = true
        }
        // No pins file yet: either a first run, or pins still in the old place.
        onLoadFailed: legacy.reload()
    }

    FileView {
        id: legacy
        path: root.legacyPath
        preload: false
        printErrors: false

        onLoaded: {
            const ids = root._parse(legacy.text(), root.legacyPath)
            root.ids = ids ?? []
            if (ids !== null && ids.length > 0) root.save()
            root.loaded = true
        }
        // Neither file: the first-run state, not an error.
        onLoadFailed: {
            root.ids = []
            root.loaded = true
        }
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

    // Replace the whole list — the dock's edits (Taskbar.pin/unpin/movePin) and its
    // one-time key migration arrive as a finished list rather than as one step.
    function replace(list) {
        root.ids = list.slice()
        root.save()
    }

    function save() {
        // setText writes through FileView — no `sh -c`, no mkdir dance.
        file.setText(JSON.stringify(root.ids))
    }
}
