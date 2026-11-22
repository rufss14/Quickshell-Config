import QtQuick
import QtQuick.Layouts
import Quickshell
import "../config"

// ── ToggleOrb ─────────────────────────────────────────────────────────────────
// A switch as a Material 3 Expressive toggle button: off, a round tonal button; on, it MORPHS into
// a filled cookie in the accent and the icon takes its filled form — the shape change is the
// state, which reads from across a room in a way a colour change alone doesn't. Pressing squashes
// it on the fast spatial spring; hover swells it a touch. A momentary action (next wallpaper,
// lock) is the same orb that never stays lit.
//
// Shared by the desktop toggles tile, the desktop menu and anything else that wants a row of
// them; the caller owns what "on" means and what a press does (ShellActions).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string label: ""
    property string symbolOn: ""
    property string symbolOff: ""
    property bool lit: false
    // Why it can't run here, or "": a missing backend dims it and says nothing on click.
    property string why: ""
    // Show the name under the orb.
    property bool named: true
    property color accent: Colors.of(QsWindow.window).primary
    property real maxSide: Tokens.iconXl * 2 + Tokens.spacingLg

    signal activated()

    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.checkable: true
    Accessible.checked: root.lit
    Accessible.onPressAction: if (root.why === "") root.activated()

    opacity: root.why === "" ? 1 : 0.4

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingXs

        Item {
            id: face
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property real side: Math.min(width, height, root.maxSide)

            SpringValue {
                id: squash
                spec: Motion.springSpatialFast
                epsilon: 0.0005
                target: mouse.pressed ? 0.88 : mouse.containsMouse && root.why === "" ? 1.06 : 1
            }

            MorphShape {
                anchors.centerIn: parent
                width: face.side
                height: face.side
                scale: squash.value
                spec: Motion.springSpatialFast
                shape: Config.barShape ? "squircle" : root.lit ? "cookie9" : "circle"
                fillColor: root.lit ? root.accent : Colors.of(QsWindow.window).plate
            }
            MaterialIcon {
                anchors.centerIn: parent
                scale: squash.value
                name: root.lit ? root.symbolOn : root.symbolOff
                fill: root.lit ? 1 : 0
                font.pixelSize: Math.round(face.side * 0.4)
                color: root.lit ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fg
            }
            MouseArea {
                id: mouse
                anchors.centerIn: parent
                width: face.side
                height: face.side
                enabled: root.why === ""
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.activated()
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.named
            horizontalAlignment: Text.AlignHCenter
            text: root.label
            variant: "caption"
            font.weight: root.lit ? Font.DemiBold : Font.Normal
            color: root.lit ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).fgMuted
            elide: Text.ElideRight
        }
    }
}
