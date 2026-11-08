import QtQuick
import Quickshell.Hyprland
import "../config"
import "../state"

// ── SidePeek ──────────────────────────────────────────────────────────────────
// An event on a sidebar module opens a card beside it for a moment (modules/panels/
// EventPeek, the side panel "peek"; `fire(kind)`). Non-visual, like SideHover: the
// module says WHAT happened, this decides WHETHER it may show. The clips peek's rules,
// for every module (2026-10-31, the user's pick: "event peeks"):
//   • only on the focused monitor — every screen's sidebar hears the event;
//   • only into a free slot: a panel the user opened is never pushed aside (a hover chip
//     is a guest, and gives way);
//   • not over the bar's own panel column on this side, not while arranging or sunk.
// A peek already up keeps its place: the next event waits for it to go.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    // The module's rail id (where the card opens beside) and the screen it is on.
    property string from: ""
    property var screen: null

    readonly property bool _barPanelOnSide:
        (Config.dockPosition === "left" ? UiState.leftKey
       : Config.dockPosition === "right" ? UiState.rightKey : "") !== ""

    function fire(kind) {
        if (UiState.sidePanel !== "" && UiState.sidePanel !== "hover") return
        if (root._barPanelOnSide || UiState.sidebarArrange || UiState.sidebarHidden) return
        const mon = Hyprland.focusedMonitor
        if (!mon || !root.screen || mon.name !== root.screen.name) return
        UiState.openSidePanel("peek", root.from, root.screen, kind)
    }
}
