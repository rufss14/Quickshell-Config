import QtQuick
import Quickshell
import "../config"

// ── CellFeedback ──────────────────────────────────────────────────────────────
// IconButton's state ladder, for a control that can't be an IconButton: a dock
// app, a stats ring, a clips cell — the sidebar wears the top bar's style. The
// accent at 0.18 while hovered, and the accent's ripple from where the press went
// down (IconButton says why the press is a wave rather than a darker fill).
//
// `barLadder` off is the house wash instead — StateLayer's own quiet hover in
// `accent`, no tinted fill — for a control shared with surfaces that don't wear
// the bar's style (DockIconStrip, which the overview's dock uses too). One
// StateLayer either way, so a strip of buttons doesn't pay for two.
//
// ── The active indicator ─────────────────────────────────────────────────────
// `active` (its panel is open, its state is on) draws IconButton's mark: a short accent
// bar, sized off the glyph and settling in on its length rather than snapping. The top
// bar puts it under the content, on the side toward the windows; so does this, on the
// sidebar's edge toward them (the dock's rule — DockIconStrip `indicatorsInward`). Only
// a caller that sets `active` gets one; the overview's dock and the power menu don't.
//
// Driven by the caller's own MouseArea — `hovered`, `press(x, y)`, `release()` —
// the way StateLayer is, so it never takes input from the control it sits under.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool  hovered: false

    // ── The pill's shared hover plate ─────────────────────────────────────────
    // IconButton's (HoverTrack): on the bar's ladder, in a pill that offers one (BarGroup;
    // the sidebar's hosts, for their region pill), hover is the one plate sliding between
    // buttons, and this draws only the press. Off the ladder (the overview's dock), never.
    property var _track: null
    function _findTrack() {
        for (let p = root.parent; p; p = p.parent)
            if (p.hoverTrack !== undefined) return p.hoverTrack
        return null
    }
    readonly property bool _tracking: root.hovered && root.barLadder
    on_TrackingChanged: {
        if (!root._track) root._track = root._findTrack()
        if (!root._track) return
        if (root._tracking) root._track.claim(root)
        else                root._track.release(root)
    }
    Component.onCompleted: root._track = root._findTrack()
    Component.onDestruction: if (root._track) root._track.release(root)
    // IconButton's hover spring: the plate's swell rides it (IconButton says why one spring).
    SpringValue {
        id: hov
        spec: Motion.springSpatialFast
        epsilon: 0.002
        target: root.hovered && root.barLadder ? 1 : 0
    }
    readonly property real _grow: hov.value * Tokens.spacingXs
    // The caller's glyph rises on the same spring (IconButton's 8%), so the cell, the tray and
    // anything else on this ladder lift in step with the plate.
    readonly property real lift: 1 + 0.08 * hov.value
    property real  pointerX: root.width  / 2
    property real  pointerY: root.height / 2
    property color accent:  Colors.of(QsWindow.window).primary
    // The sidebar's inner pill (SidePill "inner", the bar's roundness) less the spacingXs it
    // keeps round a cell, so the plate's curve runs parallel to the pill's (IconButton's
    // "concentric" note).
    property real  radius:  Tokens.corner(Config.barShape, Math.max(0, Config.barRoundness - Tokens.spacingXs))
    property bool  barLadder: true
    property bool  active: false
    // The longest the indicator runs: a glyph's length. A module taller than a cell (the focused
    // window's title) passes more, and the bar then spans what it's marking.
    property real  markMax: Config.sidebarGlyphPx

    // The sidebar's own edge (SideRail.edge's rule: anything that isn't a side is the bottom).
    readonly property string _edge: Config.dockPosition === "left" || Config.dockPosition === "right"
        ? Config.dockPosition : "bottom"
    readonly property real _markLength: root.active
        ? Math.max(0, Math.min(root.markMax, (root._edge === "bottom" ? root.width : root.height) - Tokens.spacingMd * 2)) : 0

    function press(x, y) { root._pressed = true;  ripple.press(x, y) }
    function release()   { root._pressed = false; ripple.release() }

    // IconButton's plate, on the sidebar: concentric with the inner pill, growing ALONG the
    // edge on hover (the pill keeps spacingXs across a cell, spacingSm past a group's ends) and
    // squashing and stretching on press. The along axis is the sidebar's: up and down on a
    // side, across on the bottom. On the house wash (barLadder off) nothing grows or stretches.
    property bool _pressed: false
    SpringValue {
        id: pressSpring
        spec: Motion.springSpatialFast
        epsilon: 0.002
        target: root._pressed && root.barLadder ? 1 : 0
    }
    // Which way "along" runs: the sidebar's edge by default; a top-bar caller (the tray) says false.
    property bool alongY: root._edge !== "bottom"
    readonly property real  _alongGrow:  root._grow + pressSpring.value * Tokens.spacingXs / 2
    readonly property real  _acrossTrim: pressSpring.value * Tokens.spacingXs / 2
    // The indicator's length on the standard spatial spring, as IconButton's mark.
    SpringValue { id: markLen; spec: Motion.springSpatial; epsilon: 0.05; target: root._markLength }

    // On the ladder the layer draws hover too, louder (0.18) and as IconButton does: a tint
    // that grows from the pointer's entry point. Off it, the house wash (0.08, no reveal).
    // `pointerX/Y` are the caller's own MouseArea (`pointerX: mouse.mouseX`); a caller that
    // gives none gets the tint blooming from the centre.
    StateLayer {
        id: ripple
        anchors.fill: parent
        layerColor: root.accent
        hovered: root.hovered
        reveal: root.barLadder
        // The shared plate draws hover while there is one; the press wave stays here.
        hoverOpacity: root._track && root.barLadder ? 0 : root.barLadder ? 0.26 : 0.08
        ringOpacity: root._track || !root.barLadder ? 0 : 0.4
        pointerX: root.pointerX
        pointerY: root.pointerY
        // The plate grows along the edge on hover and stretches on press (see above).
        anchors.topMargin:    root.alongY ? -root._alongGrow : root._acrossTrim
        anchors.bottomMargin: root.alongY ? -root._alongGrow : root._acrossTrim
        anchors.leftMargin:   root.alongY ? root._acrossTrim : -root._alongGrow
        anchors.rightMargin:  root.alongY ? root._acrossTrim : -root._alongGrow
        radius: Math.max(0, Math.min(root.radius, Math.min(root.width, root.height) / 2 - root._acrossTrim))
    }

    Rectangle {
        radius: Tokens.radiusFull
        color: root.accent
        // Across the edge it is borderChrome thick; along it, the glyph's length.
        width:  root._edge === "bottom" ? Math.max(0, markLen.value) : Tokens.borderChrome
        height: root._edge === "bottom" ? Tokens.borderChrome : Math.max(0, markLen.value)
        x: root._edge === "left" ? root.width - width - Tokens.spacingXs
         : root._edge === "right" ? Tokens.spacingXs
         : (root.width - width) / 2
        y: root._edge === "bottom" ? Tokens.spacingXs : (root.height - height) / 2
    }
}
