import QtQuick
import QtQuick.Shapes
import Quickshell
import "../config"

// ── WaveSlider ────────────────────────────────────────────────────────────────
// ValueSlider's handle and drag, with the flat fill replaced by end-4/dots'
// WavyLine — a travelling sine drawn up to `value`'s fraction of the track, a
// plain rail for what's left, and a thin vertical playhead bar on the join.
// The wave (see the `wave` Shape) is end-4's verbatim: constant 2px amplitude,
// frequency 6, phase off the wall clock, redrawn at 30Hz.
//
// ── `level` gates the wave, it doesn't size it ────────────────────────────────
// Fed from a PwNodePeakMonitor + Audio.meterLevel(): 0..1, how loud the source
// actually is right now. The amplitude stays constant (end-4's look); `level`
// only decides whether the wave is ALIVE — travelling at its fixed amplitude —
// or eased flat and still, so an idle slider isn't redrawing the wave at all.
//
// ── Shape, not Canvas ─────────────────────────────────────────────────────────
// This was a Canvas, rasterised on the CPU at 30Hz whenever sound played — the bar's
// volume pill wears it. Now the curve is an SVG path string the GPU draws, the same
// reasoning WaveformSpectrum gives. The CPU only builds ~60 path segments per redraw.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real value:   0.0     // 0..maximum
    property real maximum: 1.0

    property real notchAt: 0

    property color accent: enabled ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgFaint

    // 0..1, live — how loud the source actually is right now (see the header
    // comment). Not the same axis as `value`. `_smoothLevel` is what the wave
    // actually reads; this is only the target it eases toward.
    property real level: 0.0
    property real _smoothLevel: 0.0
    Behavior on _smoothLevel {
        NumberAnimation { duration: 450; easing.type: Motion.travel }
    }
    onLevelChanged: root._smoothLevel = root.level
    Component.onCompleted: root._smoothLevel = root.level

    // Ease the handle toward the value (smooth on a discrete change — a volume
    // scroll). OFF for a value that's already being animated every frame from
    // outside (a media playhead): easing on top of that is the "chase" Motion.qml
    // warns about — the handle rubber-bands behind the position it should sit on.
    property bool smoothHandle: true

    signal moved(real value)
    signal scrolled(int delta)

    readonly property alias pressed: drag.pressed

    implicitHeight: Tokens.pillHeight
    implicitWidth:  120

    readonly property real _fraction: Math.max(0, Math.min(1, value / maximum))
    readonly property color _accent: root.accent

    // Where the handle sits, in pixels — the one point the wave, the empty
    // remainder and the handle itself all measure from.
    readonly property real _fillX: root.width * root._fraction
    // A small gap pulled back from _fillX so the wave's rounded end cap sits just
    // short of the handle bar — the handle then reads as being a step ahead of the
    // progress line rather than buried in its last crest. end-4's StyledSlider
    // uses handleWidth/2 (≈1.5) here; more than that gives a clear step.
    readonly property int _handleGap: 7

    // The notch needs a full-width reference that doesn't shrink as the value
    // fills in (unlike emptyRail below) — a plain Item rather than a visible bar.
    Item {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width:  parent.width
        height: 4                         // end-4's Wavy trackWidth

        Rectangle {
            visible: root.notchAt > 0 && root.notchAt < root.maximum
            x: track.width * (root.notchAt / root.maximum) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width:  1
            height: 7
            radius: 1
            color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.38)
        }
    }

    // ── The empty remainder ────────────────────────────────────────────────────
    // Only from the wave's edge onward — a flat line running the FULL width
    // (the original ValueSlider-derived version) put a straight bar right
    // through the middle of every crest and trough, reading as a baseline
    // scoring out the wave rather than as "what's left to fill". The wave IS
    // the filled portion now; nothing else needs to say so underneath it.
    Rectangle {
        id: emptyRail
        anchors.verticalCenter: track.verticalCenter
        x:      Math.min(track.width, root._fillX + root._handleGap)
        width:  Math.max(0, track.width - x)
        height: track.height
        radius: height / 2
        color:  Colors.of(QsWindow.window).alpha(root._accent, 0.22)
    }

    // ── The wave ─────────────────────────────────────────────────────────────
    // end-4/dots' WavyLine, verbatim: a 4px round-capped sine, CONSTANT amplitude
    // (lineWidth × 0.5 = 2px), frequency 6, phase straight off the wall clock so
    // it travels — `_phase` is advanced by the FrameAnimation below. The wavelength is
    // measured across the FULL width so the pattern stays put as `drawEnd` (the
    // value fraction) reveals more or less of it.
    //
    // The one thing added: `_amp` eases to 0 at silence, so an idle slider shows a
    // flat line (and stops redrawing) rather than end-4's always-on wiggle.
    Shape {
        id: wave
        anchors.left:           track.left
        anchors.verticalCenter: track.verticalCenter
        width:  track.width
        height: Math.max(12, root.height * 0.7)
        preferredRendererType: Shape.CurveRenderer

        readonly property real drawEnd: Math.max(0, root._fillX - root._handleGap)
        readonly property color strokeColor: root._accent

        readonly property real lineW:     4
        readonly property real frequency: 6

        readonly property bool alive: Config.motionEnabled && root._smoothLevel > 0.02
        property real _amp: 0
        Behavior on _amp { NumberAnimation { duration: Motion.trail; easing.type: Motion.travel } }
        onAliveChanged: wave._amp = wave.alive ? wave.lineW * 0.5 : 0
        Component.onCompleted: wave._amp = wave.alive ? wave.lineW * 0.5 : 0

        // Advances the phase at most 30 times a second, not once per display frame: each
        // step rebuilds the path string, and a wave travelling ~8px/s needs no more.
        // `_since` collects the frame times in between.
        property real _phase: 0
        property real _since: 0
        FrameAnimation {
            // `visible`: a slider in a closed panel has nothing to animate for.
            running: wave.visible && (wave.alive || wave._amp > 0.01)
            onTriggered: {
                wave._since += frameTime
                if (wave._since < 1 / 30) return
                wave._since = 0
                wave._phase = Date.now() / 400.0
            }
        }

        // The ribbon's centre line as an SVG path: a sine sampled every 3px, drawn as a
        // smooth curve THROUGH the samples with quadratic segments to their midpoints.
        readonly property string _curve: {
            if (wave.drawEnd <= 1) return ""
            const amplitude = wave._amp
            const phase = wave._phase
            const centerY = wave.height / 2
            const k = wave.frequency * 2 * Math.PI / wave.width
            const end = wave.drawEnd
            const x0 = wave.lineW / 2
            // Each sample's y once (the loop used to take sin() twice per sample, and print 17-digit
            // floats into a string that is parsed every 33ms), numbers cut to 0.01 px.
            const r = v => Math.round(v * 100) / 100
            const xs = [x0]
            for (let x = x0 + 3; x < end; x += 3) xs.push(x)
            const n = xs.length
            const ys = new Array(n)
            for (let i = 0; i < n; i++) ys[i] = centerY + amplitude * Math.sin(k * xs[i] + phase)
            const parts = ["M " + r(xs[0]) + " " + r(ys[0])]
            for (let i = 1; i < n; i++)
                parts.push("Q " + r(xs[i - 1]) + " " + r(ys[i - 1]) + " " + r((xs[i - 1] + xs[i]) / 2)
                           + " " + r((ys[i - 1] + ys[i]) / 2))
            parts.push("Q " + r(xs[n - 1]) + " " + r(ys[n - 1]) + " " + r(end)
                       + " " + r(centerY + amplitude * Math.sin(k * end + phase)))
            return parts.join(" ")
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: wave.strokeColor
            strokeWidth: wave.lineW
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            // "M0 0", never "": an empty PathSvg warns once per frame (see VectorIcon).
            PathSvg { path: wave._curve === "" ? "M0 0" : wave._curve }
        }
    }

    // A thin vertical bar — end-4's StyledSlider handle. Taller than the wave so
    // it reads as the playhead, but not floor-to-ceiling. Tracks `_fillX` (the
    // value fraction) directly.
    Rectangle {
        id: handle
        anchors.verticalCenter: track.verticalCenter
        width:  drag.containsMouse || drag.pressed ? 2 : 3
        height: Math.max(12, root.height * 0.6)
        radius: width / 2
        color:  root._accent

        // Clamped so the bar stays fully on the track at both extremes.
        x: Math.max(0, Math.min(root.width - width, root._fillX - width / 2))

        Behavior on x {
            enabled: root.smoothHandle && !root.pressed
            NumberAnimation { duration: Motion.track; easing.type: Motion.trackCurve }
        }
        Behavior on width { NumberAnimation { duration: Motion.respond } }
        Behavior on color { ColorAnimation  { duration: Motion.respond } }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        // The rail is 3px tall — an exactly-rail-sized hit target would be
        // nearly unclickable. Extend it to the full control height.
        anchors.topMargin:    -Tokens.spacingMd
        anchors.bottomMargin: -Tokens.spacingMd
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        function commit(x) {
            root.moved(Math.max(0, Math.min(1, x / root.width)) * root.maximum)
        }
        onPressed:         function(m) { commit(m.x) }
        onPositionChanged: function(m) { if (pressed) commit(m.x) }
        onWheel:           function(w) { root.scrolled(w.angleDelta.y > 0 ? 1 : -1) }
    }
}
