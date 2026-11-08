import QtQuick
import Quickshell
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

    // ══ FILLS GO BEHIND THE BAR, THE OUTLINE GOES IN FRONT OF IT ══════════════
    // This file is mounted TWICE by Bar.qml — once at `z: -1` for the material,
    // once after every bar surface for the stroke. `part` says which.
    //
    // ── Why it has to be two ──────────────────────────────────────────────────
    // One mount at `z: -1` is what this was, and it cannot work. The whole point
    // of the anchored modes is that the bar's underside is the ring's top edge —
    // so the line under the bar and the bar's own bottom edge are the SAME line,
    // drawn at the same y. Behind the bar, that line is painted over by the bar's
    // own fill and simply never appears. ("On Bar on frame the bar doesn't seem to
    // have a border" — it had one, underneath itself.)
    //
    // The obvious repair is to let the BAR draw that border instead. That works
    // until the corners: the ring's arcs have to meet it, the bar's border runs
    // straight across the two side strips where pill-material and strip-material
    // are one mass, and erasing it there also erases the arc arriving on a
    // horizontal tangent — so the arc has to be redrawn, and now two antialiased
    // strokes composite into one harder, wider curve. That was the choppy corner.
    //
    // Splitting by layer dissolves all of it. The outline is one continuous stroke
    // — up the left stub, round the arc, under the bar, round, down the right stub
    // — drawn ONCE, on top, where nothing can cover it. Nothing to erase, nothing
    // to redraw, nothing to align. The fills stay behind, where the bar's widgets
    // sit on top of them as they always did.
    //
    // The stroke lands on the bar's bottom edge, which is where the bar's own
    // border would have been; it is 1–2px and never over a widget.
    property string part: "fill"
    readonly property bool drawFills: root.part === "fill"
    readonly property bool drawLines: root.part === "line"

    // frameDepth, not frameThickness: the clamped effective ring thickness. The
    // raw pref can exceed what a thin bar can hold; the clamp lives in Config so
    // every piece of frame geometry agrees on the real value.
    // ── Two thicknesses, not one ──────────────────────────────────────────────
    // `thickness` used to answer both "how wide is a side strip" and "how deep is
    // the top mass", because in the floating modes they are the same band. Anchored,
    // they part company: the BAR is the top mass (full bar height), while the strips
    // stay at the ring's own depth.
    //
    // Splitting them is the whole of the anchored geometry. The band stands down,
    // the corners drop to the bar's underside, and the border path stops drawing the
    // horizontal run because the bar's own bottom border is that line.
    readonly property int thickness: Config.frameDepth

    // Where the top mass ends — the y the concave corners sit at and the arcs meet.
    readonly property int topDepth:
        Config.barAnchored ? Config.barExtent : Config.frameDepth

    // Anchored, the bar draws the top mass itself, so there is no band to fill.
    readonly property bool barIsEdge: Config.barAnchored

    // ── Who owns the line under the bar ───────────────────────────────────────
    // Exactly one thing may draw it, or the two strokes land on the same pixel and
    // the join reads as a seam instead of a continuous edge.
    //
    //   floating         the band's underside — this file owns it.
    //   unifiedAnchored  the bar IS the top mass and is drawn BORDERLESS, so this
    //                    file owns the line and carries it unbroken from the left
    //                    stub, under the bar, to the right stub. One stroke, no join.
    //
    // This file only renders with `screenFrame` on, so the no-frame half of the
    // rule lives in Config.barDrawsUnderline — which is what stops "Bar on frame"
    // with the frame OFF from having no bottom edge at all.

    readonly property int radius: Config.frameCornerRadius
    // The ring's stroke, not the pill's — this is the band, drawn here only because
    // same-layer surfaces stack by map order (see the file header).
    readonly property real bw: Config.frameBorderWidth

    // ── Where the arcs' horizontal tangent lands ──────────────────────────────
    // The concave corner sweeps off a side stub and onto the underside of whatever
    // the top mass is — and it has to land on that thing's stroke CENTRELINE, or
    // the outline steps by half the difference right at the join.
    //
    // Usually that stroke is this file's own, at `bw`. In `pillsAnchored` it is the
    // PILL's bottom border, a Surface stroke at `Config.barBorderWidth` — a
    // separate user slider. Reading `bw` in both cases was only correct while the
    // two happened to agree, which is the default and nothing else; the Bar page
    // splits them deliberately.
    readonly property real underBw:
        Config.barAnchored && Config.barDrawsUnderline ? Config.barBorderWidth
                                                       : root.bw
    readonly property real underCL: root.topDepth - root.underBw / 2


    // ── Fills: band and stubs ─────────────────────────────────────────────────
    // The band. Absent when the bar is the top edge — the bar's own surface covers
    // exactly this rectangle and then some.
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.topDepth
        color: Colors.of(QsWindow.window).frameFill
        visible: root.drawFills && !root.barIsEdge
    }
    // ── The stubs, butt-joined under the top mass ─────────────────────────────
    // They carry the ring down the bar's window to meet ScreenFrame's strips, and
    // they start where the top mass ENDS rather than at y=0.
    //
    // Running them full height overlapped whatever covers x < thickness above
    // `topDepth`: the band itself in the floating modes (both top corners), and the
    // flush edge PILL in the anchored ones (a `thickness`-wide column down the full
    // height of each end of the bar). Both layers are translucent and both are
    // `frameFill`, so the overlap composited twice — at the 0.97 defaults, α 0.998
    // against α 0.941 either side of it. That is a visibly darker vertical strip at
    // each end of the bar, which is a large part of what "doesn't merge with the
    // frame" looked like.
    //
    // ScreenFrame's own header calls out this exact failure and butt-joins its
    // strips to the bar's window for it; this is the same discipline one file over.
    // Every pixel of the ring is now painted by exactly one thing.
    //
    // The premise is that the top mass covers x < thickness for y < topDepth. The
    // band does by construction. An anchored EDGE PILL does because it is flush
    // (`sideInset` is 0 when fused) — unless its region holds no modules at all, in
    // which case that corner shows wallpaper. That is a layout with an empty end,
    // and the honest picture of one.
    component Stub: Rectangle {
        y: root.topDepth
        height: Math.max(0, root.height - root.topDepth)
        width: root.thickness
        color: Colors.of(QsWindow.window).frameFill
        visible: root.drawFills
    }

    Stub { x: 0 }
    Stub { x: root.width - root.thickness }

    // ── Top concave corners ───────────────────────────────────────────────────
    // Fill only — their arcs are stroked by the border path below, so the whole
    // outline is one stroke with no per-piece endpoints to mismatch.
    ConcaveCorner {
        which: 0
        x: root.thickness; y: root.topDepth
        width: root.radius; height: root.radius
        fill: Colors.of(QsWindow.window).frameFill
        visible: root.drawFills && root.radius > 0
    }
    ConcaveCorner {
        which: 1
        x: parent.width - root.thickness - root.radius; y: root.topDepth
        width: root.radius; height: root.radius
        fill: Colors.of(QsWindow.window).frameFill
        visible: root.drawFills && root.radius > 0
    }

    // ── The border, one continuous path ───────────────────────────────────────
    // Straight runs on the innermost borderWidth of the material; arcs at
    // r + bw/2, which is the same line. Starts and ends at the bar's bottom
    // edge, where ScreenFrame's stroke picks up at the identical x.
    // ── Five paths, not one ───────────────────────────────────────────────────
    // It was a single continuous stroke: up the left stub, round the arc, along the
    // band's underside, round again, down the right stub. That is still exactly
    // what RENDERS in every mode but one — consecutive paths share their endpoints,
    // so the outline is unbroken and there is no join to misalign. Splitting costs
    // nothing; it buys the ability to drop a piece, which cannot be done from the
    // middle of a single ShapePath.
    //
    // Exactly one piece ever drops: the HORIZONTAL RUN, in `pillsAnchored`. There,
    // each pill draws its own bottom border and desktop shows between them, so a
    // rule across those gaps would hang in mid-air over the wallpaper.
    //
    // The arcs are never dropped. They were, briefly, while FrameFusion redrew them
    // over an eraser — machinery that existed only because this whole file used to
    // be behind the bar. It is in front of it now (see `part`), so the arcs are
    // drawn here, once, and nothing else has any reason to touch them.
    // ── FlatCap on every segment, and it is not cosmetic ──────────────────────
    // ShapePath's capStyle defaults to SquareCap, which extends a stroke half a
    // line-width PAST each endpoint. Consecutive segments share their endpoints, so
    // every join was double-covered over a full `borderWidth`: measured 190 against
    // a 165 baseline at the arc's landing and again at its foot — a bright blip at
    // each of the four joins, on the most looked-at curve in the shell.
    //
    // The arithmetic says the same thing. The stroke is outlineBar (0.85) times
    // surfaceOpacity (0.97) = α 0.8245; covered twice that is 1−(1−0.8245)² = 0.969,
    // which over this bar predicts 188 against the 190 measured.
    //
    // FlatCap ends the stroke exactly at its endpoint, so segments butt instead of
    // overlapping. The tangents are already continuous — the arcs are built tangent
    // to the runs they meet — so there is nothing for a cap to smooth over.
    Shape {
        anchors.fill: parent
        visible: root.drawLines
        preferredRendererType: Shape.CurveRenderer

        // Left stub, up to where its arc begins.
        ShapePath {
            strokeColor: Colors.of(QsWindow.window).frameLine
            strokeWidth: root.bw
            // Butt the segments, don't overhang them — see the note above the Shape.
            capStyle: ShapePath.FlatCap
            fillColor: "transparent"

            startX: root.thickness - root.bw / 2
            startY: root.height
            PathLine {
                x: root.thickness - root.bw / 2
                y: root.topDepth + root.radius
            }
        }

        // Left concave corner.
        ShapePath {
            strokeColor: Colors.of(QsWindow.window).frameLine
            strokeWidth: root.bw
            // Butt the segments, don't overhang them — see the note above the Shape.
            capStyle: ShapePath.FlatCap
            fillColor: "transparent"

            startX: root.thickness - root.bw / 2
            startY: root.topDepth + root.radius
            PathArc {
                x: root.thickness + root.radius
                y: root.underCL
                radiusX: root.radius + root.bw / 2
                radiusY: root.radius + root.bw / 2
                direction: PathArc.Clockwise
            }
        }

        // The underside of the top mass — see above.
        ShapePath {
            strokeColor: Colors.of(QsWindow.window).frameLine
            strokeWidth: root.bw
            // Butt the segments, don't overhang them — see the note above the Shape.
            capStyle: ShapePath.FlatCap
            fillColor: "transparent"

            startX: root.thickness + root.radius
            startY: root.underCL
            PathLine {
                x: root.width - root.thickness - root.radius
                y: root.underCL
            }
        }

        // Right concave corner.
        ShapePath {
            strokeColor: Colors.of(QsWindow.window).frameLine
            strokeWidth: root.bw
            // Butt the segments, don't overhang them — see the note above the Shape.
            capStyle: ShapePath.FlatCap
            fillColor: "transparent"

            startX: root.width - root.thickness - root.radius
            startY: root.underCL
            PathArc {
                x: root.width - root.thickness + root.bw / 2
                y: root.topDepth + root.radius
                radiusX: root.radius + root.bw / 2
                radiusY: root.radius + root.bw / 2
                direction: PathArc.Clockwise
            }
        }

        // Right stub, from where its arc ends.
        ShapePath {
            strokeColor: Colors.of(QsWindow.window).frameLine
            strokeWidth: root.bw
            // Butt the segments, don't overhang them — see the note above the Shape.
            capStyle: ShapePath.FlatCap
            fillColor: "transparent"

            startX: root.width - root.thickness + root.bw / 2
            startY: root.topDepth + root.radius
            PathLine {
                x: root.width - root.thickness + root.bw / 2
                y: root.height
            }
        }
    }
}
