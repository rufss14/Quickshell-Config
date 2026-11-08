import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── ShapeTile ─────────────────────────────────────────────────────────────────
// A toggle with some life, for a setting worth a sentence: its icon sits on an M3E shape that is a plain disc
// while the setting is off and morphs into `shape` (a cookie, a burst, a clover…) when it turns on — turning
// one petal as it goes, on a spring that overshoots — and the tile presses in on a spring and washes in the
// accent. A second line says what the setting does right now, and an On / Off capsule says it at a glance.
//
// QuickToggleTile is the quiet version (a chip, two lines, a fill). This one is for a short list of settings that
// ARE the page (the Gaming panel's effects), where the tiles have room to be looked at. Same contract: a
// missing optional tool dims the tile and ignores the tap — the caller puts the reason in `subLabel`.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string symbol:   ""
    property string label:    ""
    property string subLabel: ""
    property string help:     ""
    property bool   active:   false
    property bool   available: true
    property color  accent:   Colors.of(QsWindow.window).primary
    // The shape the badge takes while the setting is on (components/shapes.js).
    property string shape:    "cookie9"

    signal toggled()

    readonly property bool hovered: hover.hovered && root.available
    readonly property int pad: Tokens.spacingMd + Tokens.spacingXs

    Layout.fillWidth: true
    implicitHeight: row.implicitHeight + root.pad * 2
    opacity: root.available ? 1.0 : 0.45
    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

    // Pressed in on a spring (position and size springs overshoot a little on release, which is the pop).
    SpringValue { id: press; target: tap.pressed && root.available ? 1 : 0; spec: Motion.springSpatialFast }
    scale: 1 - press.value * 0.05

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radiusCard
        color: root.active ? Colors.of(QsWindow.window).alpha(root.accent, root.hovered ? 0.26 : 0.18)
                           : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, root.hovered ? 0.10 : 0.06)
        Behavior on color { ColorAnimation { duration: Motion.respond } }
    }

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: root.pad
        spacing: Tokens.spacingMd

        Item {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Tokens.iconXl + Tokens.spacingLg
            Layout.preferredHeight: Tokens.iconXl + Tokens.spacingLg

            MorphShape {
                anchors.fill: parent
                shape: root.active ? root.shape : "circle"
                fillColor: root.active ? root.accent : Colors.of(QsWindow.window).surfaceHigh
            }
            MaterialIcon {
                anchors.centerIn: parent
                name: root.symbol
                fill: root.active ? 1 : 0
                font.pixelSize: Tokens.iconLg
                color: root.active ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgMuted
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: root.label
                variant: "body"
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: root.subLabel
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
        }

        // On / Off, as a capsule that fills with the accent.
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: Tokens.iconMd + Tokens.spacingSm
            implicitWidth: stateText.implicitWidth + Tokens.spacingLg * 2
            radius: height / 2
            color: root.active ? root.accent : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
            Behavior on color { ColorAnimation { duration: Motion.respond } }
            StyledText {
                id: stateText
                anchors.centerIn: parent
                text: root.active ? "On" : "Off"
                variant: "caption"
                font.weight: Font.DemiBold
                color: root.active ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgMuted
            }
        }
    }

    HelpTip { text: root.help }
    HoverHandler { id: hover; cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler   { id: tap; enabled: root.available; onTapped: root.toggled() }
}
