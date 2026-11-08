.pragma library

// ── kelvin.js ─────────────────────────────────────────────────────────────────
// Colour temperature in kelvin → an sRGB hex string, for SHOWING what a warmth
// setting will look like before it is applied.
//
// ── What this is for, and what it is not ──────────────────────────────────────
// The night-light page's preview swatch. It is NOT how the screen is actually
// warmed: hyprsunset/gammastep set gamma ramps through wlr-gamma-control, and their
// exact curve is theirs. This is the well-known Tanner Helland approximation to a
// Planckian locus, which is close enough to answer "is 4000K too orange for me"
// without anyone having to apply it to find out.
//
// Tested (`bun scripts/test-kelvin.js`) because it is arithmetic with magic numbers
// in it: a transposed digit would still produce a plausible-looking colour, which is
// exactly the kind of wrong that never gets noticed.
// ─────────────────────────────────────────────────────────────────────────────

function _clamp(v) { return Math.max(0, Math.min(255, Math.round(v))) }

function _hex2(n) { const s = n.toString(16); return s.length < 2 ? "0" + s : s }

// 1000–40000K. Below 1000 the approximation diverges; above 40000 nothing changes.
function rgb(kelvin) {
    const t = Math.max(1000, Math.min(40000, Number(kelvin) || 6500)) / 100

    let r, g, b

    if (t <= 66) {
        r = 255
        g = 99.4708025861 * Math.log(t) - 161.1195681661
    } else {
        r = 329.698727446 * Math.pow(t - 60, -0.1332047592)
        g = 288.1221695283 * Math.pow(t - 60, -0.0755148492)
    }

    if (t >= 66)      b = 255
    else if (t <= 19) b = 0
    else              b = 138.5177312231 * Math.log(t - 10) - 305.0447927307

    return { r: _clamp(r), g: _clamp(g), b: _clamp(b) }
}

function hex(kelvin) {
    const c = rgb(kelvin)
    return "#" + _hex2(c.r) + _hex2(c.g) + _hex2(c.b)
}

// How warm this reads, in words. The page prints the number too — this is the half
// that means something without a frame of reference.
function describe(kelvin) {
    const k = Number(kelvin) || 6500
    if (k >= 6400) return "Neutral — no adjustment"
    if (k >= 5000) return "Barely warm"
    if (k >= 4000) return "Warm"
    if (k >= 3000) return "Very warm"
    return "Candlelight"
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { rgb, hex, describe }
}
