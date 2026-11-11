pragma Singleton

import Quickshell
import QtQuick
import "../config"

// ── BarDrag ───────────────────────────────────────────────────────────────────
// The drag currently in flight on the bar, while it is in arrange mode.
//
// ── Why a singleton rather than properties on the overlay ─────────────────────
// Three objects have to agree about one gesture: the SLOT you picked up (inside
// BarGroupRow, which is a Repeater nested two deep in a BarGroup inside a
// BarRegion), the drop targets (also slots, and the region backgrounds), and the
// ghost that follows the pointer (drawn by BarArrange, which must paint above
// everything and so is a sibling of all of them).
//
// Threading that through as properties and signals meant six signals crossing
// BarGroupRow, which is a shared component the settings preview also builds — so it
// would have grown an arrange-mode API it has no business knowing about. One piece
// of transient state that all three read is smaller and does not leak.
//
// It is in state/ beside UiState for the same reason UiState is: this is what the
// UI is DOING right now, never persisted, and meaningless across a restart.
//
// ══ The drag is a PLATFORM drag, and that is the whole architecture ═══════════
// `Drag.dragType: Drag.Automatic` — a real QDrag, routed by the compositor over
// wl_data_device — rather than the scene-graph drag Qt does inside one window.
//
// It has to be. The bar is a layer-shell surface and Settings is an ordinary
// xdg-toplevel; a scene-graph drag cannot cross between them, which is why adding a
// module used to be a CLICK that dropped it at a guessed position, and why removing
// one needed a shelf hanging off the bottom of the bar. Both were workarounds for a
// limit that turns out not to apply on this path.
//
// MEASURED before being relied on, in both directions, because neither the docs nor
// training data settle whether a wlr-layer-shell surface can take part in platform
// DnD at all:
//   app window → layer surface   `LAYER enter`, `LAYER drop`
//   layer surface → app window   `REVERSE ARRIVED`, dragFinished = Qt.MoveAction
//
// Two consequences worth knowing before editing anything here:
//   · `Drag.keys` does NOT survive the compositor. For a drag arriving from outside
//     the window, a DropArea matches its `keys` against the drag's MIME FORMATS —
//     so the key has to be a real mime type. See `mime` below.
//   · Qt draws the drag image itself, from `Drag.imageSource`. Nothing tracks the
//     pointer any more: during a QDrag the platform holds the grab, so MouseAreas
//     stop receiving move events entirely.
//
// ── The three rules this file used to open with ───────────────────────────────
// They were about the scene-graph drag and are now structurally impossible rather
// than merely avoided, which is a better place to be. Recorded because the reasoning
// is still live if anyone reintroduces an internal drag anywhere in the shell:
//
//   1. Never bind Drag.active to a MouseArea's drag.active — releasing clears it,
//      firing every onExited and clearing the drop target BEFORE onReleased.
//      NOW: binding it is the only way to START an automatic drag, and it is safe,
//      because the drop arrives as its own event carrying its own position.
//   2. Read the drop target before tearing the drag down.
//      NOW: no shared target has to survive to a release — each DropArea computes
//      the placement in its own onDropped, from the event.
//   3. Commit on release only. Config.layout is a JS array the bar Repeaters over,
//      so every write rebuilds every delegate; committing per-frame would destroy
//      the widget holding the mouse grab mid-gesture.
//      STILL TRUE, and still obeyed — `commit()` runs from onDropped and nowhere
//      else. This one is not obsolete, it is the reason `drop` is only ever used to
//      draw indicators.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── The gesture itself is ModuleDrag's (2026-11-08) ───────────────────────
    // One drag for both surfaces, so a module picked up on the sidebar can land here.
    // These mirror it for the bar's readers. `dragging` is true only for a module the
    // bar can take — one with a bar form — so the seams and empty-region zones don't
    // open for a drag that would be refused on drop. Start and end a drag through
    // ModuleDrag.begin / end; only `drop` is written here.
    readonly property string dragId: ModuleDrag.dragId
    readonly property bool dragging: ModuleDrag.dragging && Config.moduleInfo(ModuleDrag.dragId) !== null

    // (`dragPos`, `dragSize`, `pressPos` and `threshold` lived here, tracking the
    // pointer so an overlay could draw a ghost under it. All four are gone with the
    // ghost: during a platform QDrag the compositor holds the pointer grab, so the
    // MouseArea receives no move events and there is nothing to track. Qt draws the
    // drag image itself from `Drag.imageSource`.)

    // Where the pointer currently is, as a destination, or null when over nothing.
    // Written by the drop targets on enter/exit.
    //
    //   { kind: "chip",   owner, region, group, index }
    //   { kind: "gap",    region, groupIndex }
    //   { kind: "region", region }
    //   { kind: "shelf" }
    //
    // ── Purely for DRAWING now ────────────────────────────────────────────────
    // It used to be the commit's input: the last target written before the mouse
    // released. It is not any more — each DropArea computes the placement itself in
    // `onDropped`, from the drop event's own position. What this still feeds is the
    // feedback: the insertion bar, the hollow seam outline, the empty-region
    // highlight and the description line.
    //
    // That matters if you are tempted to remove it: a stale or missing `drop` no
    // longer breaks a placement, it just makes the bar stop showing you where the
    // module will land.
    property var drop: null
    // A DropArea that lit up for a module the bar can't take (its containsDrag still
    // tracks the mime) mustn't draw an indicator for it; nor may one outlive the drag.
    onDropChanged: if (root.drop !== null && !root.dragging && ModuleDrag.dragging) root.drop = null
    property Connections _end: Connections {
        target: ModuleDrag
        function onDraggingChanged() { if (!ModuleDrag.dragging) root.drop = null }
    }

    // "Move to the bar" before the placement, when it comes from the sidebar.
    function _across() { return Config.sidebarPlaced(root.dragId) ? "Move to the bar  ·  " : "" }

    // ── What the current drop would actually DO, in words ─────────────────────
    // The indicators say WHERE — a line between two modules, an outline in a seam,
    // a tinted region. What they cannot say is which of the four kinds of placement
    // that is, and the difference matters: dropping between two modules of a group
    // JOINS that group, while dropping two pixels further left in the seam makes a
    // NEW group. Those produce visibly different bars and the gesture that picks
    // between them is a few pixels of pointer travel.
    //
    // Three shapes were tried in the head before this one. Labelling the regions
    // (the "Left / Centre / Right" captions) named the place but never the action.
    // A tooltip by the cursor sits under the ghost, which is the one thing already
    // following the pointer. A caption per target would be twenty-odd captions
    // flickering on and off across the bar.
    //
    // So it is ONE line, in the shelf, which is the only fixed piece of arrange-mode
    // furniture and is already where your eye goes when you pick something up.
    //
    // A module id rather than a label, deliberately: `Config.moduleList` has proper
    // names, but the thing on screen next to the pointer is the WIDGET, and "join
    // the volume group" next to a pill you recognise as the volume pill is a
    // stronger match than the catalogue's "Volume".
    function describe() {
        if (!root.dragging) return ""

        const d = root.drop
        if (!d) return "Drop it back on the bar, or on the shelf to take it off"

        switch (d.kind) {
            case "chip": {
                const group = (Config.layout[d.region] ?? [])[d.group] ?? []
                // The group it would join, named by whatever else is in it. A group
                // of one is named by that one; a bigger group by its first member
                // plus a count, because listing four ids is longer than the line.
                const others = group.filter(function (x) { return x !== root.dragId })
                const naming = others.length === 0 ? "an empty group"
                             : others.length === 1 ? others[0]
                             : others[0] + " +" + (others.length - 1)
                return root._across() + "Join the " + naming + " group  ·  " + Config.regionLabel(d.region)
            }
            case "gap":
                return root._across() + "New group of its own  ·  " + Config.regionLabel(d.region)
            case "region":
                return root._across() + "New group at the end  ·  " + Config.regionLabel(d.region)
            case "shelf":
                // Named by where it ENDS UP, not by what is lost. "Take it off the
                // bar" describes a deletion; the module is not deleted, it goes back
                // to the catalogue on the settings page, and saying so is the
                // difference between a gesture that feels reversible and one that
                // does not.
                return "Move it back to Your modules"
        }
        return ""
    }

    // Recomputed whenever the gesture changes. A plain function is not a binding
    // dependency — `drop` and `dragging` are — so the consumers bind to THIS and the
    // line updates as the pointer sweeps, rather than being evaluated once when the
    // shelf was built and then never again.
    readonly property string description: {
        // Touched so the binding re-runs. Reading them inside describe() is not
        // enough: QML tracks dependencies captured during evaluation of the binding
        // expression itself, and a function call made from it does register its own
        // property reads — but only for properties it actually reaches on that pass.
        // `drop` being null short-circuits before `dragging` is read, so the binding
        // would stop tracking one of the two inputs exactly when it matters.
        void root.drop
        void root.dragging
        return root.describe()
    }

    // ── The MIME type an out-of-window drag carries ───────────────────────────
    // Settings is an ordinary application window and the bar is a layer-shell
    // surface, so a module dragged from the settings page's catalogue onto the bar
    // is a PLATFORM drag — a real QDrag routed by the compositor over
    // wl_data_device — not the scene-graph drag the bar uses internally.
    //
    // Measured before being relied on (scratchpad probe, app window → layer surface):
    // `LAYER enter` then `LAYER drop`. Neither the docs nor training data settle
    // whether a wlr-layer-shell surface can be a drop target, and this repo has been
    // bitten by assuming API behaviour before.
    //
    // ── Why a mime type and not `Drag.keys` ───────────────────────────────────
    // `Drag.keys` is a scene-graph concept and does not survive the trip through the
    // compositor. For a drag arriving from outside the window, a DropArea matches its
    // `keys` against the drag's MIME FORMATS instead — so the key IS the mime type,
    // and it has to be a real one. Vendor-prefixed so nothing else on the desktop can
    // be mistaken for a bar module.
    //
    // One mime for every module drag now (ModuleDrag.mime, 2026-11-08); this mirrors it.
    readonly property string mime: ModuleDrag.mime

    // The module id carried by an incoming platform drag, or "" if it isn't one of
    // ours or has no bar form. Called from the bar's drop handlers, which read the id
    // off the drop event itself rather than trusting `dragId`.
    function idFromDrop(d) {
        const id = ModuleDrag.idFromDrop(d)
        return Config.moduleInfo(id) ? id : ""
    }

    // ── The one place a placement is applied ──────────────────────────────────
    // Split out of end() so an incoming platform drag commits through exactly the
    // same four cases. Two copies of this switch is two places for "drop into a
    // group" to mean something subtly different depending on which window you
    // started the gesture in.
    function commit(id, target) {
        if (!id || !target) return false

        switch (target.kind) {
            case "chip":   Config.moveIntoGroup(id, target.region, target.group, target.index); break
            case "gap":    Config.moveToOwnGroup(id, target.region, target.groupIndex);         break
            case "region": Config.moveToOwnGroup(id, target.region,
                                                 (Config.layout[target.region] ?? []).length);  break
            // Off whichever surface it is on (a sidebar module dropped on the shelf too).
            case "shelf":  Config.placeModule(id, "");                                          break
            default:       return false
        }
        return true
    }

    // (`end()` lived here — called from the slot's onReleased, it read `drop` and
    // committed. It is gone because there is no longer a mouse release to call it
    // from: a platform drag ends when the compositor delivers the drop, and every
    // DropArea now commits in its own `onDropped` with a target it computed from the
    // drop event itself. That is strictly better — the target no longer has to
    // survive in shared state from the last onEntered until a release somewhere
    // else, which is what rules 1 and 2 above were entirely about.)

    // A drag was released on a target. Commits and then clears, because nothing here
    // saw a mouse release to clear it for us — for a drag from the settings window
    // the press, travel and release all belong to that window, and even for one that
    // started on the bar the platform owns the gesture from the threshold onward.
    function dropExternal(id, target) {
        const ok = root.commit(id, target)
        root.drop = null
        ModuleDrag.end()
        return ok
    }

    // Dropped without a target, or the mode was left mid-gesture. Clears without
    // committing — used when arrange mode ends under an active drag, which would
    // otherwise leave `dragId` set and the next entry into the mode already dragging.
    function cancel() {
        root.drop = null
        ModuleDrag.end()
    }
}
