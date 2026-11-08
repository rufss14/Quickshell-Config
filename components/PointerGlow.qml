import QtQuick
import QtQuick.Shapes
import Quickshell
import "../config"

// ── PointerGlow ───────────────────────────────────────────────────────────────
// A soft light under the pointer while it is over a card: the fill brightens
// around it, and the stretch of OUTLINE nearest it catches the light. Settings
// cards and tiles wear it; it is what makes a page of them feel like it answers the
// hand rather than sitting there.
//
// Reads the card's own HoverHandler (`hover`) instead of adding one, so it costs no
// handler of its own and can never take hover from anything. Draws nothing at all
// unless hovered (a fading-out light is still drawn until it reaches zero).
//
// One Shape, two paths with the same radial gradient: the fill, faint; and a 1px
// ring (the card's outline traced twice and filled odd-even) much stronger — the
// "edge facing the pointer". `radius` must be the card's corner radius so the ring
// lies exactly on its border.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property HoverHandler hover: null
    property color color: Colors.of(QsWindow.window).fg
    property real  radius: Tokens.radiusCard
    // How far the light reaches from the pointer, and how bright its centre is.
    property real  reach: 220
    property real  fillStrength: 0.07
    property real  edgeStrength: 0.55
    // The ring's width — the card's own border width.
    property real  edge: Tokens.borderWidth

    anchors.fill: parent

    // 0..1, eased, so the light fades in and out rather than switching.
    property real level: (root.hover && root.hover.hovered && root.enabled) ? 1 : 0
    Behavior on level { NumberAnimation { duration: Motion.standard; easing.type: Motion.respondCurve } }

    // Where the hover handler's parent sits in THIS item's coordinates, for a glow whose
    // handler lives on an ancestor (the bar group's, which must contain the buttons: a
    // handler on a lower sibling is not hovered while a button above it holds the pointer).
    property point origin: Qt.point(0, 0)

    readonly property real px: root.hover ? root.hover.point.position.x - root.origin.x : 0
    readonly property real py: root.hover ? root.hover.point.position.y - root.origin.y : 0

    visible: root.level > 0.001 && root.width > 0 && root.height > 0

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root.px; centerY: root.py
                focalX:  root.px; focalY:  root.py
                centerRadius: root.reach
                GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(root.color, root.fillStrength * root.level) }
                GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(root.color, 0) }
            }
            PathRectangle {
                x: 0; y: 0
                width: root.width; height: root.height
                radius: root.radius
            }
        }

        ShapePath {
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            fillGradient: RadialGradient {
                centerX: root.px; centerY: root.py
                focalX:  root.px; focalY:  root.py
                centerRadius: root.reach * 0.8
                GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(root.color, root.edgeStrength * root.level) }
                GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(root.color, 0) }
            }
            PathRectangle {
                x: 0; y: 0
                width: root.width; height: root.height
                radius: root.radius
            }
            PathRectangle {
                x: root.edge; y: root.edge
                width: root.width - root.edge * 2; height: root.height - root.edge * 2
                radius: Math.max(0, root.radius - root.edge)
            }
        }
    }
}
