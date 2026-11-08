pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import "../../config"
import "../../components"

// ── OverviewZoom ──────────────────────────────────────────────────────────────
// The overview's way in and out of a workspace (2026-10-20, the user's pick of "zoom into
// the workspace"):
//   · "out" — you chose a workspace (a cell, a window, Enter, Alt let go): its cell grows
//     to the screen and every window on it flies from its preview to where it really is;
//     the overview closes as they land, so the real windows take over in place;
//   · "in"  — the overview opening: the windows of the workspace you're on shrink from
//     where they are into their cell, while the grid assembles round them.
// The stand-ins are live captures of the same windows, so the hand-off at either end shows
// nothing. Their path is a lerp between the real rect and the preview's rect read EVERY
// FRAME (WorkspaceGrid.previewSceneRect, through all the transforms the entrance is
// animating), so they land on the preview however the grid is moving.
//
// ── Seamless, 2026-10-24 (the user: "seamless and very smooth, in n out") ─────
// What the first version got wrong, and what each piece below is for:
//   · It moved at the wrong RATE. A rect lerped in px is a zoom that starts at several
//     times the pace it ends at (the size triples, the first frames carry most of it), and
//     it ran on emphasizedDecel, which spends half its distance in two frames. Now the
//     SCALE is what is eased: `k` is the lerp weight of a geometric zoom (s^x, so the
//     picture grows by the same fraction every frame), on `Motion.zoomCurve` — ease in AND
//     out.
//   · (Hyprland's own layer fade runs underneath the opening — stand-ins at partial alpha over
//     the real window for ~150ms. Turning it off with `no_anim` was tried and reverted: the
//     compositor's blur follows that same alpha, and went from nothing to full in one frame.)
//   · The compositor's workspace SLIDE (500ms) is going on under a leave. The old backdrop
//     thinned out from the first frames and the dim lifted during the flight, so the real
//     windows were seen sliding in. Now the dim HOLDS (and the board deepens it) to the end,
//     and the overview closes on that full frame: Hyprland's layer fade takes the dim, the
//     stand-ins AND the blur away together (the blur follows the layer's alpha, so nothing
//     the shell fades can do it — blanking the overlay first dropped it in one frame, the
//     flash on arriving). The real window's border and shadow arrive through that fade.
//   · The stand-ins landed square (radius 0) on a window that is rounded 16: now the
//     compositor's own rounding (blend.lua), 0 for a fullscreen one.
//   · The board is the DIM'S colour, not the cell's, at half strength, and only on a leave
//     (opening has no workspace switch to hide). A first try made it a flat 0.9 sheet in the
//     cell's colour across the whole screen — a flash, worst on a light theme — and it also
//     crossed the compositor's blur threshold (hypr/rules.lua `ignore_alpha` 0.6), so it
//     stays under it. A workspace with no windows gets none of it, and a shorter, plain
//     fade: there is nothing to land and nothing sliding.
//   · The grid's previews no longer vanish when the flight starts: the stand-ins (plain
//     captures, sharp, unmipmapped) fade OVER them, and fade away to reveal them on the
//     way in. Hiding the preview and showing a stand-in in the same frame was a pop from
//     the smooth picture to a grittier one.
//
// Window coordinates: this is full-screen and untransformed, over the stage.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property var grid
    // "" | "in" | "out"
    property string mode: ""
    property int ws: -1
    // 0 → 1 over the flight on Motion.zoomCurve (where it is)…
    property real t: 0
    // …and 0 → 1 on a line (when it is): what the fades are timed by, since they have to be
    // long enough to cover the compositor's slide whatever the curve is doing.
    property real u: 0
    property var wins: []
    property int radius: Math.max(2, Tokens.radiusCard - 4)

    // How far toward the REAL place, 0 → 1: out goes there, in comes back. Eased (`t`), then
    // re-weighted so the lerp is a GEOMETRIC zoom: the preview → real factor is
    // `scaleFull`, a zoom of s^x has scale 1 + k·(s − 1) for k = (s^x − 1) / (s − 1), and
    // every rect here is a plain lerp by k. Under 1.05 there is no zoom to speak of.
    readonly property real scaleFull: 1 / Math.max(0.05, root.grid.previewScale)
    readonly property real _x: root.mode === "out" ? root.t : 1 - root.t
    readonly property real k: root.scaleFull > 1.05 ? (Math.pow(root.scaleFull, root._x) - 1) / (root.scaleFull - 1) : root._x

    // ── The envelopes (all of `u`) ────────────────────────────────────────────
    function ramp(x) { const c = Math.max(0, Math.min(1, x)); return c * c * (3 - 2 * c) }
    // Nothing to land, nothing sliding: a workspace with no windows.
    readonly property bool empty: root.wins.length === 0
    // The board's own fade, over the last third of a leave: it has done its job (the compositor's
    // slide is over by then) and the overview closes on the dim alone. Only the board — the dim,
    // the stand-ins and the compositor's blur stay as they are to the last frame, and
    // Hyprland's layer fade takes them away together (Overview `landed`).
    readonly property real tail: root.ramp((root.u - 0.7) / 0.3)
    // The board's strength (0 → 1 of `boardAlpha`): rises as the cell starts to grow. A leave
    // with windows only.
    readonly property real boardAlpha: 0.5
    readonly property real veil: root.mode === "out" && !root.empty ? Math.min(root.ramp(root.u / 0.16), 1 - root.tail) : 0
    // How long it takes: a workspace with nothing on it is a plain fade.
    readonly property int span: Math.round((root.mode === "out" ? Motion.zoomOut : Motion.zoom) * (root.empty ? 0.6 : 1))
    // The stand-ins' own opacity: out fades them IN over the previews and keeps them to the last
    // frame (the compositor fades them with the layer); in shows them from the first frame (they sit on the real windows) and fades
    // them out over the last bit to reveal the previews.
    readonly property real standIn: root.mode === "out" ? root.ramp(root.u / 0.16) : root.ramp((1 - root.u) / 0.16)

    signal finished(string mode)
    // "in" only: the stand-ins have their first frames (or `patience` ran out) and the
    // flight starts — the overview reveals itself on this (Overview `revealed`).
    signal ready()
    readonly property int patience: 150

    function start(m, ws) {
        root._waiting = false
        wait.stop()
        root.wins = root.grid.zoomWindows(ws)
        root.ws = ws
        root.mode = m
        root.t = 0
        root.u = 0
        if (m === "in") { root._waiting = true; wait.restart(); Qt.callLater(root._check) }
        else flight.restart()
    }
    // Opening: hold at t = 0 (the stand-ins sitting exactly on the real windows, invisible
    // until their capture arrives) until every one has a frame — a stand-in that started
    // flying blank and then filled in was the "frame still has to load".
    property bool _waiting: false
    function _check() {
        if (!root._waiting) return
        for (let i = 0; i < flyers.count; i++) {
            const f = flyers.itemAt(i)
            if (f && !f.ready) return
        }
        root._go()
    }
    function _go() {
        if (!root._waiting) return
        root._waiting = false
        wait.stop()
        root.ready()
        flight.restart()
    }
    Timer { id: wait; interval: root.patience; onTriggered: root._go() }
    function stop() {
        root._waiting = false
        wait.stop()
        flight.stop()
        root.mode = ""
        root.wins = []
    }

    function lerp(a, b, f) { return a + (b - a) * f }

    visible: root.mode !== ""

    ParallelAnimation {
        id: flight
        NumberAnimation {
            target: root
            property: "t"
            from: 0
            to: 1
            duration: root.span
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.zoomCurve
        }
        NumberAnimation {
            target: root
            property: "u"
            from: 0
            to: 1
            duration: root.span
        }
        onFinished: {
            const m = root.mode
            root.stop()
            root.finished(m)
        }
    }

    // ── The board: a deeper dim growing out of the cell (leave only) ───────────
    // It hides the workspace switch going on underneath (Hyprland's own slide) along with
    // the dim, which holds to the end of a leave; the board alone steps back over the last
    // third (`tail`). The dim's colour, at half strength: it deepens what is
    // already there instead of laying a different colour over it.
    Rectangle {
        id: backdrop
        readonly property var found: { root.t; return root.veil > 0 ? root.grid.cellSceneRect(root.ws) : null }
        readonly property rect cell: backdrop.found ?? Qt.rect(0, 0, root.width, root.height)
        // No cell to grow from (a workspace off this page): no board, only the windows.
        visible: root.mode === "out" && backdrop.found !== null && root.veil > 0.001
        x: root.lerp(backdrop.cell.x, 0, root.k)
        y: root.lerp(backdrop.cell.y, 0, root.k)
        width: root.lerp(backdrop.cell.width, root.width, root.k)
        height: root.lerp(backdrop.cell.height, root.height, root.k)
        radius: root.lerp(Tokens.radiusCard, 0, root.k)
        color: Colors.of(QsWindow.window).base
        opacity: root.boardAlpha * root.veil
    }

    // ── The windows ───────────────────────────────────────────────────────────
    Repeater {
        id: flyers
        model: root.wins

        ClippingRectangle {
            id: flyer
            required property var modelData
            readonly property bool ready: shot.hasContent
            onReadyChanged: if (flyer.ready) root._check()
            readonly property rect cell: {
                root.t
                return root.grid.previewSceneRect(flyer.modelData.address) ?? flyer.modelData.real
            }
            readonly property rect real: flyer.modelData.real
            x: root.lerp(flyer.cell.x, flyer.real.x, root.k)
            y: root.lerp(flyer.cell.y, flyer.real.y, root.k)
            width: root.lerp(flyer.cell.width, flyer.real.width, root.k)
            height: root.lerp(flyer.cell.height, flyer.real.height, root.k)
            // Lands with the compositor's own rounding (blend.lua), not the shell's scaled
            // one — Hyprland's doesn't follow Config.radiusScale — and square if fullscreen.
            radius: root.lerp(root.radius, flyer.modelData.full ? 0 : (Blend.v.rounding || 16), root.k)
            color: "transparent"
            opacity: root.standIn

            // A plain capture, not SharpCapture: a stand-in spends most of the flight big, where
            // there's nothing to sharpen, and a mipmapped layer per window built on the very
            // first frame of the overview was frames the open couldn't spare. The preview
            // underneath is the smooth one, and the stand-in fades over it.
            // Hidden until its frame is in: over the real window it stands for, it's invisible
            // anyway, and a blank box would not be.
            ScreencopyView {
                id: shot
                anchors.fill: parent
                visible: shot.hasContent
                captureSource: flyer.modelData.wayland
                live: true
            }
        }
    }
}
