.pragma library

// ── quickpicks.js ─────────────────────────────────────────────────────────────
// The wallpapers the bar pill's quick card offers to try: `count` pictures from the library that are not
// the one on screen, chosen by `seed` (the card re-rolls by changing it). The same seed gives the same
// pictures, so the card does not reshuffle itself while the pointer rests on it. Pure so
// `bun scripts/test-quickpicks.js` can check it.
//   paths  every wallpaper's absolute path     current  the file NAME on screen ("" for none)
function _rng(seed) {
    let a = seed >>> 0
    return function () {
        a = (a + 0x6D2B79F5) >>> 0
        let t = a
        t = Math.imul(t ^ (t >>> 15), t | 1)
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
}

function sample(paths, current, count, seed) {
    const pool = paths.filter(p => p.split("/").pop() !== current)
    const rnd = _rng(seed)
    const n = Math.min(count, pool.length)
    for (let i = 0; i < n; i++) {
        const j = i + Math.floor(rnd() * (pool.length - i))
        const t = pool[i]; pool[i] = pool[j]; pool[j] = t
    }
    return pool.slice(0, n)
}
