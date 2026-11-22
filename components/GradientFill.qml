import QtQuick

// ── GradientFill ──────────────────────────────────────────────────────────────
// Three colours along a line at any angle, filling its parent's shape (clip it with the parent: a
// ClippingRectangle). Qt's Gradient only runs along an axis, so this is a horizontal one on a rectangle
// that is exactly as long as the surface's projection onto the line, turned: the same line the blob's
// shader uses (services/gradient.js axis), so a preview matches the bar. `colors` are the three stops as
// services/gradient.js colours() makes them.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var colors: ["#000000", "#000000", "#000000"]
    property real mid: 0.5
    property real angle: 0
    // Optional: the line itself, [x0, y0, dx, dy] in this item's coordinates (services/gradient.js axis), for a
    // piece of a bigger gradient: a tile shows the slice of the screen's gradient that lies under it, so it is
    // the colour of the bar beside it. Left null, the colours span this item.
    property var line: null

    readonly property real _a: root.angle * Math.PI / 180
    readonly property real _run: Math.abs(root.width * Math.cos(root._a)) + Math.abs(root.height * Math.sin(root._a))

    readonly property real _len: root.line ? Math.hypot(root.line[2], root.line[3]) : root._run
    Rectangle {
        width: root._len
        // Across the line it only has to cover the item, wherever the line passes.
        height: root.line ? (Math.hypot(root.width, root.height) + root._len) * 2 : Math.hypot(root.width, root.height)
        x: (root.line ? root.line[0] + root.line[2] / 2 : root.width / 2) - width / 2
        y: (root.line ? root.line[1] + root.line[3] / 2 : root.height / 2) - height / 2
        rotation: root.angle
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0;        color: root.colors[0] }
            GradientStop { position: root.mid; color: root.colors[1] }
            GradientStop { position: 1;        color: root.colors[2] }
        }
    }
}
