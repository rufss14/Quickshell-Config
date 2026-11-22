import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── UpdateNewsCard ── the newest Arch news post, always (island only; 2026-11-15). ────────────────────────────
// On the island this stands in for UpdateNewsLine: the latest headline and its date, whether or not you have seen
// it. Posted after your last full upgrade (Updates.newsUnread) its badge fills in the accent, a dot sits on it and
// the foot says so in the warning tone; older, it stays quiet. A press opens the post. The feed is fetched when
// the card appears (refreshNews keeps its 30-minute floor).
Rectangle {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property bool unread: Updates.newsUnread
    readonly property string dateText: Updates.newsDate === "" ? ""
        : new Date(Updates.newsDate + "T00:00:00").toLocaleDateString(Qt.locale(), "d MMM yyyy")

    Component.onCompleted: Updates.refreshNews()

    implicitHeight: col.implicitHeight + Tokens.spacingMd * 2
    radius: Tokens.radiusXl
    color: root.palette.plate

    SpringValue {
        id: lean
        target: area.pressed ? 0.97 : area.containsMouse ? 1.015 : 1
        spec: Motion.springSpatialFast
        epsilon: 0.001
    }
    scale: lean.value

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Qt.openUrlExternally(Updates.newsUrl)
    }
    StateLayer {
        anchors.fill: parent
        radius: root.radius
        hovered: area.containsMouse
    }
    Accessible.role: Accessible.Link
    Accessible.name: Translation.tr("Arch news: %1").arg(Updates.newsTitle)
    Accessible.onPressAction: Qt.openUrlExternally(Updates.newsUrl)

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingXs

        RowLayout {
            Layout.fillHeight: false
            Layout.fillWidth: true
            spacing: Tokens.spacingSm
            Item {
                implicitWidth: Tokens.iconLg + Tokens.spacingXs
                implicitHeight: implicitWidth
                MorphShape {
                    anchors.fill: parent
                    shape: root.unread ? "cookie6" : "circle"
                    spec: Motion.springSpatialFast
                    turns: false
                    fillColor: root.unread ? root.palette.primary : root.palette.alpha(root.palette.fg, 0.10)
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: "newspaper"
                    fill: 1
                    font.pixelSize: Tokens.iconMd
                    color: root.unread ? root.palette.fgOnPrimary : root.palette.fgDim
                }
                Rectangle {
                    visible: root.unread
                    anchors.top: parent.top
                    anchors.right: parent.right
                    width: Tokens.spacingSm
                    height: width
                    radius: width / 2
                    color: root.palette.warning
                    border.width: 2
                    border.color: root.color
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: Translation.tr("Arch news")
                    variant: "micro"
                    color: root.palette.fgDim
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.dateText !== ""
                    text: root.dateText
                    variant: "micro"
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }
            MaterialIcon {
                Layout.alignment: Qt.AlignTop
                name: "open_in_new"
                font.pixelSize: Tokens.iconSm
                color: root.palette.fgDim
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: Updates.newsTitle !== "" ? Updates.newsTitle : Translation.tr("Open the news page")
            variant: "caption"
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
        }
        StyledText {
            Layout.fillWidth: true
            text: root.unread ? Translation.tr("New since your last upgrade") : Translation.tr("Read before upgrading")
            variant: "micro"
            font.weight: root.unread ? Font.DemiBold : Font.Normal
            color: root.unread ? root.palette.warning : root.palette.fgDim
            elide: Text.ElideRight
        }
    }
}
