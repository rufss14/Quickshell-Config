import QtQuick
import QtQuick.Shapes
import Quickshell
import "../config"

// ── FocusTrace ────────────────────────────────────────────────────────────────
// A line that draws itself round a field when it takes focus: two strokes leave the middle
// of the top edge, run down either side and meet at the bottom, then it holds. On blur it
// fades. It sits INSIDE the border (inset by half its own width), over the field's own
// focus outline — the outline says "focused" at once, this says it with motion.
//
// Fill the thing it traces and set `radius` to that thing's corner. Draws nothing at rest.
//
// A dashed stroke does the drawing: one dash as long as the progress, then a gap longer than
// the whole outline, so only the first stretch is ever painted. ShapePath's dashPattern is
// in multiples of the stroke width, hence the divisions. The second stroke is the first one
// mirrored across the vertical axis, so both halves are the same path.
//
// CurveRenderer, as StateLayer and the other rounded shapes use: the geometry renderer
// facets small curves, and every corner here is one.
Item {
    id: root

    property bool  active: false
    property real  radius: Tokens.radiusSm
    property color color:  Colors.of(QsWindow.window).focus
    property real  lineWidth: Tokens.borderChrome

    anchors.fill: parent

    // Per half: how far along its half of the outline each stroke has got, 0..1.
    property real progress: 0
    property real _fade: 0

    // The stroke's centre line, inset so the line lies inside the border.
    readonly property real _inset: root.lineWidth / 2
    readonly property real _w: Math.max(0, root.width  - root.lineWidth)
    readonly property real _h: Math.max(0, root.height - root.lineWidth)
    readonly property real _r: Math.max(0, Math.min(root.radius - root._inset, root._w / 2, root._h / 2))
    readonly property real _perimeter: 2 * (root._w - 2 * root._r) + 2 * (root._h - 2 * root._r) + 2 * Math.PI * root._r

    visible: root._fade > 0.001
    opacity: root._fade

    onActiveChanged: {
        out.stop()
        into.stop()
        if (root.active) {
            root.progress = 0
            root._fade = 1
            // Motion off: no drawing, and no line — the field's own outline carries focus.
            if (Motion.emphasized > 0) into.restart()
            else root._fade = 0
        } else {
            out.restart()
        }
    }

    NumberAnimation {
        id: into
        target: root; property: "progress"
        from: 0; to: 1
        duration: Motion.emphasized
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.emphasizedDecel
    }

    SequentialAnimation {
        id: out
        NumberAnimation { target: root; property: "_fade"; to: 0; duration: Motion.exit; easing.type: Motion.exitCurve }
        ScriptAction { script: root.progress = 0 }
    }

    // One half of the outline; the second is the first mirrored. A Repeater, not an inline
    // `component`: a hot reload cannot introduce a used inline component (docs/qml-api-caution.md).
    Repeater {
        model: 2

        Shape {
            required property int index
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            transform: Scale { origin.x: root.width / 2; xScale: index === 0 ? 1 : -1 }

            ShapePath {
                strokeWidth: root.lineWidth
                strokeColor: root.color
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                strokeStyle: ShapePath.DashLine
                // Dash: this half's share of the outline drawn so far. Gap: more than all of it.
                dashPattern: [Math.max(0.001, root.progress * root._perimeter / 2) / root.lineWidth,
                              root._perimeter * 2 / root.lineWidth]

                startX: root._inset + root._w / 2; startY: root._inset
                PathLine { x: root._inset + root._w - root._r; y: root._inset }
                PathArc  { x: root._inset + root._w; y: root._inset + root._r
                           radiusX: root._r; radiusY: root._r }
                PathLine { x: root._inset + root._w; y: root._inset + root._h - root._r }
                PathArc  { x: root._inset + root._w - root._r; y: root._inset + root._h
                           radiusX: root._r; radiusY: root._r }
                PathLine { x: root._inset + root._r; y: root._inset + root._h }
                PathArc  { x: root._inset; y: root._inset + root._h - root._r
                           radiusX: root._r; radiusY: root._r }
                PathLine { x: root._inset; y: root._inset + root._r }
                PathArc  { x: root._inset + root._r; y: root._inset
                           radiusX: root._r; radiusY: root._r }
                PathLine { x: root._inset + root._w / 2; y: root._inset }
            }
        }
    }
}
