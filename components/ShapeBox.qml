import QtQuick
import "../config"

// ── ShapeBox ──────────────────────────────────────────────────────────────────
// The holder behind an icon — a panel header's chip, a settings section's — in whichever
// shape Config.iconShape says. Passive, like Scallop: it draws a filled outline and nothing
// else; the caller puts the icon on it.
//
//   "default"  `fallback`: each place's own shape (a rounded square in a panel header, the
//              cookie in a settings section), so an untouched config looks as it always did
//   "squircle" a rounded square with a corner radius of 36% of the box
//   "cookie"   Scallop, 8 petals — the shell's signature
//   "clover"   Scallop, 4 deep petals (Material 3 Expressive's four-leaf)
//   "circle"
//
// "rounded" is only ever a `fallback` (the header's old chip), not a setting: it is the
// squircle's less committed cousin.
//
// ii's shapes come from a general rounded-polygon library; this is the handful of them the
// shell would actually put behind an icon, on the Scallop it already had (which is a
// GPU curve-renderer Shape — no Canvas).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string fallback: "cookie"
    property color  fillColor:   "transparent"
    property color  strokeColor: "transparent"
    property real   strokeWidth: Tokens.borderWidth
    // Extra petal depth while the holder is "hot" (the card is hovered); ignored by the
    // plain shapes, which the caller scales and turns instead.
    property real   extraPetal: 0

    readonly property string shape: Config.iconShape === "default" ? root.fallback : Config.iconShape
    readonly property bool petalled: root.shape === "cookie" || root.shape === "clover"

    Scallop {
        anchors.fill: parent
        visible: root.petalled
        points:     root.shape === "clover" ? 4 : 8
        petalDepth: (root.shape === "clover" ? 0.20 : 0.13) + root.extraPetal
        fillColor:   root.fillColor
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.petalled
        radius: root.shape === "circle"   ? Math.min(width, height) / 2
              : root.shape === "squircle" ? Math.min(width, height) * 0.36
              :                             Tokens.radiusSm + 2
        color: root.fillColor
        border.width: root.strokeColor.a > 0 ? root.strokeWidth : 0
        border.color: root.strokeColor
        antialiasing: true
    }
}
