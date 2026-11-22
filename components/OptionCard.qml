import QtQuick
import Quickshell
import "../config"

// ── OptionCard ───────────────────────────────────────────────────────────────
// One choice, as a card instead of a chip: a badge and a name (and, where there is
// something to say, a second line). Off it is a lifted plate with a plain disc for a badge; on it takes the
// accent container, goes round to a full pill and the disc blooms into a shape of its own, on springs, the
// way the source rail's choice does. A press dips it, the pointer leans it in.
//
// `on` is the caller's: a radio group lights the one that is chosen, a switch lights while it is on.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property string symbol: ""
    property string label: ""
    property string detail: ""
    property bool   on: false
    property string shape: "cookie9"
    signal activated()

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property color ink: root.on ? root.palette.fgOnPrimaryContainer : root.palette.fg
    readonly property color inkDim: root.on ? root.palette.alpha(root.palette.fgOnPrimaryContainer, 0.72) : root.palette.fgMuted

    implicitHeight: Tokens.iconXl + Tokens.spacingMd
    implicitWidth: row.implicitWidth + Tokens.spacingMd * 2
    color: root.on ? root.palette.primaryContainer : root.palette.plate
    Behavior on color { ColorAnimation { duration: Motion.standard } }

    SpringValue { id: shapeK; target: root.on ? 1 : 0; spec: Motion.springSpatial; epsilon: 0.002 }
    radius: Tokens.radiusSm + Math.max(0, shapeK.value) * (root.height / 2 - Tokens.radiusSm)
    SpringValue {
        id: lean
        target: tap.pressed ? 0.95 : hover.hovered && !root.on ? 1.03 : 1
        spec: Motion.springSpatialFast
        epsilon: 0.001
    }
    scale: lean.value
    opacity: root.enabled ? 1 : 0.4

    StateLayer {
        anchors.fill: parent
        radius: root.radius
        hovered: hover.hovered && !root.on
        layerColor: root.ink
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Tokens.spacingSm
        anchors.right: parent.right
        anchors.rightMargin: Tokens.spacingMd
        spacing: Tokens.spacingSm

        Item {
            id: badge
            anchors.verticalCenter: parent.verticalCenter
            width: Tokens.iconXl - Tokens.spacingXs
            height: width
            MorphShape {
                anchors.fill: parent
                shape: root.on ? root.shape : "circle"
                spec: Motion.springSpatialFast
                fillColor: root.on ? root.palette.primary : root.palette.section
            }
            MaterialIcon {
                anchors.centerIn: parent
                name: root.symbol
                fill: root.on ? 1 : 0
                font.pixelSize: Tokens.iconMd
                color: root.on ? root.palette.fgOnPrimary : root.palette.fgMuted
                Behavior on fill  { NumberAnimation { duration: Motion.standard } }
                Behavior on color { ColorAnimation { duration: Motion.standard } }
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - badge.width - parent.spacing
            spacing: 0
            StyledText {
                width: parent.width
                text: root.label
                variant: "label"
                font.weight: root.on ? Font.DemiBold : Font.Medium
                color: root.ink
                elide: Text.ElideRight
            }
            StyledText {
                width: parent.width
                visible: root.detail !== ""
                text: root.detail
                variant: "micro"
                color: root.inkDim
                elide: Text.ElideRight
            }
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; enabled: root.enabled; onTapped: root.activated() }

    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.checkable: true
    Accessible.checked: root.on
    Accessible.onPressAction: root.activated()
}
