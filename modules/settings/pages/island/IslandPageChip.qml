pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../../../../config/islands.js" as Islands

// ── IslandPageChip ────────────────────────────────────────────────────────────
// One page on the Island page's board (IslandBoard): the page's icon on a badge, its name, a grip. The first
// page of a rail wears the island rail's own filled indicator in that page's shape, so a column reads as the
// rail it stands for. Drag it (anywhere on the chip) to move it; right-click or long-press for the same moves
// as a menu. It moves nothing itself: the board does, from where it is dropped.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string key: ""
    // The first page on its rail: the one the island opens on first.
    property bool lead: false
    // The launcher and Updates: always alone in the middle column, so no grip and no menu.
    property bool locked: false
    // This chip's page is the one being carried: its place stays behind as a faint ghost.
    property bool lifted: false
    // How far down it stands aside for a page being dropped above it (a spring follows).
    property real shift: 0
    // The board (drag and menu); null for the copy that follows the pointer.
    property Item board: null

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property var meta: Islands.pageMeta(root.key)
    readonly property bool hot: hover.hovered && !root.locked

    implicitHeight: Tokens.iconXl + Tokens.spacingMd

    Accessible.role: Accessible.Button
    Accessible.name: Translation.tr(root.meta.label)
    Accessible.description: root.locked ? Translation.tr("Always opens alone in the middle")
                                        : Translation.tr("Drag to move, or open the menu")
    Accessible.onPressAction: if (root.board && !root.locked) root.board.openMenu(root.key, root, root.width / 2, root.height / 2)

    SpringValue { id: gap; target: root.shift; spec: Motion.springSpatial; epsilon: 0.2 }

    Item {
        id: face
        width: root.width
        height: root.height
        y: gap.value
        opacity: root.lifted ? 0.3 : 1
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.hot ? root.palette.alpha(root.palette.fg, Tokens.stateHover) : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }

        MorphShape {
            id: badge
            x: Tokens.spacingXs
            anchors.verticalCenter: parent.verticalCenter
            width: root.height - Tokens.spacingXs * 2
            height: width
            shape: root.lead ? root.meta.shape : "circle"
            fillColor: root.lead ? root.palette.primary : root.palette.surfaceHigh
            Behavior on fillColor { ColorAnimation { duration: Motion.standard } }
        }
        MaterialIcon {
            anchors.centerIn: badge
            name: root.meta.icon
            fill: root.lead ? 1 : 0
            font.pixelSize: Tokens.iconMd
            color: root.lead ? root.palette.fgOnPrimary : root.hot ? root.palette.fg : root.palette.fgMuted
            Behavior on color { ColorAnimation { duration: Motion.standard } }
        }

        StyledText {
            anchors.left: badge.right
            anchors.leftMargin: Tokens.spacingMd
            anchors.right: grip.left
            anchors.rightMargin: Tokens.spacingSm
            anchors.verticalCenter: parent.verticalCenter
            text: Translation.tr(root.meta.label)
            variant: "label"
            font.weight: root.lead ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
        }

        MaterialIcon {
            id: grip
            anchors.right: parent.right
            anchors.rightMargin: Tokens.spacingMd
            anchors.verticalCenter: parent.verticalCenter
            name: root.locked ? "lock" : "drag_indicator"
            font.pixelSize: Tokens.iconMd
            color: root.palette.fgDim
            opacity: root.locked || root.hot ? 1 : 0.45
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        }
    }

    HoverHandler {
        id: hover
        enabled: root.board !== null
        cursorShape: root.locked ? Qt.ArrowCursor : drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    }
    HoverTip {
        text: root.locked ? Translation.tr("Always opens alone in the middle: it needs the keyboard to itself") : ""
    }

    DragHandler {
        id: drag
        target: null
        enabled: root.board !== null && !root.locked
        // The settings page scrolls: without this its Flickable takes a vertical drag over for a scroll.
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        onActiveChanged: {
            if (drag.active) root.board.beginDrag(root.key, root, drag.centroid.scenePosition)
            else root.board.endDrag()
        }
        onCentroidChanged: if (drag.active) root.board.moveDrag(drag.centroid.scenePosition)
    }
    TapHandler {
        enabled: root.board !== null && !root.locked
        acceptedButtons: Qt.RightButton
        onTapped: function (point) { root.board.openMenu(root.key, root, point.position.x, point.position.y) }
    }
    TapHandler {
        enabled: root.board !== null && !root.locked
        onLongPressed: root.board.openMenu(root.key, root, root.width / 2, root.height / 2)
    }
}
