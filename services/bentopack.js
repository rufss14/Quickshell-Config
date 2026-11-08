.pragma library

// ── bentopack.js ──────────────────────────────────────────────────────────────
// Row packing for a bento grid: every row ends flush at the right edge.
//
// ── The problem ───────────────────────────────────────────────────────────────
// A GridLayout places items one after another and, when the next one does not fit in
// what is left of the row, WRAPS it — leaving the rest of that row empty. (Measured on
// Qt 6.11.2: spans [2,2,4,2] in 6 columns put the 4 on row two and left two columns of
// row one blank.) On a page of tiles that is the "empty space": a lone tile in the last
// row, a 1-column card that did not fit beside a 2-column one, three tiles in two
// columns. The Theme page looks right because it happens to tile exactly.
//
// ── The fix ───────────────────────────────────────────────────────────────────
// Work out the rows the grid WILL make (same rule: wrap when it doesn't fit), then
// hand each row's leftover columns to the items in it, evenly. Two tiles in a
// three-column page become 3|3 sub-columns instead of 2|2|gap.
//
// The grid runs on `sub` sub-columns (6: divisible by 1, 2 and 3 page columns), so an
// even split is exact for every row a 1–3 column page can form. Anything left over —
// only possible if a caller picks an odd `sub` — goes to the last items in the row.
//
// Pure: spans in, spans out, no QML. `bun scripts/test-bentopack.js`.
// ─────────────────────────────────────────────────────────────────────────────

// spans: base span of each child in sub-columns; 0 / undefined = not laid out (hidden).
// Returns an array of the same length with the effective span of each child.
function pack(spans, sub) {
    const out = [];
    for (let i = 0; i < spans.length; i++) out.push(0);

    let row = [];      // indices in the current row
    let used = 0;

    function flush() {
        if (row.length === 0) return;
        const left = sub - used;
        const each = Math.floor(left / row.length);
        let rest = left - each * row.length;
        for (let k = 0; k < row.length; k++) out[row[k]] += each;
        // Odd remainder: one extra column each to the LAST items, so a row never
        // ends short.
        for (let k = row.length - 1; k >= 0 && rest > 0; k--, rest--) out[row[k]] += 1;
        row = [];
        used = 0;
    }

    for (let i = 0; i < spans.length; i++) {
        if (!spans[i] || spans[i] < 1) continue;
        const s = Math.min(spans[i], sub);
        if (used + s > sub) flush();
        out[i] = s;
        row.push(i);
        used += s;
    }
    flush();
    return out;
}

// What a child asking for `span` page columns takes, in sub-columns, on a page of
// `cols` columns (1–3). A span wider than the page is the page.
function baseSpan(span, cols, sub) {
    const c = Math.max(1, cols);
    const s = Math.max(1, Math.min(span === undefined ? 1 : span, c));
    return Math.round(s * sub / c);
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { pack, baseSpan };
}
