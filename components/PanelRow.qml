pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── PanelRow ──────────────────────────────────────────────────────────────────
// One thing in a panel's list (a network, a display, a rule, a task), as a tonal M3E row: its symbol on a
// shape, a title over a line of detail, and whatever it offers on the right. ShapeTile is the toggle; this is
// the row that is a THING, which may or may not be clickable.
//
//   active      this is the one in use: the row takes `primaryContainer` and the disc morphs into `shape`
//   clickable   the whole row is a button (`activated`); it presses in on a spring and takes the state layer
//   available   false dims it and ignores the tap; the caller says why in `subtitle`
//
// Children are the trailing controls. `below` is content under the row, inside the same card (a slider, a
// password field), so a row can open out without becoming a second card.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string symbol:    ""
    property string glyph:     ""
    property url    iconSource: ""
    property string title:     ""
    property string subtitle:  ""
    property bool   active:    false
    property bool   clickable: false
    property bool   available: true
    property bool   badge:     true
    property string shape:     "cookie9"
    property color  accent:    Colors.of(QsWindow.window).primary
    property int    pad:       Tokens.spacingMd + Tokens.spacingXs
    property string help:      ""

    default property alias trailing: trailingRow.data
    property alias below: belowCol.data

    signal activated()

    readonly property bool hovered: hover.hovered && root.available
    readonly property color ink: root.active ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                                             : Colors.of(QsWindow.window).fg
    readonly property color inkDim: root.active ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fgOnPrimaryContainer, 0.78)
                                                : Colors.of(QsWindow.window).fgDim

    Layout.fillWidth: true
    Layout.fillHeight: false
    implicitHeight: body.implicitHeight + root.pad * 2
    opacity: root.available ? 1.0 : 0.5
    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

    SpringValue { id: press; target: tap.pressed && root.clickable && root.available ? 1 : 0; spec: Motion.springSpatialFast }
    scale: 1 - press.value * 0.03

    Accessible.role: root.clickable ? Accessible.Button : Accessible.ListItem
    Accessible.name: root.title
    Accessible.description: root.subtitle
    Accessible.onPressAction: if (root.clickable && root.available) root.activated()

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radiusCard
        color: root.active ? Colors.of(QsWindow.window).primaryContainer : Colors.of(QsWindow.window).section
        Behavior on color { ColorAnimation { duration: Motion.standard } }

        // The state layer: the row's ink at the hover alpha, only where the row acts.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: root.ink
            opacity: !root.clickable || !root.hovered ? 0 : tap.pressed ? Tokens.statePress + Tokens.stateHover : Tokens.stateHover
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        }
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: root.pad
        spacing: Tokens.spacingSm

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            Item {
                visible: root.badge
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Tokens.iconXl + Tokens.spacingMd
                Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd

                MorphShape {
                    anchors.fill: parent
                    shape: root.active ? root.shape : "circle"
                    fillColor: root.active ? root.accent : Colors.of(QsWindow.window).surfaceHigh
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    visible: root.iconSource.toString() === ""
                    name: root.symbol
                    glyph: root.glyph
                    fill: root.active ? 1 : 0
                    font.pixelSize: Tokens.iconLg
                    color: root.active ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgMuted
                }
                Image {
                    anchors.centerIn: parent
                    visible: root.iconSource.toString() !== ""
                    source: root.iconSource
                    width: Tokens.iconLg
                    height: Tokens.iconLg
                    sourceSize: Qt.size(Tokens.iconLg * 2, Tokens.iconLg * 2)
                    asynchronous: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    variant: "body"
                    font.weight: Font.DemiBold
                    color: root.ink
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.subtitle !== ""
                    text: root.subtitle
                    variant: "caption"
                    color: root.inkDim
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                id: trailingRow
                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
            }
        }

        ColumnLayout {
            id: belowCol
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: belowCol.children.length > 0
            spacing: Tokens.spacingSm
        }
    }

    HelpTip { text: root.help }
    HoverHandler { id: hover; cursorShape: root.clickable && root.available ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler   { id: tap; enabled: root.clickable && root.available; onTapped: root.activated() }
}
