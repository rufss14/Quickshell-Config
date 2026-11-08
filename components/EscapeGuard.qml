import QtQuick

// ── EscapeGuard ───────────────────────────────────────────────────────────────
// What makes Escape close a panel docked in a shell window.
//
// `Keys` is an attached property that only works on an Item (a PanelWindow isn't one),
// and it only fires on the item that has ACTIVE FOCUS. So the catcher is an Item given
// focus when a panel opens — and any later moment the window is left with no focused
// item at all makes Escape reach nobody, with nothing in the log:
//   · a text field that lets go (`searchInput.focus = false` on a click elsewhere,
//     Escape that clears a search, a field committed and blurred);
//   · a focused item that hides or unloads (a picker that folds away, a view swapped
//     out) — Qt drops its focus and gives it to nothing.
// That was "sometimes, with the mouse on the panel, Escape doesn't close it".
//
// It is also the one place that sees the panel's KEYS: whatever Escape would not handle is passed on
// as `keyPressed`, and each dock gives it to the panel it has open — so a panel can have keyboard
// navigation without taking focus (which would cut it off from Escape).
//
// So this reclaims focus whenever it falls to nothing (the window's content item) while
// a panel is wanted. It never takes it from a real focus holder: a text field that has
// focus keeps it, and Escape still reaches the field first (it peels its own layer).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // A panel this guard serves is open: reclaim focus when it's lost.
    property bool wanted: false
    signal escaped()

    focus: true
    Keys.onEscapePressed: root.escaped()
    // Every other key, for the dock to hand to the open panel (`handleKey` on it). Only while no field
    // holds focus — a field keeps its own keys, so typing "t" in a box never means "today".
    signal keyPressed(var event)
    Keys.onPressed: (event) => root.keyPressed(event)

    function claim() { root.forceActiveFocus() }

    Connections {
        target: root.Window
        function onActiveFocusItemChanged() { if (root.wanted) Qt.callLater(root._reclaim) }
    }
    onWantedChanged: if (root.wanted) Qt.callLater(root._reclaim)

    function _reclaim() {
        if (!root.wanted) return
        const w = root.Window
        const a = w.activeFocusItem
        if (!a || a === w.contentItem) root.forceActiveFocus()
    }
}
