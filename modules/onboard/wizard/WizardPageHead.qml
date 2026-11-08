import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/setupplan.js" as Plan
import "../../../state"
import ".."

// ── A page's title block: a cookie, the name with its last word in the accent, a status ──
// (Was SetupWizard's inline `PageHead`.)
RowLayout {
    id: ph
    property string icon:   ""
    property string lead:   ""
    property string tail:   ""
    property string badge:  ""
    property string status: ""
    property bool   done:   false
    property bool   shown:  true

    Layout.fillWidth: true
    Layout.fillHeight: false
    spacing: Tokens.spacingMd

    PopIn { id: phPop; active: ph.shown }

    SetupCookie {
        Layout.alignment: Qt.AlignVCenter
        size: 46
        name: ph.icon
        lit: true
        turning: true
        badge: ph.done ? "ok" : ""
        opacity: phPop.opacity
        scale: phPop.scale
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.alignment: Qt.AlignVCenter
        spacing: 1
        RowLayout {
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            StyledText { text: ph.lead; variant: "headline"; font.weight: Font.DemiBold }
            StyledText { text: ph.tail; variant: "headline"; font.weight: Font.DemiBold; color: Colors.of(QsWindow.window).primary }
            Badge { visible: ph.badge !== ""; label: ph.badge; tint: Colors.of(QsWindow.window).fgDim }
        }
        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            visible: ph.status !== ""
            text: ph.status
            variant: "caption"; color: ph.done ? Verdict.tint(true) : Colors.of(QsWindow.window).fgDim; elide: Text.ElideRight
        }
    }
}
