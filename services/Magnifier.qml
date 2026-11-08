pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../config"
import "magnifier.js" as M

// ── Magnifier ─────────────────────────────────────────────────────────────────
// Zoom the whole screen around the pointer: Hyprland's own cursor zoom
// (`cursor:zoom_factor`), stepped by SUPER+CTRL+scroll and toggled by SUPER+CTRL+Z.
// The OSD shows the level while it changes.
//
// The binds post CUSTOM EVENTS (`qs-zoom:in|out|toggle|reset`, hypr/binds.lua) on the
// event socket the shell already reads — Switcher's channel — so a scroll notch costs
// no process start. Each change is EASED here: a few `hyprctl eval` steps through
// log-space (magnifier.js ramp), since Hyprland jumps straight to a new zoom. Only the
// newest target is kept; a step in flight is never queued behind a stale one.
//
// A Hyprland config reload resets the zoom to the config's (1), so it's put back on
// `configreloaded`. Logic: magnifier.js (`bun scripts/test-magnifier.js`).
// `qs ipc -c ~/.config/quicktest call magnifier zoomIn|zoomOut|toggle|reset|status`.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // Where it's headed (what the keys step from), and what Hyprland has now.
    property real level: 1
    property real applied: 1
    property real _last: 2          // the toggle's "back to where I was"
    readonly property bool zoomed: root.level > 1.001

    function zoomIn()  { root.go(M.step(root.level, 1)) }
    function zoomOut() { root.go(M.step(root.level, -1)) }
    function toggle()  { root.go(M.toggle(root.level, root._last)) }
    function reset()   { root.go(1) }

    function go(target) {
        const to = M.clamp(target)
        if (to > 1.001) root._last = to
        root.level = to
        // One step with motion off; otherwise about a fast motion's worth of frames.
        root._queue = M.ramp(root.applied, to, Motion.fast > 0 ? root.steps : 1)
        stepper.restart()
        Osd.announce("magnifier", "\u{F0349}", "Magnifier", M.label(to), M.fraction(to), to <= 1.001)
    }
    readonly property int steps: 5

    property var _queue: []
    Timer {
        id: stepper
        interval: Math.max(1, Math.round(Motion.fast / root.steps))
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root._queue.length === 0) { stepper.stop(); return }
            // A step still in flight: skip this tick rather than stack evals.
            if (evalProc.running) return
            const next = root._queue[0]
            root._queue = root._queue.slice(1)
            root._send(next)
        }
    }

    function _send(z) {
        root.applied = z
        evalProc.command = ["hyprctl", "eval", M.lua(z)]
        evalProc.running = true
    }
    Process {
        id: evalProc
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.warn("Magnifier: hyprctl eval:", text.trim())
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                if (root.zoomed) { root._queue = [root.level]; stepper.restart() }
                return
            }
            if (event.name !== "custom") return
            switch (M.parseEvent(event.data)) {
            case "in":     root.zoomIn(); break
            case "out":    root.zoomOut(); break
            case "toggle": root.toggle(); break
            case "reset":  root.reset(); break
            }
        }
    }

    IpcHandler {
        target: "magnifier"
        function zoomIn(): void { root.zoomIn() }
        function zoomOut(): void { root.zoomOut() }
        function toggle(): void { root.toggle() }
        function reset(): void { root.reset() }
        function status(): string { return "level=" + root.level + " applied=" + root.applied }
    }
}
