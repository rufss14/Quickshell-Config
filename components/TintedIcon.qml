import QtQuick
import Quickshell
import QtQuick.Effects
import "../config"

// ── TintedIcon ────────────────────────────────────────────────────────────────
// One SVG asset, colourised to a single flat colour.
//
// ── Mask, not colorize ────────────────────────────────────────────────────────
// `MultiEffect.colorization` is a MULTIPLY onto the source's own luminance, not a
// flat override — a genuinely near-white source (like this shell's other assets,
// baked `#e3e3e3`) multiplies out close enough to the target color to look right,
// but the effect never actually stops caring what shade the file was drawn in,
// and at partial coverage (a thin 1–2px stroke, antialiased) the blend leans back
// toward the source's own hue rather than the requested one — which is exactly
// what made these icons read as dim and off-color instead of the accent they were
// asked for.
//
// Masking sidesteps the question entirely: a solid `color` Rectangle, revealed
// only where the icon's own alpha is opaque. The icon becomes a pure STENCIL —
// its fill color never enters the output at all, so nothing about how it was
// drawn can leave a tint behind. Same technique VisualizerPill already uses to
// round the album art's corners (`maskSource` + `maskThresholdMin`), proven in
// this exact runtime.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property url source: ""
    property color color: Colors.of(QsWindow.window).fg
    property int size: Tokens.iconMd

    // Bound directly, not just implicitWidth/Height: a bare Item doesn't default
    // `width`/`height` to its implicit size the way Text or Image do, and every
    // call site here anchors the icon inside a Row rather than sizing it
    // explicitly — an unbound width would leave everything below filling a 0×0
    // parent and rendering nothing.
    width:  root.size
    height: root.size
    implicitWidth:  root.size
    implicitHeight: root.size

    Image {
        id: mask
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(root.size, root.size)
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: false
    }

    Rectangle {
        id: fill
        anchors.fill: parent
        color: root.color
        visible: false

        Behavior on color { ColorAnimation { duration: Motion.respond } }
    }

    MultiEffect {
        anchors.fill: parent
        source: fill
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
    }
}
