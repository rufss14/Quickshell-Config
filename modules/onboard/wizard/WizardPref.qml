import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/setupplan.js" as Plan
import "../../../state"

// ── One preference: what it is on the left, the control on the right ─────
// The control is the child (anchored into the slot it is given).
// (Was SetupWizard's inline `Pref`.)
Rectangle {
    id: pf
    property string title: ""
    property string note: ""
    property bool shown: true
    property int pops: 0
    property real controlWidth: 230
    default property alias control: slot.data

    PopIn { id: pfPop; active: pf.shown; index: pf.pops }
    Layout.fillWidth: true
    Layout.fillHeight: false
    implicitHeight: pfRow.implicitHeight + Tokens.spacingMd * 2
    radius: Tokens.radiusPill
    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.035)
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
    opacity: pfPop.opacity
    scale: pfPop.scale

    RowLayout {
        id: pfRow
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingLg
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 1
            StyledText { text: pf.title; variant: "body"; font.weight: Font.DemiBold }
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: pf.note
                variant: "caption"; emphasis: "dim"; wrapMode: Text.WordWrap
            }
        }
        Item {
            id: slot
            Layout.preferredWidth: pf.controlWidth
            Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
