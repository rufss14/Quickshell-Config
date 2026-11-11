pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── PanelHero ─────────────────────────────────────────────────────────────────
// The subject of a bar or sidebar panel, as one tonal card: an M3E shape with the panel's symbol on it, a
// headline, a line of what is true right now, and the panel's main action on the right. It is the Game Mode
// panel's hero as a component, so every panel states its subject the same way.
//
//   active   the thing is on / connected / running: the card takes `primaryContainer`, the shape morphs from a
//            plain disc into `shape` and fills with the accent, and two rings leave it once. While `turning`
//            the shape turns slowly (render-thread RotationAnimator; rests with reduced motion).
//   warn     on, but something is wrong: the card leans to `warning` and the shape is a burst.
//
// Children are the trailing actions (a capsule PanelButton, a Toggle). `footer` is content inside the card under
// the row (a slider, a row of chips), so the controls that change the subject live in the same object.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property string symbol:    ""
    // The symbol while not `active`; "" = the same one, outlined.
    property string offSymbol: ""
    // A picture on the shape in place of the symbol (an app's icon).
    property url    iconSource: ""
    property string title:     ""
    property string line:      ""
    property bool   active:    false
    property bool   warn:      false
    property string shape:     "cookie9"
    property bool   turning:   root.active
    property color  accent:    Colors.of(QsWindow.window).primary
    property int    pad:       Tokens.spacingMd + Tokens.spacingXs
    // The badge's box. `compact` is for a hero that is one row among cards rather than the whole top.
    property bool   compact:   false
    // The headline's type step; "display" is for a hero whose title is a number to read at a glance (a clock).
    property string titleVariant: root.compact ? "title" : "headline"

    default property alias actions: actionRow.data
    property alias footer: footerCol.data

    // What sits on the card: text and custom footer content read it for contrast.
    readonly property color ink: root.warn || !root.active ? Colors.of(QsWindow.window).fg
                                                           : Colors.of(QsWindow.window).fgOnPrimaryContainer
    readonly property color inkDim: root.warn || !root.active ? Colors.of(QsWindow.window).fgMuted
                                                              : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fgOnPrimaryContainer, 0.78)

    Layout.fillWidth: true
    Layout.fillHeight: false
    implicitHeight: body.implicitHeight + root.pad * 2
    radius: Tokens.radiusXl
    color: root.warn   ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceContainer,
                                                        Colors.of(QsWindow.window).warning, 0.26)
         : root.active ? Colors.of(QsWindow.window).primaryContainer
         :               Colors.of(QsWindow.window).section
    Behavior on color { ColorAnimation { duration: Motion.standard } }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: root.pad
        spacing: Tokens.spacingMd

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingLg

            Item {
                id: badge
                Layout.alignment: Qt.AlignVCenter
                readonly property int box: root.compact ? Tokens.iconXl + Tokens.spacingLg
                                                        : Tokens.iconXl * 2 + Tokens.spacingMd
                Layout.preferredWidth: badge.box
                Layout.preferredHeight: badge.box

                Repeater {
                    model: 2
                    delegate: Rectangle {
                        id: ring
                        required property int index
                        anchors.centerIn: parent
                        width: badge.box
                        height: badge.box
                        radius: width / 2
                        color: "transparent"
                        border.width: Tokens.borderWidth * 2
                        border.color: root.accent
                        opacity: 0
                        SequentialAnimation {
                            id: ringAnim
                            PauseAnimation { duration: ring.index * Motion.respond * 2 }
                            ParallelAnimation {
                                NumberAnimation { target: ring; property: "scale"; from: 1; to: 1.6; duration: Motion.ripple; easing.type: Motion.travel }
                                NumberAnimation { target: ring; property: "opacity"; from: 0.55; to: 0; duration: Motion.ripple }
                            }
                        }
                        Connections {
                            target: root
                            function onActiveChanged() { if (root.active && Config.motionEnabled) ringAnim.restart() }
                        }
                    }
                }
                Item {
                    anchors.fill: parent
                    RotationAnimator on rotation {
                        running: root.turning && root.active && Motion.ambientOn && root.visible
                        from: 0; to: 360
                        duration: Motion.glide * 40
                        loops: Animation.Infinite
                    }
                    MorphShape {
                        anchors.fill: parent
                        shape: root.warn ? "burst" : root.active ? root.shape : "circle"
                        fillColor: root.warn   ? Colors.of(QsWindow.window).warning
                                 : root.active ? root.accent
                                 :               Colors.of(QsWindow.window).surfaceHigh
                    }
                }
                Image {
                    anchors.centerIn: parent
                    visible: root.iconSource.toString() !== ""
                    source: root.iconSource
                    width: badge.box * 0.56
                    height: width
                    sourceSize: Qt.size(128, 128)
                    asynchronous: true
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    visible: root.iconSource.toString() === ""
                    name: root.active || root.offSymbol === "" ? root.symbol : root.offSymbol
                    fill: root.active ? 1 : 0
                    font.pixelSize: root.compact ? Tokens.iconLg : Tokens.iconXl
                    color: root.warn   ? Colors.of(QsWindow.window).shadow
                         : root.active ? Colors.of(QsWindow.window).fgOnPrimary
                         :               Colors.of(QsWindow.window).fgMuted
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    variant: root.titleVariant
                    font.weight: Font.DemiBold
                    color: root.ink
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.line !== ""
                    text: root.line
                    variant: "label"
                    color: root.inkDim
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                id: actionRow
                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
            }
        }

        ColumnLayout {
            id: footerCol
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: footerCol.children.length > 0
            spacing: Tokens.spacingSm
        }
    }
}
