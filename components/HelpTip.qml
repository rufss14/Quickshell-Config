import QtQuick
import "../state"

// ── HelpTip ───────────────────────────────────────────────────────────────────
// Puts a control's explanation in its surface's tip (components/TipBubble: the settings card's, the
// bar window's) when the pointer rests on the item this is declared in. A HoverHandler and nothing else: passive, so it
// steals no clicks and no hover from the control's own handlers, adds no geometry,
// and works inside a Layout (a handler is not a layout item).
//
// Why the explanation is a tip and not a line under the label: a page of controls
// that each carry a sentence reads as a wall of text, and most of those sentences
// are read once. The control keeps a short STATE line ("Every new wallpaper repaints
// the shell"); the sentence that says why it exists is here, one hover away.
// TipBubble draws the tip (see UiState.showTip) after a short rest, so sweeping
// the pointer across a page doesn't flash a tip per card.
//
// `active` is for the owner's own hint that help exists — the small info mark beside
// a label — shown only while the pointer is on it.
// ─────────────────────────────────────────────────────────────────────────────
HoverHandler {
    id: root

    property string text: ""
    // A tip whose words cost something to work out (a bar pill's "what is it doing", read from its
    // service): a function asked when the pointer arrives, in place of a `text` binding that would be
    // evaluated for every pill from the moment it exists.
    property var provide: null
    // A bar pill's tip: the bar's blob draws it (modules/bar/PillTip) when it is welded, and TipBubble
    // stands down for it.
    property bool pill: false
    readonly property bool active: root.hovered && (root.text !== "" || root.provide !== null)

    enabled: root.text !== "" || root.provide !== null

    function _say() {
        const t = root.provide ? root.provide() : root.text
        if (t) UiState.showTip(root, t)
        else UiState.hideTip(root)
    }
    onHoveredChanged: {
        if (root.hovered) root._say()
        else UiState.hideTip(root)
    }
    // A label that changes under a resting pointer (a state line) re-reads.
    onTextChanged: if (root.hovered) root._say()

    // A page that unloads under a resting pointer must not leave the tip up.
    Component.onDestruction: UiState.hideTip(root)
}
