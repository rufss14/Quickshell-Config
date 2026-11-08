import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── HourlyChart ───────────────────────────────────────────────────────────────
// The next 24 hours as one picture: the temperature as a curve, and under it the chance
// of rain hour by hour as faint bars. Is it warming or cooling, and when does it rain —
// the two things a number cannot say.
//
// Hover it and it becomes a scrubber: a marker follows the pointer hour by hour and
// `idx` says which one (-1 when not hovered), so the tile can read that hour out wherever
// suits it. A dot at the left edge is "now".
//
// ── What it hands Sparkline ───────────────────────────────────────────────────
// Sparkline wants 0..1 values and draws `capacity` slots right-aligned. Raw degrees clamp
// to a flat line at the top, and the default 60 slots would put 24 hours in the right 40%
// — which is what the medium tile did before this. So: normalised here, capacity = count.
//
// ── The wipe ──────────────────────────────────────────────────────────────────
// On load the curve and the bars are revealed left to right, once (a clip that grows).
// Nothing loops: a tile on the desktop all day pays for any animation that never rests.
// `active: false` (a settings preview) skips it. Motion off: every duration is 0.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property color accent: Colors.of(QsWindow.window).primary
    property color rainColor: Colors.of(QsWindow.window).info
    property bool showRain: true
    property bool active: true

    readonly property int n: Weather.hourlyTemps.length
    readonly property var norm: {
        const v = Weather.hourlyTemps
        if (v.length < 2) return []
        const lo = Math.min(...v), hi = Math.max(...v)
        // A floor on the span, and the series centred in it: a day that only moves 2°
        // should look flat, not fill the whole height like a 20° swing would.
        const span = Math.max(6, hi - lo), mid = (hi + lo) / 2
        return v.map(t => 0.5 + 0.8 * (t - mid) / span)
    }

    // Which hour the pointer is on, or -1.
    readonly property int idx: hover.hovered && root.n > 1
        ? Math.max(0, Math.min(root.n - 1, Math.round(hover.point.position.x / Math.max(1, root.width) * (root.n - 1))))
        : -1

    implicitHeight: 40
    visible: root.n > 1

    // ── The wipe ──────────────────────────────────────────────────────────────
    property real wipe: root.active ? 0 : 1
    onNChanged: if (root.n > 1 && root.wipe === 0 && !draw.running) draw.start()
    Component.onCompleted: if (root.n > 1 && root.wipe === 0) draw.start()
    SequentialAnimation {
        id: draw
        PauseAnimation { duration: Motion.standard }
        NumberAnimation {
            target: root; property: "wipe"; to: 1
            duration: Motion.spatialSlow
            easing.type: Motion.expressive
        }
    }

    Item {
        width: root.width * root.wipe
        height: root.height
        clip: true

        Item {
            width: root.width
            height: root.height

            // Rain chance, under the curve. A hairline bar per hour, so it reads as a
            // texture of wet hours rather than a second chart competing with the line.
            Repeater {
                model: root.showRain ? root.n : 0
                Rectangle {
                    required property int index
                    readonly property real chance: (Weather.hourlyPrecip[index] ?? 0) / 100
                    width: Math.max(2, root.width / root.n * 0.5)
                    height: chance * root.height * 0.5
                    x: index / (root.n - 1) * root.width - width / 2
                    y: root.height - height
                    radius: width / 2
                    color: Colors.of(QsWindow.window).alpha(root.rainColor, 0.4)
                }
            }

            Sparkline {
                anchors.fill: parent
                values: root.norm
                capacity: Math.max(2, root.n)
                accent: root.accent
                curved: true
            }
        }
    }

    // "Now": the first sample, which is the current hour.
    Rectangle {
        visible: root.n > 1
        x: -width / 2
        y: root.height - (root.norm[0] ?? 0) * root.height - height / 2
        width: Tokens.spacingMd - Tokens.spacingXs; height: width; radius: width / 2
        color: root.accent
        opacity: root.wipe > 0.02 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
    }

    HoverHandler { id: hover }

    // The scrub marker. Eased on the live-tracking timing, not the UI's: it is following
    // a pointer, and at 150ms it would visibly trail it.
    Rectangle {
        x: (root.idx < 0 ? 0 : root.idx / (root.n - 1) * root.width) - width / 2
        width: 1
        height: root.height
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.25)
        opacity: root.idx < 0 ? 0 : 1
        Behavior on x       { NumberAnimation { duration: Motion.track; easing.type: Motion.trackCurve } }
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
    }
    Rectangle {
        x: (root.idx < 0 ? 0 : root.idx / (root.n - 1) * root.width) - width / 2
        y: (root.idx < 0 ? 0 : root.height - root.norm[root.idx] * root.height) - height / 2
        width: Tokens.spacingMd; height: width; radius: width / 2
        color: root.accent
        opacity: root.idx < 0 ? 0 : 1
        scale: root.idx < 0 ? 0.4 : 1
        Behavior on x       { NumberAnimation { duration: Motion.track; easing.type: Motion.trackCurve } }
        Behavior on y       { NumberAnimation { duration: Motion.track; easing.type: Motion.trackCurve } }
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        Behavior on scale {
            NumberAnimation {
                duration: Motion.spatial
                easing.bezierCurve: Motion.spring
                easing.type: Easing.BezierSpline
            }
        }
    }
}
