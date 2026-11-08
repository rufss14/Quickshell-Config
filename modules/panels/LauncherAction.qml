import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"

// ── LauncherAction ────────────────────────────────────────────────────────────
// The one actionable answer above the results: a sum, a command to run, a question to
// ask. A band of its own rather than a row in the list — it is not an app, it does not
// take the list's selection, and putting it in the model would make Down/Up land on
// something that cannot be launched.
//
// The whole band is the button; the panel decides what a tap does, so a click and
// Enter can never disagree about it.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property string icon: ""            // Material Symbols name
    property string title: ""
    property string detail: ""
    signal activated()

    readonly property var c: Colors.of(QsWindow.window)

    // M3E: a tonal plate on the accent's container, its glyph on a cookie, a state layer for
    // hover and a small spring squash for the press.
    radius: Tokens.radiusSm
    color: root.c.primaryContainer

    SpringValue {
        id: squash
        spec: Motion.springSpatialFast
        target: tap.pressed ? 0.985 : 1
        epsilon: 0.0005
    }
    scale: squash.value

    HoverHandler { id: hover }
    TapHandler { id: tap; onTapped: root.activated() }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.c.fgOnPrimaryContainer
        opacity: tap.pressed ? Tokens.statePress : hover.hovered ? Tokens.stateHover : 0
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin:  Tokens.spacingLg
        anchors.rightMargin: Tokens.spacingLg
        spacing: Tokens.spacingLg

        MorphShape {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth:  Tokens.iconXl
            Layout.preferredHeight: Tokens.iconXl
            shape: hover.hovered ? "cookie9" : "cookie6"
            fillColor: root.c.primary
            MaterialIcon {
                anchors.centerIn: parent
                name: root.icon
                color: root.c.fgOnPrimary
                font.pixelSize: Math.round(Tokens.iconXl * 0.58)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.title
                variant: "body"
                font.family: Tokens.fontMono
                font.bold: true
                color: root.c.fgOnPrimaryContainer
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: root.detail
                variant: "caption"
                color: root.c.alpha(root.c.fgOnPrimaryContainer, 0.8)
                elide: Text.ElideRight
            }
        }
    }
}
