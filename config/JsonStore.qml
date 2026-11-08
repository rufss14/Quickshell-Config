import Quickshell.Io
import QtQuick

// ── JsonStore ─────────────────────────────────────────────────────────────────
// One JSON document on disk: read once at startup, written back when it changes.
//
// ── Why this exists ───────────────────────────────────────────────────────────
// Persistence in this shell was three unrelated mechanisms:
//
//   PersistentProperties    Config.qml. Survives a hot RELOAD and nothing else. The
//                           type has no disk I/O at all — it only carries values from
//                           one config generation to the next, in-process. Every
//                           preference in the settings app was lost on restart.
//   FileView + setText      Pins.qml. Correct, but hand-rolled at the call site.
//   five `sh -c` Processes  ColorSchemePanel. `ls | sed` to list, a heredoc to save,
//                           `cat` to load, `rm -f` to delete.
//
// This is the one mechanism. Pins.qml's approach, generalised.
//
// ── It owns its file ──────────────────────────────────────────────────────────
// Nothing else writes the path a store is pointed at. That's why `watchChanges` is
// deliberately NOT set: watching a file we write ourselves turns every save into a
// reload, and a reload that lands back on `value` into another save.
//
// ── Writes are debounced ──────────────────────────────────────────────────────
// A slider drag changes a property every frame. Each change would otherwise be a full
// re-serialise plus a write, so they're coalesced into one write once the value has
// settled.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    // Set once at construction. Re-pointing a live store isn't supported — build a
    // second one instead.
    property string path: ""

    // What `value` holds before the file is read, and what it keeps if there's no file.
    property var defaults: ({})

    // The document. ASSIGN to it — never mutate in place. Same rule as Config.layout,
    // and for the same reason: an in-place mutation fires no change signal, so it is
    // never written and is lost on exit.
    property var value: root.defaults

    // False until the file has been read, or confirmed absent. Writes are refused
    // until then: a save racing the initial read would serialise `defaults` over a
    // perfectly good file and wipe it.
    property bool ready: false

    property int debounceMs: 400

    signal loaded()

    // Force a write now rather than at the end of the debounce — for the cases where
    // the next thing to happen might be process exit.
    //
    // ── Why this blocks ───────────────────────────────────────────────────────
    // A normal save is asynchronous, which is right when the shell is going to be
    // around to finish it. The teardown case is exactly when it won't: an async write
    // queued as the engine is being destroyed has no thread left to land on. So the
    // flush path — and ONLY the flush path — writes synchronously. Leaving
    // `blockWrites` on permanently would stall the UI thread on every slider drag,
    // which is the whole reason the debounce exists.
    function flush() {
        root._debounce.stop()
        if (!root.ready) return

        const wasBlocking = root._file.blockWrites
        root._file.blockWrites = true
        root._write()
        root._file.blockWrites = wasBlocking
    }

    // ── Reload is a teardown ──────────────────────────────────────────────────
    // `Quickshell.reload()` destroys and rebuilds the QML engine IN-PROCESS, so every
    // object here — this store, its FileView, and the 400ms debounce Timer that was
    // about to fire — goes away together. Anything changed inside that last window was
    // silently discarded: load a bar preset and reload within 400ms and the reload
    // genuinely did undo it, because the preset never reached disk.
    //
    // Same pattern NotesWidget already uses for the note you were typing, and for the
    // same reason.
    //
    // Gated on the debounce actually being in flight: a running timer is precisely the
    // "there is a change that hasn't reached disk" state, so an idle store costs a
    // reload nothing.
    Component.onDestruction: if (root._debounce.running) root.flush()

    // ── Internals ─────────────────────────────────────────────────────────────

    // Set while `value` is being assigned FROM disk, so the resulting change signal
    // doesn't immediately schedule a write of what was just read.
    property bool _applying: false

    // A write is waiting on the directory to exist.
    property bool _pendingWrite: false
    property bool _dirReady: false

    readonly property string _dir: {
        const i = root.path.lastIndexOf("/")
        return i > 0 ? root.path.substring(0, i) : ""
    }

    onValueChanged: {
        if (root.ready && !root._applying) root._debounce.restart()
    }

    property Timer _debounce: Timer {
        interval: root.debounceMs
        repeat: false
        onTriggered: root._write()
    }

    function _write() {
        if (!root.ready) return

        // FileView writes a file, not a directory tree, and `presets/` won't exist on
        // a fresh profile. One mkdir, once, on the first write of a store's lifetime —
        // not per save.
        //
        // NOTE: unverified whether FileView creates missing parents itself. If it does,
        // this is redundant rather than wrong, and it's cheap enough to keep as the
        // guarantee.
        if (!root._dirReady && root._dir !== "") {
            root._pendingWrite = true
            root._mkdir.running = true
            return
        }

        root._file.setText(JSON.stringify(root.value, null, 2))
    }

    property Process _mkdir: Process {
        running: false
        command: ["mkdir", "-p", root._dir]
        onExited: function(code) {
            root._dirReady = code === 0
            if (!root._dirReady)
                console.warn("JsonStore: could not create", root._dir, "— exit", code)

            if (root._pendingWrite) {
                root._pendingWrite = false
                if (root._dirReady) root._write()
            }
        }
    }

    property FileView _file: FileView {
        path: root.path
        // REQUIRED. FileView is lazy: without preload it doesn't read until something
        // calls text(), so `onLoaded` never fires on its own and every store silently
        // comes back empty. (Same trap documented in Pins.qml and Colors.qml.)
        preload: true

        // No file yet is the FIRST-RUN state, not a failure. Without this every fresh
        // profile logs a "File does not exist" on startup.
        printErrors: false

        // Write to a temp file and rename over. A crash or a full disk mid-write leaves
        // the previous document intact instead of a truncated one.
        atomicWrites: true

        onLoaded: {
            let parsed
            try {
                parsed = JSON.parse(this.text())
            } catch (e) {
                // ── A corrupt file is not a reason to overwrite it ─────────────
                // These files are hand-editable by design, so "malformed" usually means
                // a typo in something the user wrote, not machine garbage. Staying
                // un-ready means we never write, which keeps whatever is in there
                // recoverable. The alternative — carry on with defaults — would quietly
                // destroy it on the next slider drag.
                console.warn("JsonStore: malformed JSON in", root.path, "—", e)
                console.warn("JsonStore: refusing to write", root.path,
                             "until it parses. Settings will not persist. Fix or delete it.")
                return
            }

            root._applying = true
            root.value = parsed
            root._applying = false

            root._dirReady = true   // the file loaded, so its directory exists
            root.ready = true
            root.loaded()
        }

        // Missing file on first run lands here. So does an unreadable one — that case
        // warns on the failed write rather than here, because there's nothing useful to
        // say until we actually try.
        onLoadFailed: {
            root.ready = true
            root.loaded()
        }

        onSaveFailed: function(error) {
            console.warn("JsonStore: could not write", root.path, "—", error)
        }
    }
}
