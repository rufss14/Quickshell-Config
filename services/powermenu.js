.pragma library

// ── powermenu.js ──────────────────────────────────────────────────────────────
// What the power menu offers: which actions exist, in what order, which letter fires each,
// which ones ask twice and what they ask, and which only appear when the machine can do
// them. The one view is the welded edge column (modules/bar/PowerDock); the table is here,
// with a test, because a QML expression buried in a panel cannot be tested.
//
//     bun scripts/test-powermenu.js
//
// Deliberately colour-free: `tone` names a palette role ("warning" | "danger") and each
// view looks it up in ITS screen's palette. Capabilities (`needs`) are read from
// services/Session by the view, which passes them in as `caps`.
// ─────────────────────────────────────────────────────────────────────────────

// key, glyph, label, what it does, the letter that fires it, whether the first press only
// ARMS it (the second fires), what the armed one asks, how loud its warning is, whether it
// ends the session (so the interruptions it would cause are listed), and what the machine
// must be able to do for it to appear. Restarting is the recoverable one: the warning
// colour, not the danger.
var ACTIONS = [
    { key: "lock",      glyph: "\u{F033E}", label: "Lock",      hint: "Everything keeps running",
      letter: "L", confirm: false },
    { key: "logout",    glyph: "\u{F0343}", label: "Log out",   hint: "Close every app",
      letter: "E", confirm: true, ends: true, ask: "Log out?",   tone: "danger" },
    { key: "reboot",    glyph: "\u{F0709}", label: "Restart",   hint: "Back in a minute",
      letter: "R", confirm: true, ends: true, ask: "Restart?",   tone: "warning" },
    { key: "shutdown",  glyph: "\u{F0425}", label: "Shut down", hint: "Power off",
      letter: "P", confirm: true, ends: true, ask: "Shut down?", tone: "danger" }
]

// ── Four, on purpose ──────────────────────────────────────────────────────────
// It had seven: lock, suspend, hibernate, log out, restart, firmware, shut down. Too many to
// read at a glance for a menu whose whole point is one quick, deliberate choice. What is
// left is what is reached for: step away (lock), end the session, restart, power off. Suspend,
// hibernate and "restart into firmware" are still Session functions (and `Session.run` still
// knows their keys); they are only not in this table. To bring one back, add its row here —
// `needs` (see `available`) still gates one the machine can't do, with nothing else to change.

// Can this machine do `a`? `caps` is { hibernate: bool, firmware: bool }.
function available(a, caps) {
    return a.needs === undefined || (!!caps && caps[a.needs] === true)
}

// The action a typed character fires, or -1. Case-insensitive; one character only (a
// pasted word, or an empty string from a modifier key, is not a shortcut). `list` is the
// table to look in — ACTIONS unless a test (or a caller with a trimmed one) says otherwise.
function indexForLetter(text, caps, list) {
    var L = list || ACTIONS
    if (typeof text !== "string" || text.length !== 1) return -1
    var t = text.toUpperCase()
    for (var i = 0; i < L.length; i++)
        if (L[i].letter === t) return available(L[i], caps) ? i : -1
    return -1
}

// The next available action from `cursor` in direction `dir` (+1 / −1), wrapping round,
// skipping any the machine can't do. From "none" (−1) forward is the first, backward the
// last. −1 if nothing is available at all.
function step(cursor, dir, caps, list) {
    var L = list || ACTIONS
    var n = L.length
    var i = cursor < 0 ? (dir > 0 ? -1 : n) : cursor
    for (var k = 0; k < n; k++) {
        i = (i + dir + n) % n
        if (available(L[i], caps)) return i
    }
    return -1
}

// A button's height when `n` of them must fit in `room` pixels with `gap` between and
// `pad` round the stack: the design size, shrunk only as far as the screen forces.
function buttonSize(n, room, gap, pad, ideal) {
    if (n <= 0) return ideal
    var fit = Math.floor((room - pad * 2 - gap * (n - 1)) / n)
    return Math.max(1, Math.min(ideal, fit))
}
