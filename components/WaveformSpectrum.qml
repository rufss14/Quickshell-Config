import QtQuick
import Quickshell
import QtQuick.Shapes
import "../config"

// ── WaveformSpectrum ──────────────────────────────────────────────────────────
// The spectrum as one continuous ribbon instead of discrete bars — a smoothed
// curve through each bin's level, filled to the baseline. Quadratic-through-
// midpoints is the standard trick for a smooth line through unevenly-spaced data
// without needing a real spline: each segment curves toward the midpoint of its
// two neighbours instead of the neighbour itself, which is what keeps the curve
// from kinking at every sample.
//
// Redrawn on every `levels` change — cava publishes at 60fps (see
// services/CavaStream.qml), so there is no extra smoothing to add here; the frame rate
// itself is the animation.
//
// ── Shape, not Canvas ─────────────────────────────────────────────────────────
// This was a Canvas: a JS paint callback rasterising the whole item in software on
// the GUI thread, then uploading the result as a texture — every cava frame. As the
// desktop background that item is the full screen width (1920×270 here), so it was
// ~2 MB of pixels filled, stroked and uploaded sixty times a second whenever music
// played. Now the curve is one SVG path string and the GPU draws it; per frame the
// CPU only builds ~32 path segments. Same reasoning Sparkline's header gives.
//
// CurveRenderer, not the default: it draws quadratic segments natively and
// antialiases analytically. The default geometry renderer needs MSAA for smooth
// edges, and the Canvas this replaced was antialiased.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var  levels:   []
    property int  barCount: 32
    property color accent:  Colors.of(QsWindow.window).primary
    property bool centered: false

    // Keeps the 3px stroke inside the item at full level.
    readonly property real _margin: 4
    readonly property real _baseline: root.centered ? root.height / 2 : root.height - root._margin

    // Whether to build the path at all. Follows `visible`: a hidden spectrum still gets every
    // cava frame, and building its path then is wasted. A host that draws it hidden ON PURPOSE
    // sets it true — CavaBG's stencil is an invisible layer a mask reads, so `visible` is false
    // there while the ribbon is exactly what's on screen (2026-10-31: following `visible`
    // alone left the desktop wave blank).
    property bool drawing: root.visible

    // The ribbon's top edge. "" while there is nothing to draw, or while not `drawing`.
    readonly property string _curve: {
        const n = root.barCount
        const w = root.width, h = root.height
        if (!root.drawing || n < 2 || w <= 0 || h <= 0) return ""

        // Measured 2026-11-02 (gdb sampling of the GUI thread, music playing): ~70% of the JS time
        // was this binding and the two PathSvg bindings under it, run once per cava frame. Every
        // `root.x` is a property lookup, so the loops read locals, and the numbers are cut to
        // 0.01 px (the string is parsed twice a frame; a 17-digit float is most of it).
        const stepX  = w / (n - 1)
        const usable = Math.max(1, h - root._margin * 2)
        const lv     = root.levels
        const m      = lv.length
        const base   = root.centered ? h / 2 : h - root._margin
        const amp    = root.centered ? usable / 2 : usable

        const py = new Array(n)
        for (let i = 0; i < n; i++) {
            const v = i < m ? lv[i] : 0
            py[i] = Math.round((base - amp * (v < 0 ? 0 : v > 1 ? 1 : v)) * 100) / 100
        }

        const parts = ["M 0 " + py[0]]
        for (let i = 0; i < n - 1; i++)
            parts.push("Q " + Math.round(i * stepX * 100) / 100 + " " + py[i] + " "
                       + Math.round((i + 0.5) * stepX * 100) / 100 + " "
                       + Math.round((py[i] + py[i + 1]) * 50) / 100)
        parts.push("L " + Math.round((n - 1) * stepX * 100) / 100 + " " + py[n - 1])
        return parts.join(" ")
    }

    Shape {
        anchors.fill: parent
        visible: root._curve !== ""
        preferredRendererType: Shape.CurveRenderer
        // The curve is re-processed (stroked, the fill triangulated) every cava frame, and as the
        // desktop background that is once per screen, 60 times a second, twice a frame (fill
        // and ribbon). Synchronously that is all on the GUI thread; asynchronous hands the
        // path processing to a worker, so the GUI thread only swaps in the result. The picture
        // trails by at most a frame, which at cava's own 60Hz publish rate is not a thing the
        // eye can place.
        asynchronous: true

        // Fill under the curve.
        ShapePath {
            strokeColor: "transparent"
            strokeWidth: 0
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: 0; y2: root.height
                GradientStop { position: 0; color: Colors.of(QsWindow.window).alpha(root.accent, 0.90) }
                GradientStop { position: 1; color: Colors.of(QsWindow.window).alpha(root.accent, 0.35) }
            }
            // "M0 0", never "": an empty PathSvg warns once per frame (see VectorIcon).
            PathSvg {
                path: root._curve === "" ? "M0 0"
                    : root._curve + " L " + root.width + " " + root._baseline
                                  + " L 0 " + root._baseline + " Z"
            }
        }

        // The ribbon itself, on top.
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.accent
            strokeWidth: 3
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.FlatCap     // the Canvas's default "butt" end
            PathSvg { path: root._curve === "" ? "M0 0" : root._curve }
        }
    }
}
