.pragma library

// ── calmspot.js ───────────────────────────────────────────────────────────────
// Where on a wallpaper a desktop widget reads best: the quietest part of the picture, away from
// its detail (a face, a skyline, text), or — for the opposite taste — the busiest. The picture is
// cut into a grid; each cell's "energy" is how much its pixels change from their neighbours
// (the sum of the horizontal and vertical brightness steps); a block of cells the size of the
// widget is scored by its mean energy.
//
//     bun scripts/test-calmspot.js
//
// Pure: pixels in, numbers out. components/WallEnergy reads the picture and calls this.
// ─────────────────────────────────────────────────────────────────────────────

// Mean edge energy per cell. `px` is RGBA bytes (canvas getImageData().data), `w` × `h` pixels,
// cut into `cols` × `rows` cells. Row-major, length cols * rows. The first row and column of the
// picture have no neighbour above/left and count as 0 there.
function energy(px, w, h, cols, rows) {
    var g = new Array(w * h)
    for (var i = 0; i < g.length; i++) g[i] = 0.3 * px[i * 4] + 0.59 * px[i * 4 + 1] + 0.11 * px[i * 4 + 2]
    var sum = new Array(cols * rows), n = new Array(cols * rows)
    for (var c = 0; c < sum.length; c++) { sum[c] = 0; n[c] = 0 }
    for (var y = 0; y < h; y++) {
        var cy = Math.min(rows - 1, Math.floor(y * rows / h))
        for (var x = 0; x < w; x++) {
            var cell = cy * cols + Math.min(cols - 1, Math.floor(x * cols / w))
            n[cell]++
            if (x > 0 && y > 0)
                sum[cell] += Math.abs(g[y * w + x] - g[y * w + x - 1]) + Math.abs(g[y * w + x] - g[(y - 1) * w + x])
        }
    }
    var out = new Array(cols * rows)
    for (var k = 0; k < out.length; k++) out[k] = n[k] > 0 ? sum[k] / n[k] : 0
    return out
}

// The top-left cell {cx, cy, score} of the best `bw` × `bh` block: the lowest mean energy for "calm",
// the highest for "busy". `avoid` is a list of {cx, cy, w, h} blocks (other widgets) a candidate may
// not overlap; a tie goes to the block nearest the middle of the screen (the one least likely to
// hug an edge). null when nothing fits. A block bigger than the grid is clamped to it.
function best(grid, cols, rows, bw, bh, mode, avoid) {
    if (!grid || grid.length !== cols * rows) return null
    bw = Math.max(1, Math.min(cols, Math.round(bw)))
    bh = Math.max(1, Math.min(rows, Math.round(bh)))
    var busy = mode === "busy"
    var taken = avoid || []
    var pick = null
    for (var cy = 0; cy + bh <= rows; cy++) {
        for (var cx = 0; cx + bw <= cols; cx++) {
            var clash = false
            for (var t = 0; t < taken.length && !clash; t++)
                clash = cx < taken[t].cx + taken[t].w && taken[t].cx < cx + bw
                     && cy < taken[t].cy + taken[t].h && taken[t].cy < cy + bh
            if (clash) continue
            var s = 0
            for (var y = cy; y < cy + bh; y++)
                for (var x = cx; x < cx + bw; x++) s += grid[y * cols + x]
            s /= bw * bh
            var mid = Math.abs(cx + bw / 2 - cols / 2) + Math.abs(cy + bh / 2 - rows / 2)
            if (pick === null
                || (busy ? s > pick.score + 1e-9 : s < pick.score - 1e-9)
                || (Math.abs(s - pick.score) <= 1e-9 && mid < pick.mid))
                pick = { cx: cx, cy: cy, score: s, mid: mid }
        }
    }
    return pick === null ? null : { cx: pick.cx, cy: pick.cy, score: pick.score }
}

// The cell block a rectangle of `wpx` × `hpx` pixels covers on a `cols` × `rows` grid over a
// `screenW` × `screenH` screen, rounded UP (a half cell still counts) and at least one cell each way.
function cellsFor(wpx, hpx, screenW, screenH, cols, rows) {
    return { w: Math.max(1, Math.ceil(wpx / (screenW / cols))), h: Math.max(1, Math.ceil(hpx / (screenH / rows))) }
}

// A pixel rectangle ({x, y, w, h}) as the cell block it occupies, for `avoid`.
function blockOf(r, screenW, screenH, cols, rows) {
    var cw = screenW / cols, ch = screenH / rows
    var cx = Math.max(0, Math.floor(r.x / cw)), cy = Math.max(0, Math.floor(r.y / ch))
    var ex = Math.min(cols, Math.ceil((r.x + r.w) / cw)), ey = Math.min(rows, Math.ceil((r.y + r.h) / ch))
    return { cx: cx, cy: cy, w: Math.max(0, ex - cx), h: Math.max(0, ey - cy) }
}
