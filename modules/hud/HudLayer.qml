pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/hud.js" as H

// ── HudLayer ──────────────────────────────────────────────────────────────────
// The PINNED HUD widgets, on screen (services/Hud explains the HUD). Full screen, above
// everything, mapped only while the overview is closed (that is where the same widgets
// live as cards) and something pinned belongs on THIS monitor (hud.js visible):
//   · an "over games" widget: a fullscreen window covers this monitor
//     (Fullscreen.byMonitor) — not the desktop, a browser, a tiled game — and it is the
//     focused one, so alt-tabbing out of the game steps it aside;
//   · an "always" widget: this is the overlay's home monitor (Hud.homeScreen) — a plain
//     overlay, over the desktop and every window.
// There is no edit mode here any more (2026-10-20: it was SUPER+G); placing is the
// overview island's (HudInspector).
//
// ── Click-through is the input mask ───────────────────────────────────────────
// ONLY the pinned, non-click-through widgets' rectangles take input — a window with an
// empty mask is transparent for input in Quickshell, so a pinned overlay never costs a
// click. One Region per widget, pointing at the frame while `hit` and at nothing
// otherwise; declared out rather than looped because Regions can't come from a Repeater.
//
// No keyboard focus, ever: it would eat the game's keys. Its own namespace.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: win

    // `screen` is PanelWindow's own property, assigned by shell.qml — not redeclared.

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-hud"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Captured imperatively, not read in the binding below: `visible` is derived from it,
    // and `screen` re-notifies on map/unmap — CavaBG's binding loop (see its header).
    property string monitorName: ""
    function _syncMonitor() { win.monitorName = win.screen?.name ?? "" }
    onScreenChanged: win._syncMonitor()
    Component.onCompleted: win._syncMonitor()

    readonly property var ctx: ({
        game: Fullscreen.byMonitor[win.monitorName] === true && Hyprland.focusedMonitor?.name === win.monitorName,
        home: win.monitorName !== "" && Hud.homeScreen === win.monitorName
    })
    readonly property bool wanted: Hud.anyPinned && !UiState.overviewOpen && H.anyPinned(Hud.layout, win.ctx)

    anchors.top:    true
    anchors.left:   true
    anchors.right:  true
    anchors.bottom: true
    color: "transparent"
    visible: win.wanted

    mask: Region {
        Region { item: wStats.hit     ? wStats     : null }
        Region { item: wClips.hit     ? wClips     : null }
        Region { item: wVoice.hit     ? wVoice     : null }
        Region { item: wInput.hit     ? wInput     : null }
    }

    Item {
        id: area
        anchors.fill: parent

        HudWidget { id: wStats;  wid: "stats";  ctx: win.ctx; live: win.wanted; boundsW: area.width; boundsH: area.height; body: Component { HudStats {} } }
        HudWidget { id: wClips;  wid: "clips";  ctx: win.ctx; live: win.wanted; boundsW: area.width; boundsH: area.height; body: Component { HudClips {} } }
        HudWidget { id: wVoice;  wid: "voice";  ctx: win.ctx; live: win.wanted; boundsW: area.width; boundsH: area.height; body: Component { HudVoice {} } }
        HudWidget {
            id: wInput
            wid: "input"
            plain: true
            resizable: true
            ctx: win.ctx; live: win.wanted; boundsW: area.width; boundsH: area.height
            body: Component { HudInput {} }
        }
    }
}
