import QtQuick
import QtQuick.Shapes

// ── ConcaveCorner ─────────────────────────────────────────────────────────────
// The sliver where the screen frame meets desktop content: the area between a
// square corner and a quarter-circle arc, plus (optionally) the frame's border
// stroked along the arc so the ring's outline continues around the curve.
//
// Shape with the curve renderer, not Canvas: Canvas rasterises on the CPU and
// its arc edges show at 1× — this is exactly the "unpolished corners" that got
// v2 rejected. Shape is scene-graph geometry with proper antialiasing, and the
// stroke path is NOT clipped at the item's bounds, so its endpoints overlap the
// straight border lines that continue from them — no notch at the junctions.
//
// ── The STROKE half is currently unused, and that overlap is why ──────────────
// All four call sites (BarFrameEdge ×2, ScreenFrame ×2) ask for `fill` only and
// pass no `line`/`lineWidth`, so `strokeWidth: -1` disables it at every one of
// them. Both files stroke their own arcs instead, as segments of one continuous
// path — which is what lets those outlines run stub → arc → underside with no
// per-piece endpoints to align.
//
// Worth knowing before switching a caller back on: the overlap described above is
// exactly the failure that had to be fixed in those files. Two strokes covering
// the same pixels do not reinforce, they composite at 1−(1−α)², so an "overlap so
// there's no notch" join reads as a bright blip instead — measured at 190 against
// a 165 baseline before BarFrameEdge's segments were given FlatCap. A caller that
// wants this stroke should butt it against its neighbours, not overlap them.
// Flagged rather than deleted: the arc geometry is correct and cheap to keep.
//
// Draws the TOP-LEFT orientation; `which` rotates it into the other three
// (0 = top-left, 1 = top-right, 2 = bottom-right, 3 = bottom-left). Always
// square; the caller sizes it to the corner radius. The border stroke rides at
// radius r + lineWidth/2 — the innermost lineWidth of the MATERIAL, matching
// the straight lines, which occupy the innermost lineWidth of their strips.
Item {
    id: root

    property int which: 0
    property color fill
    property color line
    property real lineWidth: 0

    Shape {
        anchors.fill: parent
        rotation: root.which * 90
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillColor: root.fill
            startX: 0; startY: 0
            PathLine { x: root.width; y: 0 }
            PathArc {
                x: 0; y: root.width
                radiusX: root.width; radiusY: root.width
                direction: PathArc.Counterclockwise
            }
            PathLine { x: 0; y: 0 }
        }

        ShapePath {
            strokeColor: root.lineWidth > 0 ? root.line : "transparent"
            // -1 disables the stroke outright; 0 would still draw a hairline.
            strokeWidth: root.lineWidth > 0 ? root.lineWidth : -1
            fillColor: "transparent"
            startX: root.width; startY: -root.lineWidth / 2
            PathArc {
                x: -root.lineWidth / 2; y: root.width
                radiusX: root.width + root.lineWidth / 2
                radiusY: root.width + root.lineWidth / 2
                direction: PathArc.Counterclockwise
            }
        }
    }
}
