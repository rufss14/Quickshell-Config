import QtQuick
import Quickshell
import "../../../config"
import "../../../components"

// ── ClipsPlate ── a card of ClipsIsland: a flat plate on the island's ground that arrives on a spring. ────────
// `tone` is its fill (the section tone; a wash while recording or warning); `popIndex` its place in the
// cascade, -1 for none.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: plate
    property color tone: Colors.of(QsWindow.window).section
    property int popIndex: -1

    radius: Tokens.radiusCard
    color: plate.tone
    Behavior on color { ColorAnimation { duration: Motion.standard } }

    PopIn { id: pop; active: plate.popIndex >= 0; index: Math.max(0, plate.popIndex) }
    opacity: plate.popIndex >= 0 ? pop.opacity : 1
    scale: plate.popIndex >= 0 ? pop.scale : 1
}
