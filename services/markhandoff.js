.pragma library

// ── The active mark's hand-off ────────────────────────────────────────────────
// A button's active underline (IconButton) used to shrink away where it was and grow back
// somewhere else when the open panel changed hands. This remembers the mark that just left,
// per window (a screen's name), so the next one to switch on within a moment can fly in
// from there instead of growing from nothing.
//
// Shared state on purpose — `.pragma library` — because the two buttons never know about
// each other. Positions are the window's own coordinates (`mapToItem(null, …)`), which is
// why the key is the window and not "the shell": two monitors' bars are two windows.

var _last = {}

// A mark switched off: where its centre was, and how wide it was.
function leave(key, cx, cy, w) {
    _last[key] = { cx: cx, cy: cy, w: w, t: Date.now() }
}

// The mark that left `key`'s window within `withinMs`, once; null if none, or too long ago.
function take(key, withinMs) {
    const l = _last[key]
    if (!l) return null
    delete _last[key]
    return (Date.now() - l.t) <= withinMs ? l : null
}
