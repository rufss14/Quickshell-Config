import QtQuick
import Quickshell
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
    property color accent: Colors.of(QsWindow.window).primary
    property int thickness: 8

    // ── sampleInterval ────────────────────────────────────────────────────────
    // How often `value` is refreshed, in ms. 0 (default) = a one-off change, eased on
    // the UI's own timing.
    //
    // Set it and the ring settles into each sample over Motion.settle, then rests.
    //
    // It used to travel for exactly one interval, linearly, arriving as the next sample
    // landed — smoother, and never still: a ring that is always moving redraws its whole
    // surface at the display's refresh rate for as long as it is on screen, which on the
    // desktop and the lock screen is all day. Motion.settle has the measurements. The
    // interval still caps the ease, so a stream faster than the token never chases.
    // motionEnabled is honoured — off, this falls back to the plain eased behaviour.
    property int sampleInterval: 0

    readonly property bool tracking: root.sampleInterval > 0 && Config.motionEnabled

    // ── glide ─────────────────────────────────────────────────────────────────
    // Opt in to Motion.glide instead of the settle: a longer, in-and-out ease for a
    // ring that is watched (the sidebar's stats pill). Honours motionEnabled too.
    property bool glide: false
    readonly property bool _gliding: root.glide && Config.motionEnabled

    // ── wavy: Material 3 Expressive's wavy indicator ─────────────────────────
    // The filled arc is drawn as a wave along the ring, the track continues it after a
    // gap, both in the accent's own tones (the track is the accent at low alpha, so a
    // per-tile accent keeps the pair). Opt-in; every existing gauge stays a plain ring.
    //
    // The wave is anchored to the RING, not to the arc's end: it sits still and a growing
    // value reveals more of it. So nothing moves at rest — the "always-moving ring
    // redraws all day" cost sampleInterval above warns about does not come back. The
    // outline is rebuilt only while the value eases. The wave lies flat at 0 and springs up
    // as soon as there is something to show.
    property bool wavy: false
    // Wavy, but lying flat for now: the wave springs down and back up without the ring
    // changing size or tone (a paused track's progress — VisualizerPill).
    property bool flat: false

    // Whatever goes in the hole. The caller supplies it, because the gauge has no
    // opinion about whether that's "63%" or "63°C".
    default property alias content: hole.data

    implicitWidth:  120
    implicitHeight: 120

    readonly property real _v: Math.max(0, Math.min(1, root.value))
    readonly property real _size: Math.min(root.width, root.height)
    // The arc is stroked centred on its own path, so the radius has to come in by half
    // the stroke or the ring's outer edge is clipped by the item's bounds.
    // Wavy: in by the wave's height too, so its crests stay inside the item.
    // A pixel at the least: on the sidebar's 2px rings a quarter-stroke wave is half a pixel,
    // which draws as a plain ring.
    readonly property real _amp: root.wavy ? Math.max(1, root.thickness * 0.25) : 0
    readonly property real _radius: (root._size - root.thickness) / 2 - root._amp

    // The value as drawn: eased here rather than on `value`, so the caller can hand over
    // raw samples and the ring does the smoothing. One Behavior, on the one property that
    // actually moves — nothing else here animates, so there's nothing for it to chase.
    // (It used to sit on the fill's sweepAngle; moved here so the wave can read it too.)
    //
    // Decelerating either way: a sampled value now arrives and RESTS, so the house curve
    // fits it the same as a one-off change (see sampleInterval).
    property real _shown: root._v
    Behavior on _shown {
        NumberAnimation {
            duration: root._gliding ? Motion.glide
                    : root.tracking ? Math.min(root.sampleInterval, Motion.settle)
                                    : Motion.standard
            easing.type: root._gliding ? Motion.glideCurve : Motion.travel
        }
    }

    // ── The wave (wavy only) ──────────────────────────────────────────────────
    SpringValue {
        id: waveAmp
        spec: Motion.springSpatial
        epsilon: 0.002
        target: root.wavy && !root.flat && root._shown > 0.01 ? 1 : 0
    }
    // Crests two and a half strokes apart, whatever the ring's size — 6px at the least, the
    // same floor's reason: closer than that a thin ring's wave reads as a fuzzy edge.
    readonly property int _waves: Math.max(6, Math.round(2 * Math.PI * root._radius / Math.max(6, root.thickness * 2.5)))
    // The gap between the fill's end and the track, in degrees: a stroke's width plus the
    // two round caps reaching into it.
    readonly property real _gapDeg: root._radius > 0 ? (root.thickness * 2) / root._radius * 180 / Math.PI : 0
    readonly property var _wave: {
        if (!root.wavy) return []
        const sweep = 2 * Math.PI * root._shown
        if (sweep <= 0.0001) return []
        const c = root._size / 2, R = root._radius, A = root._amp * waveAmp.value
        // Eight points a crest, 48–160 round the circle: a small ring that glides every second
        // (the sidebar's timer) rebuilds this each frame of the glide, so it gets fewer.
        const n = Math.max(2, Math.ceil(sweep / (2 * Math.PI) * Math.min(160, Math.max(48, root._waves * 8))))
        const out = new Array(n + 1)
        for (let i = 0; i <= n; i++) {
            const along = sweep * i / n                 // from twelve o'clock
            const r = R + A * Math.sin(root._waves * along)
            const t = along - Math.PI / 2
            out[i] = Qt.point(c + r * Math.cos(t), c + r * Math.sin(t))
        }
        return out
    }

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
        //
        // Wavy: what is left of the circle after the fill, with a gap at both ends, in the
        // accent's own tone (Material's track) — the whole circle while there is no fill.
        ShapePath {
            strokeColor: root.wavy ? Colors.of(QsWindow.window).alpha(root.accent, 0.22)
                                   : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.10)
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: root.wavy ? ShapePath.RoundCap : ShapePath.FlatCap

            PathAngleArc {
                readonly property bool gapped: root.wavy && root._shown > 0.01
                centerX: root._size / 2
                centerY: root._size / 2
                radiusX: root._radius
                radiusY: root._radius
                startAngle: gapped ? -90 + 360 * root._shown + root._gapDeg : 0
                sweepAngle: gapped ? Math.max(0, 360 * (1 - root._shown) - 2 * root._gapDeg) : 360
            }
        }

        // ── Fill ──────────────────────────────────────────────────────────────
        ShapePath {
            // Off (not just transparent) while the wave draws the fill instead.
            strokeColor: root.wavy ? "transparent" : root.accent
            strokeWidth: root.wavy ? -1 : root.thickness
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
                sweepAngle: 360 * root._shown
            }
        }

        // ── Fill, wavy ────────────────────────────────────────────────────────
        ShapePath {
            strokeColor: root.wavy && root._wave.length > 0 ? root.accent : "transparent"
            strokeWidth: root.wavy ? root.thickness : -1
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root._wave }
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
