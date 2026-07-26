import QtQuick
import "../config"

// ── FrameGlaze ──────────────────────────────────────────────────────────────
// The glass treatment for the screen frame's strips. It looks like the pills'
// GlassOverlay in spirit — translucent, with a lit inner edge — but it is built the
// opposite way round, and that difference is the whole point.
//
// A pill's GlassOverlay grades and sheens over its HEIGHT, which is a few tens of px.
// A frame strip is a few tens of px THICK and up to a whole screen LONG. Reusing the
// pill overlay there put a sheen 34% of the strip's *length* down each side — a
// spotlight fading from the top corners to mid-screen, which read (correctly) as
// "messy". The fix is to grade across the strip's THICKNESS instead: a soft glow
// brightest at the INNER edge (the one facing the desktop) and gone by the outer edge.
// That is uniform along the length however long the strip is, and it reads as the
// bevel of a pane of glass — the same lit-edge cue the pills carry, sized to a ring.
//
// `inner` names the edge that faces the desktop content, per strip:
//   top band → "bottom",  bottom strip → "top",  left strip → "right",  right → "left".
Item {
    id: root

    property string inner: "top"
    property real   intensity: 1.0
    property color  lightColor: Colors.fg

    readonly property real a: 0.16 * intensity
    readonly property bool horiz: inner === "left" || inner === "right"
    // Whether the bright edge is at gradient position 0 (top for vertical, left for
    // horizontal) rather than position 1.
    readonly property bool brightAtStart: inner === "top" || inner === "left"

    Rectangle {
        anchors.fill: parent
        antialiasing: true
        gradient: Gradient {
            orientation: root.horiz ? Gradient.Horizontal : Gradient.Vertical
            // Concentrated on the inner half, gone by the middle — a bevel, not a wash.
            // Fades to the light colour at ZERO ALPHA, never "transparent": Qt lerps
            // straight RGBA, so #00000000 would drag the colour toward black.
            GradientStop { position: 0.0
                color: Colors.alpha(root.lightColor, root.brightAtStart ? root.a : 0.0) }
            GradientStop { position: 0.5; color: Colors.alpha(root.lightColor, 0.0) }
            GradientStop { position: 1.0
                color: Colors.alpha(root.lightColor, root.brightAtStart ? 0.0 : root.a) }
        }
    }
}
