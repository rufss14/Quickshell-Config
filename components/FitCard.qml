import QtQuick
import Quickshell
import "../config"

// ── FitCard ───────────────────────────────────────────────────────────────────
// A card for an overlay that must always be wholly on screen, whatever size the panel under it is
// (the karaoke results and the "joined mid-song" warning). It lays its content out at its NATURAL
// size, then scales the whole card down to fit the room it has, centred — and follows the panel as
// that room changes, so it resizes with it instead of spilling past an edge or hiding its buttons
// below a scroll.
//
//   idealWidth   how wide it wants to be at full size
//   availW/availH  the room it has (its parent, less `margin` a side) — for a caller to drop
//                optional sections when the room is small, so a short panel gets a shorter card and
//                not just a smaller one
//   fit          the scale it settled on, never below `minFit` (past that the text is not worth
//                reading, and a caller should have dropped something long before)
//
// The children go in as ordinary content, in an Item `pad` in from the card's edge; put ONE
// ColumnLayout (or any item with a real implicit height, given `width: card.innerWidth`) in it — the
// card is as tall as what it holds.
//
// ── Why scale, rather than lay out smaller ────────────────────────────────────
// A card laid out at the room's size re-wraps and re-flows on every frame of a panel that is
// animating its height; one laid out at its own size and then scaled just gets smaller. The dock
// does exactly this to the whole panel for its zoom (BarDock.cardBody), for the same reason.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: card

    property real idealWidth: 580
    property real pad: Tokens.spacingLg
    property real margin: Tokens.spacingMd
    property real minFit: 0.45
    // Vertical nudge from centre: an entrance slides the card in with this.
    property real offsetY: 0

    readonly property real availW: card.parent ? Math.max(0, card.parent.width  - card.margin * 2) : card.idealWidth
    readonly property real availH: card.parent ? Math.max(0, card.parent.height - card.margin * 2) : 0
    readonly property real innerWidth: card.width - card.pad * 2
    readonly property real fit: card.height > 0 && card.availH > 0
        ? Math.max(card.minFit, Math.min(1, card.availH / card.height, card.availW / card.width)) : 1

    default property alias content: inner.data

    anchors.centerIn: card.parent
    anchors.verticalCenterOffset: card.offsetY
    width: card.idealWidth
    height: inner.childrenRect.height + card.pad * 2
    scale: card.fit
    transformOrigin: Item.Center

    radius: Tokens.radiusCard
    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surfaceContainer, 0.96)
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).outlineFor(Tokens.elevationNested)

    // Swallow clicks on the card, so they don't reach whatever is behind it.
    MouseArea { anchors.fill: parent }

    Item {
        id: inner
        x: card.pad
        y: card.pad
        width: card.innerWidth
        height: childrenRect.height
    }
}
