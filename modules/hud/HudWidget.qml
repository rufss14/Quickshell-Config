pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/hud.js" as H

// ── HudWidget ─────────────────────────────────────────────────────────────────
// The frame a pinned HUD widget sits in on screen: its position, its card, and whether
// it takes clicks (`hit`, what HudLayer's input mask reads). The widgets put their content
// in `body` and know nothing about where they are. Placing and options are the overview's
// (HudInspector); this only draws what the layout says.
//
// ── Position is the centre, as a fraction ─────────────────────────────────────
// Saved as (cx, cy) in 0..1 (services/hud.js), turned into x/y here against the screen's
// size, so a layout survives a different monitor; `clampCentre` keeps the whole rectangle
// on it. (The inspector's map draws a live copy of the same body to know its footprint.)
//
// ── Size and transparency ─────────────────────────────────────────────────────
// `opts.opacity` fades the CARD's fill (never the content: a number you can't read is no
// use over a game). A `resizable` body (the input overlay) gets `opts.scale` as `sizeScale`
// and lays itself out bigger rather than being stretched; a `plain` one (input)
// has no card at all and handles its own.
//
// ── The body is Loader-gated ──────────────────────────────────────────────────
// A widget that isn't pinned builds nothing, and neither does a pinned one while the
// layer is down (`live`) — so nothing samples on the desktop (the stats widget holds
// SysInfo only while it exists).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: frame

    required property string wid
    property Component body
    // No card, no padding: the body draws its own (the input overlay).
    property bool plain: false
    property bool resizable: false
    // The layer is up (HudLayer.wanted), and what it's up over ({ game, home }, hud.js
    // visible) — null where it doesn't matter (the map, arranging): "is it pinned".
    property bool live: true
    property var ctx: null
    // The inspector's map: draw it even unpinned (the one being placed), and while a drag
    // runs, at `override` ({ cx, cy }) instead of the saved place — committed once on release.
    property bool preview: false
    property var override: null

    // The screen's size — what a fraction is a fraction of.
    property real boundsW: 0
    property real boundsH: 0

    readonly property var entry: Hud.layout.widgets[frame.wid]
    readonly property bool shown: frame.preview || H.visible(frame.entry, frame.ctx)
    readonly property bool hit: H.interactive(frame.entry, frame.ctx)

    readonly property int pad: Tokens.spacingLg
    implicitWidth:  loader.implicitWidth  + (frame.plain ? 0 : frame.pad * 2)
    implicitHeight: loader.implicitHeight + (frame.plain ? 0 : frame.pad * 2)
    width: implicitWidth
    height: implicitHeight

    readonly property var _at: H.clampCentre(frame.override?.cx ?? frame.entry.cx, frame.override?.cy ?? frame.entry.cy,
                                             frame.width, frame.height, frame.boundsW, frame.boundsH)
    x: Math.round(frame._at.cx * frame.boundsW - frame.width / 2)
    y: Math.round(frame._at.cy * frame.boundsH - frame.height / 2)
    // Glides when re-placed from the overview; lands at once when it first appears.
    Behavior on x { enabled: frame.visible && frame.override === null; NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
    Behavior on y { enabled: frame.visible && frame.override === null; NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    opacity: frame.shown ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Motion.respond } }

    // ── The card ──────────────────────────────────────────────────────────────
    SurfaceShadow { surface: card; visible: !frame.plain }
    Surface {
        id: card
        anchors.fill: parent
        visible: !frame.plain
        elevation: Tokens.elevationPopup
        fillOpacity: frame.entry.opts.opacity ?? 1
        itemOpacity: 1
    }

    Loader {
        id: loader
        anchors.centerIn: parent
        active: frame.shown && frame.live
        sourceComponent: frame.body
    }

    Binding {
        target: loader.item
        property: "sizeScale"
        value: frame.entry.opts.scale || 1
        when: frame.resizable && loader.item !== null
    }
}
