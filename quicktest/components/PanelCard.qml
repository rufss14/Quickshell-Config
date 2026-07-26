import QtQuick
import "../config"

// ── PanelCard ─────────────────────────────────────────────────────────────────
// A row inside a panel: a network, a display, a wallpaper, a saved scheme.
//
// It sits INSIDE a panel Card, so it's Nested elevation — an outline tuned for
// sitting on a wallpaper is invisible against the card's own fill, and the row
// would look like the card simply changed colour.
//
// `active` is for the one row that is currently the subject (the connected
// network, the display you're dragging). It takes the `focus` outline — "this is
// the one" — never a `primary` fill, which would say "press me".
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool  active: false
    property color accent: Colors.focus

    readonly property bool hovered: hover.hovered

    default property alias content: contentArea.data

    radius: Tokens.radiusPill

    color: root.active   ? Colors.alpha(root.accent, hover.hovered ? 0.20 : 0.13)
         : hover.hovered ? Colors.surfaceHigh
         : Colors.surfaceContainer

    border.width: Tokens.borderWidth
    border.color: root.active   ? Colors.alpha(root.accent, 0.45)
                : hover.hovered ? Colors.outlineFocus
                : Colors.outlineFor(Tokens.elevationNested)

    Behavior on color        { ColorAnimation { duration: Motion.respond } }
    Behavior on border.color { ColorAnimation { duration: Motion.respond } }

    HoverHandler { id: hover }

    Item {
        id: contentArea
        anchors.fill: parent
    }
}
