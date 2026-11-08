pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import QtQuick.Shapes
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/weather.js" as W
import "../../services/ics.js" as Ics
import "../../services/holidays.js" as H
import "../../services/dayfacts.js" as Facts
import "../../services/dayplan.js" as Plan
import "../../services/quickadd.js" as Quick
import "../../services/alarms.js" as AL
import "../../services/worldclock.js" as Z

// ClockMoon — moved out of ClockPanel.qml (2026-11-08), unchanged.
// ── The moon, drawn ───────────────────────────────────────────────────────
// A lit limb and a terminator, as two arcs of one path: the limb is always a half
// circle on the lit side, and the terminator is an ellipse whose width is the
// cosine of the phase — thin crescent, straight line at a quarter, bulging for a
// gibbous. Mirrored south of the equator, where the moon waxes from the left.
Item {
    id: moonItem
    property real phase: 0          // 0 new → 0.5 full → 1
    property bool southern: false

    implicitWidth:  Tokens.iconMd
    implicitHeight: Tokens.iconMd

    readonly property real r: Math.min(width, height) / 2
    readonly property real k: Math.cos(2 * Math.PI * moonItem.phase)
    readonly property bool waxing: moonItem.phase < 0.5

    transform: Scale { origin.x: moonItem.width / 2; xScale: moonItem.southern ? -1 : 1 }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.14)
    }
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillColor: Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).fg, Colors.of(QsWindow.window).warning, 0.25)
            startX: moonItem.r
            startY: 0
            PathArc {
                x: moonItem.r; y: moonItem.r * 2
                radiusX: moonItem.r; radiusY: moonItem.r
                direction: moonItem.waxing ? PathArc.Clockwise : PathArc.Counterclockwise
            }
            PathArc {
                x: moonItem.r; y: 0
                radiusX: Math.max(0.01, moonItem.r * Math.abs(moonItem.k)); radiusY: moonItem.r
                // Bulges toward the lit side for a crescent, away for a gibbous.
                direction: (moonItem.waxing ? moonItem.k > 0 : moonItem.k < 0)
                           ? PathArc.Counterclockwise : PathArc.Clockwise
            }
        }
    }
}
