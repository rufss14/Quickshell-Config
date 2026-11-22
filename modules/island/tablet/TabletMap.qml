pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── TabletMap ─────────────────────────────────────────────────────────────────
// The tablet drawn to its real shape, with the part of it the pen uses as a block of accent you can take hold
// of: drag it to move, drag its corner to resize. Where the pen is right now is a dot on it (a ring that
// swells with the pressure, filled while it touches), so the map doubles as the live view.
//
// Sizes are the tablet's own millimetres (`Tablet.profile.area`); this only scales them to fit. A change that
// does not come from the hand (a profile switch, "fill the screen") moves the block on a spring; while a hand
// holds it, it follows with no easing at all, since any lag between a hand and what it holds reads as broken.
//
// Dragging writes through Tablet.setArea / resizeArea on every move. The service debounces what goes to disk
// and to the compositor, so this does not.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    property color ink: root.palette.fgOnPrimaryContainer
    property bool editable: true

    readonly property var dev: Tablet.device
    readonly property var area: Tablet.profile ? Tablet.profile.area : ({ x: 0, y: 0, w: 1, h: 1 })
    readonly property var pen: Tablet.pen
    readonly property bool locked: Tablet.profile ? Tablet.profile.lockRatio : true

    // Pixels per millimetre, and the tablet's size on screen.
    readonly property real k: root.dev ? Math.max(0.01, Math.min(root.width / root.dev.widthMm, root.height / root.dev.heightMm)) : 1
    readonly property real bodyW: root.dev ? root.dev.widthMm * root.k : 0
    readonly property real bodyH: root.dev ? root.dev.heightMm * root.k : 0

    readonly property bool dragging: mover.pressed || grip.pressed

    SpringValue { id: sx; target: root.area.x * root.k; spec: Motion.springSpatial; epsilon: 0.05 }
    SpringValue { id: sy; target: root.area.y * root.k; spec: Motion.springSpatial; epsilon: 0.05 }
    SpringValue { id: sw; target: root.area.w * root.k; spec: Motion.springSpatial; epsilon: 0.05 }
    SpringValue { id: sh; target: root.area.h * root.k; spec: Motion.springSpatial; epsilon: 0.05 }
    // A hand holding the block is the truth: put the springs where it is so letting go does not lurch.
    function _pin() { sx.jump(sx.target); sy.jump(sy.target); sw.jump(sw.target); sh.jump(sh.target) }
    onAreaChanged: if (root.dragging) root._pin()
    onKChanged: root._pin()

    Rectangle {
        id: body
        anchors.centerIn: parent
        width: root.bodyW
        height: root.bodyH
        radius: Tokens.radiusSm
        color: root.palette.alpha(root.ink, 0.1)
        // The picture's canvas: the one place a hairline belongs.
        border.width: Tokens.borderWidth
        border.color: root.palette.alpha(root.ink, 0.22)

        // ── The part the pen uses ─────────────────────────────────────────────
        Rectangle {
            id: zone
            x: sx.value
            y: sy.value
            width: sw.value
            height: sh.value
            radius: Tokens.radiusSm
            color: root.palette.primary

            // How big it is, in the tablet's own millimetres, once there is room to say it.
            StyledText {
                anchors.centerIn: parent
                visible: parent.width > implicitWidth + Tokens.spacingLg && parent.height > implicitHeight + Tokens.spacingLg
                text: Translation.tr("%1 × %2 mm").arg(Math.round(root.area.w)).arg(Math.round(root.area.h))
                variant: "caption"
                font.weight: Font.DemiBold
                font.features: ({ tnum: 1 })
                color: root.palette.fgOnPrimary
            }

            // A lip at the corner that says "pull here".
            Rectangle {
                id: lip
                visible: root.editable
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Tokens.spacingSm
                width: Tokens.spacingLg
                height: width
                radius: width / 2
                color: root.palette.alpha(root.palette.fgOnPrimary, grip.pressed || grip.containsMouse ? 0.95 : 0.55)
                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }
        }

        // Move.
        MouseArea {
            id: mover
            property real startX: 0
            property real startY: 0
            property var from: null
            anchors.fill: zone
            enabled: root.editable
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onPressed: m => {
                const p = mapToItem(body, m.x, m.y)
                startX = p.x
                startY = p.y
                from = root.area
            }
            onPositionChanged: m => {
                if (!pressed) return
                const p = mapToItem(body, m.x, m.y)
                Tablet.setArea({ x: from.x + (p.x - startX) / root.k, y: from.y + (p.y - startY) / root.k, w: from.w, h: from.h })
            }
            Accessible.role: Accessible.Graphic
            Accessible.name: Translation.tr("The part of the tablet the pen uses")
        }

        // Resize: from the corner, a hand-sized target around the lip.
        MouseArea {
            id: grip
            property real startX: 0
            property real startY: 0
            property var from: null
            x: zone.x + zone.width - width + Tokens.spacingSm
            y: zone.y + zone.height - height + Tokens.spacingSm
            width: Tokens.iconXl + Tokens.spacingSm
            height: width
            enabled: root.editable
            hoverEnabled: true
            cursorShape: Qt.SizeFDiagCursor
            onPressed: m => {
                const p = mapToItem(body, m.x, m.y)
                startX = p.x
                startY = p.y
                from = root.area
            }
            onPositionChanged: m => {
                if (!pressed) return
                const p = mapToItem(body, m.x, m.y)
                const w = from.w + (p.x - startX) / root.k
                // Locked, the height follows the screen's shape; free, the corner goes where the hand goes.
                if (root.locked) Tablet.resizeArea(w)
                else Tablet.setArea({ x: from.x, y: from.y, w: w, h: from.h + (p.y - startY) / root.k })
            }
        }

        // ── The pen ───────────────────────────────────────────────────────────
        // `x` and `y` are 0..1 across the whole tablet. A dot outside the block still shows where the pen is,
        // but in the card's own ink, because nothing it draws there reaches the screen.
        Item {
            id: dot
            readonly property bool here: root.pen !== null && root.pen.in === true
            readonly property real px: here ? root.pen.x * body.width : 0
            readonly property real py: here ? root.pen.y * body.height : 0
            readonly property bool inside: px >= zone.x && px <= zone.x + zone.width && py >= zone.y && py <= zone.y + zone.height
            readonly property color tone: inside ? root.palette.fgOnPrimary : root.ink
            readonly property real press: here ? root.pen.p : 0
            x: px
            y: py
            visible: here
            opacity: here && root.pen.touch ? 1 : 0.6

            Rectangle {
                anchors.centerIn: parent
                width: Tokens.spacingLg + dot.press * Tokens.iconXl
                height: width
                radius: width / 2
                color: "transparent"
                border.width: Tokens.borderWidth * 2
                border.color: dot.tone
            }
            Rectangle {
                anchors.centerIn: parent
                width: Tokens.spacingMd
                height: width
                radius: width / 2
                color: dot.tone
                visible: dot.here && root.pen.touch
            }
        }
    }
}
