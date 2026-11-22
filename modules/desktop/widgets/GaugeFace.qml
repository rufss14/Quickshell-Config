import QtQuick
import QtQuick.Effects
import Quickshell
import QtQuick.Shapes
import "../../../config"
import "../../../components"

// ── GaugeFace ─────────────────────────────────────────────────────────────────
// The picture on a Gauge tile (GaugeWidget): one value, 0..1, as either
//   water   a glass in your shape that fills — two slow waves ride its surface, the nearer one
//           in the accent, the farther one fainter and the other way round; or
//   ring    the shell's wavy ring round a small shape of yours.
// It draws no number; the tile puts that beside it.
//
// The water is a pair of tiled sine strips (two periods wide, drawn once per size) slid sideways
// by a plain animation, so nothing recomputes per frame; the level rides a spring, so a jump in
// the value is a swell, not a cut. The strips are clipped to the glass's own shape by a mask.
// `running` stops the waves (the widget is off screen, or ambient motion is off); the water then
// just rests at its level.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real value: 0
    property string shape: "pentagon"
    property bool water: true
    property color accent: Colors.of(QsWindow.window).primary
    property bool running: true
    // The wave sample every this many pixels (a coarser sine is cheaper and reads the same at a glance).
    readonly property real _step: Math.max(4, root.width / 24)

    readonly property var palette: Colors.of(QsWindow.window)

    SpringValue {
        id: level
        target: Math.max(0, Math.min(1, root.value))
        spec: Motion.springSpatial
        epsilon: 0.0005
    }

    // ── Water ─────────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: root.water

        // The empty glass.
        MorphShape {
            anchors.fill: parent
            shape: root.shape
            turns: false
            fillColor: root.palette.plate
        }

        // The silhouette the water is cut to: a hidden layer, read only by the effect.
        Item {
            id: silhouette
            anchors.fill: parent
            visible: false
            layer.enabled: true
            MorphShape {
                anchors.fill: parent
                shape: root.shape
                turns: false
                fillColor: "white"
            }
        }

        Item {
            id: tank
            anchors.fill: parent
            layer.enabled: true
            layer.smooth: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: silhouette
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            // The surface sits at (1 - level) of the glass; the amplitude is a twentieth of it, and the
            // sheet extends below the glass so a swell never shows an edge.
            readonly property real amp: root.height * 0.045
            readonly property real surfaceY: root.height * (1 - level.value)

            WaveStrip {
                id: far
                period: root.width
                lift: tank.surfaceY - tank.amp * 0.4
                phase: 0.5
                seconds: 9
                reverse: true
                fill: root.palette.alpha(root.accent, 0.38)
            }
            WaveStrip {
                id: near
                period: root.width
                lift: tank.surfaceY
                phase: 0
                seconds: 6
                reverse: false
                fill: root.accent
            }
        }
    }

    // ── Ring ──────────────────────────────────────────────────────────────────
    RadialGauge {
        anchors.fill: parent
        visible: !root.water
        thickness: Math.max(6, Math.round(root.width * 0.09))
        value: root.value
        accent: root.accent
        wavy: true

        MorphShape {
            anchors.fill: parent
            anchors.margins: Tokens.spacingSm
            shape: root.shape
            spec: Motion.springSpatialFast
            fillColor: root.palette.primaryContainer
        }
    }

    // One tiled sine strip, slid sideways forever (while `running`).
    component WaveStrip: Item {
        id: strip
        property real period: 100
        property real lift: 0
        property real phase: 0
        property real seconds: 6
        property bool reverse: false
        property color fill: "white"

        width: strip.period * 2
        height: root.height * 2
        y: strip.lift
        // `x` is the animation's alone (a binding beside it would fight it); it starts at the phase.
        Component.onCompleted: strip.x = -strip.phase * strip.period

        // Two periods of sine, then down and back along the bottom: a closed sheet.
        readonly property var points: {
            const out = []
            const n = Math.ceil(strip.width / root._step)
            for (let i = 0; i <= n; i++) {
                const x = Math.min(strip.width, i * root._step)
                out.push(Qt.point(x, tank.amp * Math.sin(x / strip.period * 2 * Math.PI)))
            }
            out.push(Qt.point(strip.width, strip.height))
            out.push(Qt.point(0, strip.height))
            return out
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: strip.fill
                strokeColor: "transparent"
                strokeWidth: -1
                PathPolyline { path: strip.points }
            }
        }

        // Slid by one period, then it is where it began: seamless.
        NumberAnimation on x {
            running: root.running && root.water && Motion.ambientOn
            loops: Animation.Infinite
            from: strip.reverse ? -strip.period - strip.phase * strip.period : -strip.phase * strip.period
            to:   strip.reverse ? -strip.phase * strip.period : -strip.period - strip.phase * strip.period
            duration: strip.seconds * 1000
        }
    }
}
