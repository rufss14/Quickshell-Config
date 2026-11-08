// ── test-depthink.js ──────────────────────────────────────────────────────────
// Tests for services/depthink.js, the depth clock's text-colour guard.
//
//     bun scripts/test-depthink.js          (or: node scripts/test-depthink.js)
//
// Pure functions; touches nothing. Both files are loaded by stripping their `.pragma` / `.import`
// lines, so the tests run against the real files.
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const read = f => readFileSync(join(here, "..", "services", f), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "").replace(/^\s*\.import\s+.*$/m, "");
const C = new Function(read("contrast.js") + "\nreturn { luminance, ratio, over, alphaFor };")();
const { pick } = new Function("C", read("depthink.js") + "\nreturn { pick };")(C);

let failed = 0;
function check(name, ok, detail) { if (!ok) { failed++; console.log("FAIL", name, detail ?? ""); } }
const rgb = (r, g, b) => ({ r: r / 255, g: g / 255, b: b / 255 });
const grey = v => ({ r: v, g: v, b: v });
const dark = rgb(20, 60, 80), light = rgb(235, 245, 250), mid = rgb(120, 130, 140);

// A preference that already reads is returned as it is — the palette's own colour, untouched.
check("the first reading candidate is returned as given", pick([dark, light], 0.9, 3.5) === dark);
check("the next is used when the first can't read", pick([light, dark], 0.9, 3.5) === dark);
check("a light ground takes the dark colour, a dark ground the light", pick([dark, light], 0.1, 3.5) === light);

// Nothing reads: the best is pushed, and the result does read.
const pushed = pick([mid], 0.55, 3.5);
check("a mid-grey colour over a mid-grey ground is pushed, not returned", pushed !== mid);
check("what is pushed reaches the target", C.ratio(pushed, grey(0.55)) >= 3.5 - 1e-6, String(C.ratio(pushed, grey(0.55))));
check("it is pushed by as little as it takes", C.ratio(pushed, grey(0.55)) < 3.5 + 0.1, String(C.ratio(pushed, grey(0.55))));
check("a light ground pushes toward black, so it gets darker than it was",
      C.luminance(pushed) < C.luminance(mid));
const pushedUp = pick([mid], 0.45, 3.5);
check("a dark-ish ground pushes toward white, so it gets lighter", C.luminance(pushedUp) > C.luminance(mid));

// Every candidate list, every ground, a target the extremes can meet: the answer always reads.
let worst = 99;
for (let l = 0; l <= 1.0001; l += 0.05)
    for (const list of [[dark, light], [light, dark], [mid], [dark], []]) {
        const c = pick(list, l, 3.5);
        worst = Math.min(worst, C.ratio(c, grey(l)));
    }
check("over every ground the result reads at 3.5:1", worst >= 3.5 - 1e-6, String(worst));

// A target nothing can reach falls to black / white, the most there is.
const best = pick([mid], 0.5, 12);
check("an impossible target gives plain black or white", (best.r === 0 || best.r === 1) && best.r === best.g && best.g === best.b);
check("no candidates still gives something", pick([], 0.8, 3.5).r === 0);

if (failed) { console.log(failed + " FAILED"); process.exit(1); }
console.log("all passed");
