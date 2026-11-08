.pragma library

// ── fillslider.js ─────────────────────────────────────────────────────────────
// The outline of FillSlider's fill: a box that runs from `top` down to the bottom of a
// w × h track, small round corners on top, and a sine along the top edge that is
// strongest in the middle and dies to nothing at the corners (so it never meets them at a
// height). The bottom is square on purpose — FillSlider clips the fill to the track's own
// round end, which is the only way a fill shorter than the track's radius still follows it.
//
// Flat [x0, y0, x1, y1, …], clockwise from the bottom-left. Pure, so
// `bun scripts/test-fillslider.js` can hold it to account.

var CORNER_STEPS = 5
var WAVES = 2          // crests across the width

function outline(w, h, top, amp, phase, ri) {
    var r = Math.max(0, Math.min(ri, w / 2, Math.max(0, h - top)))
    var out = []
    function pt(x, y) { out.push(x, y) }

    pt(0, h + 1)
    pt(0, top + r)
    // Top-left inner corner: 180° → 270° (screen y runs down, so 270° is "up").
    for (var i = 1; i <= CORNER_STEPS; i++) {
        var a = Math.PI + (Math.PI / 2) * (i / CORNER_STEPS)
        pt(r + r * Math.cos(a), top + r + r * Math.sin(a))
    }
    // The wave, left to right, between the two corners.
    var span = Math.max(0, w - 2 * r)
    var n = amp > 0.01 ? Math.max(8, Math.round(span / 3)) : 1
    for (var j = 0; j <= n; j++) {
        var x = r + span * (j / n)
        var env = span > 0 ? Math.sin(Math.PI * (x - r) / span) : 0
        pt(x, top + amp * env * Math.sin(WAVES * 2 * Math.PI * x / w + phase))
    }
    // Top-right inner corner: 270° → 360°.
    for (var k = 1; k <= CORNER_STEPS; k++) {
        var b = 1.5 * Math.PI + (Math.PI / 2) * (k / CORNER_STEPS)
        pt(w - r + r * Math.cos(b), top + r + r * Math.sin(b))
    }
    pt(w, h + 1)
    return out
}

// Where the pieces of a w-wide, h-tall track sit for a level 0..1, from the bottom.
// [capH] is a stub of track kept at BOTH ends, so the handle never lands on the edge and
// a full (or empty) slider still shows the track's round end.
function layout(h, f, capH, gap, handleH) {
    var travel = Math.max(1, h - 2 * capH - handleH - 2 * gap)
    var fillH = capH + Math.max(0, Math.min(1, f)) * travel
    return {
        travel: travel,
        fillH: fillH,
        fillTop: h - fillH,
        handleTop: h - fillH - gap - handleH,
        restH: h - fillH - 2 * gap - handleH
    }
}

// The pointer's y (down from the track's top) → the level it means: the handle's CENTRE
// follows the pointer, so the handle sits under the finger instead of jumping to it.
function levelAt(y, h, capH, gap, handleH) {
    var travel = Math.max(1, h - 2 * capH - handleH - 2 * gap)
    var centreFromBottom = h - y
    var f = (centreFromBottom - capH - gap - handleH / 2) / travel
    return Math.max(0, Math.min(1, f))
}
