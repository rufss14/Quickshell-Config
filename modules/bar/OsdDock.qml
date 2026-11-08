pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../osd"

// ── OsdDock ───────────────────────────────────────────────────────────────────
// The OSD — its levels (volume, brightness, mic) and its announcement tiles (a Bluetooth
// device, the magnifier) — welded into the screen frame: it melts out of the right edge as
// a lobe of the same material, like a bar panel does from the bar and a sidebar panel does
// from the sidebar (SidePanelDock, whose shape this follows without the button it belongs
// to). Lives in the BAR's window for the reason every welded thing does — the blob only
// blends pixels inside one Qt Quick scene graph.
//
// ── Where ─────────────────────────────────────────────────────────────────────
// The right edge, centred between the bar's underside and the bottom strip. Flush on
// whatever stands there: the sidebar's face when the sidebar is on that edge, else the
// frame's own strip. Not welded (no blob, no frame, or a floating bar): the same card,
// a gap off the edge and fading in, as SidePanelDock does.
//
// ── Not while a window is fullscreen ──────────────────────────────────────────
// Hyprland hides the bar's layer under a fullscreen window, so then the floating copy
// (modules/osd/OsdSliders, Overlay layer) answers instead. Same hand-off as the
// notification deck, same `Fullscreen.byMonitor` flag; exactly one of them is up.
//
// ── What is in it ─────────────────────────────────────────────────────────────
// OsdColumn, behind a Loader that exists only while the OSD is up or melting away:
// a closed one has no sliders at all. Sized to whichever it is showing (a level column
// is narrower than a tile).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: dock

    required property SideRail rail
    // The bar's own screen: which display's brightness the column shows.
    required property var forScreen
    // The blob's spring for this lobe; identity while the plugin is absent.
    property matrix4x4 deformMatrix

    // One screen shows it — the monitor you were on when it opened (ScreenOwner).
    readonly property bool owns: screenOwner.owns
    ScreenOwner {
        id: screenOwner
        screen: dock.forScreen
        open: Osd.active
    }

    readonly property bool wanted: Osd.active && dock.owns
                                   && Fullscreen.byMonitor[dock.forScreen?.name ?? ""] !== true

    // ══ Where ═════════════════════════════════════════════════════════════════
    readonly property bool welded: dock.rail.welded
    // What it is flush on: the sidebar's face if the sidebar is on this edge, else the
    // frame's strip (0 with no frame).
    readonly property real face: dock.rail.edge === "right" && dock.rail.panelFace > 0
                                 ? dock.rail.panelFace : dock.rail.strip
    readonly property real standOff: dock.welded ? 0 : Tokens.spacingXl
    // Down the edge: from the bar's underside to the bottom strip.
    readonly property real lo: Config.barExtent
    readonly property real hi: dock.rail.screenH - dock.rail.strip

    // ── Its size: the column's own, within the room ───────────────────────────
    // Held, not bound: the column unloads as the close finishes, and a box bound to its
    // size would snap to nothing for the last frames of the melt.
    readonly property Item column: loader.item
    readonly property real colW: dock.column ? dock.column.implicitWidth  : 0
    readonly property real colH: dock.column ? dock.column.implicitHeight : 0
    property real heldW: 0
    property real heldH: 0
    onColWChanged: if (dock.colW > 0) dock.heldW = dock.colW
    onColHChanged: if (dock.colH > 0) dock.heldH = dock.colH
    // An announcement arriving over a volume change is a different width; the lobe moves to
    // it rather than snapping. Only once it is fully open: the melt itself is `grow`'s, and
    // this ramping from 0 at the same time would double it up. Not on the height: that is
    // already moving on the column's own springs (a row opening), and a second ease chasing
    // a moving target only lags it.
    Behavior on heldW {
        enabled: dock.grow > 0.99
        NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve }
    }

    // ── The melt ──────────────────────────────────────────────────────────────
    // Quicker in than a panel's (this answers a keypress; the number should be readable
    // as soon as it is up), the usual exit out.
    property real grow: dock.wanted ? 1 : 0
    Behavior on grow {
        NumberAnimation {
            duration: dock.wanted ? Motion.standard : Motion.exit
            easing.bezierCurve: Motion.emphasizedDecel
            easing.type: dock.wanted ? Easing.BezierSpline : Motion.exitCurve
        }
    }

    readonly property real acrossNow: dock.heldW * dock.grow
    readonly property real alongLen:  Math.min(dock.heldH, Math.max(0, dock.hi - dock.lo))

    // ══ Read by Bar.qml ═══════════════════════════════════════════════════════
    readonly property Item maskItem: maskBox
    // The lobe, welded only; 0 while shut.
    readonly property bool _lobe: dock.welded && dock.grow > 0.01
    readonly property real blobX: dock._lobe ? card.x : 0
    readonly property real blobY: dock._lobe ? card.y : 0
    readonly property real blobW: dock._lobe ? card.width  : 0
    readonly property real blobH: dock._lobe ? card.height : 0

    // The mask: the card while it's on screen, nothing otherwise — so the pointer can
    // drag a slider, and everything else on this edge still reaches the desktop.
    Item {
        id: maskBox
        x: card.x
        y: card.y
        width:  dock.grow > 0.01 ? card.width  : 0
        height: dock.grow > 0.01 ? card.height : 0
    }

    // ══ The card ══════════════════════════════════════════════════════════════
    // Welded, a lobe (no outline, no shadow — the blob draws the one continuous stroke);
    // floating, an ordinary card.
    Card {
        id: card

        x: dock.rail.screenW - dock.face - dock.standOff - dock.acrossNow
        y: dock.lo + (dock.hi - dock.lo - dock.alongLen) / 2
        width:  dock.acrossNow
        height: dock.alongLen

        shown:      dock.wanted
        hoverFocus: !dock.welded
        elevated:   !dock.welded
        // Welded while the blob draws the cookie field, the blob is the material — fill and cookies.
        blobMaterial: dock.welded && Morph.available && Drift.inBlob
        border.width: dock.welded ? 0 : Tokens.borderWidth
        // Grows out of the edge, not out of its own middle.
        transformOrigin: Item.Right
        transform: Matrix4x4 { matrix: dock.welded ? dock.deformMatrix : Qt.matrix4x4() }

        // The column at its own full size, pinned to the edge, so the melting box
        // uncovers it rather than squeezing it. Shown in the melt's last half.
        Loader {
            id: loader
            active: dock.wanted || dock.grow > 0.01
            sourceComponent: OsdColumn { forScreen: dock.forScreen }
            x: card.width - dock.heldW
            opacity: Math.max(0, dock.grow * 2 - 1)
        }
    }
}
