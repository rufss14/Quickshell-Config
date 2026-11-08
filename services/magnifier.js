.pragma library

// ── magnifier.js ──────────────────────────────────────────────────────────────
// The screen magnifier (services/Magnifier): Hyprland's own cursor zoom
// (`cursor:zoom_factor`), stepped from the keys and eased by the shell.
//
//     bun scripts/test-magnifier.js
// ─────────────────────────────────────────────────────────────────────────────

// The stops a scroll notch moves between. Multiplicative, so each notch FEELS the same
// size; 8× is past where a pixel is still a picture of anything.
var LEVELS = [1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 6, 8]
var MIN = 1
var MAX = 8
var PREFIX = "qs-zoom:"

function clamp(z) {
    var n = Number(z)
    if (!isFinite(n)) return MIN
    return Math.max(MIN, Math.min(MAX, n))
}

// The next stop up (dir > 0) or down from `level` — from wherever it is, so an eased
// in-between value still steps to a real stop.
function step(level, dir) {
    var z = clamp(level)
    if (dir > 0) {
        for (var i = 0; i < LEVELS.length; i++) if (LEVELS[i] > z + 1e-6) return LEVELS[i]
        return MAX
    }
    for (var j = LEVELS.length - 1; j >= 0; j--) if (LEVELS[j] < z - 1e-6) return LEVELS[j]
    return MIN
}

// Toggle: zoomed → off; off → where you last were (2× the first time).
function toggle(level, last) {
    if (clamp(level) > MIN + 1e-6) return MIN
    var l = clamp(last)
    return l > MIN + 1e-6 ? l : 2
}

// `n` values from `from` to `to` (the last is `to`), even in log-space, so 1→2 and 4→8
// take the same visual time. n < 1 is one step.
function ramp(from, to, n) {
    var a = Math.log(clamp(from)), b = Math.log(clamp(to))
    var steps = Math.max(1, Math.round(n))
    var out = []
    for (var i = 1; i <= steps; i++) out.push(Math.round(Math.exp(a + (b - a) * i / steps) * 1000) / 1000)
    return out
}

// qs-zoom:in | out | toggle | reset → that word, or "" for anything else.
function parseEvent(data) {
    if (typeof data !== "string" || data.indexOf(PREFIX) !== 0) return ""
    var w = data.slice(PREFIX.length)
    return (w === "in" || w === "out" || w === "toggle" || w === "reset") ? w : ""
}

// What `hyprctl eval` runs. The number is clamped and printed by us — nothing typed by
// anyone reaches the compositor's Lua.
function lua(level) {
    return "hl.config({ cursor = { zoom_factor = " + clamp(level).toFixed(3) + " } })"
}

// "2.5×", "off" — the OSD's label.
function label(level) {
    var z = clamp(level)
    if (z <= MIN + 1e-6) return "Off"
    return (Math.round(z * 100) / 100) + "×"
}

// 0..1 along the stops, for the OSD's meter.
function fraction(level) {
    return (Math.log(clamp(level)) - Math.log(MIN)) / (Math.log(MAX) - Math.log(MIN))
}
