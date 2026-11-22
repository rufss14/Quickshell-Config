import QtQuick
import "../config"

// ── Dumbbell ──────────────────────────────────────────────────────────────────
// A dumbbell, drawn: a bar, two plates a side. The bundled icon font has no `fitness_center`, and
// re-cutting it (`scripts/material-symbols-map.py --emit`) rewrites both icon fonts for everyone, so the
// one icon the font lacks is drawn here instead. MaterialIcon shows it for the name "dumbbell", at the
// icon's size and in its colour, so a rail, a badge and a chip can all ask for it like any other symbol.
// `fill` fattens the plates (the FILL axis of the real icons: on and chosen are heavier).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real size: 24
    property color color: "white"
    property real fill: 0

    implicitWidth: root.size
    implicitHeight: root.size

    readonly property real u: root.size / 24
    readonly property real thick: (1 + 0.18 * Math.max(0, Math.min(1, root.fill)))

    // Outer plate, inner plate, bar, inner plate, outer plate.
    Repeater {
        model: [
            { x: 1.2, w: 2.6, h: 9 },
            { x: 4.4, w: 3.6, h: 14 },
            { x: 8.0, w: 8.0, h: 2.8 },
            { x: 16.0, w: 3.6, h: 14 },
            { x: 20.2, w: 2.6, h: 9 }
        ]
        delegate: Rectangle {
            required property var modelData
            x: modelData.x * root.u
            width: modelData.w * root.u
            height: modelData.h * root.u * (modelData.h > 5 ? root.thick : 1)
            y: (root.size - height) / 2
            radius: Math.min(width, height) * 0.32
            color: root.color
        }
    }
}
