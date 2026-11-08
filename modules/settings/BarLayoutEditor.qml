pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
// Wallpaper — the strip draws the real desktop behind the bar, so translucency and
// contrast read the way they will on screen rather than against a flat card fill.
import "../../services"

// ── BarLayoutEditor ───────────────────────────────────────────────────────────
// Drag modules to lay out the bar. A direct manipulation of Config.layout — what you
// arrange here is literally what Bar.qml renders, because they read the same list.
//
// ── The editor is SHAPED LIKE THE BAR ─────────────────────────────────────────
// One horizontal pill divided into Left / Centre / Right, with the modules in each
// zone anchored the way they actually anchor on screen.
//
// It used to be three stacked full-width boxes, one per region. That was honest
// about the DATA — three independent lists — and wrong about the THING, which is one
// strip with three zones. Three costs, all of them real:
//
//   · Nothing said left/centre/right were positions on a single bar. They read as
//     three separate containers that happened to be named after directions.
//   · Moving a module from the left region to the right meant dragging DOWNWARD.
//     The direction of the gesture had no relationship to where the module ended up,
//     which is the one thing direct manipulation is supposed to get right.
//   · ~250px of page height for ~40px of content, on a page that was already the
//     tallest in the app.
//
// Now the drag direction IS the answer, the zones are labelled above the strip where
// the labels cannot move as the zones fill, and the whole editor is about 80px.
//
// ── The gestures ──────────────────────────────────────────────────────────────
//   drop on a chip   → join that chip's group, BESIDE it            (the phone-folder move)
//   drop in a gap    → become your own group there
//   drop on a region → append to it as your own group
//   drop on the pool → leave the bar
//
// Dropping one thing onto another is what makes them a cluster. That's the whole
// grouping UI: no mode, no modifier, no "new group" button — the same gesture that
// reorders also groups, and which one you get depends only on what's under the cursor.
//
// ── Inside a group, which HALF you're over is the gesture ─────────────────────
// Dropping on a chip used to always insert at that chip's index — always to its left.
// Which meant the last slot of a group had no target at all: the only thing over it was
// the chip already sitting there, and aiming at that put you in front of it. Reordering
// inside a group was a puzzle, and appending to one was impossible.
//
// So a chip is two targets, split down the middle: left half lands before it, right half
// lands after. That's how every tab strip and file list does it, `index + 1` is what
// makes the end of a group reachable, and the caret shows the answer before you commit.
// The chips also spread apart while you drag, for the same reason the Gaps widen — a 2px
// seam is not something you can aim at.
//
// ── Three rules this file exists to obey ──────────────────────────────────────
// All three are bugs this codebase has already paid for, in the overview's window drag
// and in Pins. They are cheap to honour and expensive to rediscover.
//
//   1. NEVER bind Drag.active to a MouseArea's drag.active. Releasing clears
//      drag.active, which fires every DropArea's onExited, which clears the drop
//      target — BEFORE onReleased runs. The drop then always reads null and the drag
//      always silently snaps back. `dragging` is driven by hand instead.
//
//   2. READ the drop target before tearing the drag down. Same story one level up:
//      lowering `dragging` inside the commit clears `drop` via those same onExited
//      handlers, so a commit that reads `drop` afterwards reads null.
//
//   3. COMMIT ON RELEASE ONLY. Config.layout is a JS array, and the bar Repeaters over
//      it — so every write rebuilds every delegate. Committing per-frame would destroy
//      the chip holding the mouse grab mid-drag and the gesture would die on contact.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: editor

    // One inert copy of the bar's widgets, shared by every chip and the ghost.
    property PreviewModules registry: PreviewModules {}

    // The module the inspector is pointed at. SELECTED, not hovered: hover was fine for
    // a read-only description, but the panel has controls in it now — a panel that
    // re-targets itself when the pointer drifts across a chip on its way to a swatch is
    // a panel you can't use.
    property string focusId: ""

    // ── Drag state ────────────────────────────────────────────────────────────
    property string dragId:  ""
    property bool   dragging: false
    property point  dragPos: Qt.point(0, 0)
    property size   dragSize: Qt.size(0, 0)
    property point  _pressPos: Qt.point(0, 0)

    // Where the pointer currently is, as a destination. Null when over nothing.
    // Written by the DropAreas below; read exactly once, at commit.
    property var drop: null

    readonly property int dragThreshold: 4

    function beginDrag(id, pos, w, h) {
        editor.dragId    = id
        editor._pressPos = pos
        editor.dragPos   = pos
        editor.dragSize  = Qt.size(w, h)
    }

    function moveDrag(pos) {
        editor.dragPos = pos
        if (editor.dragging || editor.dragId === "") return
        // A press is not a drag. Without a threshold, every click would spawn a ghost
        // and the chips would twitch when you meant to hover them.
        const dx = pos.x - editor._pressPos.x
        const dy = pos.y - editor._pressPos.y
        if (Math.sqrt(dx * dx + dy * dy) > editor.dragThreshold) editor.dragging = true
    }

    function endDrag() {
        // RULE 2. Capture first: `dragging = false` below fires onExited on whatever
        // DropArea we're over, which sets `drop` back to null.
        const target = editor.drop
        const id     = editor.dragId

        editor.dragging = false
        editor.dragId   = ""
        editor.drop     = null

        if (!id || !target) return

        switch (target.kind) {
            case "chip":   Config.moveIntoGroup(id, target.region, target.group, target.index); break
            case "gap":    Config.moveToOwnGroup(id, target.region, target.groupIndex);         break
            case "region": Config.moveToOwnGroup(id, target.region,
                                                 (Config.layout[target.region] ?? []).length);  break
            case "pool":   Config.removeModule(id);                                             break
        }
    }

    implicitHeight: column.implicitHeight

    ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: Tokens.spacingXs

        // ══ Zone labels ═══════════════════════════════════════════════════════
        // Above the field rather than inside it. Inside, they would either sit in the
        // middle of a zone (where the modules go) or shrink to fit beside them — and
        // a label that moves as you fill the zone is a label you stop trusting.
        //
        // Each cell is `fillWidth` with `preferredWidth: 1`, which is the idiom that
        // splits a row into equal parts regardless of what the text is: without the
        // preferred width the cells size to their own labels and "Centre" ends up
        // nowhere near the centre.
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin:  Tokens.spacingSm
            Layout.rightMargin: Tokens.spacingSm
            spacing: 0

            Repeater {
                model: Config.regionIds

                StyledText {
                    required property string modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1

                    // Each label sits over where its modules actually land, which is
                    // the only thing that makes the three zones legible as a map of
                    // the bar rather than three equal boxes.
                    horizontalAlignment: index === 0 ? Text.AlignLeft
                                       : index === Config.regionIds.length - 1
                                       ? Text.AlignRight : Text.AlignHCenter

                    text:     Config.regionLabel(modelData)
                    variant:  "caption"
                    emphasis: "dim"
                }
            }
        }

        // ══ The field IS the bar ══════════════════════════════════════════════
        // A picture of the top of the screen — the wallpaper, with the bar sitting on
        // it drawn from the real Config values — that you drag modules onto. The
        // preview and the editor are one object rather than a diagram next to one.
        //
        // ── Why this replaced three stacked boxes ─────────────────────────────
        // The old shape was honest about the DATA (three independent lists) and wrong
        // about the THING (one bar with three zones). It gave no clue that
        // left/centre/right are positions on a single strip, it cost ~250px of page
        // for ~40px of content, and dragging a module from the left region to the
        // right meant dragging DOWNWARD — a gesture whose direction had nothing to do
        // with where the module ended up. Here the drag direction is the answer.
        //
        // ── Why the real modules are legible here and not in BarPreview ───────
        // BarPreview's header argues for abstract blocks, and it is right for what it
        // does: it draws the whole 1920px screen at ~460px, where a real pill would be
        // a ~90px smudge you could neither read nor aim at.
        //
        // This is not that. It spans the full width of the page (BarPage gives it
        // `columnSpan: 2`), so a 1920px bar renders at roughly 0.8 scale — near enough
        // to 1:1 that the modules are the actual widgets, at the actual size, in the
        // actual order. That is the whole reason it can be the drop target: you are
        // arranging the bar by moving the bar.
        //
        // BarPreview stays, and still earns its place — it shows the frame RING, which
        // is a question about the whole screen and one this strip cannot answer.
        Item {
            id: field

            // The group pills set the height; everything else is padding around them.
            readonly property real barHeight: Tokens.pillHeight + Tokens.spacingLg

            Layout.fillWidth: true
            implicitHeight: field.barHeight + Tokens.spacingMd * 2

            // ── The desktop behind it ─────────────────────────────────────────
            // The real wallpaper, so the bar reads as sitting ON something. It also
            // makes translucency legible: `barOpacity` is a setting on the next
            // column, and against a flat card fill you cannot see what it does.
            Rectangle {
                anchors.fill: parent
                radius: Tokens.radiusSm
                clip: true
                color: Colors.of(QsWindow.window).surfaceContainer

                Image {
                    anchors.fill: parent
                    source: Wallpaper.currentPath !== ""
                        ? "file://" + Wallpaper.currentPath : ""
                    visible: status === Image.Ready
                    fillMode: Image.PreserveAspectCrop
                    // A wide, short crop of the top of the picture — this is a strip
                    // of the screen's top edge, not a thumbnail of the whole thing.
                    // Downscaled hard on purpose: rasterising a 4K file at full size
                    // to draw it 1500×60 is how a settings page stutters on open.
                    sourceSize: Qt.size(960, 120)
                    asynchronous: true
                    smooth: true
                    opacity: 0.45
                }
            }

            // ── The bar itself ────────────────────────────────────────────────
            // Anchored to the TOP of the strip with the real inset, leaving a sliver
            // of wallpaper below it — which is what a top bar looks like, and what
            // makes `barInset` mean something here.
            Item {
                anchors.left:   parent.left
                anchors.right:  parent.right
                anchors.top:    parent.top
                anchors.margins: Config.barShape ? 0 : Tokens.spacingMd
                height: field.barHeight

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                Repeater {
                    model: Config.regionIds

                    Item {
                        id: zone

                        required property string modelData
                        required property int index

                        readonly property var groups: Config.layout[zone.modelData] ?? []
                        readonly property bool isLast: zone.index === Config.regionIds.length - 1

                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true

                        // Dropping on a zone's empty space appends — otherwise a zone
                        // you had emptied would have no target at all and nothing could
                        // ever go back into it.
                        DropArea {
                            id: regionDrop
                            anchors.fill: parent
                            keys: ["barmodule"]
                            onEntered: editor.drop = { kind: "region", region: zone.modelData }
                            onExited:  if (editor.drop?.kind === "region"
                                        && editor.drop?.region === zone.modelData) editor.drop = null
                        }

                        // Which zone you are about to land in. The three zones have no
                        // borders of their own — they are parts of one strip — so the
                        // wash is the only thing that says which one is armed.
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: Tokens.radiusSm
                            color: regionDrop.containsDrag ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.14)
                                                           : "transparent"
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                        }

                        // The seam between zones. Short and faint on purpose: it has to
                        // divide the strip without breaking it into three boxes, which
                        // is the whole difference between this and what it replaced.
                        Rectangle {
                            visible: !zone.isLast
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width:  1
                            height: parent.height * 0.5
                            color:  Colors.of(QsWindow.window).outline
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: zone.groups.length === 0 && !regionDrop.containsDrag
                            text:     Translation.tr("Drop here")
                            variant:  "caption"
                            emphasis: "dim"
                            opacity:  0.55
                        }

                        // ── Modules sit where they will actually sit ──────────
                        // Left-aligned in the left zone, centred in the centre, right
                        // in the right — the same anchoring the real bar uses. A zone
                        // whose contents were always left-aligned would show the right
                        // region's modules hard against the seam, which is not where
                        // they render.
                        Row {
                            id: groupRow

                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left:  zone.index === 0 ? parent.left : undefined
                            anchors.right: zone.isLast ? parent.right : undefined
                            anchors.horizontalCenter: (zone.index !== 0 && !zone.isLast)
                                                    ? parent.horizontalCenter : undefined
                            spacing: 0

                            Repeater {
                                model: zone.groups.length + 1

                                // Alternating gap / group. The gaps are drop targets in
                                // their own right — that is what "become your own group
                                // here" means — so they are real items with width, not
                                // spacing. There is one more gap than group, hence `+ 1`.
                                Row {
                                    id: slot
                                    required property int index

                                    readonly property bool hasGroup: slot.index < zone.groups.length

                                    spacing: 0

                                    Gap {
                                        region:     zone.modelData
                                        groupIndex: slot.index
                                    }

                                    GroupPill {
                                        visible: slot.hasGroup
                                        region:  zone.modelData
                                        groupIndex: slot.index
                                        ids: slot.hasGroup ? zone.groups[slot.index] : []
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        }

        // ══ Available ═════════════════════════════════════════════════════════
        StyledText {
            Layout.topMargin: Tokens.spacingSm
            text:     Translation.tr("Not on the bar — drag one up, or drop one here to remove it")
            variant:  "caption"
            emphasis: "dim"
        }

        Surface {
            Layout.fillWidth: true
            elevation:    Tokens.elevationNested
            cornerRadius: Tokens.radiusSm
            implicitHeight: Math.max(48, poolFlow.implicitHeight + Tokens.spacingMd * 2)
            focused: poolDrop.containsDrag

            DropArea {
                id: poolDrop
                anchors.fill: parent
                keys: ["barmodule"]
                onEntered: editor.drop = { kind: "pool" }
                onExited:  if (editor.drop?.kind === "pool") editor.drop = null
            }

            StyledText {
                anchors.centerIn: parent
                visible:  Config.availableModules.length === 0 && !poolDrop.containsDrag
                text:     Translation.tr("Everything is on the bar")
                variant:  "caption"
                emphasis: "dim"
            }

            Flow {
                id: poolFlow
                anchors.left:  parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.spacingMd
                spacing: Tokens.spacingSm

                Repeater {
                    model: Config.availableModules

                    Chip {
                        required property var modelData
                        moduleId: modelData.id
                        muted: true
                    }
                }
            }
        }
    }

    // ══ The ghost ═════════════════════════════════════════════════════════════
    // What actually carries the Drag. The chip itself stays put and dims — moving the
    // real chip would tear it out of its Row and reflow the region under the cursor
    // while you're still aiming at it.
    //
    // Declared last so it paints above everything, and parented to the editor so it can
    // travel between regions.
    Chip {
        id: ghost

        moduleId: editor.dragId
        visible:  editor.dragging
        opacity:  0.9
        z: 100

        width:  editor.dragSize.width
        height: editor.dragSize.height
        x: editor.dragPos.x - width / 2
        y: editor.dragPos.y - height / 2

        // RULE 1: driven by hand, never bound to a MouseArea's drag.active.
        Drag.active: editor.dragging
        Drag.keys:   ["barmodule"]
        // Without a hotSpot this defaults to the item's top-left, so every drop would
        // register half a chip up and to the left of where you're actually pointing.
        Drag.hotSpot: Qt.point(width / 2, height / 2)
    }

    // ══ Pieces ════════════════════════════════════════════════════════════════

    // "It lands here." One shape for both kinds of insertion — between two groups, and
    // between two chips inside one — because it's the same promise either way, and two
    // carets that drifted apart visually would read as two different meanings.
    component Caret: Rectangle {
        property bool shown: false
        property real extent: 0

        width:  3
        radius: 2
        color:  Colors.of(QsWindow.window).focus
        height: shown ? extent : 0
        visible: height > 0.5
        Behavior on height {
            NumberAnimation { duration: Motion.fast; easing.type: Motion.travel }
        }
    }

    // A drop target between two groups: "put it here, on its own".
    component Gap: Item {
        id: gap

        property string region: ""
        property int groupIndex: 0

        // Wide enough to aim at while dragging, invisible otherwise — a permanent 18px
        // gutter between every group would make the editor look nothing like the bar
        // it's editing.
        width:  editor.dragging ? 18 : Tokens.spacingSm
        height: 34
        Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Motion.travel } }

        DropArea {
            id: gapDrop
            anchors.fill: parent
            keys: ["barmodule"]
            onEntered: editor.drop = { kind: "gap", region: gap.region, groupIndex: gap.groupIndex }
            onExited:  if (editor.drop?.kind === "gap"
                        && editor.drop?.region === gap.region
                        && editor.drop?.groupIndex === gap.groupIndex) editor.drop = null
        }

        // The insertion marker. This is the ghost preview: it shows exactly where the
        // module lands before you let go.
        Caret {
            anchors.centerIn: parent
            shown:  gapDrop.containsDrag
            extent: gap.height
        }
    }

    // A group: the chips that share one pill in the real bar.
    component GroupPill: Rectangle {
        id: groupPill

        property string region: ""
        property int groupIndex: 0
        property var ids: []

        // Where a drop would land in THIS group right now, or -1 for "not aimed here".
        // Read back off the shared drop state rather than recomputed, so the caret and
        // the commit are literally the same number — a preview that can disagree with
        // what it previews is worse than no preview.
        readonly property int pendingIndex: {
            const d = editor.drop
            return (d && d.kind === "chip"
                 && d.region === groupPill.region
                 && d.group  === groupPill.groupIndex) ? d.index : -1
        }

        implicitWidth:  chipRow.implicitWidth + Tokens.spacingMd * 2
        implicitHeight: Tokens.pillHeight + Tokens.spacingLg

        // ── Drawn as the REAL bar pill, not a generic box ─────────────────────
        // Same fill, same hairline, same corner radius the bar uses — `frameFill` and
        // `frameLine` are literally the colours BarFrameEdge and the bar's own
        // surfaces are drawn in, and they carry both of Surface's translucencies.
        //
        // This used to be `alpha(fg, 0.05)` with a nested outline, which was correct
        // while the editor was a diagram sitting in a card. It is a picture of the bar
        // now: a group here IS a pill there, so a group that looked like a settings
        // widget would be the one thing on the strip that did not match the screen.
        // Corner radius follows `barShape` for the same reason — square mode squares
        // these too.
        radius: Config.barShape ? 0 : Config.barRoundness

        color:        Colors.of(QsWindow.window).frameFill
        border.width: Config.barBorderWidth > 0 ? Tokens.borderWidth : 0
        border.color: Colors.of(QsWindow.window).frameLine

        Row {
            id: chipRow
            anchors.centerIn: parent

            // Opens up while dragging so there's a seam to aim at between two chips, and
            // room for the caret to sit in. Same idea as the Gaps widening, same reason.
            spacing: editor.dragging ? Tokens.spacingMd : Tokens.spacingXs
            Behavior on spacing {
                NumberAnimation { duration: Motion.fast; easing.type: Motion.travel }
            }

            Repeater {
                model: groupPill.ids

                Chip {
                    required property string modelData
                    required property int index

                    moduleId: modelData

                    isTarget:   true
                    dropRegion: groupPill.region
                    dropGroup:  groupPill.groupIndex
                    dropIndex:  index

                    // Landing "after chip i" and "before chip i+1" are the same slot, so
                    // only the before-caret is ever drawn for it. The trailing edge of
                    // the last chip is the one position no before-caret can express —
                    // that's the slot that used to be unreachable — so it gets its own.
                    caretBefore: groupPill.pendingIndex === index
                    caretAfter:  groupPill.pendingIndex === groupPill.ids.length
                              && index === groupPill.ids.length - 1
                }
            }
        }
    }

    // A module — rendered as the widget it actually is.
    //
    // It used to be a lozenge with "Bar mode" written in it, which names a thing you
    // then have to go and find on the bar to recognise. This is the real pill, built
    // from the same file the bar builds it from, so there's nothing to recognise.
    component Chip: Item {
        id: chip

        property string moduleId: ""
        property bool muted: false        // in the pool rather than on the bar

        // Set on chips that live in a group; the pool's chips are sources only.
        property bool   isTarget:   false
        property string dropRegion: ""
        property int    dropGroup:  0
        property int    dropIndex:  0

        // Drawn by the chip because the chip is what knows where its own edges are.
        property bool caretBefore: false
        property bool caretAfter:  false

        readonly property var info: Config.moduleInfo(chip.moduleId)
        readonly property bool isDragged: editor.dragging && editor.dragId === chip.moduleId

        implicitWidth:  Math.max(28, widget.implicitWidth)
        implicitHeight: Math.max(Tokens.pillHeight, widget.implicitHeight)

        // The dragged chip stays in place and dims, marking where it came FROM while
        // the ghost shows where it's going TO. A pooled module is dimmed too — it isn't
        // on the bar, and it shouldn't look as present as the ones that are.
        opacity: chip.isDragged ? 0.25 : chip.muted ? 0.55 : 1.0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        // The widget itself. `enabled: false` is what makes it a picture: it propagates
        // to every MouseArea inside, so the pill can't be clicked, scrolled, or hovered
        // into its own state changes — the chip's own MouseArea below owns the pointer.
        Loader {
            id: widget
            anchors.centerIn: parent
            enabled: false
            sourceComponent: editor.registry.componentFor(chip.moduleId)
        }

        // Selection ring. Drawn OVER the widget rather than as its background, because
        // the widget brings its own — a chip is a pill, and pills are already opaque.
        //
        // This used to double as the drop highlight, filling the whole chip when it was
        // the target. That was honest when a drop meant "take this chip's place", but a
        // chip is two targets now and a full-chip wash can't say WHICH half you're on.
        // The caret says it exactly, so the wash is gone rather than left to contradict.
        Rectangle {
            readonly property bool isSelected: editor.focusId === chip.moduleId && !chip.isDragged

            anchors.fill: parent
            anchors.margins: -2
            radius: Config.barRoundness
            color:  "transparent"
            border.width: 2
            border.color: Colors.of(QsWindow.window).focus
            opacity: isSelected ? 1 : 0
            visible: opacity > 0.005
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        }

        // ── The insertion carets ──────────────────────────────────────────────
        // They sit in the seam the Row opens up during a drag, which is why they're
        // anchored OUTSIDE the chip's own bounds rather than inside it.
        Caret {
            shown:  chip.caretBefore
            extent: chip.height + 4
            anchors.right: parent.left
            anchors.rightMargin: Tokens.spacingXs
            anchors.verticalCenter: parent.verticalCenter
        }

        Caret {
            shown:  chip.caretAfter
            extent: chip.height + 4
            anchors.left: parent.right
            anchors.leftMargin: Tokens.spacingXs
            anchors.verticalCenter: parent.verticalCenter
        }

        DropArea {
            id: chipDrop
            anchors.fill: parent
            keys: ["barmodule"]
            // A chip is only a target if it's ON the bar, and never itself — dropping a
            // module on itself is a no-op, and marking it as a target would promise
            // otherwise.
            enabled: chip.isTarget && editor.dragId !== chip.moduleId

            // Which half you're over is which side you land on. `dropIndex + 1` is the
            // whole point: it's the only way to name the slot after a chip, and the end
            // of a group has no other name.
            function target(x) {
                return {
                    kind:   "chip",
                    owner:  chip.moduleId,
                    region: chip.dropRegion,
                    group:  chip.dropGroup,
                    index:  x > chip.width / 2 ? chip.dropIndex + 1 : chip.dropIndex
                }
            }

            onEntered:         function(d) { editor.drop = chipDrop.target(d.x) }
            // The index changes as you sweep across the chip, so the target has to be
            // recomputed on the way — entering it once isn't enough to know where you're
            // aiming.
            onPositionChanged: function(d) { editor.drop = chipDrop.target(d.x) }

            // `drop === dropTarget` identity checks can't work any more: the target is a
            // fresh object on every move, so it would never match and the drop would
            // never clear. The owner tag is what makes "is this still mine?" answerable.
            onExited: if (editor.drop?.kind === "chip"
                       && editor.drop?.owner === chip.moduleId) editor.drop = null
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            // The page's body sits in a Flickable (SettingsPage.qml). Without this, a
            // drag that moves far enough gets stolen mid-gesture — Flickable's own pan
            // recognizer grabs the mouse away from this MouseArea and the chip stops
            // following the pointer while the whole page scrolls instead. This keeps
            // the grab here once a press has started it.
            preventStealing: true
            cursorShape: editor.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

            // Select on press, not on click: pressing is also how a drag starts, and
            // selecting then is what makes "grab a chip and configure it" one gesture.
            onPressed: function(m) {
                editor.focusId = chip.moduleId
                editor.beginDrag(chip.moduleId,
                                 chipMouse.mapToItem(editor, m.x, m.y),
                                 chip.width, chip.height)
            }
            // A MouseArea keeps the grab after a press, so this keeps firing once the
            // pointer has left the chip — which is the entire drag.
            onPositionChanged: function(m) {
                if (editor.dragId === "") return
                editor.moveDrag(chipMouse.mapToItem(editor, m.x, m.y))
            }
            onReleased:  editor.endDrag()
            onCanceled:  editor.endDrag()
        }
    }
}
