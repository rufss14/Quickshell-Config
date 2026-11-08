import QtQuick
import QtQuick.Shapes
import "../config"
import "shapes.js" as Shapes

// ── MorphShape ────────────────────────────────────────────────────────────────
// A Material 3 Expressive shape that MORPHS when you change it: `shape: "cookie9"` →
// `shape: "sunny"` and the outline flows from one to the other on a spring, turning one
// petal of the new shape as it goes (the expressive loading-indicator move). The shapes
// and why every pair morphs cleanly are in shapes.js.
//
// The morph starts from whatever is ON SCREEN, so changing the shape mid-morph turns it
// round instead of jumping back to the old outline. The spring's overshoot carries the
// outline a touch past the new shape and back — the squash that makes it read as a body
// rather than a crossfade. Animations off: it simply is the new shape.
//
// Drawn like Scallop (a Shape on the curve renderer, a polyline of the samples), so it is
// crisp at any size or turn. The outline is rebuilt in JS only while it morphs; at rest it
// is static geometry and costs nothing per frame.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string shape: "circle"
    property color fillColor: "transparent"
    property color strokeColor: "transparent"
    property real strokeWidth: Tokens.borderWidth
    // The spring the outline moves on. The fast spatial one overshoots the most (~9.5%).
    property var spec: Motion.springSpatial
    // Turn one petal per morph. Off for a shape whose orientation means something (a clock
    // dial, whose petals are the hours).
    property bool turns: true

    property var _from: Shapes.radii(root.shape)
    property var _to: root._from
    property string _shown: root.shape

    SpringValue { id: progress; spec: root.spec; epsilon: 0.001 }
    SpringValue { id: turn; spec: root.spec; epsilon: 0.05 }

    onShapeChanged: {
        if (root.shape === root._shown) return
        // From what is drawn right now, mid-morph or not.
        root._from = Shapes.mix(root._from, root._to, progress.value)
        root._to = Shapes.radii(root.shape)
        root._shown = root.shape
        progress.target = 1
        progress.jump(0)
        if (root.turns) turn.target = turn.target + Shapes.turnFor(root.shape)
    }
    Component.onCompleted: { progress.target = 1; progress.jump(1) }

    readonly property real _inset: root.strokeColor.a > 0 ? root.strokeWidth / 2 + 0.5 : 0.5
    readonly property var _outline: {
        const r = progress.value >= 1 && !progress.moving ? root._to
                : Shapes.mix(root._from, root._to, progress.value)
        const flat = Shapes.outline(r, root.width, root.height, root._inset)
        const out = new Array(flat.length / 2)
        for (let i = 0; i < out.length; i++) out[i] = Qt.point(flat[2 * i], flat[2 * i + 1])
        return out
    }

    Shape {
        anchors.fill: parent
        rotation: turn.value
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: root.fillColor
            strokeColor: root.strokeColor
            // -1 turns the stroke off outright; 0 would still draw a hairline.
            strokeWidth: root.strokeColor.a > 0 ? root.strokeWidth : -1
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root._outline }
        }
    }
}
