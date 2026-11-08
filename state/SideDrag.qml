pragma Singleton

import Quickshell
import QtQuick
import "../config"

// ── SideDrag ──────────────────────────────────────────────────────────────────
// The drag in flight while the SIDEBAR is being arranged — BarDrag's twin, for the
// edge the bar doesn't own. Everything BarDrag's header says holds here: it is a
// PLATFORM drag (`Drag.Automatic`, a real QDrag the compositor routes), so a module
// can travel between the settings window and the sidebar's layer surface in either
// direction; `Drag.keys` doesn't survive that trip, so the key IS a mime type; each
// DropArea commits in its own `onDropped`, from the event; and nothing commits
// before the drop, because a layout write rebuilds what's holding the gesture.
//
// Its own singleton and its own mime rather than BarDrag with a flag: a top-bar
// module dropped on the sidebar (or the reverse) has nowhere to go — the sidebar's
// catalogue is sidebar modules only (the user's call) — and a separate mime means
// neither surface's drop targets ever light up for the other's modules.
//
// Targets, as `drop` (drawing only) and as what a DropArea commits:
//   { kind: "chip",   owner, region, group, index }   into a group, at index
//   { kind: "gap",    region, groupIndex }            a group of its own, there
//   { kind: "region", region }                        into an empty region
//   { kind: "off" }                                   off the sidebar
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property string dragId: ""
    property bool dragging: false
    property var drop: null

    readonly property string mime: "application/x-quickshell-sidemodule"

    function idFromDrop(d) {
        if (!d || !d.formats || d.formats.indexOf(root.mime) === -1) return ""
        const id = d.getDataAsString(root.mime)
        return Config.sidebarModuleInfo(id) ? id : ""
    }

    function _label(id) { return Config.sidebarModuleInfo(id)?.label ?? id }

    // What the drop under the pointer would DO, in words — the one line arranging
    // shows beside the sidebar (BarDrag.describe's reasoning: the indicators say
    // where, this says which of the placements that is).
    function describe() {
        if (!root.dragging) return ""
        const d = root.drop
        if (!d) return "Drop it on the sidebar, or out here to take it off"
        const where = Config.sidebarRegionLabel(d.region ?? "")
        switch (d.kind) {
        case "chip": {
            const group = (Config.sidebarLayout[d.region] ?? [])[d.group] ?? []
            const others = group.filter(x => x !== root.dragId)
            // The dock never shares a group: that drop lands beside it (Config).
            if (!Config.sidebarIsSmall(root.dragId) || others.some(x => !Config.sidebarIsSmall(x)))
                return "A group of its own, beside it  ·  " + where
            const naming = others.length === 0 ? "its own"
                         : others.length === 1 ? "the " + root._label(others[0])
                         : "the " + root._label(others[0]) + " +" + (others.length - 1)
            return "Join " + naming + " group  ·  " + where
        }
        case "gap":    return "A group of its own  ·  " + where
        case "region": return "A group of its own  ·  " + where
        case "off":    return "Take it off the sidebar — it waits in Settings › Sidebar"
        }
        return ""
    }
    readonly property string description: {
        void root.drop
        void root.dragging
        return root.describe()
    }

    // The one place a placement is applied.
    function commit(id, target) {
        if (!id || !target) return false
        switch (target.kind) {
        case "chip":   Config.sidebarMoveIntoGroup(id, target.region, target.group, target.index); break
        case "gap":    Config.sidebarMoveToOwnGroup(id, target.region, target.groupIndex);         break
        case "region": Config.sidebarMoveToOwnGroup(id, target.region,
                                                    (Config.sidebarLayout[target.region] ?? []).length); break
        case "off":    Config.sidebarRemove(id);                                                  break
        default:       return false
        }
        return true
    }

    function dropExternal(id, target) {
        const ok = root.commit(id, target)
        root.drop     = null
        root.dragging = false
        root.dragId   = ""
        return ok
    }

    function cancel() {
        root.dragging = false
        root.dragId   = ""
        root.drop     = null
    }
}
