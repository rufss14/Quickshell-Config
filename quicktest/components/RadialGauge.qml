import QtQuick
import QtQuick.Shapes
import "../config"

// ── RadialGauge ───────────────────────────────────────────────────────────────
// A ring with its centre missing, and the value written in the hole.
//
// ── Why this is allowed to be a ring ──────────────────────────────────────────
// The received wisdom is that a radial gauge for a single ratio is a two-slice pie
// wearing a hat: it asks the eye to judge arc length, which it's bad at, where a bar
// would let it judge position, which it's good at. That objection is real — but it is
// an objection to the arc being the ONLY encoding.
//
// Here it isn't. The number in the middle is the primary encoding and carries the
// value exactly; the ring is redundancy that gives the tile a shape and makes "roughly
// how full" legible from across the room. That's the hero-figure-plus-meter pattern in
// a round frame, not a pie chart. Two things make it stay honest, and both are
// load-bearing:
//
//   · The scale is FIXED 0..100%. It starts at twelve o'clock and sweeps clockwise, so
//     half-full always looks half-full. A gauge that rescaled to its own recent maximum
//     would show an idle machine as dramatic.
//   · It NEVER changes hue with the value. Green→amber→red would encode the sweep
//     angle a second time and spend the only free channel restating what the arc
//     already says.
//
// Where it would NOT be allowed: comparing several of these against each other. Two
// gauges side by side are two independent readouts, never a series — that's what bars
// are for.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real value: 0            // 0..1
    property color accent: Colors.focus
    property int thickness: 8

    // ── sampleInterval ────────────────────────────────────────────────────────
    // How often `value` is refreshed, in ms. 0 (default) = a one-off change, eased on
    // the UI's own timing.
    //
    // Set it and the ring instead travels for exactly one interval, linearly, arriving
    // as the next sample lands. That's the difference between smooth and twitchy for a
    // live readout: sampled once a second and eased over Motion.standard's 150ms, the
    // arc lurches for a sixth of a second and then sits perfectly still for the other
    // five sixths. It reads as a clock ticking, not a gauge tracking.
    //
    // Same reasoning as Sparkline's glide, and the same reason the duration ISN'T a
    // Motion token: it's dictated by the data rate, not by taste. Scaling it to 2×
    // would leave the ring still moving when the next sample resets it. motionEnabled
    // is honoured — off, this falls back to the plain eased behaviour.
    property int sampleInterval: 0

    readonly property bool tracking: root.sampleInterval > 0 && Config.motionEnabled

    // Whatever goes in the hole. The caller supplies it, because the gauge has no
    // opinion about whether that's "63%" or "63°C".
    default property alias content: hole.data

    implicitWidth:  120
    implicitHeight: 120

    readonly property real _v: Math.max(0, Math.min(1, root.value))
    readonly property real _size: Math.min(root.width, root.height)
    // The arc is stroked centred on its own path, so the radius has to come in by half
    // the stroke or the ring's outer edge is clipped by the item's bounds.
    readonly property real _radius: (root._size - root.thickness) / 2

    Shape {
        anchors.centerIn: parent
        width:  root._size
        height: root._size
        // The curve renderer antialiases geometry properly; the default one leaves a
        // visibly stepped edge on a thin ring this size.
        preferredRendererType: Shape.CurveRenderer

        // ── Track ─────────────────────────────────────────────────────────────
        // The full circle, underneath. It's what makes the fill read as a FRACTION —
        // without it there's nothing to be a fraction of, and a lone arc at 63% is just
        // an arbitrary curve.
        ShapePath {
            strokeColor: Colors.alpha(Colors.fg, 0.10)
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.FlatCap

            PathAngleArc {
                centerX: root._size / 2
                centerY: root._size / 2
                radiusX: root._radius
                radiusY: root._radius
                startAngle: 0
                sweepAngle: 360
            }
        }

        // ── Fill ──────────────────────────────────────────────────────────────
        ShapePath {
            strokeColor: root.accent
            strokeWidth: root.thickness
            fillColor: "transparent"
            // Round, so the arc's leading end reads as a position rather than a cut.
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root._size / 2
                centerY: root._size / 2
                radiusX: root._radius
                radiusY: root._radius
                // -90 is twelve o'clock: Qt measures 0° at three o'clock, and a gauge
                // that starts at three reads as broken.
                startAngle: -90
                sweepAngle: 360 * root._v

                // Eased here rather than on `value`, so the caller can hand over raw
                // samples and the ring does the smoothing. One Behavior, on the one
                // property that actually moves — nothing else here animates, so there's
                // nothing for it to chase.
                //
                // Linear while tracking: a constant data rate deserves a constant
                // angular speed. OutCubic would decelerate into every sample, which puts
                // a visible tick on a value that never actually stopped changing.
                Behavior on sweepAngle {
                    NumberAnimation {
                        duration: root.tracking ? root.sampleInterval : Motion.standard
                        easing.type: root.tracking ? Easing.Linear : Motion.travel
                    }
                }
            }
        }
    }

    // The hole. Sized to the ring's inner diameter less the stroke, so content can't
    // collide with the arc.
    Item {
        id: hole
        anchors.centerIn: parent
        width:  root._size - root.thickness * 2 - 8
        height: root._size - root.thickness * 2 - 8
    }
}
