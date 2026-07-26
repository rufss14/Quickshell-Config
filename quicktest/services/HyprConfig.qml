pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── HyprConfig ─────────────────────────────────────────────────────────────────
// The user's native-Lua Hyprland config (binds + appearance + input + animations),
// read and edited through scripts/hypr-config.py. See that file for why the source
// of truth is the .lua on disk and not hyprctl (binds report as opaque `__lua`).
//
// ── Refcounted ─────────────────────────────────────────────────────────────────
// Only the Hyprland settings page reads this, and the config doesn't change on a
// timescale that wants a timer — so nothing runs until the page acquires. It also
// watches the three .lua files, so an EXTERNAL hand-edit while the page is open
// refreshes the view (our own writes are ignored for a short window after each, or
// the file-changed event they cause would re-read redundantly).
//
// ── Writes are safe by construction, in the script ─────────────────────────────
// Every write there backs up first and is gated by luac + re-parse + a value check,
// restoring the original on any failure — so this service just relays the result.
// A successful write returns the freshly-parsed config, so state updates without a
// second read. Nothing here touches the LIVE session; apply() runs `hyprctl reload`
// only when the user asks.
Singleton {
    id: root

    readonly property string _script: Quickshell.shellPath("scripts/hypr-config.py")

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    property int _refs: 0
    function acquire() { root._refs++; if (root._refs === 1) root.refresh() }
    function release() { root._refs = Math.max(0, root._refs - 1) }
    readonly property bool active: root._refs > 0

    // ── Parsed state ──────────────────────────────────────────────────────────
    readonly property var  binds:      root._binds        // [{combo, action{}, section, line, editable, …}]
    readonly property var  appearance: root._appearance   // {key: {value, file, line, type}}
    readonly property var  input:      root._input
    readonly property var  animations: root._animations   // [{leaf, enabled, speed, bezier, style, line}]
    readonly property var  meta:       root._meta
    readonly property bool loaded:     root._loaded

    property var  _binds:      []
    property var  _appearance: ({})
    property var  _input:      ({})
    property var  _animations: []
    property var  _meta:       ({})
    property bool _loaded:     false

    // ── Change / apply state ──────────────────────────────────────────────────
    readonly property bool reading:      reader.running
    readonly property bool busy:         writer.running || root._queue.length > 0
    readonly property bool applying:     reloadProc.running
    // A write has landed on disk that the running session hasn't picked up yet.
    readonly property bool pendingApply: root._pendingApply
    readonly property string lastError:  root._lastError
    readonly property bool   canUndo:    root._undo.length > 0

    property bool   _pendingApply: false
    property string _lastError: ""
    property var    _undo: []           // [{file, backup}]

    function clearError() { root._lastError = "" }

    // ── Read ──────────────────────────────────────────────────────────────────
    function refresh() { if (!reader.running) reader.running = true }

    function _applyData(d) {
        if (!d || d.error) { root._lastError = (d && d.error) || "parse error"; return }
        root._binds      = d.binds      || []
        root._appearance = d.appearance || ({})
        root._input      = d.input      || ({})
        root._animations = d.animations || []
        root._meta       = d.meta       || ({})
        root._loaded     = true
    }

    Process {
        id: reader
        running: false
        command: ["python3", root._script, "read"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root._applyData(JSON.parse(text)) }
                catch (e) { root._lastError = "could not read config: " + e }
            }
        }
    }

    // ── Write queue ───────────────────────────────────────────────────────────
    // Discrete edits, one process at a time. Each entry is the full argv tail. A
    // successful write returns {ok, backup, data}; we adopt `data` (no re-read) and
    // remember the backup so it can be undone.
    property var _queue: []

    function _run(args) {
        root._queue = root._queue.concat([args])
        root._pump()
    }
    function _pump() {
        if (writer.running || root._queue.length === 0) return
        const args = root._queue[0]
        root._queue = root._queue.slice(1)
        root._ignoreWatchUntil = Date.now() + 900
        writer.command = ["python3", root._script].concat(args)
        writer.running = true
    }

    Process {
        id: writer
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let res = null
                try { res = JSON.parse(text) } catch (e) { res = { ok: false, error: "" + e } }
                if (res && res.ok) {
                    root._lastError = ""
                    if (res.data) root._applyData(res.data)
                    else root.refresh()
                    root._pendingApply = true
                    if (res.backup) {
                        // Newest first; capped so an editing spree doesn't grow unbounded.
                        root._undo = [{ file: res.file || "", backup: res.backup }]
                            .concat(root._undo).slice(0, 40)
                    }
                } else {
                    root._lastError = (res && res.error) || "write failed"
                }
                root._pump()
            }
        }
        onExited: function(code) { if (code !== 0 && root._lastError === "") root._lastError = "write exited " + code }
    }

    // ── Edit verbs ────────────────────────────────────────────────────────────
    // Thin wrappers over the script's subcommands. `line` comes straight off the
    // parsed record, so the write targets the exact span the view is showing.
    function setValue(file, line, key, type, value) {
        root._run(["set", "--file", file, "--line", "" + line,
                   "--key", key, "--type", type, "--value", "" + value])
    }
    function setAnim(line, field, value) {
        root._run(["anim", "--line", "" + line, "--field", field, "--value", "" + value])
    }
    function rebind(line, combo) {
        root._run(["rebind", "--line", "" + line, "--combo", combo])
    }
    function setAction(line, kind, value, args) {
        const a = ["set-action", "--line", "" + line, "--kind", kind, "--value", value]
        root._run(args ? a.concat(["--args", args]) : a)
    }
    function addBind(combo, kind, value, args) {
        const a = ["add", "--combo", combo, "--kind", kind, "--value", value]
        root._run(args ? a.concat(["--args", args]) : a)
    }
    function removeBind(line) {
        root._run(["remove", "--line", "" + line])
    }

    // ── Undo ──────────────────────────────────────────────────────────────────
    // Restore the newest backup for the most recent write. cp, then re-read; the
    // session then needs a reload just like a forward edit, so pendingApply stays.
    function undo() {
        if (root._undo.length === 0 || undoProc.running) return
        const top = root._undo[0]
        root._undo = root._undo.slice(1)
        const target = root._meta.dir
            ? (root._meta.dir + "/" + top.file)
            : top.file
        root._ignoreWatchUntil = Date.now() + 900
        undoProc.command = ["cp", top.backup, target]
        undoProc.running = true
    }
    Process {
        id: undoProc
        running: false
        onExited: function(code) {
            if (code === 0) { root._pendingApply = true; root.refresh() }
            else root._lastError = "undo failed (" + code + ")"
        }
    }

    // ── Apply to the live session ─────────────────────────────────────────────
    // The one thing that touches the running compositor, and only on demand. A Lua
    // reload re-runs the whole config — fast, and the only way a __lua bind change
    // reaches the session (there is no per-bind hot reload).
    function apply() { if (!reloadProc.running) reloadProc.running = true }

    Process {
        id: reloadProc
        running: false
        command: ["hyprctl", "reload"]
        onExited: function(code) {
            if (code === 0) { root._pendingApply = false; root._lastError = "" }
            else root._lastError = "hyprctl reload failed (" + code + ")"
        }
    }

    // ── Watch for external edits ──────────────────────────────────────────────
    // Our own writes bump _ignoreWatchUntil so the file-changed they cause is a
    // no-op; a hand-edit outside that window refreshes the view.
    property real _ignoreWatchUntil: 0
    function _extChanged() {
        if (Date.now() < root._ignoreWatchUntil) return
        if (root.active) root.refresh()
    }

    FileView {
        path: (root._meta.dir || Quickshell.env("HOME") + "/.config/hypr") + "/binds.lua"
        watchChanges: true
        onFileChanged: root._extChanged()
    }
    FileView {
        path: (root._meta.dir || Quickshell.env("HOME") + "/.config/hypr") + "/theme.lua"
        watchChanges: true
        onFileChanged: root._extChanged()
    }
    FileView {
        path: (root._meta.dir || Quickshell.env("HOME") + "/.config/hypr") + "/core.lua"
        watchChanges: true
        onFileChanged: root._extChanged()
    }
}
