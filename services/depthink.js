.pragma library
.import "contrast.js" as C

// ── depthink.js ───────────────────────────────────────────────────────────────
// The depth clock's text colour, guaranteed to read on the picture behind it. Pure functions.
//
// A colour from the palette is a good start (the clock should wear the shell's own colours), but
// the palette says nothing about THIS picture: "the darker end" of a scheme can still be mid-grey
// over a mid-grey sky. So the palette's colour is only a preference — the one actually used is the
// first that reaches the contrast target over the picture's measured brightness, and when none
// does, the best of them is pushed toward black or white by as little as it takes.
//
//   pick([c1, c2], 0.9, 3.5)  → c1 if c1 reaches 3.5:1 over a ground of grey 0.9, else c2, else a
//                               pushed version, else (nothing can) plain black or white
//
// `luma` is the picture's brightness behind the clock on its stored values, 0..1 (what
// scripts/wallpaper-depth.py measures), treated as a grey ground: WCAG's contrast is computed on
// sRGB, which is what contrast.js does with it. Colours are {r, g, b} 0..1 — a QML `color` is one.
// ─────────────────────────────────────────────────────────────────────────────

var BLACK = { r: 0, g: 0, b: 0 }
var WHITE = { r: 1, g: 1, b: 1 }

function pick(candidates, luma, target) {
    const l = Math.max(0, Math.min(1, luma))
    const ground = { r: l, g: l, b: l }
    for (let i = 0; i < candidates.length; i++)
        if (C.ratio(candidates[i], ground) >= target) return candidates[i]

    // None reads. Start from the best of them, and head for whichever of black / white the ground is
    // farther from.
    let best = candidates.length ? candidates[0] : (l > 0.5 ? BLACK : WHITE)
    let bestRatio = 0
    for (let i = 0; i < candidates.length; i++) {
        const r = C.ratio(candidates[i], ground)
        if (r > bestRatio) { bestRatio = r; best = candidates[i] }
    }
    const end = l > 0.5 ? BLACK : WHITE
    if (C.ratio(end, ground) < target) return end          // the most that can be done
    let lo = 0, hi = 1
    for (let i = 0; i < 16; i++) {
        const mid = (lo + hi) / 2
        if (C.ratio(C.over(end, mid, best), ground) >= target) hi = mid
        else lo = mid
    }
    return C.over(end, hi, best)
}
