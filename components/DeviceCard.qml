import QtQuick
import QtQuick.Layouts
import Quickshell
import "../config"
import "../services"

// ── DeviceCard ────────────────────────────────────────────────────────────────
// One audio output or input as a tonal card: its kind (headset, monitor, speaker — "HD-Audio Generic" tells a
// beginner nothing) on an M3E shape that is a plain disc until this is the device in use and then a cookie, the
// name and profile, its Bluetooth codec and volume limit as badges, and the card warming toward the accent for
// the one in use. A tap anywhere makes it the default.
//
// "Which is the default" comes from the service (`current`), not from local click state, so it stays right when
// something outside the shell changes it. An output (`isSink`) adds two labelled actions: send every playing app
// here, and open its options (the panel puts those below the card).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var   node:    null
    property var   current: null
    property bool  isSink:  false
    property real  cap:     0
    property bool  editing: false
    property bool  canMove: false           // something is playing elsewhere ("Play apps here")
    property color accent:  Colors.of(QsWindow.window).primary

    signal picked()
    signal moveHere()
    signal optionsToggled()

    readonly property bool on: root.node !== null && root.node === root.current
    readonly property string codec: Audio.bluetoothCodecOf(root.node)
    readonly property int pad: Tokens.spacingMd

    Layout.fillWidth: true
    implicitHeight: row.implicitHeight + root.pad * 2

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radiusCard
        color: root.on ? Colors.of(QsWindow.window).alpha(root.accent, tap.containsMouse ? 0.24 : 0.16)
                       : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, tap.containsMouse ? 0.10 : 0.06)
        Behavior on color { ColorAnimation { duration: Motion.respond } }
    }

    // Under the row, so a button inside never also picks the device.
    MouseArea {
        id: tap
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked()
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
            Layout.preferredWidth: Tokens.iconXl + Tokens.spacingMd
            Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd
            MorphShape {
                anchors.fill: parent
                shape: root.on ? "cookie12" : "circle"
                fillColor: root.on ? root.accent : Colors.of(QsWindow.window).surfaceHigh
            }
            MaterialIcon {
                anchors.centerIn: parent
                glyph: Audio.deviceGlyph(root.node)
                fill: root.on ? 1 : 0
                font.pixelSize: Tokens.iconLg
                color: root.on ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgMuted
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: Audio.shortLabelFor(root.node)
                variant: "body"
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: Audio.profileOf(root.node)
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
        }

        Badge {
            visible: root.codec !== ""
            label: root.codec
            tint: root.accent
        }
        Badge {
            visible: root.isSink && root.cap > 0
            label: "Limit " + Math.round(root.cap * 100) + "%"
            tint: Colors.of(QsWindow.window).warning
        }

        // Labelled: an icon alone doesn't say what these do.
        PanelButton {
            visible: root.isSink && root.canMove
            variant: "ghost"
            label: Translation.tr("Play apps here")
            accent: root.accent
            onActivated: root.moveHere()
        }
        PanelButton {
            visible: root.isSink
            variant: root.editing ? "primary" : "ghost"
            label: Translation.tr("Options")
            accent: root.accent
            onActivated: root.optionsToggled()
        }
    }
}
