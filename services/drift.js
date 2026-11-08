.pragma library

// ── drift.js ──────────────────────────────────────────────────────────────────
// The cookie field behind every panel (services/Drift, components/DriftShapes): a set of
// soft shapes drifting across ONE shared, repeating plane, which each panel looks at
// through its own window.
//
//     bun scripts/test-drift.js
//
// ── Why one field, in screen coordinates ──────────────────────────────────────
// Each panel used to carry shapes of its own, so two panels side by side were two
// unrelated fields, and a panel opening or swapping restarted its own from scratch. Now
// the shapes live in one plane keyed to the SCREEN, and a panel only decides where its
// window onto that plane is: a shape drifting out of one panel's edge is the one
// entering the next, and a panel growing out of the bar reveals the field rather than
// bringing a new one.
//
// ── Repeating, so it can be small ─────────────────────────────────────────────
// A plane the size of a screen would need a hundred shapes for a panel to hold a handful.
// The plane repeats every (W × H) instead: each shape has an image in every tile, and a
// panel draws the one image that lands in its window. The jump from one image to the
// next happens W (or H) away from the window's origin — outside the panel, as long as
// the panel plus a shape is narrower than W. The tile is sized for the widest panel at
// its default zoom; a wider one shows one faint pop at its far edge, which is the
// cheapest failure there is.
//
// Depth is what makes it more than wallpaper: a shape's size, opacity and wander all follow
// one number, so the small ones are faint and settled and the big ones nearer and livelier.
// Its SPEED does not — see DRIFT: shapes that move at different speeds catch each other and
// pile up, which is what an earlier version did.
// ─────────────────────────────────────────────────────────────────────────────

// petals × depth. Depth 0 is a circle; past ~0.25 a Scallop reads as a gear.
var FORMS = [
    { p: 8, d: 0.00 }, { p: 4, d: 0.20 }, { p: 6, d: 0.14 }, { p: 7, d: 0.12 },
    { p: 9, d: 0.10 }, { p: 12, d: 0.07 }, { p: 5, d: 0.22 }, { p: 8, d: 0.24 },
    { p: 9, d: 0.12 }, { p: 6, d: 0.20 }
]
var TONES = 4

var SIZE_MIN = 28, SIZE_MAX = 112
// ONE drift velocity for the whole field, the same for every shape. It used to follow depth, 3 to 14 px/s,
// for a parallax — and that is what piled them up: the fast ones caught the slow ones
// travelling the same way, and the field jammed into clumps no amount of pushing apart
// dissolved (measured: nine shapes in one 130px circle after ten minutes). Shapes that
// all move together never catch each other, so an even spread STAYS even.
var DRIFT = 6
// What depth buys instead: a slow wander round the drift, bigger and faster for the near
// ones (px, rad/s). It is an oscillation, so it is bounded — it cannot accumulate into a
// pile the way a speed difference does.
var WANDER_MIN = 10, WANDER_MAX = 26
var ALPHA_MIN = 0.07, ALPHA_MAX = 0.16
var TURN_MAX = 10          // degrees per second, either way

function lerp(a, b, t) { return a + (b - a) * t }

// A small seedable generator, so the tests (and a screenshot) see the same field twice.
function mulberry32(seed) {
    var a = seed >>> 0
    return function () {
        a = (a + 0x6D2B79F5) >>> 0
        var t = a
        t = Math.imul(t ^ (t >>> 15), t | 1)
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
}

// `count` shapes spread over a W × H tile. `rand` is anything returning [0, 1).
//
// ── Spread out, and kept that way ─────────────────────────────────────────────
// Random positions and random headings clump: by chance at the start, and again whenever
// two paths cross. So: each shape starts in a cell of its own (a jittered grid over the
// tile, the cells dealt out at random — even coverage with none of the regularity of a
// grid), the headings share a current with some spread rather than pointing anywhere, and
// `step` pushes any overlapping pair apart (SEP below).
function make(count, W, H, rand) {
    var cols = Math.max(1, Math.ceil(Math.sqrt(count * W / H)))
    var rows = Math.max(1, Math.ceil(count / cols))
    var cells = []
    for (var c = 0; c < cols * rows; c++) cells.push(c)
    // Deal the cells out in a random order (Fisher–Yates), so size is not tied to place.
    for (var k = cells.length - 1; k > 0; k--) {
        var r = Math.floor(rand() * (k + 1))
        var t = cells[k]; cells[k] = cells[r]; cells[r] = t
    }
    var cw = W / cols, ch = H / rows
    var current = rand() * Math.PI * 2          // the way the whole field drifts

    var out = []
    for (var i = 0; i < count; i++) {
        // Even steps through depth (so every size is represented), not random: a random
        // draw can leave a field of near-identical blobs.
        var depth = count > 1 ? i / (count - 1) : 0.5
        var dir = rand() < 0.5 ? -1 : 1
        var form = FORMS[Math.floor(rand() * FORMS.length)]
        // Exactly the field's velocity — no spread. ±10% looked harmless and still shuffled an
        // even arrangement into a random one in a few minutes, and a random arrangement has the
        // odd tight group by chance alone (measured: 6 in a 130px circle, from a start of 3).
        var ang = current
        var speed = DRIFT
        var cell = cells[i % cells.length]
        out.push({
            x: ((cell % cols) + 0.5 + (rand() - 0.5) * 0.4) * cw,
            y: (Math.floor(cell / cols) + 0.5 + (rand() - 0.5) * 0.4) * ch,
            r: rand() * 360,
            vx: Math.cos(ang) * speed,
            vy: Math.sin(ang) * speed,
            vr: dir * lerp(2, TURN_MAX, rand()),
            depth: depth,
            size: lerp(SIZE_MIN, SIZE_MAX, depth),
            alpha: lerp(ALPHA_MIN, ALPHA_MAX, depth),
            points: form.p,
            petal: form.d,
            tone: Math.floor(rand() * TONES),
            phase: rand() * Math.PI * 2,
            lit: {},
            wp: rand() * Math.PI * 2,
            ww: lerp(0.12, 0.35, rand()),
            wa: lerp(WANDER_MIN, WANDER_MAX, depth),
            // Every third one gets a faint outline, so not all of them are flat fills.
            outlined: i % 3 === 0
        })
    }
    return out
}

function mod(v, m) { return ((v % m) + m) % m }

// A copy of a shape's lit pictures ({ key: [{x, y}] }), so a step never changes the field it was given.
function copyLit(lit) {
    var out = {}
    for (var key in lit) out[key] = lit[key].map(function (i) { return { x: i.x, y: i.y } })
    return out
}

// The shortest signed distance from a to b on a circle of length m — so two shapes either
// side of the tile's seam count as the neighbours they are.
function wrapDelta(a, b, m) {
    var d = mod(b - a, m)
    return d > m / 2 ? d - m : d
}

// How much room each pair keeps between their centres: their summed radii times SEP, plus
// a flat GAP. Not merely "don't overlap" — measured, that left the PAIRS fine and the GROUPS
// not: with only no-overlap, nine small shapes ended up inside one 130px circle after a few
// minutes, touching but not overlapping, which reads as a pile. The margin is what keeps
// the space between them open. SEP_RATE is how fast they are eased apart when closer than
// that — a rate, so it is gentle and independent of the frame time.
var SEP = 1.25
var GAP = 20
// …and never closer than this whatever their size: by radii alone two small shapes only
// want ~55px between them, so half a dozen could still pack into one spot (measured: 6–7 in
// a 130px circle). A flat floor on the spacing is what spreads the field out evenly.
var SPACE = 120
var SEP_RATE = 3.0

// The centre-to-centre distance a pair of shapes of these radii wants.
function wantDist(ra, rb) { return Math.max(SPACE, (ra + rb) * SEP + GAP) }

// One frame forward. Positions stay in [0, W) × [0, H); a hiccup (a stalled frame, a
// panel that was closed for a minute) is clamped so the field never lurches.
function step(field, dt, W, H, panels, bounds) {
    var d = Math.max(0, Math.min(dt, 0.1))
    var n = field.length
    var out = new Array(n)
    for (var i = 0; i < n; i++) {
        var s = field[i]
        // The wander is a sinusoidal offset: its velocity is the derivative, added to the drift
        // each frame, so the integral is bounded by `wa` and never walks off.
        var wvx = s.wa * s.ww * Math.cos(s.wp)
        var wvy = s.wa * s.ww * Math.cos(s.wp * 1.3 + 1.7)
        out[i] = {
            x: mod(s.x + (s.vx + wvx) * d, W),
            y: mod(s.y + (s.vy + wvy) * d, H),
            r: mod(s.r + s.vr * d, 360),
            vx: s.vx, vy: s.vy, vr: s.vr,
            depth: s.depth, size: s.size, alpha: s.alpha,
            points: s.points, petal: s.petal, tone: s.tone,
            phase: s.phase, outlined: s.outlined,
            lit: copyLit(s.lit),
            wp: s.wp + s.ww * d, ww: s.ww, wa: s.wa
        }
    }
    separate(out, d, W, H)

    // A shape that has been in a panel carries the screen position of THAT picture; it moves with the
    // shape — by exactly how far the shape just moved, drift, wander and separation alike. AFTER the
    // separation, or its push is never carried: measured, a recorded picture then wandered up to 54px
    // off the shape it belongs to in two minutes, so the bar drew a cookie where the panel did not — one
    // shape in two places, cut at the join — and every panel it crossed recorded it again (16 extra
    // pictures in that run).
    for (var q = 0; q < n; q++) {
        var ddx = wrapDelta(field[q].x, out[q].x, W), ddy = wrapDelta(field[q].y, out[q].y, H)
        for (var key in out[q].lit) {
            var imgs = out[q].lit[key]
            for (var m = 0; m < imgs.length; m++) { imgs[m].x += ddx; imgs[m].y += ddy }
        }
    }
    wake(out, W, H, panels, bounds)
    return out
}

// In place, on a step's fresh output.
function separate(out, d, W, H) {
    var n = out.length
    // Separation: any pair closer than wantDist() is eased apart along the line
    // between them, the smaller one moving further (it has less to lose). On the tile, so it
    // holds across the seam. dt = 0 moves nothing.
    var k = Math.min(1, SEP_RATE * d)
    if (k > 0) {
        for (var a = 0; a < n; a++) {
            for (var b = a + 1; b < n; b++) {
                var A = out[a], B = out[b]
                var dx = wrapDelta(A.x, B.x, W), dy = wrapDelta(A.y, B.y, H)
                var dist = Math.sqrt(dx * dx + dy * dy)
                var ra = A.size / 2, rb = B.size / 2
                var want = wantDist(ra, rb)
                if (dist >= want) continue
                // Exactly on top of each other: pick a direction (a stable one).
                var nx = dist > 1e-6 ? dx / dist : 1
                var ny = dist > 1e-6 ? dy / dist : 0
                var push = (want - dist) * k
                var wa = rb / (ra + rb), wb = ra / (ra + rb)    // the bigger one yields less
                A.x = mod(A.x - nx * push * wa, W); A.y = mod(A.y - ny * push * wa, H)
                B.x = mod(B.x + nx * push * wb, W); B.y = mod(B.y + ny * push * wb, H)
            }
        }
    }
}

// Where a shape of `size` sits in a window whose top-left is at `origin` (screen
// coordinates), on a tile `period` wide: the image of it that lands in
// [−size, period − size) — so a panel narrower than `period − size` never sees one
// image replaced by the next.
function place(v, origin, period, size) {
    return mod(v - origin + size, period) - size
}

// A gentle swell, ±`amount` around 1, one cycle every `seconds`. `t` is the field's clock.
function breathe(t, phase, seconds, amount) {
    return 1 + amount * Math.sin(t * 2 * Math.PI / seconds + phase)
}

// ── Cookies on the frame, the bar and the sidebar ─────────────────────────────
// Those are bands, not cards: a strip down each side, one along the bottom, the bar's band across
// the top, the sidebar's lobe. Each gets a window onto the field exactly as a panel does — but a
// band can be the whole width of the screen, and a window can only show the field's repeat
// seamlessly while it is narrower than `period − shape` (see `place`). So a long band is cut into
// pieces that are, and each piece is its own window.

// The rectangles the frame's material occupies, in screen pixels. `strip` is the frame's depth
// (0 with no frame), `topH` the bar band's height (0 for a floating bar, which has no material),
// `side` the sidebar lobe's {x, y, w, h} (w or h 0 while it is away). The top band takes the
// corners, so the side strips run between it and the bottom strip and nothing is drawn twice.
// Empty ones are left out.
function frameRects(screenW, screenH, strip, topH, side) {
    var out = []
    var top = Math.max(strip, topH)
    if (top > 0) out.push({ x: 0, y: 0, w: screenW, h: top, kind: "ring" })
    var bodyH = screenH - top - strip
    if (strip > 0 && bodyH > 0) {
        out.push({ x: 0, y: top, w: strip, h: bodyH, kind: "ring" })
        out.push({ x: screenW - strip, y: top, w: strip, h: bodyH, kind: "ring" })
    }
    if (strip > 0) out.push({ x: 0, y: screenH - strip, w: screenW, h: strip, kind: "ring" })
    // The sidebar's lobe lies partly on the frame's strip; whatever the ring already covers is
    // taken out of it, or that band would be drawn twice and read twice as opaque.
    if (side && side.w > 1 && side.h > 1) {
        var left = [{ x: side.x, y: side.y, w: side.w, h: side.h, kind: "side" }]
        for (var i = 0; i < out.length; i++) {
            var next = []
            for (var j = 0; j < left.length; j++) next = next.concat(subtract(left[j], out[i]))
            left = next
        }
        out = out.concat(left)
    }
    return out
}

// `r` with `cut` taken out: up to four rectangles (above, below, left, right of the cut) that
// together are exactly r minus cut. r itself if they don't touch; nothing if cut covers r.
function subtract(r, cut) {
    var ix0 = Math.max(r.x, cut.x), iy0 = Math.max(r.y, cut.y)
    var ix1 = Math.min(r.x + r.w, cut.x + cut.w), iy1 = Math.min(r.y + r.h, cut.y + cut.h)
    if (ix1 <= ix0 || iy1 <= iy0) return [r]
    var k = r.kind
    var out = []
    if (iy0 > r.y)           out.push({ x: r.x, y: r.y, w: r.w, h: iy0 - r.y, kind: k })        // above
    if (iy1 < r.y + r.h)     out.push({ x: r.x, y: iy1, w: r.w, h: r.y + r.h - iy1, kind: k })  // below
    if (ix0 > r.x)           out.push({ x: r.x, y: iy0, w: ix0 - r.x, h: iy1 - iy0, kind: k })  // left
    if (ix1 < r.x + r.w)     out.push({ x: ix1, y: iy0, w: r.x + r.w - ix1, h: iy1 - iy0, kind: k })  // right
    return out
}

// A rectangle cut into a grid of pieces no larger than maxW × maxH, which together are exactly
// it. (A piece the size of the rectangle is returned as itself.)
function chunks(rect, maxW, maxH) {
    var out = []
    if (rect.w <= 0 || rect.h <= 0) return out
    var nx = Math.max(1, Math.ceil(rect.w / maxW)), ny = Math.max(1, Math.ceil(rect.h / maxH))
    for (var j = 0; j < ny; j++) {
        for (var i = 0; i < nx; i++) {
            var x0 = Math.round(rect.x + rect.w * i / nx), x1 = Math.round(rect.x + rect.w * (i + 1) / nx)
            var y0 = Math.round(rect.y + rect.h * j / ny), y1 = Math.round(rect.y + rect.h * (j + 1) / ny)
            out.push({ x: x0, y: y0, w: x1 - x0, h: y1 - y0, kind: rect.kind })
        }
    }
    return out
}

// Every piece the frame needs, ready to hand to windows.
function framePieces(screenW, screenH, strip, topH, side, maxW, maxH) {
    var rects = frameRects(screenW, screenH, strip, topH, side)
    var out = []
    for (var i = 0; i < rects.length; i++) out = out.concat(chunks(rects[i], maxW, maxH))
    return out
}

// ── Cookies come from panels, and leave the screen ────────────────────────────
// A panel shows the field at full strength. The bar, the sidebar and the frame are not given a
// field of their own: they show only the shapes that have come out of a panel — and then keep
// them, drifting on across the bar, until they leave the screen. (An earlier version faded them
// out a moment after they left a panel; what was wanted was for them to drift OFF, not vanish.)
//
// ── Per PICTURE, not per shape ────────────────────────────────────────────────
// The field repeats every (W × H), so one shape has a picture at every repeat, and a screen
// shows several of them. "This shape is in a panel" must therefore not light the shape — it lit
// every copy of it, over the bar and the frame far from any panel, the moment a panel opened.
// What is recorded is the screen position of the ONE picture that overlaps a panel: `lit[key]`
// is a list of {x, y} (top-left, in that screen's pixels), carried forward with the shape's own
// motion each step, and dropped when that picture has left the screen. A surface draws exactly
// those pictures, so it never shows one that did not come from a panel, and it shows it where the
// panel showed it. `key` is the screen's name: one monitor's panels do not light another's.
//
// `panels` is { key: [{x, y, w, h}] } in screen pixels; `bounds` is {w, h}, the screen's size.
// Overlap is by centres and half-sizes (exact for axis-aligned boxes), measured on the tile so
// the picture nearest the panel is the one chosen — which is the one the panel's own window shows.
function overlaps(s, r, W, H) {
    var dx = wrapDelta(s.x + s.size / 2, r.x + r.w / 2, W)
    var dy = wrapDelta(s.y + s.size / 2, r.y + r.h / 2, H)
    return Math.abs(dx) < (s.size + r.w) / 2 && Math.abs(dy) < (s.size + r.h) / 2
}

// Where, on the screen, the picture of `s` nearest to panel `r` has its top-left.
function imageAt(s, r, W, H) {
    return {
        // wrapDelta(a, b) is b − a, so from the PANEL to the shape: the shape's picture nearest the panel.
        x: r.x + r.w / 2 + wrapDelta(r.x + r.w / 2, s.x + s.size / 2, W) - s.size / 2,
        y: r.y + r.h / 2 + wrapDelta(r.y + r.h / 2, s.y + s.size / 2, H) - s.size / 2
    }
}

var SAME = 2    // two recorded pictures closer than this (px) are one picture

function offScreen(img, size, bounds) {
    return !bounds || img.x + size < 0 || img.x > bounds.w || img.y + size < 0 || img.y > bounds.h
}

// A panel's rect may say how far its card has faded in (`a`, 0..1) and whether it is still wanted
// (`open`); a rect without them is a panel fully open. Only a panel that is all the way in lights
// what is in it: one still fading in shows its cookies at its own fade (`strength`), and lighting them
// at once put the bar's half of a shape straddling the join up at full strength while the panel's half
// was still invisible. A closing one (`open` false) lights nothing, and takes the pictures that are in
// it with it — they fade out with the card instead of leaving half a cookie on the bar's edge.
var SHOWN = 0.99
function fullyOpen(r) { return r.w > 0 && r.h > 0 && r.open !== false && (r.a === undefined || r.a >= SHOWN) }
function covers(r, img, size) {
    return r.w > 0 && r.h > 0
        && Math.abs(img.x + size / 2 - (r.x + r.w / 2)) < (size + r.w) / 2
        && Math.abs(img.y + size / 2 - (r.y + r.h / 2)) < (size + r.h) / 2
}

function wake(field, W, H, panels, bounds) {
    for (var i = 0; i < field.length; i++) {
        var s = field[i]
        // Light the pictures that overlap a panel now (once each: a picture already recorded, to
        // within SAME, is the same one).
        if (panels) {
            for (var key in panels) {
                var rects = panels[key]
                for (var j = 0; j < rects.length; j++) {
                    var r = rects[j]
                    if (!fullyOpen(r) || !overlaps(s, r, W, H)) continue
                    var at = imageAt(s, r, W, H)
                    var imgs = s.lit[key] || (s.lit[key] = [])
                    var known = false
                    for (var m = 0; m < imgs.length; m++)
                        if (Math.abs(imgs[m].x - at.x) < SAME && Math.abs(imgs[m].y - at.y) < SAME) { known = true; break }
                    if (!known) imgs.push(at)
                }
            }
        }
        // Drop the ones that have left the screen — unless a panel still has them — and the ones in
        // a panel that is closing (unless another, open, panel has them too).
        for (var k2 in s.lit) {
            var list = s.lit[k2], keep = []
            var mine = (panels && panels[k2]) || []
            for (var n = 0; n < list.length; n++) {
                var held = false, going = false
                for (var p = 0; p < mine.length; p++) {
                    if (!covers(mine[p], list[n], s.size)) continue
                    if (mine[p].open === false) going = true
                    else held = true
                }
                if (going && !held) continue
                if (held || !offScreen(list[n], s.size, bounds)) keep.push(list[n])
            }
            if (keep.length > 0) s.lit[k2] = keep
            else delete s.lit[k2]
        }
    }
}

// Is any picture lit on any screen? If not (and no panel is open) there is nothing for the bar,
// the sidebar and the frame to draw, and the field need not run for them.
function anyLit(field) {
    for (var i = 0; i < field.length; i++)
        for (var key in field[i].lit)
            if (field[i].lit[key].length > 0) return true
    return false
}

// ── Everywhere mode: a shape's life on the bar ────────────────────────────────
// The other way to put cookies on the bar, the sidebar and the frame (Config.barCookiesFrom =
// "everywhere"): not only what drifts out of a panel, but a field of their own — in which a shape
// should not drift forever, or it is a permanent crowd. `presence` is how much of it is there at
// time `t` (seconds): 0 for most of each `period` (its own phase offsets it from its neighbours, so
// they come and go at different times), and for a `duty` share of it a smooth swell — fading in,
// peaking midway, fading out — so it never pops. 0..1 always.
function presence(t, phase, period, duty) {
    var u = mod(t / period + phase / (2 * Math.PI), 1)
    if (u >= duty) return 0
    var v = Math.sin(Math.PI * u / duty)
    return v * v
}

// ── One strength per picture, the same in every window ────────────────────────
// Each window onto the field used to decide for itself how strongly to draw: a panel at full
// strength, the bar's band at double strength on a slow life ("everywhere"), or only what had
// come out of a panel ("panels"). So two windows that MEET — the bar and the panel hanging off
// it — drew the same picture of the same shape at two different strengths, and the line where
// they meet cut it: a shape crossing from the bar into a panel dimmed, vanished, or appeared out
// of nothing exactly there. (Plus, "everywhere" kept the panel's fade and seam line at the join.)
//
// The strength is now a property of the PICTURE: a pure function of where it is on the screen,
// the shape, the clock and the panels, so every window that can see a picture works out the same
// number for it, and the windows differ only in where they are. A panel draws at 1. Any picture
// overlapping a fully open panel is at 1 in every other window too — so the two halves of a shape
// straddling a join are drawn alike — and away from the panels a window shows the bar's own field
// (`base`). In between it eases from one to the other over REACH px: as the shape drifts, never at
// a line.
var REACH = 48      // px off a panel's edge over which its full strength eases into the bar's own
var BOOST = 2       // "everywhere": the bar's own field, this much stronger than a panel's (thin bands)
var LIFETIME = 70   // s: "everywhere": a shape's life on the bar, there for half of it (`presence`)

function smooth01(t) {
    var u = Math.max(0, Math.min(1, t))
    return u * u * (3 - 2 * u)
}

// How near the picture of a `size` shape with its top-left at (x, y) is to one of `rects` (this
// screen's panels): 1 while it overlaps one, easing to 0 at REACH px off its edge — times how far
// that panel's card has faded in (`a`), so a panel opening or closing brings its pull in and out
// with it instead of switching it.
function reach(x, y, size, rects) {
    var best = 0
    if (!rects) return 0
    for (var i = 0; i < rects.length; i++) {
        var r = rects[i]
        if (!(r.w > 0 && r.h > 0)) continue
        var dx = Math.max(r.x - (x + size), x - (r.x + r.w), 0)
        var dy = Math.max(r.y - (y + size), y - (r.y + r.h), 0)
        var d = Math.sqrt(dx * dx + dy * dy)
        if (d >= REACH) continue
        var k = (r.a === undefined ? 1 : r.a) * (1 - smooth01(d / REACH))
        if (k > best) best = k
    }
    return best
}

// Is (x, y) one of the recorded pictures in `list` (drift.js `wake`)?
function litAt(list, x, y) {
    if (!list) return false
    for (var i = 0; i < list.length; i++)
        if (Math.abs(list[i].x - x) < SAME && Math.abs(list[i].y - y) < SAME) return true
    return false
}

// How strongly the bar, the sidebar, the frame and the strips between them draw the picture of `s`
// with its top-left at (x, y) on the screen, as a multiple of the shape's own alpha. `rects` are this
// screen's panels, `lit` this screen's recorded pictures of the shape, `t` the field's clock.
//   "panels":     what has come out of a panel (lit) is at 1, nothing else is there
//   "everywhere": each shape on its own life, BOOST strong at its peak
// and either way it rises to 1 as it nears an open panel.
function strength(s, x, y, rects, everywhere, t, lit) {
    var base = everywhere ? BOOST * presence(t, s.phase, LIFETIME, 0.5)
                          : (litAt(lit, x, y) ? 1 : 0)
    return base + (1 - base) * reach(x, y, s.size, rects)
}

// ── What ONE QML window draws ─────────────────────────────────────────────────
// A window onto the field (components/DriftShapes) used to hold a bound item per shape — 28 each,
// in a dozen windows — and every one of them re-ran its bindings every frame because the field it
// read had changed, though most shapes were nowhere near that window. Now the window asks this ONCE
// a tick and a small pool of items draws what it returns: for each shape, the one image that lands
// in the window (`place`), if its box (with `slack` for the breathing) reaches the window's screen
// rect [ox, ox + w) × [oy, oy + h), as
//   { i, x, y, size, r, s, o, points, petal, tone, outlined }
// in screen pixels (top-left), shape order. `o` is the opacity: the shape's alpha × 1 for a panel
// (`source`), × `strength` for anything else — the same number the blob and every other window use.
function windowPictures(field, ox, oy, w, h, W, H, source, rects, everywhere, t, key) {
    var out = []
    for (var i = 0; i < field.length; i++) {
        var s = field[i]
        var x = ox + place(s.x, ox, W, s.size), y = oy + place(s.y, oy, H, s.size)
        var slack = s.size * 0.05
        if (x + s.size + slack <= ox || x - slack >= ox + w || y + s.size + slack <= oy || y - slack >= oy + h) continue
        var o = Math.min(1, s.alpha * (source ? 1 : strength(s, x, y, rects, everywhere, t, s.lit ? s.lit[key] : undefined)))
        if (o <= FAINT) continue
        out.push({ i: i, x: x, y: y, size: s.size, r: s.r, s: breathe(t, s.phase, 9, 0.05), o: o,
                   points: s.points, petal: s.petal, tone: s.tone, outlined: s.outlined })
    }
    return out
}

// ── The field as the blob draws it ────────────────────────────────────────────
// With the plugin, the cookies are not QML items at all: the blob's shader draws them inside the
// merged silhouette (so a cookie follows a fillet or a bridge exactly, where a rectangular window
// could only stop at the card's box), from one flat list per screen — STRIDE numbers per picture:
//   cx, cy, radius, rotation (rad), petals, petal depth, opacity, tone + 4 × outlined
// Every image of every shape that lands on a `sw × sh` screen, at `strength` — the same number the
// QML windows use, so both renderers draw the same field. A panel's own pictures come out at 1
// because any picture overlapping a fully open panel is at 1. Faint ones are left out.
// The radius is Scallop's (half the box less 1.5px for the stroke), times the shape's breathing.
var STRIDE = 8
var FAINT = 0.003
function pictures(field, sw, sh, rects, everywhere, t, key, W, H) {
    var out = []
    for (var i = 0; i < field.length; i++) {
        var s = field[i]
        var lit = s.lit ? s.lit[key] : undefined
        var radius = (s.size / 2 - 1.5) * breathe(t, s.phase, 9, 0.05)
        var rot = s.r * Math.PI / 180
        var code = s.tone + (s.outlined ? 4 : 0)
        // every image of the shape whose box reaches the screen
        for (var x = s.x - Math.ceil((s.x + s.size) / W) * W; x < sw; x += W) {
            if (x + s.size <= 0) continue
            for (var y = s.y - Math.ceil((s.y + s.size) / H) * H; y < sh; y += H) {
                if (y + s.size <= 0) continue
                var o = Math.min(1, s.alpha * strength(s, x, y, rects, everywhere, t, lit))
                if (o <= FAINT) continue
                out.push(x + s.size / 2, y + s.size / 2, radius, rot, s.points, s.petal, o, code)
            }
        }
    }
    return out
}

// ── The strips between a panel and the surface it is welded to ────────────────
// A welded panel is not flush against the bar, the frame or the sidebar: it is held a short way off
// (BarPanelDock's `mergeGap`, one fillet radius) so the blob can bridge the two into one mass. The
// bridging strip is part of neither rectangle — and so belonged to neither window onto the field:
// a cookie crossing from a panel onto the sidebar was cut at the strip, on both sides of it.
//
// `panels` and `surfaces` are lists of {x, y, w, h} (the surfaces carry a `kind`); a strip is
// wanted wherever a panel faces a surface across a gap of at most `maxGap` pixels (the blob's blend
// reach) with the two overlapping along the other axis. Flush or overlapping ones need none.
// Each strip carries its surface's `kind`, so a layer can ask for its own.
function gapPieces(panels, surfaces, maxGap) {
    var out = []
    for (var i = 0; i < panels.length; i++) {
        var p = panels[i]
        if (!(p.w > 0 && p.h > 0)) continue
        for (var j = 0; j < surfaces.length; j++) {
            var s = surfaces[j]
            var ox = Math.min(p.x + p.w, s.x + s.w) - Math.max(p.x, s.x)   // negative when apart
            var oy = Math.min(p.y + p.h, s.y + s.h) - Math.max(p.y, s.y)
            if (oy > 1 && ox < 0 && -ox <= maxGap)          // side by side, across a gap
                out.push({ x: Math.min(p.x + p.w, s.x + s.w), y: Math.max(p.y, s.y), w: -ox, h: oy, kind: s.kind })
            else if (ox > 1 && oy < 0 && -oy <= maxGap)     // one above the other
                out.push({ x: Math.max(p.x, s.x), y: Math.min(p.y + p.h, s.y + s.h), w: ox, h: -oy, kind: s.kind })
        }
    }
    return out
}
