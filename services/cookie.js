.pragma library

// ── cookie.js ─────────────────────────────────────────────────────────────────
// The geometry of the media cover (components/CookieCover): a "cookie" — Scallop's
// silhouette, a circle whose radius breathes N times round the turn — turning slowly
// while a track plays, with a ring of level bars standing off its edge.
//
//     bun scripts/test-cookie.js
//
// ── Why the ring needs this ───────────────────────────────────────────────────
// The bars do not stand on a fixed circle: each starts a gap OUTSIDE the cookie's edge AT
// ITS OWN ANGLE, and the cookie turns underneath them, so the ring breathes as the petals
// pass. That needs the silhouette's radius at an arbitrary angle — the same formula
// Scallop draws with (`r = (rMax − amp) + amp·(½ + ½·cos(N·a))`) — and a place where it
// can be checked, because a ring that disagrees with the shape it surrounds reads as bars
// floating off it at some angles and inside it at others.
//
// Angles are RADIANS, measured the way QML draws: 0 along +x, increasing clockwise on
// screen (y down).
// ─────────────────────────────────────────────────────────────────────────────

// Scallop's radius at shape-local angle `a`. `depth` is the petal depth as a fraction of
// rMax (0 = a circle); `points` is the petal count.
function radiusAt(a, rMax, depth, points) {
    var amp = rMax * depth
    return (rMax - amp) + amp * (0.5 + 0.5 * Math.cos(Math.max(3, points) * a))
}

// Where the cookie's edge is at SCREEN angle `theta`, when the cookie has turned by
// `phase`: the shape-local angle there is theta − phase.
function edgeDist(theta, phase, rMax, depth, points) {
    return radiusAt(theta - phase, rMax, depth, points)
}

// Screen angle of bar `i` of `n`, starting at 12 o'clock and going round clockwise.
function barAngle(i, n) {
    return i * 2 * Math.PI / n - Math.PI / 2
}

// One bar's length from a spectrum value in 0..1: never shorter than `thick` (so silence
// is a ring of dots, not a gap), never longer than `max`. A missing or non-finite value
// is silence — an empty spectrum (nothing playing, cava not up yet) must not draw NaN.
function barLength(v, thick, max) {
    var x = typeof v === "number" && isFinite(v) ? Math.max(0, Math.min(1, v)) : 0
    return Math.max(thick, x * max)
}
