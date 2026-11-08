.pragma library

// ── shapes.js ─────────────────────────────────────────────────────────────────
// Material 3 Expressive's shape set, as outlines that can MORPH into each other: the
// geometry behind `components/MorphShape`. `bun scripts/test-shapes.js`.
//
// ── Why polar, and why that makes every morph smooth ─────────────────────────
// Every shape here is a radius as a function of angle, sampled at the same SAMPLES angles.
// Two shapes are then two lists of the same length, point i of one standing at the same
// angle as point i of the other — so a morph is a plain per-sample mix of radii, with no
// matching of corners and no point appearing from nowhere. Any shape can go to any other,
// mid-flight too (from whatever is on screen), and a spring overshooting past 1 simply
// carries the outline a little beyond the target and back, which is the expressive squash.
//
// The cost of polar: only star-shaped outlines (every ray from the centre crosses the edge
// once). Every Material shape a tile wants — circle, cookies, sunny, burst, clover,
// squircle, soft polygons — is one; a pill or an arrow is not, and isn't here.
//
// Radii are normalised so the largest is 1: a shape fills its box at its widest, so
// switching shape never makes the thing jump in size by more than its own silhouette does.
// Angles: radians, 0 along +x, clockwise on screen (y down), as Scallop draws.
// ─────────────────────────────────────────────────────────────────────────────

var SAMPLES = 192

// The petal wave of a cookie, 0..1, peaking at the petal tips (θ = 0, 2π/n, …, so with
// n a multiple of 4 a tip sits at twelve o'clock). `p` > 1 narrows the tips and widens the
// valleys (a star); < 1 does the opposite (fat lobes, pinched joins: a clover).
function _wave(t, n, p) {
    var u = 0.5 + 0.5 * Math.cos(n * t)
    return p === 1 ? u : Math.pow(u, p)
}

// A regular polygon's radius at θ (flat sides), softened toward a circle by `round`.
function _poly(t, n, round) {
    var seg = 2 * Math.PI / n
    var a = ((t % seg) + seg) % seg - seg / 2
    var r = Math.cos(Math.PI / n) / Math.cos(a)
    return r * (1 - round) + round
}

// The radius function for a shape name. Unknown names are a circle, so a typo draws
// something round instead of nothing.
//   circle · cookieN (N 3–16 petals) · sunny · burst · clover · squircle · pentagon · hexagon
function _fn(name) {
    var m = /^cookie(\d+)$/.exec(name || "")
    if (m) {
        var n = Math.max(3, Math.min(16, parseInt(m[1], 10)))
        // Fewer petals cut deeper, as Material's cookies do (4 is a fat clover-ish cookie,
        // 12 is a gently scalloped disc).
        var d = n <= 4 ? 0.2 : n <= 7 ? 0.14 : n <= 9 ? 0.11 : 0.08
        return function (t) { return (1 - d) + d * _wave(t, n, 1) }
    }
    switch (name) {
    case "sunny":    return function (t) { return 0.8 + 0.2 * _wave(t, 8, 1.8) }
    case "burst":    return function (t) { return 0.72 + 0.28 * _wave(t, 12, 2.6) }
    case "clover":   return function (t) { return 0.62 + 0.38 * _wave(t, 4, 0.55) }
    case "squircle": return function (t) {
        var c = Math.abs(Math.cos(t)), s = Math.abs(Math.sin(t))
        return Math.pow(Math.pow(c, 4) + Math.pow(s, 4), -0.25)
    }
    case "pentagon": return function (t) { return _poly(t - Math.PI / 2, 5, 0.35) }
    case "hexagon":  return function (t) { return _poly(t, 6, 0.35) }
    default:         return function () { return 1 }
    }
}

// SAMPLES radii for a shape, normalised to a maximum of 1.
function radii(name) {
    var f = _fn(name)
    var out = new Array(SAMPLES), max = 0
    for (var i = 0; i < SAMPLES; i++) {
        out[i] = f(i / SAMPLES * 2 * Math.PI)
        if (out[i] > max) max = out[i]
    }
    for (var j = 0; j < SAMPLES; j++) out[j] /= max
    return out
}

// The outline `t` of the way from `a` to `b` (t past 1 overshoots, below 0 undershoots).
// Clamped at 0 so an extreme overshoot can't turn the outline inside out.
function mix(a, b, t) {
    var out = new Array(SAMPLES)
    for (var i = 0; i < SAMPLES; i++) out[i] = Math.max(0, a[i] + (b[i] - a[i]) * t)
    return out
}

// The outline as flat x,y pairs for a box `w`×`h`, inset by `inset` (half a stroke), closed
// (the first point repeated). The caller turns them into points; this stays plain JS so it
// can be tested outside Qt.
function outline(r, w, h, inset) {
    var cx = w / 2, cy = h / 2
    var R = Math.max(0, Math.min(w, h) / 2 - (inset || 0))
    var out = []
    for (var i = 0; i <= SAMPLES; i++) {
        var k = i % SAMPLES
        var t = k / SAMPLES * 2 * Math.PI
        out.push(cx + R * r[k] * Math.cos(t), cy + R * r[k] * Math.sin(t))
    }
    return out
}

// How far a morph should turn as it goes: one petal of the TARGET shape's own symmetry, so
// the new shape arrives looking settled rather than half a petal off. Degrees.
function turnFor(name) {
    var m = /^cookie(\d+)$/.exec(name || "")
    if (m) return 360 / Math.max(3, parseInt(m[1], 10))
    switch (name) {
    case "sunny":    return 45
    case "burst":    return 30
    case "clover":   return 90
    case "squircle": return 90
    case "pentagon": return 72
    case "hexagon":  return 60
    default:         return 45
    }
}
