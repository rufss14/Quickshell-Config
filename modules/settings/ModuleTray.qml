pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── ModuleTray ────────────────────────────────────────────────────────────────
// Everything not currently on the bar, drawn as the real widget. Drag one onto the
// bar to place it exactly where you want; drag one off the bar back onto this card
// to take it off again.
//
// ── The drag really does leave this window ────────────────────────────────────
// This card used to be click-only, on the stated grounds that Qt's Drag/DropArea are
// window-scoped: Settings is an xdg-toplevel, the bar is a layer-shell surface, and
// a scene-graph drag cannot cross between them. That much is true — and it is not
// the whole story, which is why the click could never be precise about where a
// module landed.
//
// `Drag.dragType: Drag.Automatic` starts a real QDrag that goes out over
// wl_data_device and is routed by the COMPOSITOR, and a wlr-layer-shell surface can
// both receive one and start one. Measured in both directions before any of this was
// built on it — see BarDrag, which holds the mime type and the evidence.
//
// So the two halves are one gesture now: drag out of this card onto a slot or a seam
// on the real bar, and the module lands at that exact position, in that exact group.
// Drag off the bar back onto this card and it comes off. Clicking still works as the
// shortcut for "anywhere sensible" — it is no longer the only way in.
//
// ── Real widgets, not names ───────────────────────────────────────────────────
// Same reasoning the shelf and the old chips carry: a lozenge reading "Bar mode"
// names a thing you then have to go and find to recognise. The widget IS the thing.
// The name appears on hover, in one shared line below the flow, rather than under
// every tile — twenty-two captions is a wall of text where the pictures were the
// point.
// ─────────────────────────────────────────────────────────────────────────────
// ── An Item wrapping a ColumnLayout, not a ColumnLayout ───────────────────────
// It WAS a bare ColumnLayout. That stopped working the moment the tray became a
// drop target, because a Layout lays out every visible child Item it has — and a
// DropArea is an Item. Left as direct children, the drop area and the highlight
// would each be given a row of their own in the column, pushing the tiles down and
// leaving two mystery gaps, while their `anchors.fill` fought the layout for
// control of the same geometry (which Qt warns about and then ignores).
//
// So the layout is one level in, and the things that must span the WHOLE card —
// the drop area and its highlight — are anchored siblings of it rather than
// members of it.
Item {
    id: root

    implicitHeight: col.implicitHeight

    // The module factory — PreviewModules.componentFor from the page.
    property var componentFor: null

    // Which tile the pointer is on, by id, or "" for none. Drives the shared name
    // line below: hovering a tile is how you find out what it is called, so the
    // answer has to be somewhere the eye already is.
    property string hovered: ""

    // ── There is no region picker here, and there was for one round ───────────
    // An "Add to: Suggested / Left / Centre / Right" chip row sat above the tiles,
    // because clicking could only ever drop a module at its catalogue `home` and
    // there was no way to say otherwise.
    //
    // It was the wrong fix for the right complaint. Naming a region still could not
    // express the two things actually being asked for — the ORDER within a group,
    // and whether a module joins a group at all — so it added a control, and a
    // decision, and still left you dragging afterwards. The real cause was that
    // dragging on the bar was broken: the arrange overlay's region bands sat above
    // every slot and seam and swallowed the drops, so region was genuinely the only
    // thing a drag could change. See BarArrange.
    //
    // With that fixed, dragging expresses all three — region, order, grouping — and
    // this becomes what it should be: a catalogue. Click to put a module on the bar,
    // then drag it exactly where you want. One control, one job.

    readonly property var _spare: Config.availableModules

    // ── Dropping a module here takes it off the bar ───────────────────────────
    // The other half of the gesture, and the one that needed the compositor: the bar
    // is a layer-shell surface and this is an ordinary window, so a module dragged
    // out of the bar arrives here as a platform drag. Measured before being relied
    // on (scratchpad probe, layer surface → app window): the drop arrives and
    // `dragFinished` reports Qt.MoveAction once accepted.
    //
    // It sits on the whole tray rather than on a dedicated bin, because the tray IS
    // the destination — "not on your bar" is a place, and this is it. A module
    // dropped here appears among the tiles immediately, which is the confirmation.
    DropArea {
        id: trayDrop
        anchors.fill: parent
        keys: [BarDrag.mime]

        onDropped: function (d) {
            const id = BarDrag.idFromDrop(d)
            if (id === "") return
            // Guard against the tray's OWN tiles being dropped back onto it: those
            // are already off the bar, so removing them again is a no-op, but
            // accepting the drop would report a successful move that did nothing.
            if (!Config.isPlaced(id)) return
            Config.removeModule(id)
            d.acceptProposedAction()
        }
    }

    // The whole card lights up while a module is over it, because the target is the
    // card and not any one tile. Drawn behind the content — see the `z`.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -Tokens.spacingSm
        z: -1
        visible: trayDrop.containsDrag
        radius: Tokens.radiusCard
        color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.12)
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).focus
    }

    ColumnLayout {
        id: col
        anchors.left:  parent.left
        anchors.right: parent.right
        anchors.top:   parent.top
        spacing: Tokens.spacingSm

    // ── Empty state ───────────────────────────────────────────────────────────
    // A tray with nothing in it and no explanation reads as broken. This is a real
    // and common state — the default layout places most of the catalogue.
    StyledText {
        Layout.fillWidth: true
        visible: root._spare.length === 0
        text: Translation.tr("Every module is on your bar")
        variant:  "caption"
        emphasis: "dim"
        wrapMode: Text.WordWrap
    }

    // ── The catalogue ─────────────────────────────────────────────────────────
    // A Flow, so it wraps to however many columns the card is wide rather than
    // running off the edge or forcing a fixed grid. Twenty-two modules at ~44px is
    // two or three rows at a settings window's width.
    Flow {
        Layout.fillWidth: true
        visible: root._spare.length > 0
        spacing: Tokens.spacingSm

        Repeater {
            model: root._spare

            Item {
                id: tile
                required property var modelData

                readonly property bool isHovered: root.hovered === tile.modelData.id

                // A floor, not a size: an icon-only module is ~40px and the clock is
                // much wider, and forcing both to one width would either crop the
                // clock or leave craters around the icons.
                implicitWidth:  Math.max(Tokens.pillIconWidth, widget.implicitWidth + Tokens.spacingMd)
                implicitHeight: Math.max(Tokens.pillHeight + Tokens.spacingMd, widget.implicitHeight)

                Surface {
                    anchors.fill: parent
                    elevation:    Tokens.elevationNested
                    cornerRadius: Tokens.radiusPill
                    focused:      tile.isHovered
                    // Off the bar, so it should not look as present as the ones that
                    // are — and it lifts to full on hover, which is the tile saying
                    // it is clickable without needing a separate affordance.
                    opacity: tile.isHovered ? 1 : 0.65
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                }

                // `enabled: false` is what makes it a picture rather than a control:
                // it propagates into every MouseArea inside the real widget, so the
                // preview's volume pill cannot change the volume and the click below
                // is the only thing that happens. One wrapper, the whole job — the
                // same contract PreviewModules documents.
                Loader {
                    id: widget
                    anchors.centerIn: parent
                    enabled: false
                    sourceComponent: root.componentFor
                        ? root.componentFor(tile.modelData.id) : null
                }

                // ── The drag proxy ────────────────────────────────────────────
                // Same arrangement BarGroupRow uses, for the same reason: a
                // MouseArea's `drag.active` only becomes true if `drag.target` points
                // at something, and it must not point at the tile — the tiles are in
                // a Flow, so dragging one would pull it out of the layout and reflow
                // the whole catalogue under the pointer aiming at it.
                Item {
                    id: dragProxy
                    width: 1
                    height: 1
                    // No `visible: false`. A bare Item draws nothing anyway, and an
                    // invisible item is a needless bet on QQuickDragAttached being
                    // willing to start a platform drag from one — the probe that
                    // verified this whole path used a visible source.

                    // A PLATFORM drag. Settings is an ordinary application window and
                    // the bar is a layer-shell surface, so a scene-graph drag can
                    // never reach it — that limit is exactly why this catalogue used
                    // to be a CLICK, and why the click could never be precise about
                    // where the module landed.
                    //
                    // `Drag.Automatic` starts a real QDrag routed by the compositor,
                    // which the bar's slots and seams receive like any other drop.
                    // Measured before being relied on: app window → layer surface
                    // delivers `enter` then `drop`.
                    //
                    // Bound to a latch we own, never to `tileHit.drag.active` — see
                    // BarGroupRow's dragProxy for the binding loop that causes and for
                    // why startDrag() is not the way out of it.
                    property bool armed: false
                    Drag.active: dragProxy.armed
                    // ── `Drag.active` is NOT bound, and must not be ───────────
                    // Binding it to `tileHit.drag.active` is a binding loop for an
                    // automatic drag: going true constructs the QDrag, the QDrag takes
                    // the pointer grab off the MouseArea, the MouseArea's drag.active
                    // goes false, and the binding drives Drag.active back down. Qt
                    // reports it against this Item rather than the MouseArea the loop
                    // runs through. Started imperatively below instead.
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.MoveAction
                    Drag.proposedAction: Qt.MoveAction
                    Drag.mimeData: {
                        const m = {}
                        m[BarDrag.mime] = tile.modelData.id
                        return m
                    }
                    Drag.hotSpot: Qt.point(tile.width / 2, tile.height / 2)

                    // Arrange mode is what turns the bar's slots and seams into drop
                    // targets, so a drag that starts here has to switch it on or there
                    // is nothing on the bar willing to receive it. Switching it on
                    // when the gesture BEGINS, rather than asking the user to press
                    // Arrange bar first, is the difference between one motion and
                    // three.
                    //
                    // It is deliberately not switched off again on drop: having just
                    // placed a module, the next thing anyone does is nudge it, and the
                    // mode is already exactly right for that. Done ends it.
                    Drag.onDragFinished: {
                        dragProxy.armed  = false
                        BarDrag.dragging = false
                    }
                }

                MouseArea {
                    id: tileHit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.OpenHandCursor

                    drag.target: dragProxy
                    drag.smoothed: false

                    onEntered: root.hovered = tile.modelData.id
                    onExited:  if (root.hovered === tile.modelData.id) root.hovered = ""

                    // Qt has already applied the platform's start distance by the time
                    // this fires, so a press that never travels stays a click.
                    //
                    // Arrange mode is what turns the bar's slots and seams into drop
                    // targets, so it has to be on before this drag arrives or there is
                    // nothing on the bar willing to receive it. Switching it on as the
                    // gesture begins, rather than asking for a button press first, is
                    // the difference between one motion and three.
                    drag.onActiveChanged: {
                        if (!tileHit.drag.active) return
                        UiState.barArrange = true
                        BarDrag.dragging   = true
                        dragProxy.armed    = true
                    }

                    // Grabbed on press rather than bound: grabToImage is asynchronous
                    // and its URL is only valid inside the callback, so taking it at
                    // press time means the picture is ready by the moment the drag
                    // threshold is crossed.
                    onPressed: {
                        UiState.inspectBarModule(tile.modelData.id)
                        widget.grabToImage(function (result) {
                            dragProxy.Drag.imageSource = result.url
                        }, Qt.size(widget.width, widget.height))
                    }

                    // Click still works, and still puts the module at its catalogue
                    // `home`. It is no longer the only way in — it is the shortcut for
                    // "anywhere sensible, I will move it later" — so it costs nothing
                    // to keep and saves a drag for the common case.
                    onClicked: Config.addModule(tile.modelData.id)
                }
            }
        }
    }

    // ── The shared name line ──────────────────────────────────────────────────
    // Holds its height whether or not anything is hovered. Bound straight to the
    // hover with nothing behind it, the line vanishes as the pointer leaves and the
    // whole card jumps a row shorter — a layout that twitches under the cursor.
    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacingXs
        visible: root._spare.length > 0

        text: {
            if (trayDrop.containsDrag) return "Let go to take it off your bar"
            const m = root._spare.find(function (x) { return x.id === root.hovered })
            return m ? m.label + " — drag it onto the bar, or click to place it"
                     : "Point at one to see what it is"
        }
        variant:  "caption"
        emphasis: (root.hovered !== "" || trayDrop.containsDrag) ? "muted" : "dim"
        elide:    Text.ElideRight
        }
    }
}
