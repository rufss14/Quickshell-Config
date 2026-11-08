import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── ChatComposer ──────────────────────────────────────────────────────────────
// The Ask page's box: a tall pill (the shell's InputField) with the send button INSIDE it, at the
// right end. The button is a quiet circle while the box is empty, fills with the accent and grows a
// little the moment there's something to send, and turns into a stop while a reply is on its way
// (a ring winding round it). Enter sends; Escape empties the box first and only then lets the
// overview have it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property color accent: Colors.of(QsWindow.window).primary
    property string placeholder: ""
    property bool busy: false
    property bool ready: true
    signal sent(string text)
    signal stopped()

    readonly property bool hasText: field.text.trim() !== ""
    function clear() { field.clear() }
    function focus_() { field.forceFocus() }

    implicitHeight: Tokens.fieldHeight + Tokens.spacingSm

    InputField {
        id: field
        anchors.fill: parent
        cornerRadius: height / 2
        elevation: Tokens.elevationCard
        enabled: root.ready
        icon: "auto_awesome"
        placeholder: root.placeholder
        trailingSpace: send.width + Tokens.spacingXs
        onAccepted: value => { if (root.ready && !root.busy && value.trim() !== "") root.sent(value.trim()) }
        onKeyPressed: event => {
            if (event.key === Qt.Key_Escape && field.text !== "") { field.clear(); event.accepted = true }
        }
    }

    // ── Send / stop ───────────────────────────────────────────────────────────
    Rectangle {
        id: send
        readonly property bool live: root.busy || (root.hasText && root.ready)
        anchors.right: parent.right
        anchors.rightMargin: Tokens.spacingXs + 1
        anchors.verticalCenter: parent.verticalCenter
        width: root.height - Tokens.spacingSm * 2
        height: width
        radius: width / 2
        color: root.busy ? Colors.of(QsWindow.window).alpha(root.accent, 0.2)
             : send.live ? root.accent
             : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, sendHover.hovered ? 0.1 : 0.05)
        SpringValue { id: sendLean; target: sendTap.pressed ? 0.88 : (send.live && !root.busy ? 1.04 : 1); spec: Motion.springSpatialFast; epsilon: 0.001 }
        scale: sendLean.value
        Behavior on color { ColorAnimation { duration: Motion.respond } }

        MaterialIcon {
            anchors.centerIn: parent
            name: root.busy ? "stop" : "arrow_upward"
            fill: 1
            font.pixelSize: Tokens.iconSm + 2
            color: root.busy ? root.accent
                 : send.live ? (root.accent.hslLightness > 0.5 ? Colors.of(QsWindow.window).base : Colors.of(QsWindow.window).fg)
                 : Colors.of(QsWindow.window).fgDim
            // The arrow lifts a little as it becomes sendable.
            SpringValue { id: arrowLift; target: send.live && !root.busy ? 0 : 2; spec: Motion.springSpatialFast }
            transform: Translate { y: arrowLift.value }
        }
        // While a reply is coming: a short arc winding round the stop.
        Canvas {
            id: ring
            anchors.fill: parent
            visible: root.busy
            property real turn: 0
            onPaint: {
                const g = getContext("2d")
                g.reset()
                g.lineWidth = 2
                g.lineCap = "round"
                g.strokeStyle = root.accent
                g.beginPath()
                g.arc(width / 2, height / 2, width / 2 - 2, ring.turn, ring.turn + Math.PI * 0.6)
                g.stroke()
            }
            onTurnChanged: requestPaint()
            NumberAnimation on turn {
                running: root.busy && Config.motionEnabled
                from: 0; to: Math.PI * 2
                duration: 900
                loops: Animation.Infinite
            }
        }
        HoverHandler { id: sendHover; cursorShape: send.live ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler {
            id: sendTap
            enabled: send.live
            onTapped: root.busy ? root.stopped() : root.sent(field.text.trim())
        }
    }
}
