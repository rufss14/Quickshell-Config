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

// ── A welcome-page topic: plate, name, how it stands; a link to its page ──
// (Was SetupWizard's inline `Topic`; `host` is the SetupWizard.)
Rectangle {
    required property var host
    id: tp
    property string icon: ""
    property string title: ""
    property var info: ({ n: 0, todo: 0, done: false, blocked: false })
    property bool isOptional: false
    property bool shown: true
    property int pops: 0
    signal picked()

    PopIn { id: tpPop; active: tp.shown; index: tp.pops }
    implicitHeight: tpCol.implicitHeight + Tokens.spacingMd * 2
    radius: Tokens.radiusPill
    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, tpHover.hovered ? 0.08 : 0.035)
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, tpHover.hovered ? 0.4 : 0.1)
    Behavior on color { ColorAnimation { duration: Motion.fast } }
    Behavior on border.color { ColorAnimation { duration: Motion.fast } }
    opacity: tpPop.opacity
    scale: tpPop.scale * (tpHover.hovered ? 1.03 : 1)
    Behavior on scale {
        NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
    }
    HoverHandler { id: tpHover }
    TapHandler { onTapped: tp.picked() }

    ColumnLayout {
        id: tpCol
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingXs
        SetupCookie {
            Layout.alignment: Qt.AlignHCenter
            size: 38
            name: tp.icon
            hot: tpHover.hovered
            lit: !tp.info.done && tp.info.todo > 0
            badge: tp.info.done ? "ok" : ""
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: tp.title
            variant: "label"; font.weight: Font.Medium
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: host.topicText(tp.info, tp.isOptional)
            variant: "caption"
            color: tp.info.done ? Verdict.tint(true) : tp.info.todo > 0 ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgDim
        }
    }
}
