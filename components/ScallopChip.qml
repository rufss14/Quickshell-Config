import QtQuick
import Quickshell
import "../config"

// ── ScallopChip ───────────────────────────────────────────────────────────────
// A glyph in a scalloped holder — the motif at card-heading size. Every Section
// wears one, so the shape repeats down a page and across the app without any single
// card having to be decorated.
//
// ── Why a holder at all ───────────────────────────────────────────────────────
// A bare glyph has no bounding box, so its optical size is whatever that particular
// Nerd Font character happens to be: 󰉼 and  are wildly different masses at the same
// pixel size, and a column of headings drawn that way has a ragged left edge with
// nothing for the eye to run down. The holder is a fixed box, so every heading starts
// at the same place and reads at the same weight.
//
// ── `hot` is driven by the CARD, not by this chip ─────────────────────────────
// The whole card is the hover target — pointing anywhere in it winds the chip. A
// HoverHandler in here would only fire over the 34px holder itself, which is the one
// part of a card nobody aims at.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string glyph: ""
    // A Material Symbols name instead of a glyph (MaterialIcon `name`); wins when set.
    property string symbol: ""
    property color  tint:  Colors.of(QsWindow.window).primary
    property bool   hot:   false
    property int    points: 8

    // The petals deepen as it winds, so the silhouette changes rather than just the
    // angle — that is what makes the gesture read as a mechanism turning.
    property real restPetal: 0.13

    implicitWidth:  34
    implicitHeight: 34

    // ONE 0→1 spring (M3E, SpringValue) winds it: the turn, the swell, the petals and the fill all
    // follow it, so they can't disagree, and the silhouette morphs instead of switching.
    SpringValue {
        id: wind
        target: root.hot ? 1 : 0
        spec: Motion.springSpatial
        epsilon: 0.002
    }
    rotation: -9 * wind.value
    scale:    1.0 + 0.08 * wind.value

    // The holder is the cookie unless Config.iconShape picks another (ShapeBox).
    ShapeBox {
        anchors.fill: parent
        fallback:   "cookie"
        extraPetal: 0.06 * wind.value + (root.restPetal - 0.13)
        fillColor:  Colors.of(QsWindow.window).alpha(root.tint, 0.16 + 0.10 * Math.max(0, Math.min(1, wind.value)))
    }

    MaterialIcon {
        anchors.centerIn: parent
        // Counter-rotates, so the glyph stays upright while its holder turns.
        rotation: -root.rotation
        glyph:  root.glyph
        name:   root.symbol
        color: root.tint
        font.pixelSize: Math.round(Math.min(root.width, root.height) * 0.46)
    }
}
