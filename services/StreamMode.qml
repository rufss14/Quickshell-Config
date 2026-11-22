pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import QtQuick
import "../config"
import "streammode.js" as Logic

// ── StreamMode ────────────────────────────────────────────────────────────────
// Hide parts of the shell from screen capture while the monitor shows everything.
//
// ── When it is on ─────────────────────────────────────────────────────────────
//   active = (Config.streamMode (the manual switch, persisted) || live) && !Config.streamOff
//   live   = an app is capturing the screen right now (PipeWire, streammode.js)
//   Config.streamOff = the user turned it off from the pill; remembered across shell loads, so a
//   later stream does not switch it back on behind their back. Turning it on by hand clears it.
// Detection is DERIVED, never written back to Config: nothing to un-set when the
// capture ends, and a shell reload mid-stream finds the capture still running and
// carries on. `live` drops only after `graceMs` of no capture, so a portal screenshot
// or a stream that reconnects doesn't flap the rules.
//
// ── How it hides ──────────────────────────────────────────────────────────────
// Hyprland layer rules with `no_screen_share` (notifications, overview) are DEFINED in
// hypr/rules.lua, switched off, and kept in _G.qs_stream. This flips them with one
// `hyprctl eval` (streammode.js). It never defines anything at runtime — that has
// crashed Hyprland before. Capture that bypasses the compositor (OBS KMS, gpu-screen-
// recorder KMS, a capture card) is not covered.
//
// ── Re-applied, because the compositor forgets ────────────────────────────────
//   · on shell start / reload — set_enabled is idempotent
//   · on a Hyprland config reload — that re-runs rules.lua and every rule starts OFF,
//     while Config.streamMode still says on
//
// `rules` records whether the block is in the user's rules.lua at all: published
// config, so the answer is probed, not assumed, and the tooltip says so rather than
// claiming a hiding that is not happening.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Who is capturing ──────────────────────────────────────────────────────
    // Without a tracker the registry is empty (Audio's note); this one is ours so the
    // detection doesn't depend on Audio having been touched.
    PwObjectTracker { objects: Pipewire.nodes?.values ?? [] }

    readonly property var _nodes: Pipewire.nodes?.values ?? []
    // PwNodes of the apps capturing the screen, one per app.
    readonly property var sources: {
        const nodes = root._nodes
        return Logic.capturers(nodes.map(n => ({ id: n.id, p: n.properties ?? ({}) })))
                    .map(i => nodes[i])
    }
    // The one the pill names and draws (a stream by two apps shows the first).
    readonly property var sourceNode: root.sources.length > 0 ? root.sources[0] : null
    readonly property string sourceLabel: root.sourceNode ? Audio.labelFor(root.sourceNode) : ""

    readonly property int graceMs: 4000
    property bool live: false
    readonly property bool _capturing: root.sources.length > 0
    on_CapturingChanged: {
        if (root._capturing) { graceTimer.stop(); root.live = true }
        else graceTimer.restart()
    }
    Timer { id: graceTimer; interval: root.graceMs; onTriggered: root.live = false }
    Component.onCompleted: { root.live = root._capturing; root._sync() }

    // ── Turned off ────────────────────────────────────────────────────────────
    // The pill's click: hiding off while the capture runs on (you need to show a notification, or
    // a menu). Persisted (Config.streamOff): the choice outlives the capture and the shell, until
    // the user clicks again or turns stream mode on by hand. The pill stays while a capture runs,
    // struck through, so a stream never starts with hiding off unseen.
    readonly property bool suspended: Config.streamOff
    function toggleSuspend() { Config.streamOff = !Config.streamOff }

    readonly property bool active: (Config.streamMode || root.live) && !Config.streamOff

    // "unknown" until the first apply answers; then "ok" or "missing".
    property string rules: "unknown"

    readonly property string statusText: Logic.status(root.active, root.rules, root.suspended)

    function toggle() {
        Config.streamMode = !Config.streamMode
        if (Config.streamMode) Config.streamOff = false
    }

    // Text the shell itself draws and that must not reach a viewer: a clipboard entry, a
    // place name. It reads "Hidden" on YOUR screen too (a compositor rule is the only thing
    // that can differ per viewer, and it blacks out whole surfaces); pause from the pill to read it. Compositor rules can't hide these (they sit inside the bar's own
    // surface), so the views ask. Reads `active`, so a binding that calls this re-runs
    // when stream mode turns on, off, or is paused.
    function mask(text) { return Logic.mask(text, root.active, Translation.tr("Hidden")) }

    onActiveChanged: root._sync()

    function _sync() {
        if (applyProc.running) return              // onExited re-checks the wish
        applyProc.wanted = root.active
        applyProc.command = ["hyprctl", "eval", Logic.lua(root.active)]
        applyProc.running = true
    }

    Process {
        id: applyProc
        property bool wanted: false
        stdout: StdioCollector { id: applyOut }
        onExited: function (code) {
            const bad = Logic.failed(code, applyOut.text)
            root.rules = bad ? "missing" : "ok"
            if (bad && applyProc.wanted)
                console.warn("StreamMode: hyprctl eval failed -", applyOut.text.trim())
            if (applyProc.wanted !== root.active) root._sync()
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") root._sync()
        }
    }
}
