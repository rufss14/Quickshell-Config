// Bound: the gridline Repeater's delegate reads `root` (an id from the enclosing
// component), which is unqualified access without this.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "../config"

// ── Sparkline ─────────────────────────────────────────────────────────────────
// A fixed-window trend line. One series, no axes, no legend, no labels — the number
// beside it is the value; this is only the shape of the last minute.
//
// ── The rules it follows, and why ─────────────────────────────────────────────
// · ONE hue. Trend-over-time with a single series is a sequential job, not a
//   categorical one — there is no identity to distinguish, so there is nothing for a
//   second hue to mean.
// · NO legend. A legend for one series names what the title already named.
// · NO value labels. A number on every point is chaos and goes unread; the stat tile's
//   figure carries the current value and this carries the shape.
// · A FIXED window. `capacity` samples wide, always. If the x-axis grew as samples
//   arrived, the line would compress as you watched and the same load would draw a
//   different shape depending on how long you'd had the page open.
// · A FIXED 0..1 y-axis. Auto-scaling to the data's own max is the classic sparkline
//   lie: an idle machine drifting between 1% and 3% would render as a dramatic
//   mountain range. 40% must look like 40% of the height.
//
// Shapes/ShapePath rather than Canvas: Canvas rasterises on the render thread through
// a JS paint callback every repaint, which for a line that updates every second is a
// lot of machinery. Shape is scene-graph geometry.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Oldest first, values 0..1.
    property var values: []
    property int capacity: 60
    property color accent: Colors.focus

    implicitHeight: 40

    readonly property bool hasData: root.values.length > 1

    // ── curved ────────────────────────────────────────────────────────────────
    // Catmull-Rom through the samples instead of straight segments between them.
    //
    // NOT named `smooth`: Item already has one, and it means antialiasing. Setting that
    // by accident would turn the line jaggy while doing nothing to its shape — the kind
    // of bug you stare at for an hour.
    //
    // It interpolates BETWEEN real samples and invents none: every sample is still a
    // point the curve passes exactly through. What changes is the path taken between
    // two of them, which was never data in the first place — a straight segment is just
    // as much an assumption about the intervening time, only an uglier one.
    property bool curved: true

    // ── damping ───────────────────────────────────────────────────────────────
    // Trailing rolling mean, in samples. 1 = off.
    //
    // Unlike `curved`, this one DOES change the data, and that's the whole point: real
    // throughput arrives in clumps, so a raw 250ms trace is a sawtooth that says
    // "bursty" and nothing else. A short mean lets the shape through and drops the
    // clatter.
    //
    // It is TRAILING, never centred: a centred window would need samples from after
    // the point it's drawing, so the line would depend on the future and the newest
    // value would keep changing after it appeared. Every point here is a mean of
    // itself and the ones before it, which is a claim you can defend.
    //
    // The cost is honest and worth stating: this HIDES short spikes. Don't turn it on
    // for a chart whose job is to show them.
    property int damping: 1

    // ── sampleInterval / the glide ────────────────────────────────────────────
    // How often a new sample arrives, in ms. 0 (default) = no glide.
    //
    // Without it the line is stationary and then JUMPS one slot sideways when a sample
    // lands — on the signal chart that's a ~5px lurch once a second. Set it and the
    // whole trace slides left continuously instead, arriving exactly as the next
    // sample does.
    //
    // Feed this `capacity + 1` samples if you can: the extra one sits off the left edge
    // and keeps it covered while the trace slides. Without it a gap opens and closes at
    // the left edge every interval. NetStats keeps the extra sample for this reason.
    property int sampleInterval: 0

    readonly property bool gliding: root.sampleInterval > 0 && Config.motionEnabled

    // ── gridlines ─────────────────────────────────────────────────────────────
    // Interior horizontal reference lines. 0 = none, 1 = a line at the midpoint.
    property int gridlines: 0

    // ── The damped series ─────────────────────────────────────────────────────
    // Everything below draws THIS, not `values`. Computed once per data change rather
    // than inside _path, which is called twice (fill and stroke) — an O(n·damping)
    // scan run twice per update for the same answer is just heat.
    readonly property var _series: {
        if (root.damping <= 1) return root.values
        const src = root.values
        const out = []
        for (let i = 0; i < src.length; i++) {
            let sum = 0, n = 0
            for (let k = Math.max(0, i - root.damping + 1); k <= i; k++) { sum += src[k]; n++ }
            out.push(sum / n)
        }
        return out
    }

    // ── The glide ─────────────────────────────────────────────────────────────
    // Every x is shifted by `_glide`, which snaps to one slot's width the instant a
    // sample lands and runs back to 0 over exactly one interval. The trace therefore
    // renders where it already was, then slides into its new position just in time for
    // the next sample. Clipped, because the newest point starts off the right edge.
    readonly property real _step: root.capacity <= 1 ? 0 : root.width / (root.capacity - 1)
    property real _glide: 0

    clip: root.gliding

    onValuesChanged: {
        if (!root.gliding) return
        root._glide = root._step
        glideAnim.restart()
    }

    // ── Why this duration is not a Motion token ───────────────────────────────
    // It is not a design decision. The glide has to last exactly one sample interval:
    // shorter and the line arrives early and sits still, longer and it's still moving
    // when the next sample resets it, which stutters. Motion.qml's own note draws this
    // same line for `track` — a property following a live value "is not UI motion and
    // must not use the UI scale", because scaling it makes a live readout worse rather
    // than calmer.
    //
    // motionEnabled IS honoured, via `gliding`: a chart that scrolls forever is exactly
    // the kind of unprompted movement that setting exists to stop. Off, the line steps
    // — which is what it did before any of this.
    NumberAnimation {
        id: glideAnim
        target: root
        property: "_glide"
        to: 0
        duration: root.sampleInterval
        easing.type: Easing.Linear    // constant data rate = constant speed
    }

    // x for sample i, pinned to `capacity` rather than to values.length — see above.
    function _x(i) {
        return (root.capacity <= 1 ? 0 : (i / (root.capacity - 1)) * root.width) + root._glide
    }
    function _y(v) { return root.height - Math.max(0, Math.min(1, v)) * root.height }

    // The line is drawn right-aligned: the newest sample sits at the right edge and
    // history trails off to the left, so a partial buffer fills from the right and the
    // line doesn't slide sideways as it fills.
    //
    // Goes NEGATIVE when handed capacity+1 samples, which is intended: the surplus
    // oldest sample lands off the left edge, where it covers the gap the glide opens.
    readonly property int _offset: root.capacity - root._series.length

    // ── The path ──────────────────────────────────────────────────────────────
    // Built as an SVG string because the number of segments is data-dependent, and
    // PathCubic has to be declared statically — there is no Repeater for path elements.
    // PathSvg is the only element that takes a curve count decided at runtime.
    //
    // `fill` closes the shape down to the baseline at both ends; the stroke doesn't.
    function _path(fill) {
        const n = root._series.length
        if (n < 2) return ""

        const px = i => root._x(root._offset + i)
        const py = i => root._y(root._series[i])
        // Clamped at both ends: Catmull-Rom needs a point either side of every segment,
        // and the first and last have only one. Duplicating the endpoint is the standard
        // answer and makes the curve leave and arrive flat rather than lurching.
        const cx = i => px(Math.max(0, Math.min(n - 1, i)))
        const cy = i => py(Math.max(0, Math.min(n - 1, i)))

        let d = fill ? "M " + px(0) + "," + root.height + " L " + px(0) + "," + py(0)
                     : "M " + px(0) + "," + py(0)

        for (let i = 0; i < n - 1; i++) {
            if (!root.curved) {
                d += " L " + px(i + 1) + "," + py(i + 1)
                continue
            }
            // Uniform Catmull-Rom to cubic Bezier. The /6 is the exact conversion for
            // tension 0.5 — the control points sit a sixth of the way along the
            // neighbouring chord, which is what makes the spline pass through every
            // sample rather than near it.
            const c1x = cx(i)     + (cx(i + 1) - cx(i - 1)) / 6
            const c2x = cx(i + 1) - (cx(i + 2) - cx(i))     / 6
            // Control points are clamped to the box, the samples having already been
            // clamped by _y(). Catmull-Rom OVERSHOOTS around a sharp change, and Shape
            // doesn't clip, so the bulge would paint over the text above the chart.
            // Measured worst case (searched, not guessed): 5px past the edge on a 40px
            // chart — 12.5% of the height. It takes a run like 1,0,1,1,0 to get there;
            // a lone 0→1→0 impulse only overshoots 0.4px, which is why this is easy to
            // eyeball as "fine" and ship.
            const lim = v => Math.max(0, Math.min(root.height, v))
            const c1y = lim(cy(i)     + (cy(i + 1) - cy(i - 1)) / 6)
            const c2y = lim(cy(i + 1) - (cy(i + 2) - cy(i))     / 6)

            d += " C " + c1x + "," + c1y + " " + c2x + "," + c2y
               + " " + px(i + 1) + "," + py(i + 1)
        }

        if (fill) d += " L " + px(n - 1) + "," + root.height + " Z"
        return d
    }

    // ── Gridlines ─────────────────────────────────────────────────────────────
    // Reference lines, drawn FIRST so the trace crosses over them — a gridline on top
    // of the data would cut the line it's meant to help you read.
    //
    // Neutral and very faint, never the accent: this is furniture. It marks where the
    // axis labels' midpoint falls and then gets out of the way. They don't glide —
    // the grid is a property of the box, not of the data moving through it.
    Repeater {
        model: Math.max(0, root.gridlines)

        Rectangle {
            required property int index

            height: 1
            width:  root.width
            // index+1 of gridlines+1 divisions: 1 line lands at the midpoint, 3 at the
            // quarters, and none ever sits on the top or bottom edge where the axis
            // labels already are.
            y: root.height * (index + 1) / (root.gridlines + 1)
            color: Colors.alpha(Colors.fg, 0.07)
        }
    }

    // ── Fill under the line ───────────────────────────────────────────────────
    // A translucent wash, not a solid block. Saturated fills are for small marks and
    // accents; a large solid block reads loud and buries the line that carries the
    // actual information.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: root.hasData

        ShapePath {
            fillColor: Colors.alpha(root.accent, 0.14)
            strokeColor: "transparent"

            // The fill starts and ends on the baseline, so it closes against the bottom
            // rather than against the first sample's height.
            PathSvg { path: root._path(true) }
        }
    }

    // ── The line ──────────────────────────────────────────────────────────────
    // 2px, round joins. Thin marks: the trend is the point, and a fat line hides its
    // own detail at this size.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: root.hasData

        ShapePath {
            strokeColor: root.accent
            strokeWidth: 2
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle:  ShapePath.RoundCap

            PathSvg { path: root._path(false) }
        }
    }

    // ── The newest sample, marked ─────────────────────────────────────────────
    // It says which end is "now" without a word of axis furniture.
    //
    // Hidden while gliding, and that isn't a compromise: the newest vertex spends the
    // whole interval off the right edge, sliding in — so a dot pinned to it would
    // flicker at the boundary once per sample, and a dot pinned to the edge instead
    // would sit off the line it's supposed to mark. A trace that visibly flows leftward
    // already says which end is now; the dot was only ever doing that job for a
    // stationary chart.
    Rectangle {
        visible: root.hasData && !root.gliding
        width:  6
        height: 6
        radius: 3
        color:  root.accent
        x: root._x(root.capacity - 1) - width / 2
        y: root._y(root._series[root._series.length - 1]) - height / 2
    }
}
