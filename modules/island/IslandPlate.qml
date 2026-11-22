import QtQuick
import Quickshell
import "../../config"
import "../../components"

// ── IslandPlate ───────────────────────────────────────────────────────────────
// A card on the island's pages, in the dialect the panels share (the clock panel, the media panel): a FLAT tonal
// fill with no outline — the section tone, or `hero` for the page's one loud card on the accent container — and a
// spring entrance, each card a beat after the one before it (the shell's PopIn: it rises from 90% size and
// overshoots). `clickable` makes it a button to another page (a state layer, `clicked()`). `order` is its place in that cascade; -1 opts out. `arrive` is 0..1 on the same spring, for a ring
// that sweeps in. `rim` lights the edge with the music (MusicRim, Config.barMusicReact).
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)

    property bool hero: false
    property color tone: root.hero ? root.palette.primaryContainer : root.palette.section
    // The text colour that reads on this fill.
    readonly property color ink: root.hero ? root.palette.fgOnPrimaryContainer : root.palette.fg
    readonly property color inkDim: root.hero ? root.palette.alpha(root.palette.fgOnPrimaryContainer, 0.72) : root.palette.fgMuted
    property int  order: -1
    property bool rim: false
    // A card that takes you somewhere: a state layer under the pointer, a hand cursor, and `clicked()`.
    property bool clickable: false
    signal clicked()
    readonly property real arrive: root.order >= 0 ? pop.arrive : 1

    radius: Tokens.radiusCard
    color: root.tone

    PopIn { id: pop; active: root.order >= 0; index: Math.max(0, root.order) }
    opacity: root.order >= 0 ? pop.opacity : 1
    scale: root.order >= 0 ? pop.scale : 1

    // Under the card's own content, so a button inside it still gets its press.
    MouseArea {
        id: press
        anchors.fill: parent
        enabled: root.clickable
        hoverEnabled: true
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
    StateLayer {
        anchors.fill: parent
        radius: root.radius
        hovered: root.clickable && press.containsMouse
        layerColor: root.ink
        reveal: true
        pointerX: press.mouseX
        pointerY: press.mouseY
    }

    MusicRim {
        anchors.fill: parent
        radius: root.radius
        visible: root.rim
    }
}
