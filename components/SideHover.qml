import QtQuick
import "../config"
import "../state"

// ── SideHover ─────────────────────────────────────────────────────────────────
// Hover on a sidebar cell opens a small card beside it (modules/panels/HoverCard,
// the side panel "hover"), and leaving puts it away. Non-visual, like ArmLatch: the
// cell says whether it is `hovered` and what to show (`arg`, the card's kind), and
// this decides WHEN.
//
// A hover card is a guest in the panel slot, never a tenant:
//   • it opens only when the slot is FREE — a panel the user opened is never pushed
//     aside by a pointer passing over another cell (the clips' peek's rule);
//   • it won't open over the bar's own panel column on this sidebar's side (opening a
//     side panel shuts that one);
//   • not while arranging, not while the sidebar is sunk.
// It opens after a short dwell (a pointer crossing the rail must not strobe cards) and
// closes a beat after leaving, so a pointer moving between two cells doesn't flicker.
//
// Both durations are interaction timings, not Motion durations: with motion off those
// are 0, and a dwell of 0 would be a card on every pass.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    property bool hovered: false
    // The cell's rail id (where the card opens beside) and the card's kind.
    property string from: ""
    property string arg: ""
    property var screen: null
    property bool enabled: true

    property int showMs: 450
    property int hideMs: 140

    readonly property bool ours: UiState.sidePanel === "hover" && UiState.sidePanelFrom === root.from
        && UiState.sidePanelArg === root.arg

    // The bar's panel column on the sidebar's own side: a side panel opening would close it.
    readonly property bool _barPanelOnSide:
        (Config.dockPosition === "left" ? UiState.leftKey
       : Config.dockPosition === "right" ? UiState.rightKey : "") !== ""

    function _open() {
        if (!root.hovered || !root.enabled || root.ours) return
        if (UiState.sidePanel !== "" || root._barPanelOnSide) return
        if (UiState.sidebarArrange || UiState.sidebarHidden) return
        UiState.openSidePanel("hover", root.from, root.screen, root.arg)
    }
    function _close() { if (root.ours) UiState.closeSidePanel() }

    property Timer _show: Timer { interval: root.showMs; onTriggered: root._open() }
    property Timer _hide: Timer { interval: root.hideMs; onTriggered: if (!root.hovered) root._close() }

    onHoveredChanged: {
        if (root.hovered) { root._hide.stop(); root._show.restart() }
        else              { root._show.stop(); root._hide.restart() }
    }
    // The cell's own thing came up (the power menu, a pick) with its card already out: put
    // it away rather than leave it standing until the pointer goes.
    onEnabledChanged: if (!root.enabled) root._close()
    // The cell left the layout (or the sidebar was rebuilt) with its card up.
    Component.onDestruction: root._close()
}
