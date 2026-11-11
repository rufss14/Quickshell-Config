import QtQuick
import Quickshell.Hyprland
import "../../config"
import "../../components"
import "../../state"

// ── BarDockPopups ─────────────────────────────────────────────────────────────
// What hangs off the dock when it is a TOP-BAR module (widgets/DockPill): its window
// previews (DockPreview, `edge: "top"`, a floating card under the bar — never melted:
// the bar's own panels own the lobes under it), its jump list (ContextMenu, opening at the
// clicked icon), and the keyboard — SUPER+T steers it, SUPER+ALT+n opens the nth app — as
// DockHost does for the sidebar's dock. Fills Bar.qml's window so a card can stand anywhere
// under the bar; the pill registers its strip here (`strip`), and Bar.qml folds the masks
// and focus wants below into the window's.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The bar dock's DockIconStrip, while there is one (DockPill sets and clears it).
    property var strip: null
    property var monitor: null

    readonly property ContextMenu menu: dockMenu
    readonly property bool previewHovered: preview.hovered
    readonly property Item previewMask: preview.maskItem
    readonly property Item menuMask: menuDismiss
    readonly property bool wantsKeyboardFocus: dockMenu.opened
    readonly property bool wantsExclusiveFocus: root.strip !== null && root.strip.kbActive

    DockPreview {
        id: preview
        anchors.fill: parent
        strip:     root.strip
        edge:      "top"
        monitor:   root.monitor
        fused:     false
        dockInner: Config.barExtent
        // Where the hovered icon is along the bar. Re-read as the hover moves (previewCenter);
        // the bar doesn't move under an open preview.
        anchorMain: root.strip && root.strip.previewCenter >= 0
            ? root.strip.mapToItem(root, root.strip.previewCenter, 0).x : -1
        peeks: Config.dockPeek
    }

    // While the jump list is open this joins the window's input mask, so the click that
    // dismisses it lands here instead of on the desktop below (DockHost's menuDismiss).
    Item {
        id: menuDismiss
        width:  dockMenu.opened ? root.width  : 0
        height: dockMenu.opened ? root.height : 0
    }

    ContextMenu {
        id: dockMenu
        anchors.fill: parent
    }

    // Escape closes the menu: on an Item, never the window (DockHost's escFocus).
    Item {
        id: escFocus
        Keys.onEscapePressed: dockMenu.close()
        Connections {
            target: dockMenu
            function onOpenedChanged() { if (dockMenu.opened) escFocus.forceActiveFocus() }
        }
    }

    // ── Keyboard, and SUPER+ALT+n: the dock on the FOCUSED monitor ────────────
    readonly property bool focusedHere: root.strip !== null
        && Hyprland.focusedMonitor !== null
        && Hyprland.focusedMonitor.name === (root.monitor?.name ?? "")

    Connections {
        target: UiState
        function onDockKeyboardChanged() {
            if (UiState.dockKeyboard && root.focusedHere) root.strip.kbStart()
        }
        function onDockActivateSeqChanged() {
            if (root.focusedHere) root.strip.activateAt(UiState.dockActivateIndex)
        }
        function onOverviewOpenChanged() { if (UiState.overviewOpen && root.strip) root.strip.kbStop() }
        function onLauncherOpenChanged() { if (UiState.launcherOpen && root.strip) root.strip.kbStop() }
    }
    Connections {
        target: root.strip
        ignoreUnknownSignals: true
        function onKbDone() { UiState.dockKeyboard = false }
        function onKbIndexChanged() { if (root.strip.kbActive) kbIdle.restart() }
    }
    // Exclusive focus holds the whole keyboard: let go after a spell with no keys.
    Timer {
        id: kbIdle
        interval: 8000
        onTriggered: if (root.strip) root.strip.kbStop()
    }
}
