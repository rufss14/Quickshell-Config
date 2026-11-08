pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// ── FrameWatch ────────────────────────────────────────────────────────────────
// Says when the shell dropped frames, and what was happening at the time. Off until asked:
// nothing runs while it is, so it costs nothing in normal use.
//
//   qs ipc -c ~/.config/quicktest call framewatch start [thresholdMs]   (default 40)
//   qs ipc -c ~/.config/quicktest call framewatch status
//   qs ipc -c ~/.config/quicktest call framewatch stop
//   qs ipc -c ~/.config/quicktest call framewatch cost [seconds]       (default 5)
//   qs ipc -c ~/.config/quicktest call framewatch costresult
//
// `cost` is the other half: not WHEN a frame was late but what the shell costs while idle — CPU by
// thread (main / render / other), its helper processes, and its own GPU time, measured by
// scripts/shell-cost.py over `seconds` and read back with `costresult`. Same numbers as running that
// script by hand; the IPC form is for a user who is asked "what does it cost for you?".
//
// "Lag after a wallpaper change" is a claim about WHEN: this puts a number and the wave's phase
// on each frame that took longer than the threshold, so a stall can be read against
// `WallWave: go / landed / done` in the same log instead of guessed at. A stall is the MAIN
// thread being blocked (a binding storm, a synchronous load) — the render thread dropping
// frames shows as long frames here too, but without a busy main thread in `lagprobe`'s thread
// breakdown. Counts, times and state names only.
Singleton {
    id: root

    property bool watching: false
    property int thresholdMs: 40
    property int frames: 0
    property int stalls: 0
    property real worstMs: 0
    property double _last: 0

    FrameAnimation {
        running: root.watching
        onTriggered: {
            const now = Date.now()
            if (root._last > 0) root._frame(now - root._last)
            root._last = now
        }
    }

    function _frame(dt) {
        root.frames++
        if (dt < root.thresholdMs) return
        root.stalls++
        root.worstMs = Math.max(root.worstMs, dt)
        console.warn("FrameWatch: " + Math.round(dt) + " ms frame"
                     + " | wave frozen=" + WallWave.frozen + " spreading=" + WallWave.spreading
                     + " holding=" + WallWave.holding + " snap=" + Motion.snap
                     + " | scene=" + WallpaperEngine.phase
                     + " | applying=" + Wallpaper.applying
                     + " | cursor busy=" + Cursor.busy)
    }

    function _reset(ms) {
        root.thresholdMs = ms > 0 ? ms : 40
        root.frames = 0
        root.stalls = 0
        root.worstMs = 0
        root._last = 0
    }

    // ── Idle cost (scripts/shell-cost.py) ─────────────────────────────────────
    property string costText: "no measurement yet — run `framewatch cost`"
    Process {
        id: costProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text)
                    if (!r.ok) { root.costText = "failed: " + r.error; return }
                    const names = o => Object.keys(o).map(k => k + " " + o[k]).join(", ")
                    root.costText = r.seconds + " s: main " + r.gui + "%, render " + r.render + "%, other " + r.other
                        + "%, helpers " + r.helpers + "% (" + names(r.helperNames) + "), gpu "
                        + (r.gpu === null ? "n/a" : r.gpu + "%") + ", rss " + r.rssMb + " MB | threads: " + names(r.threads)
                } catch (e) { root.costText = "failed: unreadable output" }
            }
        }
    }
    function cost(seconds) {
        if (costProc.running) return "already measuring"
        const s = Math.max(1, Math.min(60, seconds > 0 ? seconds : 5))
        costProc.command = ["python3", Quickshell.shellPath("scripts/shell-cost.py"),
                            String(Quickshell.processId), String(s), "--json"]
        root.costText = "measuring for " + s + " s…"
        costProc.running = true
        return root.costText
    }

    IpcHandler {
        target: "framewatch"
        function cost(seconds: int): string { return root.cost(seconds) }
        function costresult(): string { return root.costText }
        function start(thresholdMs: int): string {
            root._reset(thresholdMs)
            root.watching = true
            return "watching frames over " + root.thresholdMs + " ms"
        }
        function stop(): string {
            root.watching = false
            return root.status()
        }
        function status(): string { return root.status() }
    }
    function status() {
        return (root.watching ? "watching" : "off") + ": " + root.frames + " frames, "
             + root.stalls + " over " + root.thresholdMs + " ms, worst "
             + Math.round(root.worstMs) + " ms"
    }
}
