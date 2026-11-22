import QtQuick
import "../../config"
import "../../components"

// ── IslandPiece ───────────────────────────────────────────────────────────────
// A group of things on an island page that is not a card (the media tab's title block, a row of chips) arriving on the
// same cascade as the cards: the shell's PopIn, `order` a beat after the one before. Draws nothing; its children are
// the content. `arrive` is the spring, 0..1.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property int order: 0
    readonly property real arrive: pop.arrive

    PopIn { id: pop; active: true; index: root.order }
    opacity: pop.opacity
    scale: pop.scale
}
