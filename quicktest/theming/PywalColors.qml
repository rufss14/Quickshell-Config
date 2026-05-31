pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── PywalColors ───────────────────────────────────────────────────────────────
// Reads ~/.cache/wal/colors.json on startup and re-reads it automatically
// whenever pywal regenerates it (via inotifywait).
// Exposes: PywalColors.data  →  the parsed JSON object
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property var    data:   ({})
    property string _buf:   ""

    // ── Load / reload ─────────────────────────────────────────────────────────
    function reload() {
        _buf = ""
        pywalLoader.running = false
        pywalLoader.running = true
    }

    // ── Initial load + reload trigger ─────────────────────────────────────────
    Process {
        id: pywalLoader
        running: true
        command: ["cat", Quickshell.env("HOME") + "/.cache/wal/colors.json"]

        stdout: SplitParser {
            splitMarker: ""   // empty = deliver each chunk as-is
            onRead: function(chunk) {
                root._buf += chunk
            }
        }

        onExited: function(exitCode) {
            if (exitCode !== 0 || !root._buf) {
                console.warn("PywalColors: could not read colors.json (exit " + exitCode + ")")
                return
            }
            try {
                root.data = JSON.parse(root._buf)
                console.log("PywalColors: palette loaded")
            } catch (e) {
                console.warn("PywalColors: JSON parse error —", e)
            }
        }
    }

    // ── File watcher — triggers reload whenever wal writes colors.json ────────
    Process {
        id: colorWatcher
        running: true
        command: [
            "inotifywait",
            "--quiet",
            "--monitor",
            "--event", "close_write",
            Quickshell.env("HOME") + "/.cache/wal/colors.json"
        ]

        stdout: SplitParser {
            onRead: function(line) {
                if (line.trim().length > 0) {
                    console.log("PywalColors: change detected, reloading…")
                    root.reload()
                }
            }
        }
    }
}
