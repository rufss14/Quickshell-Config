import QtQuick
import Quickshell
import Quickshell.Widgets
import "../config"
import "../services/gradient.js" as Grad

// ── GradientPlate ─────────────────────────────────────────────────────────────
// The shell's gradient (Config.barGradient) as the fill of a rounded surface that is not part of the bar's
// blob: a desktop tile, a free popup. Drop it in as the surface's first child and set the surface's own fill
// to transparent while `shown`. It lays the gradient over `ground` (the colour the plain surface would be)
// exactly as the blob does over the bar's fill, across ITS OWN box at the shell's angle, so each tile wears
// the whole gradient. `fillOpacity` is the surface's translucency.
//
// `shown` is false while the gradient is off, so a caller can bind the surface's colour to it.
// ─────────────────────────────────────────────────────────────────────────────
ClippingRectangle {
    id: root

    property color ground: "black"
    property real fillOpacity: 1
    // [x0, y0, dx, dy] in this plate's coordinates: wear a slice of a bigger gradient (see GradientFill.line).
    property var line: null
    readonly property var palette: Colors.of(QsWindow.window)
    readonly property var doc: Grad.clean(Config.barGradient)
    readonly property bool shown: root.doc.on
    // A caller shows it with its own `visible`; the gradient being off hides it too.
    opacity: root.shown ? root.fillOpacity * Tokens.glass : 0

    color: "transparent"

    GradientFill {
        anchors.fill: parent
        visible: root.shown
        angle: root.doc.angle
        line: root.line
        mid: root.doc.mid
        colors: Grad.colours(root.doc, n => String(root.palette.role(n, root.palette.primary)), String(root.ground))
    }
}
