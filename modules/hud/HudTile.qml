import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"

// ── HudTile ───────────────────────────────────────────────────────────────────
// A one-press action on a HUD card: a symbol over a short label, on a lifted plate. Under the
// pointer it leans to 1.03 and presses to 0.95 on springs, with the shared state layer for the
// wash. `lit` is a state worth seeing at a glance (it is recording): the plate takes the `tint`.
// Disabled, it fades and takes no press.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    readonly property var pal: Colors.of(QsWindow.window)

    property string symbol: ""
    property string label: ""
    property bool lit: false
    property color tint: root.pal.primary
    signal activated()

    implicitWidth: Math.max(Tokens.sideCardUnit * 1.3, face.implicitWidth + Tokens.spacingMd * 2)
    implicitHeight: Tokens.sideCardUnit * 1.5
    radius: Tokens.radiusSm + Tokens.spacingXs
    color: root.lit ? root.pal.mix(root.pal.surfaceHigh, root.tint, 0.4) : root.pal.surfaceHigh
    opacity: root.enabled ? 1 : 0.45
    Behavior on color { ColorAnimation { duration: Motion.respond } }
    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

    SpringValue {
        id: lean
        target: !root.enabled ? 1 : press.pressed ? 0.95 : press.containsMouse ? 1.03 : 1
        spec: Motion.springSpatialFast
        epsilon: 0.0005
    }
    transform: Scale {
        origin.x: root.width / 2
        origin.y: root.height / 2
        xScale: lean.value
        yScale: lean.value
    }

    Column {
        id: face
        anchors.centerIn: parent
        spacing: Tokens.spacingXs
        MaterialIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: root.symbol
            fill: root.lit ? 1 : 0
            color: root.pal.fg
            font.pixelSize: Tokens.iconMd
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            variant: "label"
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
            color: root.pal.fg
        }
    }

    MouseArea {
        id: press
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.activated()
    }
    StateLayer {
        anchors.fill: parent
        radius: root.radius
        hovered: root.enabled && press.containsMouse
        layerColor: root.pal.fg
        reveal: true
        pointerX: press.mouseX
        pointerY: press.mouseY
    }
}
