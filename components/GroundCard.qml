import QtQuick
import Quickshell
import "../config"

// ── GroundCard ────────────────────────────────────────────────────────────────
// The ground of one overview card (the workspaces, the drawer, a HUD card, the island): a FLAT
// tonal plate in the island pages' dialect (docs/island-style.md §1), with the plates, rows and
// the one loud card of its region laid ON it. No outline, no drop shadow, no cookie field of its
// own: the field runs over the dim between the cards.
//
// Translucency is in the FILL, not in `opacity`: the compositor blurs what is behind a
// translucent fill (hypr/rules.lua, `ignore_alpha`), and an item opacity would fade the card's
// contents with it. `popup` is a card that floats over another (a peek, a help card): a touch of the
// accent on the lifted tone, since a shadow is not how this language says "above".
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)

    property bool popup: false
    // The fill before translucency; a caller may tint it (the island takes the playing cover's colour).
    property color tone: root.popup ? root.palette.mix(root.palette.surfaceHigh, root.palette.primary, 0.14) : root.palette.surfaceFor(Tokens.elevationCard)
    // How much of the fill is there. Popups are denser: they sit over content.
    property real fillAlpha: root.popup ? Math.min(1, Tokens.surfaceOpacity * 1.08) : Tokens.surfaceOpacity

    radius: Tokens.radiusXl
    // A card on the wallpaper (the overview, the HUD) wears the shell's gradient like the bar does: the plate
    // is the fill, the card's own colour steps aside. A popup keeps its dense tone, it sits over content.
    readonly property bool gradientFill: !root.popup && plate.shown
    color: root.gradientFill ? "transparent" : root.palette.fade(root.tone, root.fillAlpha * Tokens.glass)
    Behavior on color { ColorAnimation { duration: Motion.respond } }
    GradientPlate {
        id: plate
        anchors.fill: parent
        visible: !root.popup
        radius: root.radius
        ground: root.tone
        fillOpacity: root.fillAlpha
    }
}
