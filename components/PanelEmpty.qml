import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── PanelEmpty ────────────────────────────────────────────────────────────────
// A panel with nothing to list: its symbol on a tonal M3E shape, a title, and one line of what would put
// something here. The notification centre's "All caught up", as the one empty state every panel shows.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    property string symbol: ""
    property string title:  ""
    property string text:   ""
    property string shape:  Config.barShape ? "squircle" : "cookie9"
    // `quiet` is for "off" or "can't" (a surfaceHigh disc); the default is a state worth a little colour.
    property bool   quiet:  false

    Layout.fillWidth: true
    Layout.fillHeight: false
    Layout.topMargin: Tokens.spacingLg
    Layout.bottomMargin: Tokens.spacingLg
    spacing: Tokens.spacingSm

    Item {
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: Tokens.iconXl * 2 + Tokens.spacingLg
        implicitHeight: implicitWidth
        MorphShape {
            anchors.fill: parent
            shape: root.shape
            fillColor: root.quiet ? Colors.of(QsWindow.window).surfaceHigh : Colors.of(QsWindow.window).primaryContainer
        }
        MaterialIcon {
            anchors.centerIn: parent
            name: root.symbol
            fill: root.quiet ? 0 : 1
            font.pixelSize: Tokens.iconXl
            color: root.quiet ? Colors.of(QsWindow.window).fgMuted : Colors.of(QsWindow.window).fgOnPrimaryContainer
        }
    }
    StyledText {
        Layout.alignment: Qt.AlignHCenter
        visible: root.title !== ""
        text: root.title
        variant: "title"
        font.weight: Font.DemiBold
    }
    StyledText {
        Layout.fillWidth: true
        visible: root.text !== ""
        horizontalAlignment: Text.AlignHCenter
        text: root.text
        variant: "caption"
        emphasis: "dim"
        wrapMode: Text.WordWrap
    }
}
