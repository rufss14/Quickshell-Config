import QtQuick
import Quickshell
import "../../config"
import "widgets"

// ── SideWorkspaces ────────────────────────────────────────────────────────────
// The bar's workspaces (widgets/WorkspacesPill — five slots, paging, an indicator that
// stretches as it travels, occupied runs merged, a window dropped on a slot moves there),
// turned onto the sidebar: the same pill with `side` (sized from the sidebar's cell) and
// `vertical` (a quarter turn, slot 1 at the top). Four cells long (config/modules.js).
// Click a slot: that workspace. Everything else is the pill's own.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true
    // The HyprlandMonitor this sidebar is on (SideGroupHost hands it over).
    property var monitor: null

    implicitWidth:  pill.implicitWidth
    implicitHeight: pill.implicitHeight

    WorkspacesPill {
        id: pill
        anchors.fill: parent
        side: true
        vertical: root.vertical
        monitor: root.monitor
        accent: Config.moduleAccent("workspaces", Colors.of(QsWindow.window).primary)
    }
}
