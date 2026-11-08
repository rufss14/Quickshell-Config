// ── test-materialwall.js ──────────────────────────────────────────────────────
// services/materialwall.js — the Material Wallpaper's composition and polygon geometry.
//
//     bun scripts/test-materialwall.js          (or: node scripts/test-materialwall.js)
//
// Safe: pure functions.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "materialwall.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const M = new Function(src + "\nreturn { SHAPES, FORMS, FORM_LIST, DEFAULT_FORMS, outline, layout, rng, wander, spin, STYLE, CONFIG_KEY, PRESETS, lookStyle, lookOf, normaliseStyle, sameStyle, cleanName, freeName };")();

let passed = 0, failed = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) passed++;
    else { failed++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`); }
}
const near = (name, got, want, eps = 1e-9) => check(name, Math.abs(got - want) < eps, true);

// ── outline ──
const sq = [{ x: 0, y: 0, r: 0 }, { x: 1, y: 0, r: 0 }, { x: 1, y: 1, r: 0 }, { x: 0, y: 1, r: 0 }];
const sharp = M.outline(sq, 100);
check("unrounded square: its four corners, closed", sharp.length, 5);
check("unrounded square: fills the box",
    [Math.min(...sharp.map(p => p.x)), Math.max(...sharp.map(p => p.x)), Math.min(...sharp.map(p => p.y)), Math.max(...sharp.map(p => p.y))], [0, 100, 0, 100]);

// A square with every corner at radius 0.5 (half the side) is a circle: every point 50 from the centre.
const round = M.outline(sq.map(v => ({ ...v, r: 0.5 })), 100);
const radii = round.map(p => Math.hypot(p.x - 50, p.y - 50));
check("square at radius 0.5 is a circle", Math.max(...radii) - Math.min(...radii) < 0.1, true);
near("…of radius 50", radii[0], 50, 0.1);
check("outline is closed", round[0], round[round.length - 1]);

// A corner's arc is tangent to the edges: a 0.2 radius on the unit square cuts 0.2 along each side.
const cut = M.outline([{ x: 0, y: 0, r: 0.2 }, { x: 1, y: 0, r: 0 }, { x: 1, y: 1, r: 0 }, { x: 0, y: 1, r: 0 }], 1);
near("a corner of radius 0.2 starts 0.2 along the edge", cut[0].y, 0.2, 1e-9);
near("…and ends 0.2 along the other", cut[8].x, 0.2, 1e-9);

// Softness scales the radius; 0 is sharp.
const pent = M.outline(M.FORMS.pentagon, 100, 1);
check("softness 0 is the sharp pentagon (five corners and the closing point)", M.outline(M.FORMS.pentagon, 100, 0).length, 6);
check("a rounded pentagon has more points", pent.length > 5, true);
check("softness changes the shape", JSON.stringify(M.outline(M.FORMS.pentagon, 100, 1.5)) !== JSON.stringify(pent), true);

// Corners that would overrun a short edge give way instead of crossing: no point leaves the shape's box.
for (const [name, form] of Object.entries(M.FORMS)) {
    for (const k of [0.5, 1, 1.8]) {
        const o = M.outline(form, 100, k);
        check(`${name} at softness ${k}: inside its box, closed, finite`,
            o.every(p => Number.isFinite(p.x) && Number.isFinite(p.y) && p.x >= -1e-6 && p.x <= 100 + 1e-6 && p.y >= -1e-6 && p.y <= 100 + 1e-6)
            && JSON.stringify(o[0]) === JSON.stringify(o[o.length - 1]), true);
    }
}
// The larger side touches the box; a taller-than-wide shape (the ghost) is centred across.
const ghost = M.outline(M.FORMS.ghost, 100);
near("the ghost's height fills the box", Math.max(...ghost.map(p => p.y)) - Math.min(...ghost.map(p => p.y)), 100, 1e-6);
check("…and it is centred across", Math.abs(Math.min(...ghost.map(p => p.x)) - (100 - Math.max(...ghost.map(p => p.x)))) < 1e-6, true);

// ── the forms ──
check("a soft burst is ten two-corner motifs", M.FORMS.softBurst.length, 20);
check("a soft burst's tips are all the same distance out",
    Math.max(...M.FORMS.softBurst.filter((_, i) => i % 2 === 1).map(p => Math.hypot(p.x - 0.5, p.y - 0.5)))
    - Math.min(...M.FORMS.softBurst.filter((_, i) => i % 2 === 1).map(p => Math.hypot(p.x - 0.5, p.y - 0.5))) < 1e-9, true);
check("a nine-point cookie has eighteen corners", M.FORMS.cookie9.length, 18);

// ── layout ──
const L = M.layout(1920, 1080);
check("one box per shape", L.length, M.SHAPES.length);
check("every kind is one the view draws",
    L.every(b => ["circle", "rect", "poly"].includes(b.kind)), true);
check("every polygon names a slot that has a default form",
    M.SHAPES.filter(s => s.kind === "poly").every(s => M.FORMS[M.DEFAULT_FORMS[s.slot]]), true);
check("every tone is in 0..1", L.every(b => b.tone >= 0 && b.tone <= 1), true);

// Sized by the height: a circle is as wide as it is tall on any screen.
for (const [w, h] of [[1920, 1080], [3440, 1440], [1080, 1920]]) {
    const c = M.layout(w, h).filter(b => b.kind === "circle");
    check(`circles stay round at ${w}x${h}`, c.every(b => b.w === b.h), true);
}
const wide = M.layout(3440, 1440), norm = M.layout(1920, 1080);
near("size follows the height", wide[0].h / 1440, norm[0].h / 1080);
near("position follows the width",
    (wide[0].x + wide[0].w / 2) / 3440, (norm[0].x + norm[0].w / 2) / 1920);

check("only a polygon carries an outline",
    L.every(b => (b.kind === "poly") === (b.outline.length > 0)), true);
const poly = L.find(b => b.kind === "poly");
check("a polygon's outline is in its own box", Math.max(...poly.outline.map(p => p.x)) <= poly.w + 1e-9, true);

// A stack of bursts (same centre) steps lighter toward the middle and smaller.
const stacks = {};
for (const [i, b] of L.entries()) {
    if (M.SHAPES[i].slot !== "stack") continue;
    const k = Math.round(b.x + b.w / 2) + "," + Math.round(b.y + b.h / 2);
    (stacks[k] = stacks[k] || []).push(b);
}
check("two stacks of three", Object.values(stacks).map(s => s.length), [3, 3]);
for (const [k, s] of Object.entries(stacks)) {
    check(`stack ${k}: lighter and smaller toward the middle`,
        s.every((b, i) => i === 0 || (b.tone > s[i - 1].tone && b.h < s[i - 1].h)), true);
}

// ── style ──
const base = M.layout(1920, 1080), same = M.layout(1920, 1080, {});
check("no options is the composition as authored", same, base);
check("explicit neutral options are the same too",
    M.layout(1920, 1080, { contrast: 1, softness: 1, size: 1, seed: 0 }), base);

const hi = M.layout(1920, 1080, { contrast: 1.5 });
check("contrast scales every tone (until it clamps)",
    hi.every((b, i) => Math.abs(b.tone - Math.min(0.9, base[i].tone * 1.5)) < 1e-12), true);
check("contrast 0 flattens the tones to the base", M.layout(1920, 1080, { contrast: 0 }).every(b => b.tone === 0), true);
check("contrast is capped", M.layout(1920, 1080, { contrast: 50 }).every(b => b.tone <= 0.9), true);

const soft = M.layout(1920, 1080, { softness: 1.5 });
check("softness rounds a rectangle's corners", soft.every((b, i) => b.round >= base[i].round), true);
check("…up to a pill", M.layout(1920, 1080, { softness: 50 }).every(b => b.round <= 0.5), true);
check("softness 0 is sharp", M.layout(1920, 1080, { softness: 0 }).every(b => b.round === 0), true);
check("a polygon's outline follows the softness",
    JSON.stringify(soft.find(b => b.kind === "poly").outline) !== JSON.stringify(base.find(b => b.kind === "poly").outline), true);

const big = M.layout(1920, 1080, { size: 1.25 });
check("size scales every shape", big.every((b, i) => Math.abs(b.h - base[i].h * 1.25) < 1e-9), true);
check("size keeps every centre",
    big.every((b, i) => Math.abs((b.x + b.w / 2) - (base[i].x + base[i].w / 2)) < 1e-9
                     && Math.abs((b.y + b.h / 2) - (base[i].y + base[i].h / 2)) < 1e-9), true);

// seed
const a = M.layout(1920, 1080, { seed: 7 }), b = M.layout(1920, 1080, { seed: 7 }), c = M.layout(1920, 1080, { seed: 8 });
check("a seed is repeatable", a, b);
check("a different seed is a different arrangement", JSON.stringify(a) !== JSON.stringify(c), true);
check("a seed moves shapes, never off the composition's neighbourhood",
    a.every((s, i) => Math.abs(s.x + s.w / 2 - (base[i].x + base[i].w / 2)) <= 0.06 * 1920 + 1e-9
                   && Math.abs(s.y + s.h / 2 - (base[i].y + base[i].h / 2)) <= 0.06 * 1080 + 1e-9), true);
check("a seed keeps tones and sizes", a.every((s, i) => s.tone === base[i].tone && s.h === base[i].h), true);
const r1 = M.rng(3), r2 = M.rng(3);
check("rng: same seed, same stream", [r1(), r1(), r1()], [r2(), r2(), r2()]);
check("rng: in [0, 1)", Array.from({ length: 200 }, M.rng(5)).every(v => v >= 0 && v < 1), true);

// ── the form list and the slots ──
check("every listed form exists, once", M.FORM_LIST.every(f => M.FORMS[f.id]) && new Set(M.FORM_LIST.map(f => f.id)).size === M.FORM_LIST.length, true);
check("every form is listed", Object.keys(M.FORMS).every(k => M.FORM_LIST.some(f => f.id === k)), true);
for (const f of M.FORM_LIST) {
    const o = M.outline(M.FORMS[f.id], 100, 1);
    check(`form ${f.id}: a finite outline inside its box`,
        o.length > 3 && o.every(p => Number.isFinite(p.x) && Number.isFinite(p.y) && p.x >= -1e-6 && p.x <= 100 + 1e-6 && p.y >= -1e-6 && p.y <= 100 + 1e-6), true);
}
const ring = M.layout(1920, 1080, { forms: { stack: "cookie12", centre: "gem" } });
const dflt = M.layout(1920, 1080);
check("choosing a form for a slot changes that slot's shapes",
    M.SHAPES.every((s, i) => s.slot !== "stack" || JSON.stringify(ring[i].outline) !== JSON.stringify(dflt[i].outline)), true);
check("…and only that slot's (the corner kept its default)",
    M.SHAPES.every((s, i) => s.slot !== "corner" || JSON.stringify(ring[i].outline) === JSON.stringify(dflt[i].outline)), true);
check("an unknown form falls back to the slot's default",
    M.layout(1920, 1080, { forms: { stack: "nope", centre: "" } }), dflt);
check("the second colour marks the shapes it should", M.SHAPES.every((s, i) => dflt[i].alt === (s.alt === true)) && dflt.some(b => b.alt) && dflt.some(b => !b.alt), true);

// ── motion ──
check("wander is repeatable", M.wander(3, 41.5), M.wander(3, 41.5));
check("wander starts near where the shape was put", Math.abs(M.wander(2, 0).x) <= 0.1 && Math.abs(M.wander(2, 0).y) <= 0.1, true);
check("wander never strays far (a tenth of the screen, a few degrees)",
    Array.from({ length: 400 }, (_, k) => k * 7.3).every(t => M.SHAPES.every((_, i) => {
        const w = M.wander(i, t); return Math.abs(w.x) < 0.1 && Math.abs(w.y) < 0.1 && Math.abs(w.r) < 15; })), true);
check("every shape sways its own way", new Set(M.SHAPES.map((_, i) => JSON.stringify(M.wander(i, 30)))).size, M.SHAPES.length);
check("a bigger shape is calmer than a smaller one",
    Math.max(...Array.from({ length: 300 }, (_, k) => Math.abs(M.wander(0, k * 5).x))) < Math.max(...Array.from({ length: 300 }, (_, k) => Math.abs(M.wander(4, k * 5).x))), true);
check("wander is continuous (no jump between nearby moments)",
    Array.from({ length: 200 }, (_, k) => k * 3.1).every(t => Math.abs(M.wander(5, t + 0.01).x - M.wander(5, t).x) < 0.001), true);
check("spin turns polygons, alternating", [M.spin(3, 10, 2), M.spin(5, 10, 2)], [-20, -20]);
check("spin leaves a circle and a rectangle alone", [M.spin(0, 10, 2), M.spin(2, 10, 2)], [0, 0]);
check("spin at rate 0 is no turn", M.SHAPES.every((_, i) => M.spin(i, 99, 0) === 0), true);
check("spin is linear in time", M.spin(7, 20, 1.5), 2 * M.spin(7, 10, 1.5));

// ── looks ──
check("every style field has a Config key", Object.keys(M.STYLE).every(k => typeof M.CONFIG_KEY[k] === "string") && Object.keys(M.CONFIG_KEY).length === Object.keys(M.STYLE).length, true);
check("a look is a full style", M.PRESETS.every(p => JSON.stringify(Object.keys(M.lookStyle(p.id)).sort()) === JSON.stringify(Object.keys(M.STYLE).sort())), true);
check("the classic look is the default style", M.lookStyle("default", 0), M.STYLE);
check("a look keeps the seed it is given", M.lookStyle("calm", 77).seed, 77);
check("an unknown look is the default", M.lookStyle("nope", 0), M.STYLE);
check("every look is recognised as itself", M.PRESETS.every(p => M.lookOf(M.lookStyle(p.id, 123)) === p.id), true);
check("a tweak is no look", M.lookOf({ ...M.STYLE, contrast: 1.01 }), "");
check("the looks are all different", new Set(M.PRESETS.map(p => JSON.stringify(M.lookStyle(p.id, 0)))).size, M.PRESETS.length);
check("a look only names forms and roles that exist",
    M.PRESETS.every(p => ["stack", "centre", "side", "corner"].every(k => !p.style[k] || M.FORMS[p.style[k]])), true);
check("a look's values are inside the panel's ranges", M.PRESETS.every(p => { const s = M.lookStyle(p.id, 0);
    return s.contrast >= 0.5 && s.contrast <= 1.5 && s.softness >= 0.4 && s.softness <= 1.8 && s.size >= 0.7 && s.size <= 1.4
        && s.backdrop >= 0 && s.backdrop <= 0.3 && s.speed >= 0.2 && s.speed <= 3 && s.spin >= 0 && s.spin <= 1; }), true);

// ── saved presets ──
check("nothing in is the default style out", M.normaliseStyle(undefined), M.STYLE);
check("a whole style survives", M.normaliseStyle(M.lookStyle("sunny", 42)), M.lookStyle("sunny", 42));
check("every look survives", M.PRESETS.every(p => M.sameStyle(M.normaliseStyle(M.lookStyle(p.id, 5)), M.lookStyle(p.id, 5), true)), true);
check("a number is clamped to the panel's range", [M.normaliseStyle({ contrast: 9 }).contrast, M.normaliseStyle({ contrast: -1 }).contrast, M.normaliseStyle({ speed: 99 }).speed], [1.5, 0.5, 3]);
check("junk is the default", M.normaliseStyle({ contrast: "x", drift: "yes", stack: "nope", role: "#ff0000", seed: NaN, size: Infinity }),
    { ...M.STYLE });
check("a role is a role name, never a colour", M.normaliseStyle({ role: "#ff0000", role2: "ramp9" }).role2 + "|" + M.normaliseStyle({ role: "#ff0000" }).role, "ramp9|");
check("the first colour's primary is the empty spelling", M.normaliseStyle({ role: "primary" }).role, "");
check("a form that exists is kept, an unknown one is the slot's own", [M.normaliseStyle({ side: "gem" }).side, M.normaliseStyle({ side: "bogus" }).side], ["gem", ""]);
check("unknown keys are dropped", Object.keys(M.normaliseStyle({ evil: 1, __proto__: { x: 1 } })).sort(), Object.keys(M.STYLE).sort());
check("the seed is a whole, non-negative number", [M.normaliseStyle({ seed: 3.7 }).seed, M.normaliseStyle({ seed: -4 }).seed], [3, 0]);
check("sameStyle can ignore the seed", [M.sameStyle(M.lookStyle("calm", 1), M.lookStyle("calm", 2), false), M.sameStyle(M.lookStyle("calm", 1), M.lookStyle("calm", 2), true)], [true, false]);
check("a name is one trimmed line of at most 32", [M.cleanName("  a   b\n c "), M.cleanName("x".repeat(50)).length, M.cleanName(null), M.cleanName(undefined)], ["a b c", 32, "", ""]);
check("a free name is itself", M.freeName("Calm night", ["Calm"]), "Calm night");
check("a taken name gets a number, whatever its case", M.freeName("calm", ["Calm", "Calm 2"]), "calm 3");
check("no name is a name", M.freeName("  ", []), "My look");

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
