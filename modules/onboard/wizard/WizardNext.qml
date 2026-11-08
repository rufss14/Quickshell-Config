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

// ── A "what next" card on the all-set page ───────────────────────────────
// (Was SetupWizard's inline `Next`.)
Rectangle {
    id: nx
    property string icon: ""
    property string title: ""
    property string note: ""
    property bool shown: true
    property int pops: 0
    signal picked()

    PopIn { id: nxPop; active: nx.shown; index: nx.pops }
    implicitHeight: nxCol.implicitHeight + Tokens.spacingMd * 2
    radius: Tokens.radiusPill
    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, nxHover.hovered ? 0.08 : 0.035)
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, nxHover.hovered ? 0.4 : 0.1)
    Behavior on color { ColorAnimation { duration: Motion.fast } }
    opacity: nxPop.opacity
    scale: nxPop.scale * (nxHover.hovered ? 1.03 : 1)
    Behavior on scale {
        NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
    }
    HoverHandler { id: nxHover }
    TapHandler { onTapped: nx.picked() }

    ColumnLayout {
        id: nxCol
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingXs
        SetupCookie { Layout.alignment: Qt.AlignHCenter; size: 36; name: nx.icon; hot: nxHover.hovered }
        StyledText { Layout.alignment: Qt.AlignHCenter; text: nx.title; variant: "label"; font.weight: Font.Medium }
        StyledText { Layout.alignment: Qt.AlignHCenter; text: nx.note; variant: "caption"; emphasis: "dim" }
    }
}
