// ── test-contrast.js ──────────────────────────────────────────────────────────
// Regression tests for services/contrast.js, the palette's contrast guard.
//
//     bun scripts/test-contrast.js          (or: node scripts/test-contrast.js)
//
// Pure functions; touches nothing. contrast.js is loaded by stripping its `.pragma library`
// line, so the tests run against the real file.
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "contrast.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { luminance, ratio, over, alphaFor } = new Function(
    src + "\nreturn { luminance, ratio, over, alphaFor };")();

let failed = 0;
function check(name, ok, detail) {
    if (!ok) { failed++; console.log("FAIL", name, detail ?? ""); }
}
const rgb = (r, g, b) => ({ r: r / 255, g: g / 255, b: b / 255 });
const near = (a, b, eps = 0.02) => Math.abs(a - b) < eps;

// Known values: white on black is 21:1, identical colours are 1:1, mid-grey on white ~4.0:1 (#777 is 4.48).
check("white/black", near(ratio(rgb(255, 255, 255), rgb(0, 0, 0)), 21, 0.01));
check("same", near(ratio(rgb(50, 60, 70), rgb(50, 60, 70)), 1, 0.001));
check("#777 on white", near(ratio(rgb(119, 119, 119), rgb(255, 255, 255)), 4.48, 0.02), ratio(rgb(119, 119, 119), rgb(255, 255, 255)));
check("luminance black/white", luminance(rgb(0, 0, 0)) === 0 && near(luminance(rgb(255, 255, 255)), 1, 1e-9));

// over(): alpha 0 is the ground, alpha 1 is the ink.
const ink = rgb(230, 235, 240), ground = rgb(40, 60, 80);
check("over 0", near(over(ink, 0, ground).r, ground.r, 1e-9));
check("over 1", near(over(ink, 1, ground).b, ink.b, 1e-9));

// alphaFor: keeps a floor that already passes; lifts one that doesn't, just enough; never goes down.
check("passing floor kept", alphaFor(ink, ground, 4.5, 0.72) === 0.72);
for (const [name, g] of [["teal", rgb(47, 69, 85)], ["blue", rgb(58, 90, 111)], ["warm", rgb(90, 70, 60)]]) {
    const a = alphaFor(ink, g, 4.5, 0.3);
    check(name + " reaches target", ratio(over(ink, a, g), g) >= 4.5, a);
    check(name + " not above floor-needed", a <= 1);
    // Least alpha: a hair lower must miss, unless the floor was already enough.
    if (a > 0.3 + 1e-6) check(name + " is minimal", ratio(over(ink, a - 0.01, g), g) < 4.5, a);
}
check("never below floor", alphaFor(ink, rgb(0, 0, 0), 3, 0.5) === 0.5);
// Impossible: ink equal to ground can't reach any target; the answer is solid.
check("impossible gives 1", alphaFor(ground, ground, 4.5, 0.3) === 1);
// Dark ink on a light ground works the same way.
const dark = rgb(20, 20, 30), light = rgb(225, 228, 232);
const ad = alphaFor(dark, light, 4.5, 0.2);
check("dark on light", ratio(over(dark, ad, light), light) >= 4.5, ad);

console.log(failed === 0 ? "contrast: all passed" : `contrast: ${failed} FAILED`);
process.exit(failed === 0 ? 0 : 1);
