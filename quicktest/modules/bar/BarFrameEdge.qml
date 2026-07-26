import QtQuick
import QtQuick.Shapes
import "../../config"
import "../../components"

// ── BarFrameEdge ──────────────────────────────────────────────────────────────
// The screen frame's top edge, drawn INSIDE the bar's window, behind its pills.
//
// It has to live here and not in ScreenFrame: layer-shell surfaces on the same
// layer stack by MAP ORDER, so a separate top window toggled on at runtime would
// map after the bar and paint over its pills. Inside the bar's own scene, z
// ordering is guaranteed — the ring sits behind the pills.
//
// What it draws: the thin top band, two stubs carrying the ring down the bar's
// height to meet ScreenFrame's strips, the two top concave corners, and one
// continuous border path (up the left stub, around the arc, along the band's
// underside, around, down the right stub). The stub runs land on exactly the
// stroke line ScreenFrame draws below, so the border continues across the
// window boundary without a jog.
//
// When pills FUSE with the band (Config.frameFused), FrameFusion erases the
// band segment of this stroke across each pill and flares the joins — that
// happens in the pill's own scene, above this, and needs nothing from here.
//
// Colours are Colors.frameFill / frameLine — the pills' Surface recipe, defined
// once in Colors. The corners fit inside the bar's height by construction;
// that's what caps Config.frameCornerRadius.
Item {
    id: root

    // frameDepth, not frameThickness: the clamped effective ring thickness. The
    // raw pref can exceed what a thin bar can hold; the clamp lives in Config so
    // every piece of frame geometry agrees on the real value.
    readonly property int thickness: Config.frameDepth
    readonly property int radius: Config.frameCornerRadius
    readonly property real bw: Tokens.borderChrome

    // ── Fills: band and stubs ─────────────────────────────────────────────────
    // Each carries the frame's glass (Config.barGlass) as a FrameGlaze — a bevel glow
    // across the piece's THICKNESS, not the pill overlay (whose length-proportional
    // sheen turned into a spotlight down a full-screen strip). `inner` is the edge that
    // faces the desktop: the band is lit along its bottom, each stub along the side that
    // faces the bar's centre.
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.thickness
        color: Colors.frameFill
        FrameGlaze { anchors.fill: parent; inner: "bottom"; visible: Config.barGlass }
    }
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.thickness
        color: Colors.frameFill
        FrameGlaze { anchors.fill: parent; inner: "right"; visible: Config.barGlass }
    }
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: root.thickness
        color: Colors.frameFill
        FrameGlaze { anchors.fill: parent; inner: "left"; visible: Config.barGlass }
    }

    // ── Top concave corners ───────────────────────────────────────────────────
    // Fill only — their arcs are stroked by the border path below, so the whole
    // outline is one stroke with no per-piece endpoints to mismatch.
    ConcaveCorner {
        which: 0
        x: root.thickness; y: root.thickness
        width: root.radius; height: root.radius
        fill: Colors.frameFill
        visible: root.radius > 0
    }
    ConcaveCorner {
        which: 1
        x: parent.width - root.thickness - root.radius; y: root.thickness
        width: root.radius; height: root.radius
        fill: Colors.frameFill
        visible: root.radius > 0
    }

    // ── The border, one continuous path ───────────────────────────────────────
    // Straight runs on the innermost borderWidth of the material; arcs at
    // r + bw/2, which is the same line. Starts and ends at the bar's bottom
    // edge, where ScreenFrame's stroke picks up at the identical x.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Colors.frameLine
            strokeWidth: root.bw
            fillColor: "transparent"

            startX: root.thickness - root.bw / 2
            startY: root.height
            PathLine {
                x: root.thickness - root.bw / 2
                y: root.thickness + root.radius
            }
            PathArc {
                x: root.thickness + root.radius
                y: root.thickness - root.bw / 2
                radiusX: root.radius + root.bw / 2
                radiusY: root.radius + root.bw / 2
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.width - root.thickness - root.radius
                y: root.thickness - root.bw / 2
            }
            PathArc {
                x: root.width - root.thickness + root.bw / 2
                y: root.thickness + root.radius
                radiusX: root.radius + root.bw / 2
                radiusY: root.radius + root.bw / 2
                direction: PathArc.Clockwise
            }
            PathLine {
                x: root.width - root.thickness + root.bw / 2
                y: root.height
            }
        }
    }
}
