import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/setupplan.js" as Plan
import "../../../state"

// ── A key combination as keycaps: "SUPER + R" ────────────────────────────
// (Was SetupWizard's inline `KeyCombo`.)
Row {
    id: kc
    property string combo: ""
    spacing: 3
    Repeater {
        model: kc.combo.split("+").map(k => k.trim()).filter(k => k !== "")
        delegate: Rectangle {
            id: cap
            required property string modelData
            implicitWidth: Math.max(22, capText.implicitWidth + Tokens.spacingMd * 2)
            implicitHeight: 22
            radius: Tokens.radiusXs
            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
            border.width: Tokens.borderWidth
            border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.18)
            StyledText {
                id: capText
                anchors.centerIn: parent
                text: cap.modelData.toUpperCase()
                variant: "caption"; font.weight: Font.Medium; font.family: Tokens.fontMono
            }
        }
    }
}
