import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── SideInactivity ────────────────────────────────────────────────────────────
// The idle rules (services/Inactivity) as one sidebar cell: a pause mark, monochrome like
// every glyph on the edge, dimmed while the rules are off.
//
//   click    the panel beside it (again: shut it)
//   middle   switch the rules on or off
//   right    Settings › Sidebar
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true
    property var screen: null

    readonly property bool ownsPanel: UiState.sidePanelScreen
        ? UiState.sidePanelScreen === root.screen : root.screen === Quickshell.screens[0]
    readonly property bool open: UiState.sidePanel === "inactivity" && root.ownsPanel

    implicitWidth:  Config.sidebarCell
    implicitHeight: Config.sidebarCell

    SideCell {
        anchors.fill: parent
        symbol: "pause_circle"
        active: root.open
        hoverKind: "inactivity"
        tint: Inactivity.enabled ? Colors.of(QsWindow.window).stateIdleFg : Colors.of(QsWindow.window).fgDim
        onClicked:       UiState.toggleSidePanel("inactivity", "inactivity", root.screen)
        onMiddleClicked: Inactivity.setEnabled(!Inactivity.enabled)
        onRightClicked:  UiState.openSettingsTo("SidebarPage.qml")
    }
}
