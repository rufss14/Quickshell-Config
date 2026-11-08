.pragma library

// ── workspaces.js ─────────────────────────────────────────────────────────────
// The two pieces of arithmetic behind the bar's workspace indicator.
//
// ── Why these are here and not inline in the widget ───────────────────────────
// Same reason services/calc.js and services/lyricsmotion.js are: `bun` can
// exercise these directly, and a QML expression buried in a bar widget cannot be.
// Both have edge cases that are invisible until they are wrong on screen — a run
// that starts at slot 0, a run of length 1, a fully-occupied page, and the page
// boundary itself — and "wrong on screen" for this widget means one silently
// misplaced pill that you notice a week later.
//
// `page()` in particular replaces a literal that was quietly two-pages-of-five:
// `wsStart = currentWs <= 5 ? 1 : 6`. That is correct for exactly five per page
// and silently wrong for any other number, while looking like general code.
// ─────────────────────────────────────────────────────────────────────────────

// ── runs ──────────────────────────────────────────────────────────────────────
// Collapses a row of occupied/empty slots into CONTIGUOUS RUNS, left to right:
//
//     [f, t, t, f, t]  ->  [{start: 1, length: 2}, {start: 4, length: 1}]
//
// This is what makes adjacent occupied workspaces merge into ONE pill instead of
// reading as separate dots — and, more importantly, why merging animates for
// free. Two runs becoming one is a MODEL change: the Repeater destroys one item
// and the survivor's width Behavior grows it across the gap. Five independent
// dots could never do that, because no single dot owns the gap between them.
//
// `start` is a 0-based SLOT index, not a workspace id. The widget multiplies it
// by the slot width; it never has to know which page it is on.
function runs(occupied) {
    const out = []
    if (!occupied) return out

    let i = 0
    while (i < occupied.length) {
        if (!occupied[i]) {
            i++
            continue
        }
        const start = i
        while (i < occupied.length && occupied[i]) i++
        out.push({ start: start, length: i - start })
    }
    return out
}

// ── page ──────────────────────────────────────────────────────────────────────
// Which page of workspaces contains `activeId`, and where in it that id sits.
//
//     page(3,  5) -> { start: 1, index: 2 }
//     page(6,  5) -> { start: 6, index: 0 }
//     page(10, 5) -> { start: 6, index: 4 }
//
// `start` is the workspace id of the leftmost slot; `index` is the 0-based slot
// the active workspace occupies. Guards against a zero or negative perPage
// because that is a division by zero that would produce NaN positions rather
// than an error — an indicator that silently vanishes.
function page(activeId, perPage) {
    const n  = Math.max(1, Math.floor(perPage || 1))
    const id = Math.max(1, Math.floor(activeId || 1))

    const start = Math.floor((id - 1) / n) * n + 1
    return { start: start, index: id - start }
}
