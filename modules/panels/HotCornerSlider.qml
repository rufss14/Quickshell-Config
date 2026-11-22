import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"

// ── HotCornerSlider ───────────────────────────────────────────────────────────
// One level in the hot corner panel: an icon you can press (mute, for the volume) and a
// thick slider. The values come from the caller's service; this only shows them and says
// what was asked for.
// ─────────────────────────────────────────────────────────────────────────────
RowLayout {
    id: root

    property string symbol: ""
    property string title: ""
    property real value: 0
    property real maximum: 1
    property bool muted: false
    property bool iconActionable: false

    signal moved(real value)
    signal iconActivated()

    spacing: Tokens.spacingMd

    Item {
        Layout.preferredWidth: Tokens.iconXl
        Layout.preferredHeight: Tokens.iconXl
        Layout.alignment: Qt.AlignVCenter

        MaterialIcon {
            anchors.centerIn: parent
            name: root.symbol
            font.pixelSize: Tokens.iconMd
            color: root.muted ? Colors.of(QsWindow.window).fgDim : Colors.of(QsWindow.window).fg
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }
        MouseArea {
            anchors.fill: parent
            enabled: root.iconActionable
            cursorShape: Qt.PointingHandCursor
            onClicked: root.iconActivated()
        }
    }

    ValueSlider {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        accessibleName: root.title
        thickness: Tokens.spacingMd
        expressive: true
        value: root.value
        maximum: root.maximum
        onMoved: v => root.moved(v)
    }
}
