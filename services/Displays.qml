pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "displays.js" as D

// ── Displays ──────────────────────────────────────────────────────────────────
// Settings › Displays: read the monitors, apply a new layout, and take it back if you
// don't confirm it.
//
// ── How a layout is applied ───────────────────────────────────────────────────
// Written into the bundled ~/.config/hypr/hardware.lua's monitor block
// (scripts/hypr-monitors.py --write-spec, which validates every field), then
// `hyprctl reload` — the same reload wal-reload.sh runs after every colour change.
// NOT `hyprctl eval 'hl.monitor(…)'`: runtime Lua through eval is only proven safe for
// hl.on / hl.config here, and a runtime hl.bind segfaulted the compositor twice.
//
// ── Keep or revert ────────────────────────────────────────────────────────────
// A mode the screen can't show leaves you looking at nothing. So an applied layout is
// PENDING for `revertAfter` seconds: confirm with keep(), or it writes back the snapshot
// taken just before applying and reloads again — whether or not you can see the prompt.
// (If the shell itself dies mid-countdown the new layout stays; the file is the
// recovery: hypr-monitors.py on a TTY, or edit the block.)
//
// ── A config that isn't ours ──────────────────────────────────────────────────
// With your own Hyprland config (the minimal install's quicktest.lua beside it), there
// is no hardware.lua of ours to write. `editable` is false and the page offers the lines
// to paste instead (copyLines).
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property var monitors: []           // displays.js parseMonitors()
    property bool loaded: false
    property string lastError: ""

    readonly property string hardwarePath:
        (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/hypr/hardware.lua"
    property bool editable: false

    readonly property int revertAfter: 15
    property bool pending: false
    property int secondsLeft: 0
    property var _snapshot: null        // the live spec before the pending apply
    property bool busy: false

    function refresh() {
        listProc.running = false
        listProc.running = true
        ownProbe.running = false
        ownProbe.running = true
    }

    // Apply an edited copy of `monitors`. Refused while one is pending or with a problem.
    function apply(edited) {
        if (root.pending || root.busy) return false
        const why = D.problem(edited)
        if (why !== "") { root.lastError = why; return false }
        if (!root.editable) { root.lastError = "This Hyprland config isn't the bundled one — copy the lines instead"; return false }
        root.lastError = ""
        root._snapshot = D.spec(root.monitors)
        root._write(D.spec(edited), true)
        return true
    }

    function keep() {
        if (!root.pending) return
        countdown.stop()
        root.pending = false
        root._snapshot = null
        root.refresh()
    }

    function revert() {
        if (!root.pending || !root._snapshot) return
        countdown.stop()
        root.pending = false
        root._write(root._snapshot, false)
        root._snapshot = null
    }

    // The lines for a layout, to paste into a config this page doesn't edit.
    function copyLines(edited) {
        printProc._payload = JSON.stringify(D.spec(edited))
        printProc.stdinEnabled = true
        printProc.running = false
        printProc.running = true
    }

    // ── Internals ──────────────────────────────────────────────────────────────
    property string _payload: ""
    property bool _startPending: false
    function _write(spec, startPending) {
        root.busy = true
        root._payload = JSON.stringify(spec)
        root._startPending = startPending
        writeProc.stdinEnabled = true   // re-armed before every start: docs/gotchas-system.md
        writeProc.running = false
        writeProc.running = true
    }

    Process {
        id: listProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.monitors = D.parseMonitors(text)
                root.loaded = true
            }
        }
    }

    // Ours = the bundled hardware.lua with its "── Monitors" section (the line
    // hypr-monitors.py rewrites under).
    Process {
        id: ownProbe
        command: ["grep", "-q", "^-- ── Monitors", root.hardwarePath]
        onExited: function (code) { root.editable = code === 0 }
    }

    Process {
        id: writeProc
        property string out: ""
        command: ["python3", Quickshell.shellPath("scripts/hypr-monitors.py"), "--write-spec", root.hardwarePath]
        stdinEnabled: true
        stdout: SplitParser { onRead: function (line) { writeProc.out += line } }
        onStarted: {
            writeProc.out = ""
            write(root._payload + "\n")
            stdinEnabled = false
        }
        onExited: function (code) {
            let d = null
            try { d = JSON.parse(writeProc.out) } catch (e) {}
            if (code !== 0 || !d || !d.ok) {
                root.busy = false
                root.lastError = (d && d.error) ? d.error : "Couldn't write " + root.hardwarePath
                root._snapshot = null
                return
            }
            reloadProc.running = false
            reloadProc.running = true
        }
    }

    Process {
        id: reloadProc
        command: ["hyprctl", "reload"]
        onExited: function (code) {
            root.busy = false
            if (code !== 0) root.lastError = "hyprctl reload failed"
            if (root._startPending) {
                root.pending = true
                root.secondsLeft = root.revertAfter
                countdown.restart()
            }
            // Let the outputs settle before reading them back.
            reread.restart()
        }
    }
    Timer { id: reread; interval: 800; onTriggered: listProc.running = true }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            root.secondsLeft = Math.max(0, root.secondsLeft - 1)
            if (root.secondsLeft === 0) root.revert()
        }
    }

    Process {
        id: printProc
        property string _payload: ""
        command: ["python3", Quickshell.shellPath("scripts/hypr-monitors.py"), "--print-spec"]
        stdinEnabled: true
        stdout: StdioCollector {
            onStreamFinished: if (text.indexOf("hl.monitor(") !== -1) Clipboard.copyText(text.trim())
        }
        onStarted: {
            write(printProc._payload + "\n")
            stdinEnabled = false
        }
    }
}
