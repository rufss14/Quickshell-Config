import QtQuick
import QtQuick.Shapes
import "../config"

// ── FrameFusion ───────────────────────────────────────────────────────────────
// Makes a bar pill read as GROWN FROM the frame band rather than a box floating on
// it. The join is a CONCAVE FILLET: the border between pill and band is erased, and
// each of the pill's top corners sweeps out into the band on a rounded arc — a fillet
// weld, not a square cut. (The square-join version and the user's later call to bring
// the round back are in the plan.)
//
// Owned by whatever owns the pill (BarGroup, and BarRegion for the merged pill),
// declared AFTER it and filling the same box, so its fill draws over the pill's
// border and its arcs redraw the outline. It positions off the live surface box
// (pillLeft/pillRight/pillBottom), so hover grow and width animations carry the join
// along for free.
//
//   top seam  — the band's underside stroke and the pill's own top border, erased
//               across the pill's interior AND fr px past each side, so the fillet
//               arc has clear ground. Between the two fillets the pill blends up into
//               the band with no line; at each side a fillet arc carries the outline
//               from the band underside down onto the pill's vertical border.
//   edge join — for a pill merged INTO a side strip (the outermost regions): its
//               bottom border erased across to the strip's inner border, so pill and
//               strip read as one mass; the strip's own border continues below.
//
// ── Why the fillets are TANGENT arcs, not ConcaveCorner ────────────────────────
// ConcaveCorner's arc endpoints land on box edges, not on a Qt Rectangle border's
// CENTERLINE — against the pill's side border that left a ~1px hook (the "notch"
// that read as unaligned). These arcs are built genuinely tangent: one endpoint on
// the band-underside centerline with a horizontal tangent, the other on the pill
// side-border centerline with a vertical tangent, radius fr about the corner. So the
// outline flows band → arc → pill side with nothing to align. Verified in a plain-Qt
// mock (scratchpad/filletmock.qml) at 14× before shipping.
//
// Painting frameFill over a line is how a line is removed when it lives in another
// scene (the band/strip strokes are in BarFrameEdge/ScreenFrame, behind this — not
// reachable from here except by covering them). At barOpacity < 1 the covered line
// ghosts through at (1 − opacity); at the shell's opacities that is invisible.
// (The surface supplies the corners themselves: squareTop / squareLeft / squareRight.)
Item {
    id: root

    // The surface's live horizontal box, in owner coordinates.
    property real pillLeft
    property real pillRight
    // Whether this owner's surface is the one being drawn AND the fusion is on. The
    // gate lives at the call site (see Config.frameFused / Config.launcherFused).
    property bool active: false
    // The fillet strokes track the pill's focused border, so a hovered pill flares
    // in the same accent all the way up into the band.
    property bool focused: false

    // ── Merged into the frame's side strip ────────────────────────────────────
    // Set on the bar's outermost regions. That side runs straight into the strip, so
    // it gets no seam fillet (there is no side border to sweep into) — its top seam
    // extends to the screen edge and it gets an edge join at the bottom instead.
    property bool mergeLeft:  false
    property bool mergeRight: false
    // The pill's bottom, in owner coordinates. Hover grow pushes it past the box, so
    // the owner passes the live value.
    property real pillBottom: root.height

    visible: active

    readonly property real bw: Tokens.borderChrome
    // Fillet radius — how far the pill's shoulder flares into the band. Shared with
    // the frame's own corners via Config so the whole join language stays in step.
    readonly property real fr: Config.frameFilletRadius
    // The strips' inner faces, in owner coordinates — only meaningful on a merged side,
    // where the owner is flush to the screen edge.
    readonly property real stripLeft:  Config.frameDepth
    readonly property real stripRight: root.width - Config.frameDepth
    // The band's inner face, in owner coordinates — where the fused surface's top edge
    // sits. The bar's pills start barInset below the screen edge, so the band only
    // covers what is left of its thickness.
    readonly property real seam: Config.frameDepth - Config.barInset
    // The band-underside stroke centreline — where a fillet's horizontal tangent lands.
    readonly property real bandCL: seam - bw / 2

    readonly property color lineColor: focused ? Colors.outlineFocus : Colors.frameLine

    // ── Top seam eraser ────────────────────────────────────────────────────────
    // Straddles the seam (band underside stroke at bandCL, pill top border just below)
    // and spans the pill PLUS fr past each non-merged side, so the band stroke and the
    // pill's own square-top corner are cleared for the fillet arcs to redraw. On a
    // merged side it runs to the screen edge, since the fillet is replaced by an edge
    // join there.
    Rectangle {
        readonly property real l: root.mergeLeft  ? root.pillLeft  : root.pillLeft  - root.fr
        readonly property real r: root.mergeRight ? root.pillRight : root.pillRight + root.fr
        x: l
        y: root.seam - root.bw
        width: r - l
        height: root.bw * 2
        color: Colors.frameFill
    }

    // ── Seam fillets ───────────────────────────────────────────────────────────
    // A concave arc sweeping the pill's vertical side border up into the band. Drawn
    // AFTER the eraser so its stroke survives. Suppressed on a merged side.
    component SeamFillet: Item {
        id: fl
        required property bool onLeft
        anchors.fill: parent

        // Corner: the pill side-border centreline meets the band-underside centreline.
        readonly property real cx: fl.onLeft ? (root.pillLeft + root.bw / 2)
                                             : (root.pillRight - root.bw / 2)
        readonly property real cy: root.bandCL
        readonly property real dir: fl.onLeft ? -1 : 1       // toward the gap
        // Tangent point on the band underside (horizontal tangent).
        readonly property real paX: cx + dir * root.fr
        readonly property real paY: cy

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // Fill: the corner nub (corner → arc), one colour with the band and pill.
            ShapePath {
                strokeWidth: -1
                fillColor: Colors.frameFill
                startX: fl.paX; startY: fl.paY
                PathLine { x: fl.cx; y: fl.cy }
                PathLine { x: fl.cx; y: fl.cy + root.fr }
                PathArc {
                    x: fl.paX; y: fl.paY
                    radiusX: root.fr; radiusY: root.fr
                    direction: fl.onLeft ? PathArc.Counterclockwise : PathArc.Clockwise
                }
            }
            // Stroke: the arc itself, band underside → pill side.
            ShapePath {
                strokeColor: root.lineColor
                strokeWidth: root.bw
                fillColor: "transparent"
                startX: fl.paX; startY: fl.paY
                PathArc {
                    x: fl.cx; y: fl.cy + root.fr
                    radiusX: root.fr; radiusY: root.fr
                    direction: fl.onLeft ? PathArc.Clockwise : PathArc.Counterclockwise
                }
            }
        }
    }

    SeamFillet { onLeft: true;  visible: !root.mergeLeft && root.fr > 0 }
    SeamFillet { onLeft: false; visible: !root.mergeRight && root.fr > 0 }

    // ── Edge join, per merged side ─────────────────────────────────────────────
    // Erase the pill's bottom border from its outer edge across to the strip's inner
    // border centerline, so the pill's remaining bottom border meets the strip's own
    // vertical border at a square corner and the strip carries on below.
    component EdgeJoin: Item {
        id: join
        required property bool onLeft
        anchors.fill: parent

        readonly property real face:   onLeft ? root.stripLeft : root.stripRight
        readonly property real faceCL: onLeft ? face - root.bw / 2 : face + root.bw / 2

        Rectangle {
            x: join.onLeft ? root.pillLeft : join.faceCL
            y: root.pillBottom - root.bw
            width: join.onLeft ? join.faceCL - root.pillLeft
                               : root.pillRight - join.faceCL
            height: root.bw * 2
            color: Colors.frameFill
        }
    }

    EdgeJoin { onLeft: true;  visible: root.mergeLeft }
    EdgeJoin { onLeft: false; visible: root.mergeRight }
}
