.pragma library

// ── contrast.js ───────────────────────────────────────────────────────────────
// WCAG contrast maths for the palette's text roles. Pure functions, no QML, no state.
//
// Why it exists: the shell wears a palette extracted from whatever wallpaper is set, so the
// text roles (fgMuted, fgDim) are a fixed alpha of the palette's own text colour and their
// contrast depends on the wallpaper. Measured over the bundled schemes (scripts/check-contrast.py)
// the same alpha gave anywhere from 3.7:1 to 6.3:1 — and a wallpaper nobody tested can land
// lower. `alphaFor` finds the least alpha that reaches a target over a given ground, so
// PaletteRoles can keep its authored alpha where it already passes and lift it only where it
// doesn't. Compositing is in sRGB, which is how Qt blends a translucent colour.

function _lin(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }

// Relative luminance of {r, g, b} (0..1 each) — a QML `color` has these fields.
function luminance(c) {
    return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)
}

// Contrast ratio, 1..21, of two opaque colours, either way round.
function ratio(a, b) {
    const la = luminance(a), lb = luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}

// `fg` at `alpha` over the opaque `bg`, as the opaque colour the eye gets.
function over(fg, alpha, bg) {
    return {
        r: bg.r + (fg.r - bg.r) * alpha,
        g: bg.g + (fg.g - bg.g) * alpha,
        b: bg.b + (fg.b - bg.b) * alpha
    }
}

// The least alpha, not below `floor`, at which `fg` over `bg` reaches `target`:1. `floor` is
// returned as it is when it already does; 1 when even a solid `fg` can't (fg and bg alike).
// Contrast only ever rises with alpha toward a fg that contrasts with bg, so a bisection finds it.
function alphaFor(fg, bg, target, floor) {
    const lo0 = Math.max(0, Math.min(1, floor || 0))
    if (ratio(over(fg, lo0, bg), bg) >= target) return lo0
    if (ratio(over(fg, 1, bg), bg) < target) return 1
    let lo = lo0, hi = 1
    for (let i = 0; i < 16; i++) {
        const mid = (lo + hi) / 2
        if (ratio(over(fg, mid, bg), bg) >= target) hi = mid
        else lo = mid
    }
    return hi
}
