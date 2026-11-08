pragma Singleton

import Quickshell
import Quickshell.Hyprland
import QtQuick

// ── ActiveWindow ──────────────────────────────────────────────────────────────
// "What window is this screen about right now", for the focused-window module on the
// bar and the sidebar: its title, its app (icon, name, key), and the facts its panel
// acts on (floating, fullscreen, pinned).
//
// ── Per monitor, not just "the focused window" ────────────────────────────────
// With two screens, the bar on the one you are NOT using should still name what is on
// it, not mirror the other screen's window. So for each monitor: the focused window if
// it is on that monitor, else the most recently focused window on that monitor's
// active workspace (an MRU kept here, from Hyprland's own activeToplevel pushes), else
// nothing (an empty workspace).
//
// `byMonitor` is a plain notifying map the modules bind to — never a function walking
// Hyprland's lazy models from a binding (CLAUDE.md: CavaBG.suppressed's binding loop).
// Everything here is event-driven; nothing polls.
//
// Actions go through Hyprland.dispatch with the Lua dispatchers, addressed by window
// (docs/gotchas-system.md: the legacy spelling silently does nothing on this Hyprland).
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // address → sequence of its last focus, newest highest.
    property var _seq: ({})
    property int _top: 0

    function _touch(t) {
        if (!t || !t.address) return
        const next = Object.assign({}, root._seq)
        next[t.address] = ++root._top
        root._seq = next
    }

    Connections {
        target: Hyprland
        function onActiveToplevelChanged() { root._touch(Hyprland.activeToplevel) }
    }
    Component.onCompleted: root._touch(Hyprland.activeToplevel)

    // monitor name → { address, title, appId, key, name, icon, floating, fullscreen,
    //                   pinned, workspace }, or absent for an empty workspace.
    readonly property var byMonitor: {
        const seq = root._seq
        const active = Hyprland.activeToplevel
        const mons = Hyprland.monitors.values
        const tops = Hyprland.toplevels.values
        const out = {}
        for (let i = 0; i < mons.length; i++) {
            const m = mons[i]
            const ws = m.activeWorkspace
            if (!ws) continue
            let best = null, bestSeq = -1
            for (let j = 0; j < tops.length; j++) {
                const t = tops[j]
                if (!t.workspace || t.workspace.id !== ws.id) continue
                if (active && t === active) { best = t; break }
                const s = seq[t.address] ?? 0
                if (s > bestSeq) { best = t; bestSeq = s }
            }
            if (best) out[m.name] = root._describe(best)
        }
        return out
    }

    function _describe(t) {
        // `class` by bracket: a reserved word. A Wayland client names itself by appId.
        const ipc = t.lastIpcObject
        // `?? ""` on both: a window that has mapped but not yet named itself has an undefined appId, and every
        // consumer binds this to a string.
        const appId = (t.wayland ? t.wayland.appId : (ipc ? ipc["class"] : "")) ?? ""
        const key = Taskbar.keyFor(appId)
        return {
            address:    t.address ?? "",
            title:      t.title || "",
            appId:      appId,
            key:        key,
            name:       key ? Taskbar.nameFor(key) : appId,
            icon:       key ? Taskbar.iconFor(key) : "",
            floating:   !!(ipc && ipc.floating),
            fullscreen: !!(ipc && ipc.fullscreen && ipc.fullscreen > 0),
            pinned:     !!(ipc && ipc.pinned),
            workspace:  t.workspace ? t.workspace.id : 0
        }
    }

    // ── Actions on a window, by address ───────────────────────────────────────
    // Every selector through Hypr.addr(), the one place an address is normalised.
    function _sel(address) { return `{ window = "address:${Hypr.addr(address)}" }` }
    function focus(address)            { Hypr.focusWindow(address) }
    function toggleFloating(address)   { Hyprland.dispatch(`hl.dsp.window.float(${root._sel(address)})`) }
    function toggleFullscreen(address) { Hyprland.dispatch(`hl.dsp.window.fullscreen(${root._sel(address)})`) }
    function togglePin(address)        { Hyprland.dispatch(`hl.dsp.window.pin(${root._sel(address)})`) }
    function center(address)           { Hyprland.dispatch(`hl.dsp.window.center(${root._sel(address)})`) }
    function close(address)            { Hypr.closeWindow(address) }
    // Force-quit: the client is killed, not asked (a hung one ignores close). The table form
    // as close/float take it; 0.56's binary lists window.kill (not yet run from here).
    function kill(address)             { Hyprland.dispatch(`hl.dsp.window.kill(${root._sel(address)})`) }
    function toWorkspace(address, id) { Hypr.moveWindowToWorkspace(address, id) }
}
