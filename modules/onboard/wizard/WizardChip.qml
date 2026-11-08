import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/setupplan.js" as Plan
import "../../../state"

// ── A small status pill: a mark and a few words ─────────────────────────
// (Was SetupWizard's inline `Chip`.)
Rectangle {
    id: ch
    property string text: ""
    property string level: "unknown"       // ok | warn | bad | unknown
    property bool shown: true
    property int pops: 0

    PopIn { id: chPop; active: ch.shown; index: ch.pops }
    implicitHeight: 26
    implicitWidth: chRow.implicitWidth + Tokens.spacingMd * 2
    radius: Tokens.corner(Config.barShape, height / 2)
    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.05)
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.10)
    opacity: chPop.opacity
    scale: chPop.scale

    Row {
        id: chRow
        anchors.centerIn: parent
        spacing: 5
        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: ch.level === "ok" ? "check_circle" : ch.level === "bad" ? "error" : ch.level === "warn" ? "warning" : "remove"
            fill: ch.level === "unknown" ? 0 : 1
            color: ch.level === "ok" ? Verdict.tint(true) : ch.level === "bad" ? Verdict.tint(false)
                 : ch.level === "warn" ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgDim
            font.pixelSize: Tokens.iconSm - 1
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: ch.text
            variant: "caption"
        }
    }
}
