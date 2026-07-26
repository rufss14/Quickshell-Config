import QtQuick
import "../config"

// ── Accordion ─────────────────────────────────────────────────────────────────
// Sequences the swap between mutually-exclusive panels that share one container
// window.
//
// The problem it solves: the panel toggles flip their booleans in a single tick
// (old one false, new one true). Bound naively, that crossfades two cards *while
// the container resizes underneath them* — the old card is shrinking toward the
// new card's height at the same moment the new one is growing into it. That's
// the jitter.
//
// So "what the user asked for" (requestedKey) and "what the container is
// currently showing and sized for" (activeKey) are tracked separately, and a
// change to the former runs exactly three steps, in order, never overlapping:
//
//   1. fade the active card out
//   2. swap activeKey — the container now resizes to the new module's size
//   3. fade the new card in
//
// Steps with nothing to do collapse to zero duration (opening from closed has
// nothing to fade out first), so only a genuine sibling-to-sibling switch pays
// for all three.
//
// OverlayRoot had two hand-written copies of this, one for the left group and
// one for the right.
//
// Usage:
//     Accordion {
//         id: left
//         requestedKey: UiState.leftPanel      // "" when nothing is open
//     }
//     // then size the window to left.activeKey, and show the card whose key
//     // matches left.activeKey when left.contentVisible is true.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    // What the user wants open. "" means "nothing".
    property string requestedKey: ""

    // What the container is actually showing and sized for. Lags requestedKey
    // by the fade-out; this is the one to size the window from.
    property string activeKey: ""

    // Whether the active card should be faded in. False during the swap, so a
    // card never fades in before the container has finished resizing to it.
    property bool contentVisible: false

    readonly property bool anyOpen: requestedKey !== ""

    property var _seq: SequentialAnimation {
        ScriptAction   { script: root.contentVisible = false }
        // Nothing to fade out if nothing was open.
        PauseAnimation { duration: root.activeKey === "" ? 0 : Motion.exit }
        ScriptAction   { script: root.activeKey = root.requestedKey }
        // Nothing to fade in if the request was "close".
        PauseAnimation { duration: root.activeKey === "" ? 0 : Motion.emphasized }
        ScriptAction   { script: root.contentVisible = root.activeKey !== "" }
    }

    onRequestedKeyChanged: { _seq.stop(); _seq.start() }
}
