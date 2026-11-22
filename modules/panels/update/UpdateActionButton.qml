import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"

// ── UpdateActionButton ── a full-width action of the update panel; `host` is the UpdatePanel. ─────────────────
// Redone 2026-11-15 with the password card (UpdatePasswordField), so the two read as one set: a card, not a pill.
//   primary    THE thing to do: a loud card in the accent, its symbol on a badge that blooms (circle → cookie)
//              under the pointer, the label large, an arrow at the end
//   secondary  the other option: the same card, quiet (the lifted tone), a smaller badge
// Off (`disabled`, nothing typed yet) it steps back to the quiet tone whatever it is, and says nothing new.
// Under the pointer it leans in a little; a press dips it, on the shell's fast spatial spring.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    required property var host
    property string icon
    property string text
    property var clickHandler: null
    property bool  disabled: false
    property bool  primary: true

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property bool loud: root.primary && !root.disabled
    readonly property color ink: root.loud ? root.palette.fgOnPrimary : root.disabled ? root.palette.fgDim : root.palette.fg

    Layout.fillWidth: true
    implicitHeight: root.primary ? Tokens.iconXl + Tokens.spacingLg * 2 : Tokens.iconXl + Tokens.spacingMd
    radius: root.primary ? Tokens.radiusXl : Tokens.radiusCard
    color: root.loud ? root.palette.primary : root.palette.plate
    Behavior on color { ColorAnimation { duration: Motion.standard } }

    SpringValue {
        id: lean
        target: area.pressed ? 0.97 : area.containsMouse && !root.disabled ? 1.015 : 1
        spec: Motion.springSpatialFast
        epsilon: 0.001
    }
    scale: lean.value

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: !root.disabled
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.clickHandler) root.clickHandler()
    }
    StateLayer {
        anchors.fill: parent
        radius: root.radius
        hovered: area.containsMouse && !root.disabled
        layerColor: root.ink
    }

    Accessible.role: Accessible.Button
    Accessible.name: root.text
    Accessible.onPressAction: if (!root.disabled && root.clickHandler) root.clickHandler()

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.spacingMd
        anchors.rightMargin: Tokens.spacingLg
        spacing: Tokens.spacingMd

        Item {
            implicitWidth: root.primary ? Tokens.iconXl + Tokens.spacingXs : Tokens.iconXl
            implicitHeight: implicitWidth
            MorphShape {
                anchors.fill: parent
                shape: area.containsMouse && !root.disabled ? "cookie9" : "circle"
                spec: Motion.springSpatialFast
                turns: false
                fillColor: root.loud ? root.palette.alpha(root.palette.fgOnPrimary, 0.18)
                                     : root.palette.alpha(root.palette.fg, root.disabled ? 0.05 : 0.10)
            }
            MaterialIcon {
                anchors.centerIn: parent
                name: root.icon
                fill: 1
                color: root.ink
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: root.text
            variant: root.primary ? "title" : "label"
            font.weight: Font.DemiBold
            color: root.ink
            elide: Text.ElideRight
        }
        MaterialIcon {
            visible: root.primary
            name: "chevron_right"
            color: root.ink
            opacity: root.disabled ? 0.4 : 1
        }
    }
}
