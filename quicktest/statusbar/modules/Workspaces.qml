import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import "../../theming" as T

// ── Workspaces ────────────────────────────────────────────────────────────────
// Cleaned workspace indicator
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool barShape: false
    property var  monitor:  null

    readonly property int currentWs: monitor?.activeWorkspace?.id ?? 1
    readonly property int wsStart:   currentWs <= 5 ? 1 : 6

    implicitWidth:  120
    implicitHeight: T.Theme.pillHeight
    radius: T.Theme.radius(barShape)
    color:  T.Theme.pillBg

    Behavior on radius { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }

    RowLayout {
        anchors.centerIn: parent
        spacing: 8

        Repeater {
            model: 5
            delegate: Rectangle {
                id: dot

                readonly property int  wsId:      root.wsStart + index
                readonly property var  ws:        Hyprland.workspaces.values.find(w => w.id === wsId)
                readonly property bool isFocused: root.currentWs === wsId
                readonly property bool isOccupied: ws !== undefined && !isFocused
                readonly property bool isOnOther:  ws !== undefined && !isFocused && ws.monitor !== root.monitor

                Layout.preferredWidth:  isFocused ? 26 : 10
                Layout.preferredHeight: 10
                radius: barShape ? 2 : 5

                color: isFocused  ? T.Theme.color1
                     : isOnOther  ? T.Theme.pw(T.Theme.pal?.colors?.color4, 0.90)
                     : isOccupied ? T.Theme.pw(T.Theme.pal?.colors?.color2, 0.40)
                     :              T.Theme.wsEmpty

                Text {
                    anchors.centerIn: parent
                    text:             dot.wsId
                    visible:          dot.isFocused || dot.isOccupied
                    color:            T.Theme.bg
                    font { pixelSize: 7; bold: true; family: T.Theme.fontFamily }
                }

                Behavior on Layout.preferredWidth { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: T.Theme.animNormal } }
                Behavior on radius { NumberAnimation { duration: T.Theme.animSlow } }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + dot.wsId + ", on_current_monitor = true })")
                }
            }
        }
    }
}