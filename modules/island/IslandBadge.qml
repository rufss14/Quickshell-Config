import QtQuick
import Quickshell
import "../../config"
import "../../components"

// ── IslandBadge ───────────────────────────────────────────────────────────────
// A Material 3 Expressive shape that holds one thing — a symbol, or a few characters — the way the clock panel's and
// the desktop tiles' badges do. The shape morphs on a spring when `shape` changes (the weather's badge turns from a
// cookie to a sunburst as the sky clears). `filled` puts it on the accent with the text on it; otherwise it is the
// accent container with its own ink.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string shape: "cookie9"
    property string symbol: ""
    // A Nerd Font character a service hands out (Bt.deviceGlyph) in place of a symbol's name.
    property string glyph: ""
    property string text: ""
    property bool   filled: false
    property real   size: Tokens.iconXl + Tokens.spacingMd
    // Fills the symbol (Material's FILL axis).
    property bool   solid: true
    property int    textPx: Tokens.fontLabel
    // Turns the symbol inside the shape (a direction).
    property real   iconRotation: 0

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property color ink: root.filled ? root.palette.fgOnPrimary : root.palette.fgOnPrimaryContainer

    implicitWidth: root.size
    implicitHeight: root.size

    MorphShape {
        anchors.fill: parent
        shape: root.shape
        spec: Motion.springSpatialFast
        fillColor: root.filled ? root.palette.primary : root.palette.primaryContainer
    }
    MaterialIcon {
        anchors.centerIn: parent
        visible: root.symbol !== "" || root.glyph !== ""
        name: root.symbol
        glyph: root.glyph
        fill: root.solid ? 1 : 0
        font.pixelSize: Math.round(root.size * 0.46)
        color: root.ink
        rotation: root.iconRotation
    }
    StyledText {
        anchors.centerIn: parent
        visible: root.text !== ""
        text: root.text
        font.pixelSize: root.textPx
        font.weight: Font.Bold
        font.features: ({ tnum: 1 })
        color: root.ink
    }
}
