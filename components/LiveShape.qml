import QtQuick
import Quickshell
import "../config"
import "shapes.js" as Shapes

// ── LiveShape ─────────────────────────────────────────────────────────────────
// A sidebar cell's live state as a tonal Material 3 Expressive shape behind its glyph
// (2026-10-31, the user's pick: "shapes for live state"). Nothing live, nothing drawn: the
// edge stays a column of plain glyphs at rest. Something happening — Claude working, a timer
// running, a copy landing — grows a shape out of the glyph's centre, and a change of state
// morphs it (MorphShape) instead of swapping it. The desktop tiles' shape language
// (WidgetHeader), brought to the edge.
//
//   shape   "" = nothing live: it shrinks away, keeping its last outline as it goes
//   tone    its fill — primaryContainer for "going", alpha(warning or danger, 0.22) for
//           "look at me" (the armed cell's recipe; the palette has no warning container)
//   beat    a working state: one petal's turn (shapes.js turnFor) every `beatMs`, on the
//           spring — a tick, then still, never a constant redraw for the hour a session
//           works (Motion's idle budget). Off with animations.
//
// It only draws the shape. A glyph that sits INSIDE it multiplies its scale by `glyphScale`
// (Android's 2/3 — the launcher button's rule) and takes the owner's ink colour.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string shape: ""
    property color tone: Colors.of(QsWindow.window).primaryContainer
    property bool beat: false
    property int beatMs: Motion.pulse * 4

    readonly property bool live: root.shape !== ""
    // The glyph's size on the shape, against its size at rest.
    readonly property real inset: 0.68
    readonly property real glyphScale: 1 - (1 - root.inset) * Math.max(0, Math.min(1, grower.value))

    // The outline drawn: the live one, or the last one while it shrinks away.
    property string _held: root.live ? root.shape : "circle"
    onShapeChanged: if (root.live) root._held = root.shape

    SpringValue { id: grower; spec: Motion.springSpatial; target: root.live ? 1 : 0; epsilon: 0.001 }
    SpringValue { id: spin;   spec: Motion.springSpatial; epsilon: 0.05 }

    Timer {
        running: root.beat && root.live && Config.motionEnabled
        interval: root.beatMs
        repeat: true
        onTriggered: spin.target += Shapes.turnFor(root._held)
    }

    MorphShape {
        anchors.fill: parent
        shape: root._held
        fillColor: root.tone
        scale: Math.max(0, grower.value)
        rotation: spin.value
        visible: grower.value > 0.01
        Behavior on fillColor { ColorAnimation { duration: Motion.respond } }
    }
}
