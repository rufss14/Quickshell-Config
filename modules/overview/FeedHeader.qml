import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"

// ── FeedHeader ────────────────────────────────────────────────────────────────
// The top of a page of the overview's left face (OverviewFeed): the compact notification card's
// header shape (NotificationCentre `slim`) — a scalloped chip, a two-word title whose second word
// wears the page's accent, a dim subtitle, and the page's chips on the right. Part of the PAGE,
// so it travels with it when the face is swiped.
// ─────────────────────────────────────────────────────────────────────────────
RowLayout {
    id: root

    property string symbol: ""
    property string title: ""
    property string tail: ""
    property string subtitle: ""
    property color accent: Colors.of(QsWindow.window).primary
    property bool hot: false
    default property alias actions: actionRow.data

    spacing: Tokens.spacingMd

    ScallopChip {
        Layout.alignment: Qt.AlignVCenter
        symbol: root.symbol
        tint: root.accent
        hot: root.hot
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.alignment: Qt.AlignVCenter
        spacing: 0
        Row {
            spacing: Tokens.spacingXs + 1
            StyledText {
                text: root.title
                variant: "body"
                font.weight: Font.DemiBold
            }
            StyledText {
                visible: root.tail !== ""
                text: root.tail
                variant: "body"
                font.weight: Font.DemiBold
                color: root.accent
            }
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.subtitle !== ""
            text: root.subtitle
            variant: "caption"
            emphasis: "dim"
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
