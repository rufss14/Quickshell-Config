import QtQuick
import "../../config"
import "../../services"
import "../../state"

// ── SidePower ─────────────────────────────────────────────────────────────────
// The sidebar's power button: one cell. The actions are the power menu's
// (modules/bar/PowerDock — a column on the frame's edge, all but lock asking
// twice), not a column of cells on the sidebar. It used to be five cells, one per
// action, each an ArmLatch; that read as a tower of buttons beside the dock.
//
//   click   the power menu (again, or Escape: shut it)
//   middle  lock — the one action that never asks
//   right   Settings › Sidebar
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true

    implicitWidth:  Config.sidebarCell
    implicitHeight: Config.sidebarCell

    SideCell {
        id: cell
        hoverKind: "power"
        // Ask what the machine can do (hibernate, firmware) before the click needs it.
        onHoveredChanged: if (cell.hovered && Session.bootEpoch <= 0) Session.probe()
        glyph:  "\u{F0425}"                                             // 󰐥 power
        active: UiState.powerMenuOpen
        onClicked:       UiState.powerMenuOpen = !UiState.powerMenuOpen
        onMiddleClicked: Session.lock()
        onRightClicked:  UiState.openSettingsTo("SidebarPage.qml")
    }
}
