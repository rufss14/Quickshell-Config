import QtQuick
import Quickshell
import QtQuick.Shapes
import "../config"

// ── VectorIcon ────────────────────────────────────────────────────────────────
// An icon drawn from SVG path data rather than picked out of a font.
//
// ── Why this exists next to a Nerd Font ───────────────────────────────────────
// Almost every icon in this shell is a Nerd Font glyph, and should stay one: they
// inherit the type scale, they cost nothing, and for a bar pill or a menu row nobody
// is comparing them against a reference.
//
// This is for the case where the SHAPE ITSELF is the requirement — the Discord call
// controls, where the point is that the button looks like Discord's button. A font can
// only offer its nearest neighbour (Material's `monitor_share` for Discord's screen
// share, say), and "nearest neighbour" is exactly what you notice when the real thing
// is on the other monitor.
//
// ── Coordinates ───────────────────────────────────────────────────────────────
// Paths are authored on a `viewBox` grid — 24×24 by convention, the same grid Material,
// Lucide and Discord's own icons use — and scaled to `size` here. So a path can be
// lifted from any 24-grid icon set and dropped in unchanged, and one icon can be drawn
// at any size without re-authoring it.
//
// `fillPath` and `strokePath` are separate because most of these icons are both: a
// solid microphone body inside a stroked stand, a filled arrow inside a stroked screen.
// Either may be empty.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // SVG path data on the `viewBox` grid. Multiple subpaths in one string are fine.
    property string fillPath:   ""
    property string strokePath: ""

    property color color: Colors.of(QsWindow.window).fg
    property real  strokeWidth: 1.8

    property int  size: Tokens.iconLg
    property real viewBox: 24

    implicitWidth:  root.size
    implicitHeight: root.size

    // The paths are authored at `viewBox` scale and shrunk to fit. Scaling the
    // container rather than the Shape keeps the path data readable as the numbers the
    // icon was drawn with.
    Item {
        width:  root.viewBox
        height: root.viewBox
        transform: Scale {
            xScale: root.size / root.viewBox
            yScale: root.size / root.viewBox
        }

        Shape {
            anchors.fill: parent
            // The curve renderer, as everywhere else in this shell that uses Shape —
            // the geometry renderer visibly facets small curves, and every one of these
            // icons is small curves.
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor:   root.color
                strokeColor: "transparent"
                strokeWidth: 0
                fillRule:    ShapePath.WindingFill
                // An empty path is a legitimate state (stroke-only icons), and a
                // degenerate point draws nothing — which is what we want, rather than a
                // warning per frame.
                PathSvg { path: root.fillPath !== "" ? root.fillPath : "M0 0" }
            }

            ShapePath {
                fillColor:   "transparent"
                strokeColor: root.color
                strokeWidth: root.strokeWidth
                capStyle:  ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: root.strokePath !== "" ? root.strokePath : "M0 0" }
            }
        }
    }

    Behavior on color { ColorAnimation { duration: Motion.respond } }
}
