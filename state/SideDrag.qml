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
// It had its own mime once, so neither surface lit up for the other's modules. Since
// 2026-11-08 the gesture is ModuleDrag's (one mime, one dragId) and a module dragged
// off the bar can land here and the reverse; this keeps only the sidebar's targets,
// wording and commit, and Config's mutators take a module off the bar as it lands.
//
// Targets, as `drop` (drawing only) and as what a DropArea commits:
//   { kind: "chip",   owner, region, group, index }   into a group, at index
//   { kind: "gap",    region, groupIndex }            a group of its own, there
//   { kind: "region", region }                        into an empty region
//   { kind: "off" }                                   off the sidebar
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // Mirrors of ModuleDrag (start and end a drag there). `dragging` only for a module
    // with a sidebar form, so no zone opens for a drag that would be refused.
    readonly property string dragId: ModuleDrag.dragId
    readonly property bool dragging: ModuleDrag.dragging && Config.sidebarModuleInfo(ModuleDrag.dragId) !== null
    property var drop: null
    onDropChanged: if (root.drop !== null && !root.dragging && ModuleDrag.dragging) root.drop = null
    property Connections _end: Connections {
        target: ModuleDrag
        function onDraggingChanged() { if (!ModuleDrag.dragging) root.drop = null }
    }

    readonly property string mime: ModuleDrag.mime

    function idFromDrop(d) {
        const id = ModuleDrag.idFromDrop(d)
        return Config.sidebarModuleInfo(id) ? id : ""
    }

    function _across() { return Config.isPlaced(root.dragId) ? "Move to the sidebar  ·  " : "" }

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
            const naming = others.length === 0 ? "its own"
                         : others.length === 1 ? "the " + root._label(others[0])
                         : "the " + root._label(others[0]) + " +" + (others.length - 1)
            return root._across() + "Join " + naming + " group  ·  " + where
        }
        case "gap":    return root._across() + "A group of its own  ·  " + where
        case "region": return root._across() + "A group of its own  ·  " + where
        case "off":    return "Take it off — it waits in Settings › Bar › Modules"
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
        // Off whichever surface it is on (a bar module dropped on the off band too).
        case "off":    Config.placeModule(id, "");                                                break
        default:       return false
        }
        return true
    }

    function dropExternal(id, target) {
        const ok = root.commit(id, target)
        root.drop = null
        ModuleDrag.end()
        return ok
    }

    function cancel() {
        root.drop = null
        ModuleDrag.end()
    }
}
