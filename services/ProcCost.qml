pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── ProcCost ──────────────────────────────────────────────────────────────────
// What one window's process tree costs right now — CPU (% of one core) and memory — for the
// overview's window inspector. `pid` is set by whoever shows it (0 = nothing, and nothing
// runs); every `interval` scripts/proc-cost.py measures the tree over half a second. Pids
// come from Hyprland's own record of the window, and reach the script as an integer argument.
//
//     python3 scripts/test-proc-cost.py
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property int pid: 0
    readonly property int interval: 2000

    // The last reading for `pid`; `ok` false until one arrives (or once it's gone).
    property bool ok: false
    property real cpu: 0
    property real rssMb: 0
    property int procs: 0
    property int _for: 0

    onPidChanged: {
        root.ok = false
        if (root.pid > 0) Qt.callLater(root._sample)
    }

    function _sample() {
        if (root.pid <= 0 || sampler.running) return
        root._for = root.pid
        sampler.command = ["python3", Quickshell.shellPath("scripts/proc-cost.py"), String(root.pid)]
        sampler.running = true
    }

    Timer {
        interval: root.interval
        repeat: true
        running: root.pid > 0
        onTriggered: root._sample()
    }

    Process {
        id: sampler
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._for !== root.pid) return
                try {
                    const r = JSON.parse(text)
                    root.ok = r.ok === true
                    if (root.ok) { root.cpu = r.cpu; root.rssMb = r.rssMb; root.procs = r.procs }
                } catch (e) { root.ok = false }
            }
        }
    }

    // "1.2 GB" / "840 MB".
    function memText(mb) { return mb >= 1024 ? (mb / 1024).toFixed(1) + " GB" : Math.round(mb) + " MB" }
}
