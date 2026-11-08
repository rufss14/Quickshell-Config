import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import "../../../services/switcher.js" as SwitchJs
import "../../notifications"
import QtQuick.Layouts
import ".."

// ── WorkspaceGridWindows ── part of WorkspaceGrid.qml; `grid` is the WorkspaceGrid it belongs to. ──
Item {
    id: windowLayer
    required property var grid
    property alias winRepeater: winRepeater
    anchors.fill: parent
    // Over the strip: a bottom-row window's tooltip opens downward, onto the chips, and
    // drawn under them it was cut through (2026-10-20). Under the badge, tags, peek and menus.
    z: 5

    // ── Drop ghost ────────────────────────────────────────────────────
    // It lives INSIDE the window layer, and that placement is the whole fix.
    //
    // It used to be a sibling declared BEFORE windowLayer — same parent, same
    // default z — so every window preview painted straight over it. On an empty
    // workspace there was nothing to cover it, which is exactly why it appeared
    // to work there and nowhere else.
    //
    // z:500 puts it above windows at rest (1, or 10 hovered) and below the one
    // in your hand (1000): visible over the windows it's going to tile against,
    // never over the window you're actually dragging.
    //
    // Deliberately still, too. The first version pulsed, and it was noise — the
    // ghost already glides between cells and already fades in and out; a
    // breathing outline on top of that just competed with the drag.
    Rectangle {
        id: ghost
        z: 500

        // Hidden when the cursor is over no cell, and when hovering the window's
        // own workspace — a ghost saying "it'll go back exactly where it is"
        // tells you nothing.
        readonly property bool shown:
            grid.ghosting && grid.dropTarget > 0 && grid.dropTarget !== grid.dragSourceWs
            && grid.slotOf(grid.dropTarget) >= 0

        visible: opacity > 0.01
        opacity: ghost.shown ? 1 : 0

        // Positioned from ghostWs (the last REAL cell), never from dropTarget,
        // and sized to the slot it will TILE into rather than to the window's
        // current geometry. winOrigin, not cellX/cellY — ghostSlot is in
        // FIT-local coordinates (see resolveDrop), and winOrigin is where that
        // fit box actually starts on the board.
        x: grid.winOriginX(grid.ghostWs) + grid.ghostSlot.x
        y: grid.winOriginY(grid.ghostWs) + grid.ghostSlot.y
        width:  grid.ghostSlot.w
        height: grid.ghostSlot.h

        radius: Math.max(2, Tokens.radiusCard - 4)
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.16)
        border.width: 2
        border.color: Colors.of(QsWindow.window).primary

        // Ctrl held: it's a swap — say so on the window it'll trade with.
        MaterialIcon {
            anchors.centerIn: parent
            visible: grid.swapMode
            name: "swap_horiz"
            color: Colors.of(QsWindow.window).primary
            font.pixelSize: Tokens.iconXl
        }

        // Glides and reshapes as you move, rather than blinking from slot to
        // slot. This is the thing you're actually watching while you drag, so it
        // gets the emphasized curve — but at `standard`, not `spatial`: it has to
        // keep up with the pointer, and 400ms here would lag your hand.
        Behavior on x       { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        Behavior on y       { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        Behavior on width   { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        Behavior on height  { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
    }

    // ── The model is KEYED BY ADDRESS. This is load-bearing. ─────────
    // `model: grid.pageWindows` looks obviously right and is the bug that made
    // dragging fail intermittently and the overview flicker: pageWindows derives from
    // Hypr.windows, which rebuild() REASSIGNS whenever its snapshot changes — and the
    // snapshot includes each window's TITLE. A Repeater over a JS array treats any new
    // array as a full reset, so it destroyed and recreated every delegate — including
    // the one under your cursor with the MouseArea holding the grab, and every live
    // capture on screen (the flicker).
    //
    // It was then the array's LENGTH, which kept delegates alive through title
    // changes, but a window opening or closing shifted every index after it: previews
    // were handed to OTHER windows and glided between unrelated places. Now
    // (2026-10-20) a ListModel of addresses, changed one row at a time (_syncWins): a
    // preview IS its window for its whole life, a new one pops in where it lands, and
    // a closed one shrinks away before its row goes (`gone`) — the user's pick.
    Repeater {
        id: winRepeater
        model: grid.winModel

        OverviewWindow {
            id: wv
            required property int index
            required property string address
            required property bool gone
            required property bool fresh

            // The live record; the last one seen once it's gone (closed, or moved off
            // the page), so it shrinks away where it was.
            readonly property var live: grid.winMap[wv.address] ?? null
            property var held: null
            onLiveChanged: if (wv.live) wv.held = wv.live
            Component.onCompleted: { if (wv.live) wv.held = wv.live; wv.born = true }
            property bool born: false
            readonly property var win: wv.live ?? wv.held
            visible: wv.win !== null

            window: wv.win
            previewScale: grid.previewScale
            calm: grid.ghosting || grid.showAll
            ctrlMode: grid.ctrlOn
            onCtrlUsed: grid.modUsed()
            monitor: grid.monitor

            // Arrives with its cell, a beat after it (the ripple out from where you
            // are), rising out of a slight shrink; leaves with the stage, at once. One
            // that opens while the overview is up pops in where it lands, at once; one
            // that closes shrinks away (then _drop takes its row).
            readonly property bool present: grid.active && wv.born && !wv.gone
            readonly property int arriveDelay: wv.fresh || !wv.win ? 0 : grid.rippleDelay(wv.win.workspaceId, wv.index) + Motion.stagger * 2
            opacity: wv.present ? 1 : 0
            scale: wv.present ? 1 : wv.gone ? 0.6 : 0.86
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: wv.present ? wv.arriveDelay : 0 }
                    NumberAnimation { duration: wv.present ? Motion.standard : Motion.fast }
                }
            }
            Behavior on scale {
                SequentialAnimation {
                    PauseAnimation { duration: wv.present ? wv.arriveDelay : 0 }
                    NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
                }
            }
            onGoneChanged: if (wv.gone) dropLater.start()
            Timer { id: dropLater; interval: Motion.spatial; onTriggered: grid._drop(wv.address) }

            originX: wv.win ? grid.winOriginX(wv.win.workspaceId) : 0
            originY: wv.win ? grid.winOriginY(wv.win.workspaceId) : 0
            fit: wv.win ? grid.previewSizeFor(wv.win.workspaceId) : ({ w: grid.cellW, h: grid.cellH })

            // A shade tighter than the cell, so a maximised window's corner
            // nests inside the cell's corner instead of fighting it.
            cornerRadius: Math.max(2, Tokens.radiusCard - 4)

            dropTarget: grid.dropTarget
            picked: win !== null && win.address === grid.pickedAddress
            marked: win !== null && Switcher.marks.indexOf(win.address) >= 0
            faded: win !== null && grid.matching !== null && grid.matching[win.address] !== true
            receded: grid.pickedAddress !== "" && !picked
            ago: picked ? Switcher.agoText(win.address) : ""

            // Tooltips on the bottom row open DOWNWARD. Anchored above, they'd
            // point off the top of a cell into the row overhead and collide with
            // the previews living there.
            tipBelow: win ? grid.rowOf(win.workspaceId) >= grid.layRows - 1 : false

            onDragBegan: function(offX, offY, w, h, floating) {
                if (!win) return

                grid.ghostOffX     = offX
                grid.ghostOffY     = offY
                grid.ghostW        = w
                grid.ghostH        = h
                grid.ghostFloating = floating
                grid.dragAddress   = win.address

                // A floating window is never re-tiled, so its ghost is simply its
                // own footprint — no anchor, no preselect, and exact.
                if (floating)
                    grid.ghostSlot = { x: offX, y: offY, w: w, h: h }

                // Seed the ghost in the window's OWN cell, so its first move is a
                // glide from somewhere real rather than a jump in from wherever
                // the last drag happened to end.
                grid.dragSourceWs = win.workspaceId
                grid.ghostWs      = win.workspaceId
                grid.ghosting     = true
            }

            // The anchor + direction resolved by the DropArea are what MAKE the
            // window land where the ghost showed it — see Hypr.moveWindowToWorkspace.
            onSwappingChanged: grid.swapMode = swapping
            onRequestMove: function(target) {
                if (!win) return
                // Ctrl: trade places with the window it was dropped on.
                if (grid.swapMode && grid.anchorAddress !== "") {
                    Hypr.moveWindowToWorkspace(win.address, target, "", "")
                    Hypr.moveWindowToWorkspace(grid.anchorAddress, win.workspaceId, "", "")
                    grid.land(target)
                    grid.land(win.workspaceId)
                    return
                }
                // One of several marked windows: they all go (no split hint — it is for one).
                if (Switcher.marks.length > 1 && Switcher.marks.indexOf(win.address) >= 0) {
                    for (const m of Switcher.marked) Hypr.moveWindowToWorkspace(m.address, target, "", "")
                    grid.land(target)
                    return
                }
                Hypr.moveWindowToWorkspace(win.address, target,
                                           grid.ghostFloating ? "" : grid.anchorAddress,
                                           grid.ghostFloating ? "" : grid.splitDir)
                grid.land(target)
            }

            // Whatever happened — moved, snapped back, or the grab was taken
            // away — the highlight and the ghost go with it.
            onDragFinished: {
                grid.dropTarget   = -1
                grid.ghosting     = false
                grid.dragSourceWs = -1
                grid.dragAddress  = ""
                grid.swapMode     = false
                grid.clearDrop()
            }
        }
    }
}
