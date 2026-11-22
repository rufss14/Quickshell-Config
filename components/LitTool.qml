import QtQuick
import Quickshell
import "../config"

// ── LitTool ────────────────────────────────────────────────────────────────
// A round tool of the colour scheme page's cards (CardTool's lean, wash and bump), with a LIT state: while
// `lit` it stands on a disc of the accent with its glyph filled, the way the source rail's choice does. A
// `tip` is its tooltip (a HoverTip is parented to its control: keep it out of a clipping card).
// ─────────────────────────────────────────────────────────────────────────────
CardTool {
    id: root

    property bool lit: false
    property string tip: ""
    // The glyph's colour off the disc, and the colour it washes in under the pointer.
    property color ink: Colors.of(QsWindow.window).fg
    property color inkHot: root.ink
    readonly property var palette: Colors.of(QsWindow.window)

    filled: root.lit
    name: root.tip
    tint: root.lit ? root.palette.fgOnPrimary : root.ink
    hoverTint: root.lit ? root.palette.fgOnPrimary : root.inkHot

    Rectangle {
        z: -1
        anchors.fill: parent
        radius: width / 2
        color: root.palette.primary
        opacity: root.lit ? 1 : 0
        scale: root.lit ? 1 : 0.6
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        Behavior on scale   { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
    }

    HoverTip { text: root.tip; below: root.tipBelow }
    property bool tipBelow: false
}
