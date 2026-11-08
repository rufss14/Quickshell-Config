import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../config"
import "../../state"
import "../../services/dock.js" as DockJs

// ── DockReserve ───────────────────────────────────────────────────────────────
// Reserves the dock's strip of screen — Config.dockTakesSpace — so tiled windows
// make room for it. Transparent, takes no input, draws nothing: its exclusive
// zone is its entire job, the same deal as ScreenFrame's ReserveStrip.
//
// ── Why the dock can't reserve its own space ─────────────────────────────────
// The dock itself lives in Bar's window (modules/bar/DockHost), because that is
// the only way Quicktest.Blobs can melt it out of the screen frame — the blob
// fuses shapes within one scene graph, never across layer-shell surfaces. But
// Bar's window is anchored to the TOP and reserves the bar's own zone there; one
// surface holds one reservation on one edge. So the zone for the bottom (or
// side) edge has to be a window of its own, and this is it.
//
// Mapped after ScreenFrame's reservations (shell.qml declares it later), so its
// zone stacks on top of the frame's strip rather than overlapping it — which is
// where the dock actually sits.
//
// Never while auto-hiding: a reserved band for a dock that is off screen most of
// the time is just a dead strip, and it would make the reveal pointless.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: root

    // `screen` is PanelWindow's OWN property, assigned by shell.qml — deliberately
    // not redeclared here. `required property var screen` would declare a second,
    // QML-side `screen` that SHADOWS the window's: the assignment would land on the
    // shadow and the layer surface would never learn its output (measured with a C++
    // Timer.interval: the redeclared value never reached C++). Every reservation
    // would then map on the same default screen. This window is mapped on every
    // screen at once, so unlike a focused-monitor overlay nothing hides that.

    // Anything that isn't a side reads as "bottom" — the same rule DockHost uses,
    // so a hand-edited position can't reserve one edge and draw on another.
    readonly property string edge:
        (Config.dockPosition === "left" || Config.dockPosition === "right")
            ? Config.dockPosition : "bottom"

    // Not while the sidebar is hidden (SUPER+D): windows get the space back.
    // It reserves for the whole edge whichever modules stand on it, and not while it
    // auto-hides: the sidebar hides as one (SideBarHost).
    readonly property bool wanted: Config.dockTakesSpace && !UiState.sidebarHidden
                                   && Config.sidebarAnyPlaced && !Config.sidebarAutoHide

    // Lags `wanted` on the way OUT by the sidebar's exit slide. Unmapping at the
    // first frame made Hyprland re-tile every window while the bar was still
    // sliding into the frame, and the slide stuttered under it. Reserving again is
    // immediate: the bar must not come out over windows.
    property bool held: false
    onWantedChanged: {
        if (root.wanted) { release.stop(); root.held = true }
        else release.restart()
    }
    Component.onCompleted: root.held = root.wanted
    Timer {
        id: release
        interval: Motion.exit
        onTriggered: root.held = false
    }
    visible: root.held

    // A strip along its edge: bottom = left+right+bottom, a side = top+bottom+that
    // side. Every placement includes the bottom.
    anchors.bottom: true
    anchors.top:    root.edge !== "bottom"
    anchors.left:   root.edge !== "right"
    anchors.right:  root.edge !== "left"

    // What the sidebar takes from the screen edge — the same function SideRail
    // draws from (dock.js `sideSurface`) — less the frame's strip, which the frame
    // already reserves: this zone stacks on top of the frame's.
    readonly property int strip: Config.screenFrame ? Config.frameDepth : 0
    readonly property var surface: DockJs.sideSurface({
        depth: Config.sidebarDepth, strip: root.strip, anchored: Config.barAnchored,
        welded: Morph.available && Config.screenFrame && Config.barAnchored, inset: Config.barInset
    })
    readonly property int zone: Math.max(0, root.surface.reserve - root.strip)

    // Only the cross axis — the anchors stretch the other. With the default
    // exclusion mode the zone IS this size, exactly as ScreenFrame's ReserveStrip.
    implicitWidth:  root.edge === "bottom" ? 0 : root.zone
    implicitHeight: root.edge === "bottom" ? root.zone : 0

    color: "transparent"
    mask: Region {}
    WlrLayershell.namespace: "quickshell-dock-reserve"
}
