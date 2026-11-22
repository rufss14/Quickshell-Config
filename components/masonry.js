.pragma library

// ── masonry.js ────────────────────────────────────────────────────────────────
// Column packing for a grouped settings page (SettingsPage, grouped mode): groups of
// different heights flow into columns so the columns end level, the way the island
// dashboard's plates fill their box, instead of a row grid that leaves a hole under
// every short card.
//
// Pure functions, no QML: scripts/test-masonry.js runs them under bun.
//
// ── The rule ──────────────────────────────────────────────────────────────────
// Items are placed IN ORDER, each into the column that is currently shortest; a tie
// goes to the leftmost column. Order is kept so related groups that a page declares
// one after another stay near each other (the second lands beside or under the first),
// and the reading order of a column is still the page's source order.
//
// A height of 0 or less is a hidden item: it gets no place and no gap.
//
// Columns within `tieEps` px of each other count as level. A group that grows by a
// fraction of a pixel (a wrapped line settling) must not send every later group to the
// other column: that would read as the page reshuffling itself.
// ─────────────────────────────────────────────────────────────────────────────

var tieEps = 0.5

// heights: [number], columns: int (< 1 is one), gap: px between stacked items,
// full: optional [bool] aligned with heights — a true item takes the WHOLE row: it starts
// under the tallest column (a gap below it), and every column continues under it. That is
// for a wide card (a picker, a list) above, between or below the balanced columns.
// Returns { places: [{ col, y, span }], total } — `places` is aligned with `heights`
// (span is 1, or `columns` for a full-row item; a hidden item is { col: -1, y: 0, span: 0 });
// `total` is the tallest column's height.
function pack(heights, columns, gap, full) {
    var n = Math.max(1, Math.floor(columns || 1))
    var g = gap > 0 ? gap : 0
    var bottom = []
    var used = []
    for (var c = 0; c < n; c++) { bottom.push(0); used.push(false) }

    var places = []
    var hs = heights || []
    for (var i = 0; i < hs.length; i++) {
        var h = +hs[i]
        if (!(h > 0)) { places.push({ col: -1, y: 0, span: 0 }); continue }
        if (full && full[i]) {
            var top = 0, any = false
            for (var t = 0; t < n; t++) { top = Math.max(top, bottom[t]); any = any || used[t] }
            var fy = any ? top + g : 0
            places.push({ col: 0, y: fy, span: n })
            for (var u = 0; u < n; u++) { bottom[u] = fy + h; used[u] = true }
            continue
        }
        var best = 0
        for (var k = 1; k < n; k++)
            if (bottom[k] < bottom[best] - tieEps) best = k
        var y = used[best] ? bottom[best] + g : 0
        places.push({ col: best, y: y, span: 1 })
        bottom[best] = y + h
        used[best] = true
    }

    var total = 0
    for (var j = 0; j < n; j++) total = Math.max(total, bottom[j])
    return { places: places, total: total }
}

// How many columns of at least `minCol` fit in `width` with `gap` between them,
// at least one and at most `maxCols` (0 or absent = no cap).
function columnsFor(width, minCol, gap, maxCols) {
    var g = gap > 0 ? gap : 0
    var m = minCol > 0 ? minCol : 1
    var n = width > 0 ? Math.floor((width + g) / (m + g)) : 1
    n = Math.max(1, n)
    if (maxCols > 0) n = Math.min(n, Math.floor(maxCols))
    return n
}

// One column's width when `columns` share `width` with `gap` between them.
function columnWidth(width, columns, gap) {
    var n = Math.max(1, Math.floor(columns || 1))
    return Math.max(0, (width - (gap > 0 ? gap : 0) * (n - 1)) / n)
}
