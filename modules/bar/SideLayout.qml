import QtQuick
import Quickshell
import "../../config"
import "../../services"
import "../../state"

// ── SideLayout ────────────────────────────────────────────────────────────────
// Hyprland's layout on the sidebar: the current layout's icon; scroll steps through
// them live, click opens the layouts beside it (LayoutPanel — the bar's panel too).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true
    property var screen: null

    readonly property bool ownsPanel: UiState.sidePanelScreen
        ? UiState.sidePanelScreen === root.screen : root.screen === Quickshell.screens[0]

    implicitWidth:  Config.sidebarCell
    implicitHeight: Config.sidebarCell

    SideCell {
        anchors.fill: parent
        glyph: HyprLayout.info.glyph
        active: UiState.sidePanel === "layout" && root.ownsPanel
        wheel: true
        onScrolled: function (d) { HyprLayout.step(d > 0 ? -1 : 1) }
        onClicked:      UiState.toggleSidePanel("layout", "layout", root.screen)
        onRightClicked: UiState.openSettingsTo("SidebarPage.qml")
    }
}
