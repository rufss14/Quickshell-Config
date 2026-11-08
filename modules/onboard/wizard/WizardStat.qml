import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/setupplan.js" as Plan
import "../../../state"

// ── A number and what it counts ──────────────────────────────────────────
// (Was SetupWizard's inline `Stat`.)
Rectangle {
    id: st
    property string big: ""
    property string caption: ""
    property bool shown: true
    property int pops: 0

    PopIn { id: stPop; active: st.shown; index: st.pops }
    implicitHeight: stCol.implicitHeight + Tokens.spacingLg * 2
    radius: Tokens.radiusPill
    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.09)
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.22)
    opacity: stPop.opacity
    scale: stPop.scale

    ColumnLayout {
        id: stCol
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: 0
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: st.big
            variant: "display"; font.weight: Font.DemiBold
            color: Colors.of(QsWindow.window).primary
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: st.caption
            variant: "caption"; emphasis: "dim"
        }
    }
}
