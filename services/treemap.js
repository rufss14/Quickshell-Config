.pragma library

// ── treemap.js ────────────────────────────────────────────────────────────────
// Squarified treemap (Bruls, Huizing, van Wijk): lays `values` out as rectangles whose
// areas are proportional to the values and whose aspect ratios stay near 1, so a tile is
// readable instead of a sliver. Pure arithmetic — `bun scripts/test-treemap.js`.
//
//   layout([40, 30, 20, 10], 400, 200)
//     → [{ index, x, y, w, h }, …]   one per value > 0, largest first; index points back
//                                     into the array given
// Values <= 0 get no tile. The tiles exactly cover width × height (before any gap).

function _worst(row, sum, side) {
    let mx = 0, mn = Infinity
    for (const a of row) { if (a > mx) mx = a; if (a < mn) mn = a }
    const s2 = side * side, t2 = sum * sum
    return Math.max(s2 * mx / t2, t2 / (s2 * mn))
}

function layout(values, width, height) {
    const items = []
    let total = 0
    for (let i = 0; i < values.length; i++) {
        const v = Number(values[i])
        if (v > 0) { items.push({ index: i, v: v }); total += v }
    }
    const out = []
    if (items.length === 0 || width <= 0 || height <= 0) return out
    items.sort((a, b) => b.v - a.v)

    const k = width * height / total
    const areas = items.map(it => it.v * k)
    let x = 0, y = 0, w = width, h = height
    let i = 0
    while (i < areas.length) {
        const side = Math.min(w, h)
        let row = [areas[i]], sum = areas[i], worst = _worst(row, sum, side)
        let j = i + 1
        while (j < areas.length) {
            const next = row.concat([areas[j]])
            const nw = _worst(next, sum + areas[j], side)
            if (nw > worst) break
            row = next; sum += areas[j]; worst = nw; j++
        }
        // The row is a strip along the shorter side: a column when the box is wide.
        if (w >= h) {
            const cw = sum / h
            let cy = y
            for (let n = 0; n < row.length; n++) {
                const rh = row[n] / cw
                out.push({ index: items[i + n].index, x: x, y: cy, w: cw, h: rh })
                cy += rh
            }
            x += cw; w -= cw
        } else {
            const rh = sum / w
            let cx = x
            for (let n = 0; n < row.length; n++) {
                const cw = row[n] / rh
                out.push({ index: items[i + n].index, x: cx, y: y, w: cw, h: rh })
                cx += cw
            }
            y += rh; h -= rh
        }
        i = j
    }
    return out
}
