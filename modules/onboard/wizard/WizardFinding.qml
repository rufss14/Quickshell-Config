import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/setupplan.js" as Plan
import "../../../state"

// ── One finding of the health check; a click goes to the page that fixes it ──
// (Was SetupWizard's inline `Finding`.)
Rectangle {
    id: fd
    property var issue: ({ level: "info", text: "", page: -1 })
    property bool shown: true
    property int pops: 0
    signal picked()
    readonly property bool linked: fd.issue.page >= 0

    PopIn { id: fdPop; active: fd.shown; index: fd.pops }
    implicitHeight: fdRow.implicitHeight + Tokens.spacingMd * 2
    radius: Tokens.radiusSm
    readonly property color tone: fd.issue.level === "bad" ? Colors.of(QsWindow.window).danger
                                : fd.issue.level === "warn" ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgDim
    color: Colors.of(QsWindow.window).alpha(fd.tone, fdHover.hovered && fd.linked ? 0.16 : 0.09)
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).alpha(fd.tone, 0.30)
    Behavior on color { ColorAnimation { duration: Motion.fast } }
    opacity: fdPop.opacity
    scale: fdPop.scale
    HoverHandler { id: fdHover; enabled: fd.linked }
    TapHandler { enabled: fd.linked; onTapped: fd.picked() }

    RowLayout {
        id: fdRow
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingMd
        MaterialIcon {
            name: fd.issue.level === "bad" ? "error" : fd.issue.level === "warn" ? "warning" : "info"
            fill: 1; color: fd.tone; font.pixelSize: Tokens.iconSm
        }
        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            text: fd.issue.text
            variant: "caption"; wrapMode: Text.WordWrap
        }
        StyledText {
            visible: fd.linked
            text: Translation.tr("Fix")
            variant: "caption"; font.weight: Font.Medium; color: Colors.of(QsWindow.window).primary
        }
        MaterialIcon {
            visible: fd.linked
            name: "chevron_right"; color: Colors.of(QsWindow.window).primary; font.pixelSize: Tokens.iconSm
        }
    }
}
