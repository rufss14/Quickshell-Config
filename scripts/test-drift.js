// ── test-drift.js ─────────────────────────────────────────────────────────────
// services/drift.js — the shared cookie field behind every panel.
//
//     bun scripts/test-drift.js          (or: node scripts/test-drift.js)
//
// Safe: pure functions.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "drift.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const D = new Function(src + "\nreturn { make, step, place, breathe, mulberry32, mod, wrapDelta, wantDist, FORMS, frameRects, chunks, framePieces, subtract, wake, anyLit, overlaps, imageAt, presence, gapPieces, reach, strength, litAt, REACH, BOOST, LIFETIME, pictures, STRIDE, windowPictures };")();

let passed = 0, failed = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) passed++;
    else { failed++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`); }
}
const near = (name, got, want, eps = 1e-9) => check(name, Math.abs(got - want) < eps, true);

const W = 1000, H = 800;

// ── make ──
const a = D.make(28, W, H, D.mulberry32(7));
const b = D.make(28, W, H, D.mulberry32(7));
check("seeded: same field twice", a, b);
check("seeded: a different seed differs", JSON.stringify(a) === JSON.stringify(D.make(28, W, H, D.mulberry32(8))), false);
check("count", a.length, 28);
check("all inside the tile", a.every(s => s.x >= 0 && s.x < W && s.y >= 0 && s.y < H), true);
check("depth runs 0..1 in even steps", [a[0].depth, a[27].depth], [0, 1]);
check("bigger is nearer: size rises with depth", a.every((s, i) => i === 0 || s.size > a[i - 1].size), true);
check("nearer is more opaque: alpha rises with depth", a.every((s, i) => i === 0 || s.alpha > a[i - 1].alpha), true);
check("every tone is a valid index", a.every(s => s.tone >= 0 && s.tone < 4), true);
check("a single shape does not divide by zero", D.make(1, W, H, D.mulberry32(1))[0].depth, 0.5);
check("every third is outlined", a.filter(s => s.outlined).length, 10);


// ── no pile-ups (the reason the field has one drift velocity) ──
check("every shape drifts at exactly the same velocity", new Set(a.map(s => s.vx.toFixed(9) + "," + s.vy.toFixed(9))).size, 1);

const worst = (f) => {                     // smallest dist / wanted dist over all pairs, on the tile
    let w = Infinity;
    for (let i = 0; i < f.length; i++) for (let j = i + 1; j < f.length; j++) {
        const dx = D.wrapDelta(f[i].x, f[j].x, W), dy = D.wrapDelta(f[i].y, f[j].y, H);
        w = Math.min(w, Math.hypot(dx, dy) / D.wantDist(f[i].size / 2, f[j].size / 2));
    }
    return w;
};
const crowd = (f, r) => {                  // most centres inside one disc of radius r
    let best = 0;
    for (const c of f) {
        let n = 0;
        for (const o of f) if (Math.hypot(D.wrapDelta(c.x, o.x, W), D.wrapDelta(c.y, o.y, H)) <= r) n++;
        best = Math.max(best, n);
    }
    return best;
};
let worstEver = Infinity, crowdEver = 0, crowdStart = 0;
for (let seed = 1; seed <= 12; seed++) {
    let f = D.make(28, W, H, D.mulberry32(seed));
    crowdStart = Math.max(crowdStart, crowd(f, 130));
    for (let i = 0; i < 120 * 60; i++) {                   // two minutes
        f = D.step(f, 1 / 60, W, H);
        if (i === 30 * 60 || i === 120 * 60 - 1) { worstEver = Math.min(worstEver, worst(f)); crowdEver = Math.max(crowdEver, crowd(f, 130)); }
    }
}
check("pairs keep ~their spacing once settled (>= 85% of wanted)", worstEver >= 0.85, true);
check("no more than 4 shapes ever share a 130px circle", crowdEver <= 4, true);
check("…and the field does not get more crowded than it started (+1)", crowdEver <= crowdStart + 1, true);
check("a pair exactly on top of each other is pushed apart, not NaN",
      (() => { const two = D.make(2, W, H, D.mulberry32(3)); two[1].x = two[0].x; two[1].y = two[0].y;
               const r = D.step(two, 1 / 60, W, H); return r.every(s => Number.isFinite(s.x) && Number.isFinite(s.y)) && (r[0].x !== r[1].x || r[0].y !== r[1].y); })(), true);
check("the push is gentle: one frame moves a pair by under a pixel or two", (() => {
    const two = D.make(2, W, H, D.mulberry32(3)); two[1].x = two[0].x + 40; two[1].y = two[0].y;
    const r = D.step(two, 1 / 60, W, H); return Math.abs((r[1].x - r[0].x) - 40) < 8; })(), true);

// ── the wander is bounded ──
// A lone shape (nothing to push it) in a huge tile: its path is the drift plus the wander,
// and the wander must never accumulate — it stays within 2×wa of the straight line.
{
    const BIG = 1e9;
    let f = D.make(1, BIG, BIG, D.mulberry32(5));
    const s0 = f[0];
    let worstOff = 0;
    for (let i = 1; i <= 300 * 60; i++) {
        f = D.step(f, 1 / 60, BIG, BIG);
        const t = i / 60;
        worstOff = Math.max(worstOff, Math.abs(f[0].x - (s0.x + s0.vx * t)), Math.abs(f[0].y - (s0.y + s0.vy * t)));
    }
    check("5 minutes on, the wander never exceeded 2×its amplitude", worstOff <= 2 * s0.wa + 1, true);
}


// ── the frame, the bar and the sidebar ──
const area = (r) => r.w * r.h;
const overlap = (a, b) => Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)) * Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y));

// frameRects: a 1920×1080 screen, 16px frame, 40px bar band, no sidebar.
{
    const r = D.frameRects(1920, 1080, 16, 40, null);
    check("top band, two sides, bottom — four pieces", r.length, 4);
    check("the top band takes the full width", r[0], { x: 0, y: 0, w: 1920, h: 40, kind: "ring" });
    check("the sides run between the top band and the bottom strip", [r[1], r[2]], [{ x: 0, y: 40, w: 16, h: 1024, kind: "ring" }, { x: 1904, y: 40, w: 16, h: 1024, kind: "ring" }]);
    check("the bottom strip takes the full width", r[3], { x: 0, y: 1064, w: 1920, h: 16, kind: "ring" });
    check("nothing is drawn twice: no two overlap", r.every((a, i) => r.every((b, j) => i === j || overlap(a, b) === 0)), true);
    check("together they are the ring: its area exactly", r.reduce((s, x) => s + area(x), 0), 1920 * 1080 - (1920 - 32) * (1080 - 40 - 16));
}
check("no frame and a floating bar: nothing to cover", D.frameRects(1920, 1080, 0, 0, null), []);
check("a floating bar over a frame: the top is just the strip", D.frameRects(1920, 1080, 16, 0, null)[0], { x: 0, y: 0, w: 1920, h: 16, kind: "ring" });
check("no frame but an anchored bar: only the band", D.frameRects(1920, 1080, 0, 40, null), [{ x: 0, y: 0, w: 1920, h: 40, kind: "ring" }]);
// A sidebar on the left edge overlaps the 16px strip: it must not be drawn there twice.
{
    const side = { x: 0, y: 200, w: 60, h: 500 };
    const r = D.frameRects(1920, 1080, 16, 40, side);
    check("the sidebar's overlap with the strip is taken out (the rest is one piece, 44 wide, kind side)", r[r.length - 1], { x: 16, y: 200, w: 44, h: 500, kind: "side" });
    check("so still no two pieces overlap", r.every((a, i) => r.every((b, j) => i === j || overlap(a, b) === 0)), true);
    check("a sidebar wholly inside the strip adds nothing", D.frameRects(1920, 1080, 16, 40, { x: 2, y: 200, w: 10, h: 500 }).length, 4);
    check("a sidebar across the bottom is trimmed against the bottom strip", D.frameRects(1920, 1080, 16, 40, { x: 100, y: 1000, w: 800, h: 80 }).slice(4), [{ x: 100, y: 1000, w: 800, h: 64, kind: "side" }]);
}

check("…and left out while it is away", D.frameRects(1920, 1080, 16, 40, { x: 0, y: 0, w: 0, h: 0 }).length, 4);

// subtract
check("a cut that misses leaves the rectangle alone", D.subtract({ x: 0, y: 0, w: 10, h: 10 }, { x: 20, y: 20, w: 5, h: 5 }), [{ x: 0, y: 0, w: 10, h: 10 }]);
check("a cut that covers it leaves nothing", D.subtract({ x: 2, y: 2, w: 4, h: 4 }, { x: 0, y: 0, w: 10, h: 10 }), []);
{
    const r = { x: 0, y: 0, w: 100, h: 100 }, c = { x: 30, y: 40, w: 20, h: 10 };
    const parts = D.subtract(r, c);
    check("a cut from the middle leaves four pieces", parts.length, 4);
    check("their area is the rectangle minus the cut", parts.reduce((s, x) => s + area(x), 0), 100 * 100 - 20 * 10);
    check("none overlaps the cut or another", parts.every((a, i) => overlap(a, c) === 0 && parts.every((b, j) => i === j || overlap(a, b) === 0)), true);
}

// chunks: cut into pieces that fit a window, exactly covering the rectangle.
{
    const rect = { x: 0, y: 0, w: 1920, h: 40 };
    const c = D.chunks(rect, 880, 680);
    check("a screen-wide band is cut into three", c.length, 3);
    check("every piece fits", c.every(p => p.w <= 880 && p.h <= 680), true);
    check("together they are exactly the rectangle", c.reduce((s, x) => s + area(x), 0), area(rect));
    check("no gaps and no overlaps (edge to edge)", c.every((p, i) => i === 0 || p.x === c[i - 1].x + c[i - 1].w), true);
}
check("a rectangle that already fits is returned whole", D.chunks({ x: 5, y: 6, w: 100, h: 50 }, 880, 680), [{ x: 5, y: 6, w: 100, h: 50 }]);
check("an empty rectangle has no pieces", D.chunks({ x: 0, y: 0, w: 0, h: 10 }, 880, 680), []);
{
    const rect = { x: 0, y: 0, w: 1920, h: 1500 };
    const c = D.chunks(rect, 880, 680);
    check("a big one is cut both ways", c.length, 3 * 3);
    check("…and still tiles it exactly", [c.reduce((s, x) => s + area(x), 0), c.every((a, i) => c.every((b, j) => i === j || overlap(a, b) === 0))], [area(rect), true]);
}
{
    const pieces = D.framePieces(1920, 1080, 16, 40, { x: 0, y: 200, w: 60, h: 500 }, 880, 680);
    check("every frame piece fits a window", pieces.every(p => p.w <= 880 && p.h <= 680 && p.w > 0 && p.h > 0), true);
    check("pieces: 3 (top) + 2 + 2 (sides, 1024 tall) + 3 (bottom) + 1 (sidebar, trimmed to 44 wide)", pieces.length, 3 + 2 + 2 + 3 + 1);
}


// kinds survive the cutting, so a layer can ask for its own pieces.
{
    const pieces = D.framePieces(1920, 1080, 16, 40, { x: 0, y: 200, w: 60, h: 500 }, 880, 680);
    check("pieces keep their kind: ring and side", [pieces.filter(p => p.kind === "ring").length, pieces.filter(p => p.kind === "side").length], [10, 1]);
    check("every piece has one", pieces.every(p => p.kind === "ring" || p.kind === "side"), true);
}

// ── lit pictures: cookies come from panels, and drift off the screen ──
{
    const SCR = { w: 1920, h: 1080 };
    const mk = (x, y, size) => ({ x, y, size, lit: {} });
    const panel = { x: 100, y: 100, w: 400, h: 300 };
    const P = { s1: [panel] };

    check("a shape inside a panel overlaps it", D.overlaps(mk(200, 200, 60), panel, W, H), true);
    check("one straddling its edge overlaps it", D.overlaps(mk(80, 200, 60), panel, W, H), true);
    check("one clear of it does not", D.overlaps(mk(600, 200, 60), panel, W, H), false);
    check("one just touching does not (edges are exclusive)", D.overlaps(mk(40, 200, 60), panel, W, H), false);
    check("overlap works across the tile's seam", D.overlaps(mk(W - 20, 200, 60), { x: -50, y: 100, w: 120, h: 300 }, W, H), true);
    check("the picture nearest a panel is where the shape is, when it is in it", D.imageAt(mk(200, 200, 60), panel, W, H), { x: 200, y: 200 });
    check("…and across the seam it is the one just outside the screen's left", D.imageAt(mk(W - 20, 200, 60), { x: -50, y: 100, w: 120, h: 300 }, W, H), { x: -20, y: 200 });

    const a = [mk(200, 200, 60), mk(700, 600, 60)];
    D.wake(a, W, H, P, SCR);
    check("a shape in a panel has its picture recorded, where it is", a[0].lit.s1, [{ x: 200, y: 200 }]);
    check("one that never was has nothing", a[1].lit, {});
    D.wake(a, W, H, P, SCR);
    check("woken again, the same picture is not recorded twice", a[0].lit.s1.length, 1);
    check("lit for ONE picture, not for every repeat of the tile", Object.values(a[0].lit).reduce((n, l) => n + l.length, 0), 1);
    check("only the screen whose panel it is in is lit (monitors are separate)", Object.keys(a[0].lit), ["s1"]);
    // The regression: a 1920 screen shows the 1000-wide tile twice, so this shape also has a picture
    // at x = 1200 — over, say, the bar. Opening a panel must not light THAT one.
    check("a panel opening does not light the shape's picture one tile away (nothing spawns elsewhere)", a[0].lit.s1.every(i => Math.abs(i.x - 1200) > 50), true);

    // drifting off: carried with the shape, no fading, until it is off the screen
    const f = [mk(200, 200, 60)];
    f[0].vx = 10; f[0].vy = 0; f[0].vr = 0; f[0].r = 0; f[0].wa = 0; f[0].ww = 0; f[0].wp = 0; f[0].depth = 0.5; f[0].alpha = 0.1;
    let g = D.step(f, 1 / 60, W, H, P, SCR);
    check("lit by a step while in the panel", g[0].lit.s1.length, 1);
    for (let i = 0; i < 60 * 5; i++) g = D.step(g, 1 / 60, W, H, {}, SCR);
    check("five seconds after the panel went it is STILL lit — it does not fade", g[0].lit.s1.length, 1);
    check("and its recorded position moved exactly as the shape did (10px/s × 5s)", Math.abs(g[0].lit.s1[0].x - (200 + 10 / 60 + 50)) < 1.5, true);
    let guard = 0;
    while (g[0].lit.s1 && guard++ < 60 * 400) g = D.step(g, 1 / 60, W, H, {}, SCR);
    check("it keeps drifting until it LEAVES THE SCREEN, and then it is gone", g[0].lit.s1, undefined);
    check("…which took the time to cross the screen (~170s at 10px/s) — a drift, not a fade", guard / 60 > 150 && guard / 60 < 190, true);

    const e = [mk(-20, 200, 60)];
    D.wake(e, W, H, { s1: [{ x: -50, y: 100, w: 120, h: 300 }] }, SCR);
    check("a picture half off the screen but in a panel is kept", e[0].lit.s1.length, 1);

    check("anyLit: yes while one is lit", D.anyLit(a), true);
    check("anyLit: no when nothing is", D.anyLit([mk(1, 1, 10)]), false);

    const before = JSON.stringify(a);
    D.step(a, 1 / 60, W, H, P, SCR);
    check("step does not change the field it was given (lit included)", JSON.stringify(a), before);

    const m = [mk(200, 200, 60)];
    D.wake(m, W, H, { s1: [panel], s2: [{ x: 150, y: 150, w: 300, h: 300 }] }, SCR);
    check("two screens whose panels overlap it each record their own picture", Object.keys(m[0].lit).sort(), ["s1", "s2"]);
    check("a zero-size panel lights nothing", (() => { const z = [mk(200, 200, 60)]; D.wake(z, W, H, { s1: [{ x: 200, y: 200, w: 0, h: 0 }] }, SCR); return z[0].lit; })(), {});
    check("no panels at all lights nothing", (() => { const z = [mk(200, 200, 60)]; D.wake(z, W, H, undefined, SCR); return z[0].lit; })(), {});
}

// ── presence (the "everywhere" mode): a shape comes, stays a while, and goes ──
{
    const P = 60, duty = 0.5;
    let inRange = true, zeroFor = 0, maxSeen = 0;
    for (let t = 0; t < 300; t += 0.25) {
        const v = D.presence(t, 1.7, P, duty);
        if (!(v >= 0 && v <= 1)) inRange = false;
        if (v === 0) zeroFor++;
        maxSeen = Math.max(maxSeen, v);
    }
    check("presence stays within 0..1", inRange, true);
    check("it is GONE for roughly its off share of the time", Math.abs(zeroFor / 1200 - (1 - duty)) < 0.02, true);
    check("and fully there at the peak", maxSeen > 0.999, true);
    check("periodic", Math.abs(D.presence(7, 0.4, P, duty) - D.presence(7 + P, 0.4, P, duty)) < 1e-9, true);
    let worstStep = 0;
    for (let t = 0; t < 120; t += 0.05) worstStep = Math.max(worstStep, Math.abs(D.presence(t + 0.05, 0.9, P, duty) - D.presence(t, 0.9, P, duty)));
    check("it never pops (steps under 0.01 per 50ms)", worstStep < 0.01, true);
    const at = (t) => [0, 1, 2, 3, 4, 5].map(ph => D.presence(t, ph, P, duty) > 0.5);
    check("different phases come and go at different times", new Set([0, 10, 20, 30, 40, 50].map(t => at(t).join())).size > 1, true);
}


// ── the strip between a panel and what it is welded to ──
{
    const bar = { x: 0, y: 0, w: 1920, h: 40, kind: "ring" };
    const sidebar = { x: 0, y: 200, w: 44, h: 500, kind: "side" };
    // a panel 10px right of the sidebar, level with it
    let g = D.gapPieces([{ x: 54, y: 120, w: 600, h: 500 }], [sidebar], 20);
    check("a panel 10px off the sidebar has the strip between them", g, [{ x: 44, y: 200, w: 10, h: 420, kind: "side" }]);
    check("flush against it: no strip needed", D.gapPieces([{ x: 44, y: 120, w: 600, h: 500 }], [sidebar], 20), []);
    check("overlapping it: no strip", D.gapPieces([{ x: 30, y: 120, w: 600, h: 500 }], [sidebar], 20), []);
    check("further than the blob reaches: not welded, no strip", D.gapPieces([{ x: 80, y: 120, w: 600, h: 500 }], [sidebar], 20), []);
    check("level with nothing of it: no strip", D.gapPieces([{ x: 54, y: 800, w: 600, h: 100 }], [sidebar], 20), []);
    // a sidebar on the right: the strip is on the panel's right
    const right = { x: 1876, y: 200, w: 44, h: 500, kind: "side" };
    check("a sidebar on the right: the strip is to the panel's right", D.gapPieces([{ x: 1200, y: 120, w: 666, h: 500 }], [right], 20), [{ x: 1866, y: 200, w: 10, h: 420, kind: "side" }]);
    // a panel hanging 6px below the bar band
    check("a panel a little below the bar band has the strip under the band", D.gapPieces([{ x: 100, y: 46, w: 600, h: 400 }], [bar], 20), [{ x: 100, y: 40, w: 600, h: 6, kind: "ring" }]);
    check("a panel flush under the bar: none", D.gapPieces([{ x: 100, y: 40, w: 600, h: 400 }], [bar], 20), []);
    // several panels and surfaces at once; kinds are carried
    const many = D.gapPieces([{ x: 54, y: 46, w: 600, h: 500 }, { x: 0, y: 0, w: 0, h: 0 }], [bar, sidebar], 20);
    check("each panel × surface pair is found, a zero-size panel is not", many.map(x => x.kind).sort(), ["ring", "side"]);
    check("a strip never has a size of zero or less", many.every(x => x.w > 0 && x.h > 0), true);
    check("no panels, no strips", D.gapPieces([], [bar, sidebar], 20), []);
}

// ── step ──
const s1 = D.step(a, 1 / 60, W, H);
check("step keeps the count", s1.length, 28);
check("step moves by velocity", Math.abs(s1[5].x - a[5].x) > 0 || Math.abs(s1[5].y - a[5].y) > 0, true);
check("step does not mutate its input", a, D.make(28, W, H, D.mulberry32(7)));
let f = a;
for (let i = 0; i < 6000; i++) f = D.step(f, 1 / 60, W, H);   // 100 s
check("100s later every shape is still inside the tile", f.every(s => s.x >= 0 && s.x < W && s.y >= 0 && s.y < H && s.r >= 0 && s.r < 360), true);
// A stalled frame must not lurch: 10s of dt moves no further than 0.1s would.
const lurch = D.step(a, 10, W, H), calm = D.step(a, 0.1, W, H);
check("a stalled frame is clamped", lurch, calm);
check("negative dt does not run it backwards", D.step(a, -1, W, H), D.step(a, 0, W, H));

// ── place ──
const size = 60;
// Inside the window the image is where it would be, relative to the window.
near("plain offset", D.place(300, 100, W, size), 200);
// Periodic: moving by a whole tile changes nothing.
near("periodic", D.place(300 + W, 100, W, size), D.place(300, 100, W, size));
// The image always lands in [−size, W − size).
let inRange = true;
for (let v = 0; v < W; v += 7) for (let o = 0; o < 3000; o += 113) {
    const p = D.place(v, o, W, size);
    if (p < -size - 1e-9 || p >= W - size + 1e-9) inRange = false;
}
check("always lands in [−size, W−size)", inRange, true);
// The seam: continuous everywhere except the one place the image jumps by a whole tile —
// and that place is at least `size` outside the window's [0, W − size) span, i.e. a panel
// narrower than W − size never sees it.
let jumpsInside = 0;
for (let v = 0; v < 2 * W; v += 0.5) {
    const p0 = D.place(v, 0, W, size), p1 = D.place(v + 0.5, 0, W, size);
    if (Math.abs(p1 - p0) > 1) {
        // jumped: where is the image now?
        if (p1 > 0 && p1 < W - 2 * size) jumpsInside++;
        if (p0 > 0 && p0 < W - 2 * size) jumpsInside++;
    }
}
check("the jump never happens inside a panel of width W − 2·size", jumpsInside, 0);
// Two windows side by side see ONE field: the same shape, at positions that differ by
// exactly the distance between the windows.
const left = D.place(420, 0, W, size), right = D.place(420, 300, W, size);
near("side by side: the same shape, offset by the gap", left - right, 300);

// ── a recorded picture stays ON its shape, separation and all ──
// The regression: the carry ran before the separation, so a push between two shapes never reached
// the picture recorded for one of them. Measured on this very field: 54px off after two minutes, and
// 16 extra pictures recorded as panels met the strays again — the bar drew a cookie where the panel
// did not, one shape in two places, cut at the join.
{
    let g = D.make(28, W, H, D.mulberry32(3));
    const SCR = { w: 2560, h: 1440 };
    const P = { s: [{ x: 300, y: 60, w: 535, h: 500 }] };
    let worstOff = 0, pushed = 0;
    for (let i = 0; i < 60 * 120; i++) {
        const prev = g;
        g = D.step(g, 1 / 60, W, H, P, SCR);
        // a frame in which separation moved something (drift alone is the same for every shape)
        if (g.some((s, j) => Math.abs(D.wrapDelta(prev[j].x, s.x, W) - D.wrapDelta(prev[0].x, g[0].x, W)) > 0.5)) pushed++;
        for (const s of g) for (const im of (s.lit.s || []))
            worstOff = Math.max(worstOff, Math.hypot(D.wrapDelta(im.x, s.x, W), D.wrapDelta(im.y, s.y, H)));
    }
    check("the run did exercise the separation", pushed > 0, true);
    check("every recorded picture is still exactly on one of its shape's images", worstOff < 1e-6, true);
    check("…so no shape was ever recorded twice", g.every(s => (s.lit.s || []).length <= 1 || new Set(s.lit.s.map(i => Math.round(i.x) + "," + Math.round(i.y))).size === s.lit.s.length), true);
}

// ── panels fading in and out ──
{
    const SCR = { w: 1920, h: 1080 };
    const mk = (x, y, size) => ({ x, y, size, lit: {} });
    const rect = (a, open) => ({ x: 100, y: 100, w: 400, h: 300, a, open });
    const one = (r) => { const f = [mk(200, 200, 60)]; D.wake(f, W, H, { s1: [r] }, SCR); return f[0].lit; };
    check("a rect that says nothing is a panel fully open: it lights", Object.keys(one({ x: 100, y: 100, w: 400, h: 300 })), ["s1"]);
    check("a card still fading in lights nothing yet (its own fade shows its cookies)", one(rect(0.5, true)), {});
    check("…and lights once it is all the way in", Object.keys(one(rect(1, true))), ["s1"]);
    check("a closing panel lights nothing, however visible it still is", one(rect(1, false)), {});

    // closing takes what is in it — not what has already left it, nor what another open panel holds
    const f = [mk(200, 200, 60), mk(600, 200, 60), mk(470, 200, 60)];
    f.forEach(s => { s.lit.s1 = [{ x: s.x, y: s.y }]; });
    D.wake(f, W, H, { s1: [rect(0.4, false), { x: 520, y: 100, w: 300, h: 300 }] }, SCR);
    check("a picture in a closing panel goes with it", f[0].lit, {});
    check("one that has already left it keeps drifting", f[1].lit.s1.length, 1);
    check("one that an open panel beside it still has is kept", f[2].lit.s1.length, 1);
}

// ── one strength per picture: nothing changes at a join ──
{
    const S = (size, phase) => ({ size, phase, lit: {} });
    const panel = { x: 400, y: 58, w: 535, h: 420 };

    // reach
    check("reach: 1 while overlapping a panel", D.reach(500, 100, 60, [panel]), 1);
    check("reach: 1 touching its edge", D.reach(500, 58 - 60, 60, [panel]), 1);
    check("reach: 0 at REACH off it", D.reach(500, 58 - 60 - D.REACH, 60, [panel]), 0);
    check("reach: 0 with no panels", [D.reach(500, 100, 60, []), D.reach(500, 100, 60, undefined)], [0, 0]);
    near("reach: scaled by how far the card has faded in", D.reach(500, 100, 60, [{ ...panel, a: 0.3 }]), 0.3);
    check("reach: a zero-size panel pulls nothing", D.reach(500, 100, 60, [{ x: 500, y: 100, w: 0, h: 0 }]), 0);
    let mono = true, smooth = true, prev = D.reach(500, panel.y - 60, 60, [panel]);
    for (let dist = 0; dist < 120; dist += 0.25) {  // moving up and away from the panel's top edge
        const v = D.reach(500, panel.y - 60 - dist, 60, [panel]);
        if (v > prev + 1e-12) mono = false;
        if (Math.abs(v - prev) > 0.25 * 1.5 / D.REACH + 1e-9) smooth = false;
        prev = v;
    }
    check("reach: only ever falls with distance", mono, true);
    check("reach: never jumps (smoothstep's slope at most)", smooth, true);

    // THE property: whatever the mode, the clock or the shape, a picture overlapping a fully open
    // panel is drawn at 1 by every window — which is what the panel itself draws.
    const rnd = D.mulberry32(11);
    let joinOk = true;
    for (let i = 0; i < 4000; i++) {
        const size = 28 + rnd() * 84, s = S(size, rnd() * 6.28);
        // a picture somewhere across the panel's top edge, overlapping it
        const x = panel.x - size + 1 + rnd() * (panel.w + size - 2), y = panel.y - size + 1 + rnd() * (size - 2);
        const t = rnd() * 500;
        for (const everywhere of [false, true])
            if (Math.abs(D.strength(s, x, y, [panel], everywhere, t, undefined) - 1) > 1e-12) joinOk = false;
    }
    check("a picture across a join is drawn at the panel's strength (1) on the bar's side too", joinOk, true);

    // away from every panel each mode is its own
    const far = [panel], s = S(60, 1.0);
    check("panels mode, far from a panel, never in one: nothing", D.strength(s, 1500, 600, far, false, 3, undefined), 0);
    check("panels mode, far from a panel but come out of one: full", D.strength(s, 1500, 600, far, false, 3, [{ x: 1500.4, y: 599.7 }]), 1);
    check("…only the recorded picture, not another image of the shape", D.strength(s, 500, 600, far, false, 3, [{ x: 1500, y: 600 }]), 0);
    let lifeOk = true;
    for (let t = 0; t < 200; t += 0.5)
        if (Math.abs(D.strength(s, 1500, 600, far, true, t, undefined) - D.BOOST * D.presence(t, 1.0, D.LIFETIME, 0.5)) > 1e-12) lifeOk = false;
    check("everywhere mode, far from a panel: the shape's own life at BOOST", lifeOk, true);
}

// ── a cookie drifting from the bar into a panel and out the other side, frame by frame ──
// The windows are simulated as Bar.qml has them: the bar's band (0..58) is a window at the screen's
// origin, the panel hangs flush under it. The shape is drawn by whichever window it is in, at the
// strength that window gives it; at no frame may it jump, and inside the panel it is the panel's 1.
for (const everywhere of [false, true]) {
    const SCR = { w: 1920, h: 1080 };
    const panel = { x: 300, y: 58, w: 535, h: 300 };
    const f = D.make(1, W, H, D.mulberry32(5));
    // starting just above the screen: on the 800 tile, y 750 is the picture at −50 in a window at 0
    let g = [{ ...f[0], x: 500, y: 750, vx: 0, vy: 12, vr: 0, wa: 0, size: 60, phase: 2.0, lit: {} }];
    const P = everywhere ? {} : { s: [panel] };    // "everywhere" tracks nothing (Drift.qml)
    let worstJump = 0, last = null, insideOk = true, frames = 0, sawBar = false, sawPanel = false;
    for (let i = 0; i < 60 * 80; i++, frames++) {
        g = D.step(g, 1 / 60, W, H, P, everywhere ? null : SCR);
        const s = g[0];
        const x = D.place(s.x, 0, W, s.size), y = D.place(s.y, 0, H, s.size);   // the bar window's picture
        if (y > 700) break;
        const onPanel = y + s.size > panel.y && y < panel.y + panel.h;
        const bar = D.strength(s, x, y, [panel], everywhere, i / 60, s.lit.s);
        const drawn = y < panel.y ? bar : 1;                   // the panel draws 1 wherever it shows it
        if (onPanel && Math.abs(bar - 1) > 1e-9) insideOk = false;
        if (y < panel.y) sawBar = true; else sawPanel = true;
        if (last !== null) worstJump = Math.max(worstJump, Math.abs(drawn - last));
        last = drawn;
    }
    const mode = everywhere ? "everywhere" : "panels";
    check(`${mode}: the run crossed from the bar into the panel`, sawBar && sawPanel, true);
    check(`${mode}: wherever it overlaps the panel, the bar draws it as the panel does`, insideOk, true);
    check(`${mode}: it never jumps from one frame to the next (< 0.01 a frame)`, worstJump < 0.01, true);
}

// ── a panel opening and closing over a shape that straddles the join ──
{
    const SCR = { w: 1920, h: 1080 };
    const at = { x: 500, y: 30 };                 // a 60px picture across the bar's edge at 58
    const s = { size: 60, phase: 0, lit: {} };
    const card = (a, open) => ({ x: 300, y: 58, w: 535, h: 300, a, open });
    // opening: the card's own cookies are drawn at its fade, a; the bar's half must match
    let openOk = true;
    for (let a = 0; a <= 1.0001; a += 0.05) {
        const f = [{ ...s, x: at.x, y: at.y, lit: {} }];
        D.wake(f, W, H, { s: [card(a, true)] }, SCR);
        if (Math.abs(D.strength(f[0], at.x, at.y, [card(a, true)], false, 0, f[0].lit.s) - a) > 1e-9) openOk = false;
    }
    check("opening: the bar's half of a shape across the join fades in with the card's half", openOk, true);
    // closing: lit while open, then the card fades out — the bar's half goes with it
    const f = [{ ...s, x: at.x, y: at.y, lit: {} }];
    D.wake(f, W, H, { s: [card(1, true)] }, SCR);
    check("open: it is lit", f[0].lit.s.length, 1);
    let closeOk = true;
    for (let a = 1; a >= -0.0001; a -= 0.05) {
        D.wake(f, W, H, { s: [card(Math.max(0, a), false)] }, SCR);
        if (Math.abs(D.strength(f[0], at.x, at.y, [card(Math.max(0, a), false)], false, 0, f[0].lit.s) - Math.max(0, a)) > 1e-9) closeOk = false;
    }
    check("closing: the bar's half fades out with the card's half, no half cookie left behind", closeOk, true);
}

// ── the field as the blob draws it (pictures) ──
{
    const sw = 1920, sh = 1080, t = 12.5;
    const f = D.make(28, W, H, D.mulberry32(9));
    const panel = { x: 300, y: 58, w: 535, h: 420 };
    for (const everywhere of [false, true]) {
        const list = D.pictures(f, sw, sh, [panel], everywhere, t, "s", W, H);
        const mode = everywhere ? "everywhere" : "panels";
        check(`${mode}: a whole number of pictures`, list.length % D.STRIDE, 0);
        const P = [];
        for (let i = 0; i < list.length; i += D.STRIDE) P.push(list.slice(i, i + D.STRIDE));
        check(`${mode}: every picture reaches the screen`, P.every(p => p[0] + p[2] > -2 && p[0] - p[2] < sw + 2 && p[1] + p[2] > -2 && p[1] - p[2] < sh + 2), true);
        check(`${mode}: opacities are in (0, 1]`, P.every(p => p[6] > 0 && p[6] <= 1), true);
        // a picture overlapping the open panel is exactly what the panel's QML window draws: the shape's alpha
        let same = true, seen = 0;
        for (const s of f) for (let x = s.x - 2 * W; x < sw; x += W) for (let y = s.y - 2 * H; y < sh; y += H) {
            if (!(x + s.size > panel.x && x < panel.x + panel.w && y + s.size > panel.y && y < panel.y + panel.h)) continue;
            seen++;
            const p = P.find(q => Math.abs(q[0] - (x + s.size / 2)) < 1e-6 && Math.abs(q[1] - (y + s.size / 2)) < 1e-6);
            if (!p || Math.abs(p[6] - Math.min(1, s.alpha)) > 1e-9) same = false;
        }
        check(`${mode}: the run had pictures in the panel`, seen > 0, true);
        check(`${mode}: in the panel, each at the panel's own strength (its alpha)`, same, true);
    }
    check("panels mode with no panel and nothing lit draws nothing", D.pictures(f, sw, sh, [], false, t, "s", W, H).length, 0);
    check("everywhere: the field reaches the screen at all", D.pictures(f, sw, sh, [], true, 3.0, "s", W, H).length > 0, true);
    const one = [{ ...f[0], x: 10, y: 10, alpha: 0.5, phase: 0, lit: {} }];
    const shown = D.pictures(one, 2560, 1440, [{ x: 0, y: 0, w: 2560, h: 1440 }], false, 0, "s", W, H);
    check("a shape under a full-screen panel shows at every repeat (3 × 2 on 2560×1440)", shown.length / D.STRIDE, 6);
    const p0 = shown.slice(0, D.STRIDE);
    near("radius is Scallop's (half the box less 1.5) times the breathing", p0[2], (one[0].size / 2 - 1.5) * D.breathe(0, 0, 9, 0.05));
    check("the tone code carries the outline", p0[7], one[0].tone + (one[0].outlined ? 4 : 0));
}

// ── what one QML window draws (windowPictures), and how many at most ──
{
    const panel = { x: 300, y: 58, w: 535, h: 420 };
    // the same answer the old per-shape delegate worked out for itself: place, in-window, strength
    let f = D.make(28, W, H, D.mulberry32(21));
    const win = { ox: 0, oy: 0, w: 880, h: 58 };       // a piece of the bar's band
    for (let n = 0; n < 50; n++) {
        f = D.step(f, 0.25, W, H, {}, null);
        const got = D.windowPictures(f, win.ox, win.oy, win.w, win.h, W, H, false, [panel], true, n, "s");
        const want = [];
        f.forEach((s, i) => {
            const x = win.ox + D.place(s.x, win.ox, W, s.size), y = win.oy + D.place(s.y, win.oy, H, s.size);
            const sl = s.size * 0.05;
            if (x + s.size + sl <= win.ox || x - sl >= win.ox + win.w || y + s.size + sl <= win.oy || y - sl >= win.oy + win.h) return;
            const o = Math.min(1, s.alpha * D.strength(s, x, y, [panel], true, n, undefined));
            if (o > 0.003) want.push(i + ":" + x.toFixed(6) + ":" + y.toFixed(6) + ":" + o.toFixed(9));
        });
        if (JSON.stringify(got.map(p => p.i + ":" + p.x.toFixed(6) + ":" + p.y.toFixed(6) + ":" + p.o.toFixed(9))) !== JSON.stringify(want)) {
            check("windowPictures matches the per-shape rule", false, true); break;
        }
    }
    check("windowPictures: shape order", true, true);
    // the pool: the most any window shows at once, over long runs and several seeds
    const windows = { band: [0, 0, 880, 58], strip: [0, 58, 12, 680], card: [300, 58, 990, 800] };
    const most = { band: 0, strip: 0, card: 0 };
    for (const seed of [1, 2, 3, 4, 5, 6]) {
        let g = D.make(28, W, H, D.mulberry32(seed));
        for (let k = 0; k < 2400; k++) {
            g = D.step(g, 0.25, W, H, {}, null);
            for (const [name, r] of Object.entries(windows))
                most[name] = Math.max(most[name], D.windowPictures(g, r[0], r[1], r[2], r[3], W, H, true, [], false, k, "s").length);
        }
    }
    console.log("  most pictures at once:", JSON.stringify(most));
    check("a piece of the bar or a strip never shows more than DriftShapes' pool for it (12)", most.band <= 12 && most.strip <= 12, true);
    check("a card never shows more than the whole field", most.card <= 28, true);
}

// ── breathe ──
near("breathe is 1 at its zero crossing", D.breathe(0, 0, 8, 0.04), 1);
check("breathe stays within ±amount", [0, 1, 2, 3, 4, 5, 6, 7].every(t => Math.abs(D.breathe(t, 1.3, 8, 0.04) - 1) <= 0.04 + 1e-12), true);
near("breathe is periodic", D.breathe(3, 0.5, 8, 0.04), D.breathe(11, 0.5, 8, 0.04));

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
