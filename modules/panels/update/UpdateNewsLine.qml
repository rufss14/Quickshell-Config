import "../../../services"
import "../../../state"
import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Io
import "../../../config"
import "../../../components"
import "../../../services/updatefmt.js" as UF

// ── NewsLine ─────────────────────────────────────────────────────────────
// The latest Arch news headline, when it's newer than your last full upgrade.
// Click opens it in a browser. See Updates.newsUnread for why the rule is blunt.
// (Was UpdatePanel's inline `NewsLine`.)
Rectangle {
    implicitHeight: newsRow.implicitHeight + Tokens.spacingSm * 2
    radius: Tokens.radiusPill
    color: nHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.20) : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.12)
    Behavior on color { ColorAnimation { duration: Motion.respond } }

    HoverHandler { id: nHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: Qt.openUrlExternally(Updates.newsUrl) }

    RowLayout {
        id: newsRow
        anchors.fill: parent
        anchors.leftMargin:  Tokens.spacingLg
        anchors.rightMargin: Tokens.spacingLg
        anchors.topMargin:   Tokens.spacingSm
        anchors.bottomMargin: Tokens.spacingSm
        spacing: Tokens.spacingMd

        MaterialIcon { name: "newspaper"; fill: 1; font.pixelSize: Tokens.iconMd; color: Colors.of(QsWindow.window).warning }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Arch news — check before you upgrade")
                variant: "micro"
                color: Colors.of(QsWindow.window).warning
                font.weight: Font.DemiBold
            }
            StyledText {
                Layout.fillWidth: true
                text: Updates.newsTitle
                variant: "caption"
                elide: Text.ElideRight
            }
        }
        MaterialIcon { name: "open_in_new"; font.pixelSize: Tokens.iconSm; color: Colors.of(QsWindow.window).fgDim }
    }
}
