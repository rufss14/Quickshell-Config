pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
// BarDrag — the in-flight drag, shared with the arrange overlay and the shelf.
import "../../state"

// ── BarGroupRow ───────────────────────────────────────────────────────────────
// Walks one region of Config.layout and builds its groups. Everything structural
// about rendering a layout lives here: which group draws a divider, which one is at a
// screen edge and may not overflow it, and how a group's modules become widgets.
//
// It exists because there are now TWO things that render the bar — the bar, and the
// settings page's preview of it — and the second one must not be an approximation of
// the first. A preview drawn by different code is a preview that drifts: it'd keep
// showing dividers where the bar stopped drawing them, and you'd trust it right up
// until it lied.
//
// The callers differ only in what a module DOES, never in how the layout is shaped.
// So the shape is here, and the behaviour arrives as functions:
//
//   componentFor(id)     → the Component to build for a module. Required.
//   moduleVisible(id)    → may this module hide itself? (the tray, when empty)
//   slotsClickable       → preview mode: widgets go inert, slots emit slotClicked
//
// The optional one defaults to "yes", which is exactly right for a preview:
// nothing in it should vanish — a preview
// that hides the tray because your real tray is empty is showing you a bar you can't
// reconcile with the chips you just dragged.
// ─────────────────────────────────────────────────────────────────────────────
Repeater {
    id: root

    required property string region

    property var componentFor:  null
    property var moduleVisible: null

    // ── Preview mode ──────────────────────────────────────────────────────────
    // On: each slot's widget is DISABLED and an overlay above it reports clicks
    // through `slotClicked`. Off (the bar): the widget is live and the overlay is dead.
    //
    // The two must swap together, and that's the point of doing it here rather than in
    // the preview. Leaving the widgets enabled would mean right-clicking the preview's
    // visualizer ran the real handler and swapped the real spectrum for media controls —
    // the actual behaviour, fired at a copy. And the obvious alternative, an
    // `enabled: false` wrapper with a separate hit-layer floating over the top, can't
    // work: positioning that layer needs mapToItem, and mapToItem inside a binding never
    // re-evaluates — its position reads happen in C++ and don't notify. It would track
    // the layout exactly once and then silently stop.
    property bool slotsClickable: false

    signal slotClicked(string id)

    // ── Arrange mode ──────────────────────────────────────────────────────────
    // On the REAL bar, while the Bar settings page is open. Each slot becomes both a
    // drag source and a drop target, so the bar you are looking at is the bar you are
    // editing — see UiState.barArrange for why this cannot be done from the settings
    // window instead.
    //
    // Like `slotsClickable` it disables the live widget, and for the same reason: a
    // press has to reach the slot's own handler rather than toggling the thing you
    // grabbed. Both flags are honoured together so the settings preview (clickable,
    // never draggable) is unaffected.
    //
    // State goes through the BarDrag singleton rather than signals out of here. This
    // component is shared with the settings preview, and an arrange-mode API on it
    // would be six signals that only one of its two callers can ever use.
    property bool slotsArranging: false

    // (`dragSpace` lived here — the coordinate space drag positions were mapped into
    // so the hand-drawn ghost could travel between regions. Both are gone: the drag
    // is a platform QDrag now and Qt draws its own image, so nothing maps a pointer
    // position and there is no space to map it into. Removed rather than left as an
    // ignored property, because a property that is still set at three call sites and
    // read at none is a thing the next reader has to disprove.)

    model: Config.layout[root.region] ?? []

    BarGroup {
        id: barGroup
        required property int index
        required property var modelData          // the group: an array of module ids

        // Whether anything in this group wants to be on the bar right now. BarGroup
        // owns the actual show/hide, animating a collapse rather than popping — a
        // self-hiding module (the DND bell, the empty tray) is its own single-module
        // group, so the group IS the unit that appears and disappears.
        shown: {
            if (!root.moduleVisible) return true
            for (const id of barGroup.modelData) if (root.moduleVisible(id)) return true
            return false
        }


        Repeater {
            model: barGroup.modelData

            Item {
                id: slot
                required property int    index
                required property string modelData

                // Row only ever manages the X axis (same reason a Column's children can
                // set x/anchors.horizontalCenter freely) — left alone, every slot sits
                // at y=0, i.e. flush with the TOP of the row. Slots differ in height
                // (a label-driven pill like KeyboardPill's "US" isn't the same box as
                // a glyph-driven one), so without this each module lands at a
                // different visual height instead of on one shared centreline.
                //
                // Guarded because a Repeater clears a delegate's parent BEFORE its
                // bindings are torn down: without it, every rebuild of the bar's
                // modules logged "Cannot read property 'verticalCenter' of null".
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined

                visible: root.moduleVisible ? root.moduleVisible(slot.modelData) : true

                // ── Gap before this slot ────────────────────────────────────────
                // contentRow's own spacing is 0 now (BarGroup.qml) — every gap is
                // reserved here instead, so it can vary. Two neighbours that BOTH
                // opted out of the inner pill have no shared background to read as
                // a cluster, so the full inter-module gap left them looking merely
                // scattered rather than deliberately bare; tighten just that pair.
                // Anything else (either side has a pill, or this is index 0) keeps
                // the normal gap.
                readonly property int gapBefore: {
                    if (slot.index === 0) return 0
                    // A group with a custom spacing (module inspector) puts the whole
                    // gap into each member's OWN padding instead — see
                    // Config.groupSpacing and IconButton.spacing — so the reserved gap
                    // here would just be added on top of that.
                    if (Config.groupSpacing(slot.modelData) >= 0) return 0
                    const prevId = barGroup.modelData[slot.index - 1]
                    const bothBare = !Config.moduleInnerPill(prevId)
                                   && !Config.moduleInnerPill(slot.modelData)
                    return bothBare ? Tokens.spacingXs : Tokens.spacingMd
                }

                implicitWidth:  widget.implicitWidth + gapBefore
                implicitHeight: widget.implicitHeight

                // ── The entrance (state/Intro) ──────────────────────────────────
                // Where this pill sits along the whole bar, 0 (left end) → 1 (right
                // end): its region's third, then its group's share of that, then its
                // place in the group. Intro staggers the pills by it, so they fade in
                // left to right across all three regions as one sweep. Counted, not
                // measured: mapToItem in a binding never re-evaluates.
                readonly property real introPos: {
                    const r = ({ left: 0, centre: 1, right: 2 })[root.region] ?? 0
                    const n = Math.max(1, barGroup.modelData.length)
                    const g = Math.max(1, root.count)
                    return (r + (barGroup.index + (slot.index + 0.5) / n) / g) / 3
                }
                readonly property real introIn: Intro.pill(slot.introPos)

                // Right-anchored: the reserved gap is empty space on the LEFT of the
                // slot, so the widget itself still sits flush against whatever comes
                // next, same as before this property existed.
                Loader {
                    id: widget
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    // Item.enabled propagates to the loaded widget and every MouseArea
                    // inside it. This one line is what makes a preview a preview —
                    // and what makes a live bar module grabbable in arrange mode
                    // instead of firing its own handler when you try to pick it up.
                    enabled: !root.slotsClickable && !root.slotsArranging
                    sourceComponent: root.componentFor ? root.componentFor(slot.modelData) : null
                    // A module that can be the hero (it declares `hero`) recolours its text for
                    // the primaryContainer chip BarGroup draws under it (Config.moduleHero).
                    onLoaded: if (widget.item && widget.item.hero !== undefined)
                        widget.item.hero = Qt.binding(() => Config.moduleHero(slot.modelData))

                    // On the Loader, not the slot: the slot's own opacity is the drag dim.
                    opacity: slot.introIn
                    transform: Translate { y: (1 - slot.introIn) * Tokens.spacingSm }
                }

                // Dimmed where it came FROM while the ghost shows where it is going
                // TO. Not hidden: removing it would reflow the region under the
                // cursor mid-drag, moving the very targets being aimed at.
                opacity: (BarDrag.dragging && BarDrag.dragId === slot.modelData) ? 0.25 : 1.0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                // ── This slot as a drop target ────────────────────────────────
                // Which HALF you are over is the gesture: the left half lands before
                // this module, the right half after it. `dropIndex + 1` is the only
                // way to name the slot AFTER a module, and the end of a group has no
                // other name — without it, appending to a group is impossible and the
                // last position is unreachable.
                DropArea {
                    id: slotDrop
                    anchors.fill: widget
                    // TWO keys, for two kinds of drag that both land here.
                    //
                    //   "barmodule"  the scene-graph drag started on this bar. A
                    //                `Drag.keys` value, which only exists inside one
                    //                window's scene.
                    //   BarDrag.mime the PLATFORM drag started from the settings
                    //                window's module catalogue. `Drag.keys` does not
                    //                survive the compositor, so for a drag arriving
                    //                from outside the window a DropArea matches its
                    //                keys against the drag's MIME FORMATS instead —
                    //                the key has to be the mime type itself.
                    keys: ["barmodule", BarDrag.mime]

                    // Never itself: dropping a module on itself is a no-op, and
                    // marking it as a target would promise otherwise.
                    //
                    // `dragId` is "" for an incoming platform drag — that gesture's
                    // press happened in another window — so the self-check passes
                    // trivially and an external drop is always allowed.
                    enabled: root.slotsArranging && BarDrag.dragId !== slot.modelData

                    function target(x) {
                        return {
                            kind:   "chip",
                            owner:  slot.modelData,
                            region: root.region,
                            group:  barGroup.index,
                            index:  x > widget.width / 2 ? slot.index + 1 : slot.index
                        }
                    }

                    onEntered: function (d) { BarDrag.drop = slotDrop.target(d.x) }
                    // The index changes as the pointer sweeps across the module, so
                    // the target is recomputed on the way — entering once is not
                    // enough to know which half you are on.
                    onPositionChanged: function (d) { BarDrag.drop = slotDrop.target(d.x) }
                    // An identity check cannot work: the target is a fresh object on
                    // every move, so it would never match and the drop would never
                    // clear. The owner tag is what makes "is this still mine?"
                    // answerable.
                    onExited: if (BarDrag.drop?.kind === "chip"
                               && BarDrag.drop?.owner === slot.modelData) BarDrag.drop = null

                    // ── Only an EXTERNAL drop commits here ────────────────────
                    // The internal drag commits in BarDrag.end(), on the mouse
                    // release that belongs to this window. A platform drag has no
                    // such release here — press, travel and release all belong to the
                    // settings window — so the drop event is the only moment we get.
                    //
                    // `idFromDrop` returns "" for anything that is not one of ours,
                    // which is also what makes this a no-op on the internal path.
                    onDropped: function (d) {
                        const id = BarDrag.idFromDrop(d)
                        if (id === "") return
                        BarDrag.dropExternal(id, slotDrop.target(d.x))
                        // An unaccepted drop is a REFUSED drop, and the source is
                        // entitled to act on that. Measured in the probe: without
                        // this the source reports Qt.IgnoreAction on a drop that
                        // plainly landed.
                        d.acceptProposedAction()
                    }
                }

                // "It lands here, INSIDE this group." Drawn in the seam beside the
                // module rather than over it, so it says WHICH SIDE rather than
                // merely "this one".
                //
                // ── A solid bar, and the seams are hollow outlines ────────────
                // Both used to be an identical 2px accent line, and that was the one
                // genuinely ambiguous thing about arranging the bar: dropping between
                // two modules of a group JOINS the group, while dropping a few pixels
                // further out — in the seam — makes a NEW group. Two different bars,
                // one indicator.
                //
                // So the two are now different SHAPES rather than the same shape in
                // two places: a solid bar means "slot in here", a hollow outline the
                // size of a pill means "a new group appears here". Backed up by
                // BarDrag.description in the shelf, which names it in words.
                Rectangle {
                    readonly property bool before:
                        BarDrag.drop?.kind === "chip"
                        && BarDrag.drop?.region === root.region
                        && BarDrag.drop?.group === barGroup.index
                        && BarDrag.drop?.index === slot.index
                    readonly property bool after:
                        BarDrag.drop?.kind === "chip"
                        && BarDrag.drop?.region === root.region
                        && BarDrag.drop?.group === barGroup.index
                        && BarDrag.drop?.index === barGroup.modelData.length
                        && slot.index === barGroup.modelData.length - 1

                    x: after ? widget.x + widget.width + 1 : widget.x - 4
                    anchors.verticalCenter: widget.verticalCenter
                    width:  3
                    radius: 1.5
                    height: (before || after) ? widget.height + 6 : 0
                    visible: height > 0.5
                    color: Colors.of(QsWindow.window).focus
                    Behavior on height {
                        NumberAnimation { duration: Motion.fast; easing.type: Motion.travel }
                    }
                }

                // ── The group line ────────────────────────────────────────────
                // A rule under every module, spanning its whole SLOT — the reserved
                // gap on the left included. Neighbours in one group are adjacent
                // slots, so their rules butt together into a single continuous line
                // per group, and the padding between groups leaves a visible break.
                // One line per group, drawn without anything knowing where a group
                // starts or ends.
                //
                // It exists because grouping is otherwise invisible exactly when you
                // are deciding about it: in merged and unified modes there is no pill
                // around each group at all, so "these three are one group and that one
                // is on its own" is a fact about `Config.layout` with nothing on
                // screen expressing it. You could drag a module into a group and see
                // no difference.
                //
                // Drawn BELOW the slot rather than inside it — `y` past the slot's own
                // height. Safe for the same reason the seams are: a slot has an
                // explicit implicitWidth and implicitHeight, so a child outside those
                // bounds cannot feed back into the Row's size and start a polish loop.
                // See BarGroup for the two attempts that did.
                //
                // `slot.parent.height - slot.y`, not `slot.height` — slots are now
                // vertically CENTRED on the row (see the anchors.verticalCenter note
                // above), and they don't all share one height (a label-driven pill
                // like KeyboardPill's "US" isn't the same box as a glyph-driven one).
                // A line hung off each slot's own bottom edge broke into segments at
                // different heights instead of butting into one line; hanging it off
                // the ROW's shared bottom edge (translated into this slot's local
                // coordinates) keeps every segment on the same line regardless of its
                // own slot's height.
                Rectangle {
                    x: 0
                    // Same teardown guard as the slot's anchor above.
                    y: (slot.parent ? slot.parent.height : slot.height) - slot.y + 3
                    width:  slot.width
                    height: 2
                    radius: 1
                    visible: root.slotsArranging
                    // The dragged module's own line dims with it, so the break it
                    // leaves behind shows which group it is currently counted in.
                    color: (BarDrag.dragging && BarDrag.dragId === slot.modelData)
                         ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.2)
                         : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.55)
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                }

                // Sized to the widget, not the slot — the reserved gap on the left
                // isn't part of the button and shouldn't be part of its hit box.

                // Dead on the real bar, so it can't intercept a click meant for the
                // widget underneath. A disabled MouseArea is transparent to input.
                // ── The seams BETWEEN groups ──────────────────────────────────
                // "Put it here, as its own group." Without these the only placements
                // are "join an existing group" and "append to the region", so the
                // ORDER of groups could never be changed — you could pull a module
                // out of a group but never put it back as the second of four.
                //
                // They live in the SLOT, drawn outside the first and last module of
                // each group, rather than on an overlay layer belonging to BarGroup.
                // Two attempts at the latter both failed (BarGroup carries the full
                // account); what makes this version safe is that a slot has an
                // explicit implicitWidth and implicitHeight, so a child sitting at a
                // negative x cannot feed back into the Row's size and start a polish
                // loop. Nothing here is anchored to anything but this slot.
                //
                // Written out twice rather than factored into an inline component:
                // `component` declarations are only legal at the TOP LEVEL of a file,
                // and this is four objects deep inside a Repeater delegate. Declared
                // here it parses cleanly and then fails at load — the exact class of
                // error the syntax check cannot see.

                // Before this group — carried by its FIRST module only.
                Item {
                    id: seamBefore

                    readonly property int groupIndex: barGroup.index
                    readonly property bool armed: BarDrag.drop?.kind === "gap"
                                               && BarDrag.drop?.region === root.region
                                               && BarDrag.drop?.groupIndex === seamBefore.groupIndex

                    // Wide enough to aim at while dragging, nothing at rest — a
                    // permanent gutter beside every group would change what the bar
                    // looks like when nobody is arranging it.
                    width:  BarDrag.dragging ? 18 : 0
                    height: widget.height
                    y: widget.y
                    x: widget.x - width - 2
                    visible: BarDrag.dragging && root.slotsArranging && slot.index === 0

                    DropArea {
                        anchors.fill: parent
                        // Both kinds — see the slot's DropArea for why the platform
                        // drag's key has to be the mime type.
                        keys: ["barmodule", BarDrag.mime]
                        enabled: root.slotsArranging
                        onEntered: BarDrag.drop = { kind: "gap", region: root.region,
                                                    groupIndex: seamBefore.groupIndex }
                        onExited:  if (seamBefore.armed) BarDrag.drop = null
                        onDropped: function (d) {
                            const id = BarDrag.idFromDrop(d)
                            if (id === "") return
                            BarDrag.dropExternal(id, { kind: "gap", region: root.region,
                                                       groupIndex: seamBefore.groupIndex })
                            d.acceptProposedAction()
                        }
                    }

                    // A hollow pill the size of the gap, NOT a line: "a new group
                    // appears here". See the note on the chip indicator above.
                    //
                    // The seam's own width stays fixed whether armed or not. Growing
                    // it would be the mid-drag reflow this file already warns about
                    // one indicator up — the targets would move under the pointer
                    // that is aiming at them.
                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin:    -3
                        anchors.bottomMargin: -3
                        visible: seamBefore.armed
                        radius: Tokens.corner(Config.barShape, Tokens.radiusPill)
                        color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.14)
                        border.width: Tokens.borderChrome
                        border.color: Colors.of(QsWindow.window).focus
                    }
                }

                // After this group — carried by its LAST module only. `index + 1` is
                // the only way to name the position after a group, and without it the
                // end of the region is unreachable as a group boundary.
                Item {
                    id: seamAfter

                    readonly property int groupIndex: barGroup.index + 1
                    readonly property bool armed: BarDrag.drop?.kind === "gap"
                                               && BarDrag.drop?.region === root.region
                                               && BarDrag.drop?.groupIndex === seamAfter.groupIndex

                    width:  BarDrag.dragging ? 18 : 0
                    height: widget.height
                    y: widget.y
                    x: widget.x + widget.width + 2
                    visible: BarDrag.dragging && root.slotsArranging
                             && slot.index === barGroup.modelData.length - 1

                    DropArea {
                        anchors.fill: parent
                        keys: ["barmodule", BarDrag.mime]
                        enabled: root.slotsArranging
                        onEntered: BarDrag.drop = { kind: "gap", region: root.region,
                                                    groupIndex: seamAfter.groupIndex }
                        onExited:  if (seamAfter.armed) BarDrag.drop = null
                        onDropped: function (d) {
                            const id = BarDrag.idFromDrop(d)
                            if (id === "") return
                            BarDrag.dropExternal(id, { kind: "gap", region: root.region,
                                                       groupIndex: seamAfter.groupIndex })
                            d.acceptProposedAction()
                        }
                    }

                    // Hollow pill, same as seamBefore — see its note.
                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin:    -3
                        anchors.bottomMargin: -3
                        visible: seamAfter.armed
                        radius: Tokens.corner(Config.barShape, Tokens.radiusPill)
                        color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.14)
                        border.width: Tokens.borderChrome
                        border.color: Colors.of(QsWindow.window).focus
                    }
                }

                // ── The drag proxy ────────────────────────────────────────────
                // `drag.target` has to point at SOMETHING for a MouseArea's
                // `drag.active` ever to become true, and `drag.active` going true is
                // what constructs the QDrag. It must not point at the slot or the
                // widget: those live in the Row, so dragging one would physically
                // pull it out of the layout and reflow the whole region under the
                // pointer that is aiming at it.
                //
                // So it points here — an empty, invisible, unparented-from-layout
                // Item that nothing measures. It is moved by the drag and its
                // position is never read.
                Item {
                    id: dragProxy
                    width: 1
                    height: 1
                    // No `visible: false`. A bare Item draws nothing anyway, and an
                    // invisible item is a needless bet on QQuickDragAttached being
                    // willing to start a platform drag from one — the probe that
                    // verified this whole path used a visible source.

                    // ── This is a PLATFORM drag, not a scene-graph one ────────
                    // `Drag.Automatic` starts a real QDrag, routed by the compositor
                    // over wl_data_device, so it can leave the bar's layer-shell
                    // surface entirely and be dropped on the settings window's module
                    // catalogue. Measured before being relied on (scratchpad probe,
                    // layer surface → app window): `REVERSE ARRIVED`, with
                    // `dragFinished action = 2` (Qt.MoveAction) once the target
                    // accepted.
                    //
                    // It still reaches this window's own DropAreas — the slots and
                    // seams a few pixels away — so ONE gesture now does all four
                    // placements plus removal, where before the bar had an internal
                    // drag that physically could not reach settings and settings had
                    // a click that could not be precise.
                    //
                    // The mime type is the payload AND the key: `Drag.keys` is a
                    // scene-graph concept and does not survive the compositor.
                    //
                    // ── `Drag.active` is bound to a latch WE own ──────────────
                    // Two wrong versions preceded this one, and both failure modes are
                    // worth keeping because each looks like the obvious fix for the
                    // other.
                    //
                    // 1. `Drag.active: slotHit.drag.active` — the documented idiom,
                    //    and a binding loop here: going true constructs the QDrag, the
                    //    QDrag takes the pointer grab off the MouseArea, the
                    //    MouseArea's own drag.active goes FALSE, and the binding drives
                    //    Drag.active back down. Qt reports it against the item owning
                    //    the attached Drag — this Item — not the MouseArea the loop
                    //    runs through, which is why the message points here.
                    //
                    // 2. Dropping the binding and calling `Drag.startDrag()` from the
                    //    MouseArea instead: "startDrag() drag must be active". That
                    //    function does not START anything, it re-issues a drag that is
                    //    already active — for `Drag.Automatic`, setting `active` true
                    //    is itself what constructs the QDrag.
                    //
                    // So: a plain bool that only this file writes. The handler latches
                    // it true once the platform's start distance has been passed, and
                    // `Drag.onDragFinished` clears it. Qt can no longer reach it, so
                    // there is no cycle, and `active` still goes true by assignment,
                    // which is the one thing that actually starts the drag.
                    property bool armed: false

                    Drag.active: dragProxy.armed
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.MoveAction
                    Drag.proposedAction: Qt.MoveAction
                    Drag.mimeData: {
                        const m = {}
                        m[BarDrag.mime] = slot.modelData
                        return m
                    }

                    // What the pointer carries: a picture of the actual module,
                    // grabbed on press. Qt draws this itself during an automatic
                    // drag, which is why BarArrange no longer needs a hand-drawn
                    // ghost following BarDrag.dragPos — during a QDrag the pointer is
                    // grabbed by the platform and the MouseArea stops receiving move
                    // events, so a hand-driven ghost would simply freeze.
                    Drag.hotSpot: Qt.point(widget.width / 2, widget.height / 2)

                    // The platform tells us the gesture is over. This is the only
                    // teardown — there is no mouse release to hang it off, because the
                    // QDrag owns the pointer from the threshold onward.
                    Drag.onDragFinished: {
                        dragProxy.armed  = false
                        BarDrag.dragging = false
                        BarDrag.dragId   = ""
                        BarDrag.drop     = null
                    }
                }

                MouseArea {
                    id: slotHit
                    anchors.fill: widget
                    enabled: root.slotsClickable || root.slotsArranging
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: root.slotsArranging
                        ? (BarDrag.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                        : Qt.PointingHandCursor

                    // Only in arrange mode: with a target set at all times, an
                    // ordinary click on a live bar module would arm a drag.
                    drag.target: root.slotsArranging ? dragProxy : null
                    drag.smoothed: false

                    // A MouseArea keeps the grab after a press, so the drag threshold
                    // is still measured once the pointer has left the module. Without
                    // preventStealing a drag that travels far enough can be taken by
                    // an ancestor's own pan recognizer mid-gesture.
                    preventStealing: root.slotsArranging

                    // ── Where the drag actually starts ────────────────────────
                    // Qt has already applied the platform's start distance by the time
                    // this fires, so it is the correct moment: a press that never
                    // travels far enough never reaches here, which is what stops an
                    // ordinary click on a module from spawning a drag.
                    //
                    // Raising the latch is what starts the drag — see dragProxy.
                    drag.onActiveChanged: {
                        if (!slotHit.drag.active) return
                        BarDrag.dragging = true
                        BarDrag.dragId   = slot.modelData
                        dragProxy.armed  = true
                    }

                    onPressed: {
                        if (!root.slotsArranging) return
                        // Selecting on PRESS, not on click: pressing is also how a drag
                        // starts, and selecting then is what makes "grab a module and
                        // configure it" one gesture. The settings page's inspector
                        // reads this.
                        UiState.inspectBarModule(slot.modelData)
                        // The drag image is grabbed here rather than bound, because
                        // grabToImage is asynchronous and returns a URL that is only
                        // valid once the callback runs. Grabbing on press means it is
                        // ready by the time the threshold is crossed.
                        // targetSize is required, not optional: Drag applies its own
                        // sourceSize to the image it is handed, and Qt refuses that on
                        // a grabToImage url ("Ignoring sourceSize request…").
                        widget.grabToImage(function (result) {
                            dragProxy.Drag.imageSource = result.url
                        }, Qt.size(widget.width, widget.height))
                    }

                    // Only the preview's click contract. In arrange mode a press is
                    // the start of a drag and selection already happened above, so
                    // firing this too would be a second meaning for one press.
                    onClicked: if (!root.slotsArranging) root.slotClicked(slot.modelData)
                }

                // Hover ring — otherwise there's nothing to suggest the preview
                // responds to a pointer at all.
                Rectangle {
                    anchors.fill: widget
                    anchors.margins: -1
                    radius: Config.barRoundness
                    color: "transparent"
                    border.width: 1
                    border.color: Colors.of(QsWindow.window).outlineFocus
                    opacity: slotHit.containsMouse ? 1 : 0
                    visible: opacity > 0.005
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                }
            }
        }
    }
}
