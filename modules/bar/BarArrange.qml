pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../state"

// ── BarArrange ────────────────────────────────────────────────────────────────
// Arrange mode's own furniture, drawn inside the BAR's window: the region labels,
// the region-background drop targets, the shelf of modules that are not on the bar,
// and the ghost that follows the pointer.
//
// The draggable modules themselves are NOT here — they are the real ones, on the
// real bar, made grabbable by BarGroupRow's `slotsArranging`. That is the whole point
// of the mode: you rearrange the bar by moving the bar, not a copy of it.
//
// ── Why this lives in the bar's window and not in settings ────────────────────
// Qt's Drag/DropArea only work within ONE window. Settings is an xdg-toplevel and the
// bar is a layer-shell surface, so a module can never be dragged from one into the
// other — which means the shelf of unplaced modules has to be here, next to the bar,
// or there is no way to put a module onto the bar by dragging at all.
//
// Bar.qml already reserves window height past the bar strip for its panels, for the
// neighbouring reason (one scene graph, so shapes can blend). The shelf is that same
// arrangement: reserved room below the bar, masked in only while it is up.
//
// ── It draws nothing at rest ──────────────────────────────────────────────────
// Everything here is behind `UiState.barArrange`, and Bar.qml keeps the whole thing
// behind a Loader — so a bar that is not being arranged pays for none of it, not even
// the shelf's inert widget copies, which are real bar modules and not cheap.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The three regions, so labels and drop targets can be positioned over them.
    // Passed in rather than found, because only Bar.qml knows which items they are.
    //
    // Named *Item rather than *Region on purpose. Bar.qml's regions carry the ids
    // `leftRegion` / `center` / `rightRegion`, and a property called `leftRegion`
    // here would make the natural `leftRegion: leftRegion` at the call site resolve
    // to THIS property rather than to the outer id — a silent self-assignment that
    // leaves it null, so the labels never appear and nothing says why.
    property Item leftItem:   null
    property Item centreItem: null
    property Item rightItem:  null

    // How tall the bar strip is — everything here positions relative to it.
    property real barHeight: Config.barExtent

    // How to build a module, for the shelf and the ghost. Bar.qml passes its OWN
    // `moduleFor` — the same factory the bar itself renders from — rather than this
    // file importing the settings preview's registry. Two reasons: it keeps the bar
    // from depending on modules/settings, and a shelf built from a second catalogue
    // is a second catalogue to keep in step.
    property var componentFor: null

    // ── The shelf's height ────────────────────────────────────────────────────
    // Passed IN by Bar.qml rather than defined here, because the bar window has to
    // reserve this much room while this component does not yet exist — so the number
    // lives on the Loader. Defining it in both places would be two constants that
    // must agree, and the failure when they drift is a shelf drawn partly outside the
    // window with no clue why.
    //
    // A fixed ceiling rather than a measured height, and never animated: it feeds the
    // window's implicitHeight, and animating that resizes the actual Wayland surface
    // every frame. Same discipline as the window's own ceiling — see Bar.qml.
    property real shelfHeight: 0

    anchors.fill: parent

    // ── The region labels are gone ────────────────────────────────────────────
    // Three captions reading "Left", "Centre", "Right" used to float under the
    // regions. They were removed because they answered a question nobody was asking:
    // the bar is a horizontal strip, so which end is the left end is not information,
    // and the captions still could not say the thing that IS ambiguous — whether the
    // drop under your pointer joins a group or makes a new one.
    //
    // `BarDrag.description` says that instead, in the shelf. See BarDrag.describe().
    //
    // `leftItem`/`centreItem`/`rightItem` are still passed in: the region SPLITS below
    // are computed from their live geometry, which is what makes every horizontal
    // position on the bar belong to exactly one region.

    // ── Region backgrounds as drop targets, ONLY where a region is empty ──────
    // "Put it in this region, as its own group." The one placement that nothing else
    // can express: an empty region has no modules to aim between and no seams to aim
    // into, so without this a region you emptied could never be refilled.
    //
    // ══ These used to cover the WHOLE bar, and that broke dragging entirely ═══
    // The bands were full-height across every region, on the reasoning — written in
    // this file — that "a module and a seam both sit ON this band, and their
    // DropAreas are deeper in the stack so they win."
    //
    // That is false here, and the way it is false is worth stating because it is not
    // visible from either file alone. Bar.qml mounts this whole component in a Loader
    // at `z: 60`, declared AFTER the three BarRegions. Qt delivers a drag to the
    // TOPMOST DropArea that accepts the keys, and z-order beats nesting depth — so
    // the bands were above every slot and every seam on the bar, and swallowed the
    // lot. The symptom was that dragging could only ever change a module's REGION:
    // never its order within a group, never which group it joined, because the two
    // targets that decide those never received a single drag event.
    //
    // Restricting the bands to empty regions removes the overlap instead of trying
    // to out-rank it. A populated region is now governed entirely by its slots (drop
    // between two modules → join that group) and its seams (drop in the gap → a new
    // group), which is what those were always for. Appending to the END of a
    // populated region is still reachable: that is the last group's `seamAfter`.
    //
    // Dropping on the dead space between two populated regions now does nothing and
    // the module returns home. That is the correct trade — a target you cannot see is
    // worse than no target, and the shelf's line says what the pointer is over.
    component ZoneDrop: Item {
        id: band
        property string region: ""

        height: root.barHeight
        y: 0

        readonly property bool regionEmpty: (Config.layout[band.region] ?? []).length === 0

        DropArea {
            id: bandDrop
            anchors.fill: parent
            // Both kinds: the bar's own modules and a module dragged in from the
            // settings window's catalogue. See BarDrag.mime for why an out-of-window
            // drag's key has to be the mime type itself.
            keys: ["barmodule", BarDrag.mime]
            enabled: band.regionEmpty
            onEntered: BarDrag.drop = { kind: "region", region: band.region }
            onExited:  if (BarDrag.drop?.kind === "region"
                        && BarDrag.drop?.region === band.region) BarDrag.drop = null
            onDropped: function (d) {
                const id = BarDrag.idFromDrop(d)
                if (id === "") return
                BarDrag.dropExternal(id, { kind: "region", region: band.region })
                d.acceptProposedAction()
            }
        }

        // Only drawn for an empty region, and only while something is in the air —
        // it is an invitation to drop, so it has nothing to say at rest. A dashed
        // outline rather than a fill: "this region is empty, it can hold something".
        Rectangle {
            anchors.fill: parent
            anchors.margins: Tokens.spacingSm
            visible: band.regionEmpty && BarDrag.dragging
            radius: Tokens.radiusPill
            color: (BarDrag.drop?.kind === "region" && BarDrag.drop?.region === band.region)
                 ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.16) : "transparent"
            border.width: Tokens.borderWidth
            border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.45)
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }
    }

    // The two split points: halfway between left's right edge and centre's left edge,
    // and likewise on the other side. Read off the live region geometry so they track
    // the centre group sliding as the layout changes.
    readonly property real splitLeft: (root.leftItem && root.centreItem)
        ? (root.leftItem.x + root.leftItem.width + root.centreItem.x) / 2
        : root.width / 3
    readonly property real splitRight: (root.centreItem && root.rightItem)
        ? (root.centreItem.x + root.centreItem.width + root.rightItem.x) / 2
        : root.width * 2 / 3

    ZoneDrop { region: "left";   x: 0;               width: root.splitLeft }
    ZoneDrop { region: "centre"; x: root.splitLeft;  width: root.splitRight - root.splitLeft }
    ZoneDrop { region: "right";  x: root.splitRight; width: root.width - root.splitRight }

    // ── Off the bar ───────────────────────────────────────────────────────────
    // The band under the bar. Drag a module down out of the bar and let go, and it
    // comes off — it is then in "Your modules" on the settings page, which is where
    // everything not on your bar lives.
    //
    // ── There is no card here any more, and that is the whole change ──────────
    // This was a raised `Surface` — a shelf — that held every module NOT on the bar
    // as a row of real widgets you could drag up. Then it was the same card with the
    // widgets replaced by a bin glyph. Both were a popup hanging off the bottom of
    // the screen, and a popup is a heavy thing to put on screen for a target you
    // approach maybe twice.
    //
    // So the card is gone and what remains is the ROOM: a bare band, no fill, no
    // border, no icon, that only reports what is about to happen. Dropping in it is
    // "drag it off the bar", which is the gesture people already try — the card was
    // never adding anything to it except the suggestion that it was needed.
    //
    // The band still has to be a real DropArea rather than "anywhere outside the
    // bar": a release over nothing at all has no drop target, and BarDrag.end()
    // correctly treats that as a cancel. Something has to be there to catch it.
    Item {
        id: offBar

        anchors.left:  parent.left
        anchors.right: parent.right
        y: root.barHeight
        height: Math.max(0, root.shelfHeight)

        DropArea {
            id: shelfDrop
            anchors.fill: parent
            keys: ["barmodule", BarDrag.mime]
            onEntered: BarDrag.drop = { kind: "shelf" }
            onExited:  if (BarDrag.drop?.kind === "shelf") BarDrag.drop = null
            onDropped: function (d) {
                const id = BarDrag.idFromDrop(d)
                if (id === "") return
                BarDrag.dropExternal(id, { kind: "shelf" })
                d.acceptProposedAction()
            }
        }

        // A hairline that appears only while the pointer is actually over the band,
        // so there is SOMETHING confirming the boundary was crossed. Not a card: one
        // line, the width of the bar, in the danger colour because what happens next
        // is a removal.
        Rectangle {
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    parent.top
            anchors.leftMargin:  Tokens.spacingXl
            anchors.rightMargin: Tokens.spacingXl
            height: 2
            radius: 1
            visible: shelfDrop.containsDrag
            color: Colors.of(QsWindow.window).danger
        }

        // ── The one line that says what is about to happen ────────────────────
        // At rest it explains the mode. Mid-drag it is taken over by
        // `BarDrag.description`, which names the exact placement under the pointer —
        // "Join the volume group · Left" versus "New group of its own · Left".
        //
        // It is here rather than by the cursor because the ghost is already there —
        // a tooltip under the ghost is a label on top of the thing it labels.
        StyledText {
            anchors.left:  parent.left
            anchors.right: parent.right
            anchors.top:   parent.top
            anchors.leftMargin:  Tokens.spacingXl
            anchors.rightMargin: Tokens.spacingXl
            anchors.topMargin:   Tokens.spacingMd
            horizontalAlignment: Text.AlignHCenter

            text: BarDrag.dragging
                ? BarDrag.description
                : "Drag a module along the bar to reorder it, onto another to group "
                + "them, or down here to take it off"

            variant: "caption"
            // Both branches stated. `emphasis` is what normally decides the colour,
            // and assigning `color` at all replaces that binding wholesale — so a
            // conditional that leaves one branch `undefined` does not fall back to
            // the emphasis, it hands the Text an invalid colour.
            color: BarDrag.drop?.kind === "shelf" ? Colors.of(QsWindow.window).danger
                 : BarDrag.dragging               ? Colors.of(QsWindow.window).focus
                 :                                  Colors.of(QsWindow.window).fgDim
            elide: Text.ElideRight
        }
    }

    // ── There is no ghost any more ────────────────────────────────────────────
    // An Item followed `BarDrag.dragPos`, carried the scene-graph `Drag`, and drew a
    // copy of the module under the cursor. All three jobs are gone:
    //
    //   · The DRAG is now a platform QDrag started by the slot itself
    //     (BarGroupRow's dragProxy), because that is the only kind that can leave a
    //     layer-shell surface and reach the settings window.
    //   · The IMAGE is drawn by Qt from `Drag.imageSource` — a live grab of the real
    //     module, taken on press. It follows the pointer across window boundaries,
    //     which a scene-graph item inside this window could never do.
    //   · The POSITION cannot be tracked here any more even in principle: during a
    //     QDrag the platform holds the pointer grab, so the MouseArea stops receiving
    //     move events and a hand-driven ghost would freeze in place mid-gesture.
    //
    // `componentFor` is still passed in from Bar.qml — nothing here builds a module
    // now, but the property is cheap and the next thing that needs one will want it.
}
