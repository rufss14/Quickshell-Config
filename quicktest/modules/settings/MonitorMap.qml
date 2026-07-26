pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../components"
import "../../services"

// ── MonitorMap ────────────────────────────────────────────────────────────────
// Your displays, to scale, arranged the way Hyprland has them.
//
// This is not decoration and it isn't a chart either — it's a scale drawing. Hyprland
// puts every monitor at a real x/y in one shared coordinate space, so the arrangement
// is data we already have, and drawing it answers the one question the text rows can't:
// which screen is where. "HDMI-A-1 · 1680×1050" tells you nothing about the fact that
// it sits to the right of the other one and its top edges line up.
//
// ── One transform for everything ──────────────────────────────────────────────
// The bounding box of every monitor is measured in desktop pixels, then fitted into
// this item with a single scale factor and a single offset. Every rectangle goes
// through the same two, which is what makes it a scale drawing rather than a diagram:
// a screen twice as wide really is twice as wide here, and a screen 20px lower really
// is proportionally lower. Fitting each monitor independently would be a lie that
// looks like a drawing.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var monitors: Hypr.monitors

    // ── The desktop's bounding box, in Hyprland's coordinates ─────────────────
    // Monitors can sit at negative x/y (a screen placed left of or above the primary),
    // so the box is min→max rather than 0→max. Assuming an origin at 0,0 would push
    // those off the top-left of the drawing.
    readonly property var box: {
        if (root.monitors.length === 0) return { x: 0, y: 0, w: 1, h: 1 }
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
        for (const m of root.monitors) {
            x0 = Math.min(x0, m.x)
            y0 = Math.min(y0, m.y)
            x1 = Math.max(x1, m.x + m.width)
            y1 = Math.max(y1, m.y + m.height)
        }
        return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) }
    }

    readonly property int pad: Tokens.spacingMd

    // One factor, chosen so the whole box fits both ways. min() of the two, so the
    // limiting dimension decides and nothing is stretched.
    readonly property real scaleFactor: Math.min(
        (root.width  - root.pad * 2) / root.box.w,
        (root.height - root.pad * 2) / root.box.h)

    // Centred in whatever room is left over on the non-limiting axis.
    readonly property real offsetX: (root.width  - root.box.w * root.scaleFactor) / 2
    readonly property real offsetY: (root.height - root.box.h * root.scaleFactor) / 2

    Repeater {
        model: root.monitors

        Rectangle {
            id: screen
            required property var modelData

            readonly property bool focused: screen.modelData.focused === true

            x: root.offsetX + (screen.modelData.x - root.box.x) * root.scaleFactor
            y: root.offsetY + (screen.modelData.y - root.box.y) * root.scaleFactor
            // 2px of surface between neighbouring screens, rather than a heavy border
            // drawn around each to separate them. Two monitors that touch in Hyprland's
            // coordinates would otherwise render as one undivided slab.
            width:  screen.modelData.width  * root.scaleFactor - 2
            height: screen.modelData.height * root.scaleFactor - 2

            radius: Tokens.radiusSm

            // The focused screen is `focus` — "this is the one you're on". Every other
            // screen is present, not absent, so it gets a real surface rather than a
            // ghost outline.
            color: screen.focused
                ? Colors.alpha(Colors.focus, 0.16)
                : Colors.alpha(Colors.fg, 0.06)

            border.width: Tokens.borderWidth
            border.color: screen.focused ? Colors.alpha(Colors.focus, 0.55) : Colors.outline

            Behavior on color        { ColorAnimation { duration: Motion.respond } }
            Behavior on border.color { ColorAnimation { duration: Motion.respond } }

            Column {
                anchors.centerIn: parent
                spacing: 1

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text:  screen.modelData.name
                    color: screen.focused ? Colors.focus : Colors.fg
                    variant: "caption"
                    font.weight: Font.DemiBold
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    // Only when it fits. A label clipped by its own rectangle — or
                    // spilling out of it — is worse than no label: the resolution is in
                    // the rows below this, and this drawing's job is the arrangement.
                    visible: screen.height > 46 && screen.width > 84
                    text: screen.modelData.width + "×" + screen.modelData.height
                    variant:  "caption"
                    emphasis: "dim"
                }
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.monitors.length === 0
        text:    "No displays reported"
        variant: "caption"
        emphasis: "dim"
    }
}
