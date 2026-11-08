import QtQuick
import "../state"

// ── HelpTip ───────────────────────────────────────────────────────────────────
// Puts a settings control's explanation in the card's tip when the pointer rests on
// the item this is declared in. A HoverHandler and nothing else: passive, so it
// steals no clicks and no hover from the control's own handlers, adds no geometry,
// and works inside a Layout (a handler is not a layout item).
//
// Why the explanation is a tip and not a line under the label: a page of controls
// that each carry a sentence reads as a wall of text, and most of those sentences
// are read once. The control keeps a short STATE line ("Every new wallpaper repaints
// the shell"); the sentence that says why it exists is here, one hover away.
// SettingsCard draws the tip (see UiState.showTip) after a short rest, so sweeping
// the pointer across a page doesn't flash a tip per card.
//
// `active` is for the owner's own hint that help exists — the small info mark beside
// a label — shown only while the pointer is on it.
// ─────────────────────────────────────────────────────────────────────────────
HoverHandler {
    id: root

    property string text: ""
    readonly property bool active: root.hovered && root.text !== ""

    enabled: root.text !== ""

    onHoveredChanged: {
        if (root.hovered) UiState.showTip(root, root.text)
        else UiState.hideTip(root)
    }
    // A label that changes under a resting pointer (a state line) re-reads.
    onTextChanged: if (root.hovered) UiState.showTip(root, root.text)

    // A page that unloads under a resting pointer must not leave the tip up.
    Component.onDestruction: UiState.hideTip(root)
}
