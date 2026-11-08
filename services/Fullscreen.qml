pragma Singleton
import Quickshell
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
// (2) is native too: `HyprlandWorkspace.hasFullscreen`, a notifying property.
// Quickshell sets it on the focused workspace straight from the `fullscreen` event,
// and on EVERY tracked workspace from the `hasfullscreen` field of a `j/workspaces`
// answer — it requests one itself on each `fullscreen` event. We ask for one more,
// debounced, on the events that can change the answer without that event reliably
// arriving (a window opening, closing, or moving). Read in the installed build's own
// source, not assumed: wayland/hyprland/ipc/connection.cpp and workspace.cpp under
// /usr/src/debug/quickshell-git.
//
// It used to be `hyprctl -j workspaces` in a Process, parsed here, from when the flag
// lived only in the IPC record. Hyprland.refreshWorkspaces() is that same request over
// the socket Quickshell already holds — no subprocess — and the answer lands as a
// property change instead of JSON. Still event-driven, not polling: nothing runs while
// the window state is still.
//
// ── The combine is PUSHED, not pulled ───────────────────────────────────────────
// `activeOn()` used to do the combining itself, and callers bound straight to the
// function call — `suppressed: Fullscreen.activeOn(screen.name)`. That produced a real
// "Binding loop detected for property suppressed" at runtime (CavaBG.qml:50), because a
// binding that CALLS a function captures whatever that function happens to touch:
// `Hyprland.monitors` and the lazily-maintained `activeWorkspace` objects behind it,
// which can notify while the binding is still evaluating and re-enter it.
//
// So the combining moved in here and became a plain, notifying property — `byMonitor`,
// a monitor name → bool map recomputed on the events that change the answer. Callers now
// bind to a value instead of to a function call, which is what makes the loop impossible
// rather than merely unlikely: there is no longer any model traversal happening inside
// somebody else's binding.
//
// `activeOn()` survives as a pure lookup into that map (no traversal, no lazy model
// access), so existing call sites keep working and stay safe to bind to.
//
// NOTE this was necessary but not sufficient, and the loop outlived it. CavaBG's
// binding had a SECOND re-entrant dependency that had nothing to do with this service:
// the window's own `screen` property, which re-notifies on map/unmap while that same
// window's `visible` is derived from the binding's result. See CavaBG.qml — a consumer
// binding to byMonitor still has to keep window-lifecycle properties out of the
// expression.
Singleton {
    id: root

    // monitor name → true when THAT monitor's active workspace holds a fullscreen window.
    readonly property var byMonitor: root._byMonitor
    property var _byMonitor: ({})

    // Is monitor `name`'s currently-active workspace fullscreen? A map lookup — safe to
    // call from a binding, because it reads one plain property and nothing else.
    function activeOn(name) {
        return name ? root._byMonitor[name] === true : false
    }

    // ── The combine ─────────────────────────────────────────────────────────────
    // Folds the two facts together: which workspace each monitor is showing and
    // whether that workspace holds a fullscreen window — both native, both read off
    // Hyprland.monitors here. Called from signal handlers only — never from a binding.
    function _recombine() {
        const next = ({})
        const mons = Hyprland.monitors.values
        for (let i = 0; i < mons.length; i++) {
            if (mons[i].activeWorkspace?.hasFullscreen === true) next[mons[i].name] = true
        }
        root._byMonitor = next
    }

    // ── Watching the flag ───────────────────────────────────────────────────────
    // One Connections per tracked workspace, so the flag flipping on ANY of them —
    // including one no monitor is showing yet — recombines. A workspace created with a
    // fullscreen window already in it never CHANGES the flag (it arrives true), so a
    // workspace coming or going recombines too.
    Instantiator {
        model: Hyprland.workspaces
        delegate: Connections {
            required property var modelData
            target: modelData
            function onHasFullscreenChanged() { root._recombine() }
        }
        onObjectAdded:   root._recombine()
        onObjectRemoved: root._recombine()
    }

    // ── Refresh, debounced ──────────────────────────────────────────────────────
    // Coalesce a burst of events (open + fullscreen arrive together) into one request.
    // The answer arrives as hasFullscreenChanged on whichever workspaces moved.
    Timer {
        id: debounce
        interval: 80; repeat: false
        onTriggered: Hyprland.refreshWorkspaces()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            // ── The fullscreen FLAGS may have changed → refresh ────────────────
            // The recombine follows from hasFullscreenChanged once the answer lands.
            case "fullscreen":      // a window entered or left fullscreen
            case "openwindow":      // may open directly into fullscreen
            case "closewindow":     // the fullscreen window may have been closed
            case "movewindowv2":    // moved to another workspace/monitor
                debounce.restart()
                return

            // ── Which workspace a monitor SHOWS may have changed → recombine ───
            // No refresh needed: the fullscreen flags are unchanged, only the
            // monitor→workspace mapping is, and that is already native and fresh in
            // Hyprland.monitors. This is the half that used to come for free from
            // binding to activeOn() and now has to be asked for explicitly — the
            // price of not traversing the model inside somebody else's binding.
            case "workspace":
            case "workspacev2":
            case "focusedmon":
            case "focusedmonv2":
            case "moveworkspace":
            case "moveworkspacev2":
            case "monitoradded":
            case "monitoraddedv2":
            case "monitorremoved":
                root._recombine()
                return
            }
        }
    }

    // One read at startup, before any event has had a reason to fire. It can land before
    // Hyprland.monitors has populated, in which case byMonitor is briefly empty — which
    // reads as "nothing is fullscreen", the safe way to be wrong (decoration draws when it
    // needn't, rather than staying hidden). The first workspace or monitor event corrects it.
    Component.onCompleted: {
        Hyprland.refreshWorkspaces()
        root._recombine()
    }
}
