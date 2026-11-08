// ── test-shapes.js ────────────────────────────────────────────────────────────
// Regression tests for components/shapes.js, the morphable outlines behind MorphShape.
//
//     bun scripts/test-shapes.js          (or: node scripts/test-shapes.js)
//
// Pure functions; touches nothing. shapes.js is loaded by stripping its `.pragma library`
// line, so the tests run against the real file.
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "components", "shapes.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { SAMPLES, radii, mix, outline, turnFor } = new Function(
    src + "\nreturn { SAMPLES, radii, mix, outline, turnFor };")();

let failed = 0;
function check(name, ok, detail) {
    if (!ok) { failed++; console.log("FAIL", name, detail ?? ""); }
}
const near = (a, b, eps) => Math.abs(a - b) < eps;
const at = (r, deg) => r[Math.round(((deg % 360) + 360) % 360 / 360 * SAMPLES) % SAMPLES];

const NAMES = ["circle", "cookie4", "cookie6", "cookie7", "cookie9", "cookie12", "sunny", "burst",
               "clover", "squircle", "pentagon", "hexagon"];

// Every shape: SAMPLES finite radii, max exactly 1, nothing at or below 0 (still star-shaped).
for (const n of NAMES) {
    const r = radii(n);
    check(n + " length", r.length === SAMPLES, r.length);
    check(n + " finite", r.every(Number.isFinite));
    check(n + " max 1", near(Math.max(...r), 1, 1e-9), Math.max(...r));
    check(n + " positive", Math.min(...r) > 0.3, Math.min(...r));
}

// Unknown names fall back to a circle rather than nothing.
check("unknown = circle", radii("nope").every(v => near(v, 1, 1e-12)));
check("circle round", radii("circle").every(v => v === 1));

// A cookie with 4k petals has a TIP at twelve o'clock (270° on screen), so a clock's petals
// line up with its hours.
for (const n of ["cookie4", "cookie12"]) check(n + " tip at 12", near(at(radii(n), 270), 1, 1e-9), at(radii(n), 270));
// …and a valley between two tips.
check("cookie12 valley", at(radii("cookie12"), 15) < 0.95, at(radii("cookie12"), 15));

// Squircle: flat-ish sides, fullest on the diagonals.
const sq = radii("squircle");
check("squircle diagonal", at(sq, 45) > at(sq, 0), [at(sq, 45), at(sq, 0)]);

// mix: 0 is the source, 1 the target, between is between, overshoot goes past, never < 0.
const a = radii("circle"), b = radii("cookie9");
check("mix 0", mix(a, b, 0).every((v, i) => near(v, a[i], 1e-12)));
check("mix 1", mix(a, b, 1).every((v, i) => near(v, b[i], 1e-12)));
const half = mix(a, b, 0.5);
check("mix between", half.every((v, i) => v <= Math.max(a[i], b[i]) + 1e-12 && v >= Math.min(a[i], b[i]) - 1e-12));
check("mix overshoot", mix(a, b, 1.1).some((v, i) => v < b[i] - 1e-9));
check("mix clamps", mix(a, radii("burst"), 40).every(v => v >= 0));

// outline: closed (first point repeated), inside the box after the inset, centred.
const o = outline(radii("sunny"), 100, 80, 2);
check("outline length", o.length === (SAMPLES + 1) * 2, o.length);
check("outline closed", o[0] === o[o.length - 2] && o[1] === o[o.length - 1]);
let inBox = true;
for (let i = 0; i < o.length; i += 2) if (o[i] < 10 - 1e-9 || o[i] > 90 + 1e-9 || o[i + 1] < 2 - 1e-9 || o[i + 1] > 78 + 1e-9) inBox = false;
check("outline in box", inBox);
check("outline empty box", outline(radii("circle"), 0, 0, 2).every(v => v === 0));

// turnFor: one petal of the target's symmetry.
check("turn cookie12", turnFor("cookie12") === 30);
check("turn sunny", turnFor("sunny") === 45);

if (failed) { console.log(failed + " failed"); process.exit(1) }
console.log("shapes: all passed")
