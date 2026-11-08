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

// ── A big choice card (Hyprland: which way) ──────────────────────────────
// (Was SetupWizard's inline `Choice`.)
Rectangle {
    id: cc
    property string icon: ""
    property string title: ""
    property string note: ""
    property bool picked: false
    property bool suggested: false
    property bool shown: true
    property int pops: 0
    signal chosen()

    PopIn { id: ccPop; active: cc.shown; index: cc.pops }
    implicitHeight: ccCol.implicitHeight + Tokens.spacingLg * 2
    radius: Tokens.radiusPill
    color: cc.picked ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.12)
         : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, ccHover.hovered ? 0.07 : 0.035)
    border.width: cc.picked ? 2 : Tokens.borderWidth
    border.color: cc.picked ? Colors.of(QsWindow.window).primary
                            : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, ccHover.hovered ? 0.18 : 0.08)
    Behavior on color { ColorAnimation { duration: Motion.fast } }
    Behavior on border.color { ColorAnimation { duration: Motion.fast } }
    opacity: ccPop.opacity
    scale: ccPop.scale * (ccHover.hovered && !cc.picked ? 1.015 : 1)
    Behavior on scale {
        NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
    }
    HoverHandler { id: ccHover }
    TapHandler { onTapped: cc.chosen() }

    ColumnLayout {
        id: ccCol
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingSm
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            SetupCookie { size: 40; name: cc.icon; lit: cc.picked; hot: ccHover.hovered }
            Item { Layout.fillWidth: true }
            Badge { visible: cc.suggested; label: "suggested"; tint: Colors.of(QsWindow.window).primary }
            // The mark that says this one is chosen.
            Rectangle {
                implicitWidth: 22; implicitHeight: 22; radius: 11
                color: cc.picked ? Colors.of(QsWindow.window).primary : "transparent"
                border.width: cc.picked ? 0 : 2
                border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.25)
                Behavior on color { ColorAnimation { duration: Motion.fast } }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: "check"; fill: 1
                    color: Colors.of(QsWindow.window).fgOnPrimary
                    font.pixelSize: Tokens.iconSm
                    scale: cc.picked ? 1 : 0
                    Behavior on scale {
                        NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
                    }
                }
            }
        }
        StyledText { text: cc.title; variant: "title"; font.weight: Font.DemiBold }
        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            text: cc.note
            variant: "caption"; emphasis: "dim"; wrapMode: Text.WordWrap
        }
        Item { Layout.fillHeight: true }
    }
}
