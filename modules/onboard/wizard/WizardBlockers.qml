import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/setupplan.js" as Plan
import "../../../state"

// ── What stops it, or is worth knowing first ─────────────────────────────
// (Was SetupWizard's inline `Blockers`.)
ColumnLayout {
    spacing: Tokens.spacingSm
    Repeater {
        model: Setup.blockers
        delegate: Rectangle {
            id: bk
            required property var modelData
            readonly property bool fatal: modelData.level === "fatal"
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: bRow.implicitHeight + Tokens.spacingMd * 2
            radius: Tokens.radiusSm
            color: Colors.of(QsWindow.window).alpha(bk.fatal ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).warning, 0.12)
            border.width: Tokens.borderWidth
            border.color: Colors.of(QsWindow.window).alpha(bk.fatal ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).warning, 0.32)
            RowLayout {
                id: bRow
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                spacing: Tokens.spacingMd
                MaterialIcon {
                    name: bk.fatal ? "error" : "warning"; fill: 1
                    color: bk.fatal ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).warning
                    font.pixelSize: Tokens.iconSm
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: bk.modelData.text
                    variant: "caption"; wrapMode: Text.WordWrap
                }
                PanelButton {
                    visible: bk.fatal
                    variant: "ghost"
                    accent: Colors.of(QsWindow.window).primary
                    symbol: "refresh"; label: "Re-check"
                    onActivated: Setup.recheck()
                }
            }
        }
    }
}
