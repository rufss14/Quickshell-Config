pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"

// ── ScreenTimeChip ── part of ScreenTimePanel's hero ─────────────────────────────────────────────────
// A small pill: an icon (a Material Symbol, or an app's own picture) and one line. It pops in and out on
// a spring: its WIDTH is what springs, so a row of chips opens up for a newcomer instead of snapping, and
// the content scales and fades with it. `shown: false` takes it back out.
//
// `tappable` makes the whole pill a button (`tapped`); `stepper` puts a minus and a plus at its ends
// (`stepped(-1 | 1)`) — the goal chip, so the goal moves without leaving the card.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string symbol: ""
    property url iconSource: ""
    property string text: ""
    property color ink: Colors.of(QsWindow.window).fg
    property color plate: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.10)
    property bool shown: true
    // The line is cut here, so one long app name can't push the chip off the card.
    property real maxTextWidth: Tokens.sideCardUnit * 4
    property bool tappable: false
    property bool stepper: false
    signal tapped()
    signal stepped(int dir)

    SpringValue { id: pop; target: root.shown ? 1 : 0; spec: Motion.springSpatial }

    readonly property real _full: row.implicitWidth + Tokens.spacingMd * 2
    implicitWidth: Math.max(0, root._full * pop.value)
    implicitHeight: Tokens.iconLg + Tokens.spacingSm * 2
    visible: pop.value > 0.01
    clip: true

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.plate
        opacity: Math.min(1, pop.value)
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.tappable
        cursorShape: root.tappable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.tapped()
    }

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        x: Tokens.spacingMd
        spacing: Tokens.spacingSm
        opacity: Math.min(1, Math.max(0, pop.value * 1.4 - 0.4))
        scale: 0.7 + 0.3 * Math.min(1, pop.value)
        transformOrigin: Item.Left

        Item {
            visible: root.stepper
            Layout.preferredWidth: Tokens.iconMd + Tokens.spacingSm
            Layout.preferredHeight: Tokens.iconMd + Tokens.spacingSm
            Layout.alignment: Qt.AlignVCenter
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Colors.of(QsWindow.window).alpha(root.ink, minusMouse.containsMouse ? 0.22 : 0.10)
                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }
            MaterialIcon { anchors.centerIn: parent; name: "remove"; color: root.ink; font.pixelSize: Tokens.iconMd }
            MouseArea { id: minusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.stepped(-1) }
        }
        Item {
            Layout.preferredWidth: Tokens.iconMd
            Layout.preferredHeight: Tokens.iconMd
            Layout.alignment: Qt.AlignVCenter
            Image {
                anchors.fill: parent
                visible: root.iconSource.toString() !== ""
                source: root.iconSource
                sourceSize: Qt.size(Tokens.iconMd * 2, Tokens.iconMd * 2)
                fillMode: Image.PreserveAspectFit
                smooth: true
                layer.enabled: Config.colorizeIcons
                layer.effect: MonoIconEffect {}
            }
            MaterialIcon {
                anchors.centerIn: parent
                visible: root.iconSource.toString() === ""
                name: root.symbol
                color: root.ink
                font.pixelSize: Tokens.iconMd
            }
        }
        StyledText {
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: root.maxTextWidth
            text: root.text
            variant: "caption"
            font.weight: Font.Medium
            color: root.ink
            elide: Text.ElideRight
        }
        Item {
            visible: root.stepper
            Layout.preferredWidth: Tokens.iconMd + Tokens.spacingSm
            Layout.preferredHeight: Tokens.iconMd + Tokens.spacingSm
            Layout.alignment: Qt.AlignVCenter
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Colors.of(QsWindow.window).alpha(root.ink, plusMouse.containsMouse ? 0.22 : 0.10)
                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }
            MaterialIcon { anchors.centerIn: parent; name: "add"; color: root.ink; font.pixelSize: Tokens.iconMd }
            MouseArea { id: plusMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.stepped(1) }
        }
    }
}
