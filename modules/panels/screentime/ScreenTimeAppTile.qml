pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── ScreenTimeAppTile ── part of ScreenTimePanel's pages ──────────────────────────────────────────────
// One app of a legend: its icon on a plate of the tint it wears in the bars and beads, its name, and a line
// (`detail`: its week, or its share of the day). `other` is the neutral "everyone else" tile. It springs in when
// `when` turns true (`delay` ms late), swells under the pointer, and says so through `hovered`, so a page can
// light that app's slice and dim the rest.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: tile

    required property var panel
    property string appId: ""
    property bool other: false
    property int rank: 0
    property string detail: ""
    property bool when: true
    property int delay: 0

    readonly property bool hovered: mouse.containsMouse
    readonly property string icon: tile.other ? "" : ScreenTime.iconOf(tile.appId)

    implicitHeight: col.implicitHeight + Tokens.spacingMd * 2
    radius: Tokens.radiusCard - Tokens.spacingSm
    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, tile.hovered ? 0.10 : 0.05)
    Behavior on color { ColorAnimation { duration: Motion.respond } }

    SpringReveal { id: pop; when: tile.when; delay: tile.delay; spec: Motion.springSpatial }
    SpringValue { id: hov; target: tile.hovered ? 1 : 0; spec: Motion.springSpatialFast }
    opacity: Math.min(1, pop.value)
    scale: (0.85 + 0.15 * Math.min(1.1, pop.value)) * (1 + 0.04 * hov.value)

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingXs

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Tokens.iconXl + Tokens.spacingMd
            Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Colors.of(QsWindow.window).alpha(tile.panel.tint(tile.rank), 0.28)
                border.width: Tokens.borderWidth * 2
                border.color: tile.panel.tint(tile.rank)
            }
            Image {
                anchors.centerIn: parent
                width: Tokens.iconLg
                height: Tokens.iconLg
                visible: tile.icon !== ""
                source: tile.icon
                sourceSize: Qt.size(Tokens.iconLg * 2, Tokens.iconLg * 2)
                fillMode: Image.PreserveAspectFit
                smooth: true
                layer.enabled: Config.colorizeIcons
                layer.effect: MonoIconEffect {}
            }
            MaterialIcon {
                anchors.centerIn: parent
                visible: tile.icon === ""
                name: tile.other ? "more_horiz" : ScreenTime.isGame(tile.appId) ? "sports_esports" : "apps"
                color: Colors.of(QsWindow.window).fgMuted
                font.pixelSize: Tokens.iconLg
            }
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: tile.other ? Translation.tr("Other") : ScreenTime.labelOf(tile.appId)
            variant: "caption"
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: tile.detail
            variant: "caption"
            emphasis: "dim"
            elide: Text.ElideRight
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
    }
}
