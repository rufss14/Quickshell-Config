pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// ── Fullscreen ─────────────────────────────────────────────────────────────────
// "Is a fullscreen window covering monitor X right now?" — so decoration that lives
// BEHIND windows (the desktop audio visualizer) can stop drawing when nothing can
// see it. A fullscreen window is opaque over the whole output, including the bottom
// band CavaBG sits in, so animating 64 bars 60× a second there is pure waste.
//
// ── Why it is split this way ────────────────────────────────────────────────────
// Two facts decide whether a monitor is covered:
//   1. which workspace is active on it, and
//   2. whether THAT workspace holds a fullscreen window.
//
// (1) is native and reactive — `HyprlandMonitor.activeWorkspace` updates itself on
// every workspace switch, so a plain binding tracks it for free and we never spawn
// anything on a workspace change (the most frequent event).
//
// (2) is not exposed as a reactive property — `hasfullscreen` lives only in the
// workspace's IPC record, and workspace IPC objects are not kept fresh. So we ask
// `hyprctl -j workspaces` for the flags, but ONLY when a fullscreen-affecting event
// says they might have changed (a window entering/leaving fullscreen, or one opening,
// closing, or moving). Those are rare; the call is debounced and lightweight. This is
// event-driven, not polling: nothing runs while the window state is still.
//
// The combine (`activeOn`) reads BOTH the native activeWorkspace and `_wsFull`, so a
// binding on it re-evaluates on a workspace switch (native) AND on a fullscreen toggle
// (the requery) — which is exactly the pair of things that change the answer.
Singleton {
    id: root

    // workspaceId → true when that workspace holds a fullscreen window.
    property var _wsFull: ({})

    // Reactive: is monitor `name`'s currently-active workspace fullscreen?
    function activeOn(name) {
        if (!name) return false
        const mons = Hyprland.monitors.values
        for (let i = 0; i < mons.length; i++) {
            if (mons[i].name === name) {
                const wsId = mons[i].activeWorkspace?.id
                return root._wsFull[wsId] === true
            }
        }
        return false
    }

    // ── Requery, debounced ──────────────────────────────────────────────────────
    // Coalesce a burst of events (open + fullscreen arrive together) into one call.
    Timer {
        id: debounce
        interval: 80; repeat: false
        onTriggered: query.running = true
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            case "fullscreen":      // a window entered or left fullscreen
            case "openwindow":      // may open directly into fullscreen
            case "closewindow":     // the fullscreen window may have been closed
            case "movewindowv2":    // moved to another workspace/monitor
                debounce.restart()
            }
        }
    }

    Process {
        id: query
        command: ["hyprctl", "-j", "workspaces"]
        stdout: StdioCollector { id: queryOut }
        onExited: function(code) {
            if (code !== 0) {
                console.warn("Fullscreen: hyprctl workspaces failed (exit " + code + ")")
                return
            }
            try {
                const wss = JSON.parse(queryOut.text)
                const next = ({})
                for (let i = 0; i < wss.length; i++) {
                    if (wss[i].hasfullscreen) next[wss[i].id] = true
                }
                root._wsFull = next
            } catch (e) {
                console.warn("Fullscreen: could not parse workspaces —", e)
            }
        }
    }

    // One read at startup, before any event has had a reason to fire.
    Component.onCompleted: query.running = true
}
