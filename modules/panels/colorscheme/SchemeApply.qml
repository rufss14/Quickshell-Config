import QtQuick
import Quickshell
import "../../../config"
import "../../../components"

// ── SchemeApply ───────────────────────────────────────────────────────────────
// The page's one loud action. A filled pill in the accent with a round badge: idle it is a quiet disc with a
// palette, while the run goes the disc turns into a spinning cookie and breathes, and when it lands the badge
// pops into a tick on the page's `done` colour and the label says so. A press dips it, the pointer leans it in.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property string label: ""
    property string doneLabel: ""
    property string busyLabel: ""
    property bool busy: false
    property bool done: false
    // Colour of the tick once it landed (Verdict.tint(true): the one "it worked" colour that does not follow the wallpaper).
    property color doneTint: Colors.of(QsWindow.window).primary
    signal activated()

    readonly property var palette: Colors.of(QsWindow.window)

    implicitHeight: Tokens.iconXl + Tokens.spacingMd
    implicitWidth: row.implicitWidth + Tokens.spacingLg * 2 + Tokens.spacingSm
    radius: height / 2
    color: root.palette.primary
    opacity: root.enabled ? 1 : 0.45
    Behavior on opacity { NumberAnimation { duration: Motion.respond } }

    SpringValue {
        id: lean
        target: tap.pressed ? 0.95 : hover.hovered && root.enabled ? 1.03 : 1
        spec: Motion.springSpatialFast
        epsilon: 0.001
    }
    scale: lean.value

    onDoneChanged: if (root.done) tickPop.restart()

    StateLayer {
        anchors.fill: parent
        radius: root.radius
        hovered: hover.hovered && root.enabled
        layerColor: root.palette.fgOnPrimary
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Tokens.spacingSm

        Item {
            id: tick
            anchors.verticalCenter: parent.verticalCenter
            width: Tokens.iconLg + Tokens.spacingXs
            height: width
            property real pop: 1
            property real breath: 1
            SequentialAnimation {
                id: tickPop
                NumberAnimation { target: tick; property: "pop"; from: 0.4; to: 1.35; duration: Motion.respond; easing.type: Motion.travel }
                NumberAnimation { target: tick; property: "pop"; to: 1; duration: Motion.standard; easing.type: Motion.overshoot }
            }
            SequentialAnimation {
                loops: Animation.Infinite
                running: root.busy && root.visible && Config.motionEnabled
                NumberAnimation { target: tick; property: "breath"; to: 0.35; duration: Motion.standard; easing.type: Motion.inOut }
                NumberAnimation { target: tick; property: "breath"; to: 1; duration: Motion.standard; easing.type: Motion.inOut }
            }
            MorphShape {
                anchors.fill: parent
                shape: root.busy ? "cookie6" : "circle"
                spec: Motion.springSpatialFast
                turns: false
                fillColor: root.done ? root.palette.fgOnPrimary
                         : root.palette.alpha(root.palette.fgOnPrimary, root.busy ? 0.32 : 0.2)
                Behavior on fillColor { ColorAnimation { duration: Motion.standard } }
                NumberAnimation on rotation {
                    from: 0; to: 360
                    duration: Motion.spin
                    loops: Animation.Infinite
                    running: root.busy && root.visible && Config.motionEnabled
                }
            }
            MaterialIcon {
                anchors.centerIn: parent
                name: root.done ? "check" : "palette"
                fill: 1
                font.pixelSize: Tokens.iconMd
                color: root.done ? root.doneTint : root.palette.fgOnPrimary
                opacity: root.busy ? tick.breath : 1
                scale: tick.pop
                Behavior on color { ColorAnimation { duration: Motion.standard } }
            }
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.busy ? root.busyLabel : root.done ? root.doneLabel : root.label
            variant: "label"
            font.weight: Font.DemiBold
            color: root.palette.fgOnPrimary
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; enabled: root.enabled; onTapped: root.activated() }

    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.onPressAction: root.activated()
}
