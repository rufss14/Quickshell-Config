// ── test-antiflash.js ─────────────────────────────────────────────────────────
// services/antiflash.js — the reading → gain → shader arithmetic of AntiFlash.
//
//     bun scripts/test-antiflash.js
//
// Safe: pure functions, plus glslangValidator on the generated shader in a temp file
// (skipped with a note when it isn't installed).
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync, writeFileSync, mkdtempSync } from "fs";
import { dirname, join } from "path";
import { tmpdir } from "os";
import { spawnSync } from "child_process";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "antiflash.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { gainFor, decide, ramp, shader, meanLuma } =
    new Function(src + "\nreturn { gainFor, decide, ramp, shader, meanLuma };")();

let pass = 0, fail = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) pass++;
    else { fail++; console.log("FAIL " + name + "\n  got:  " + g + "\n  want: " + w); }
}

check("dark: no dim", gainFor(0.3, 0.55, 0.35), 1);
check("at threshold: no dim", gainFor(0.55, 0.55, 0.35), 1);
check("white page", gainFor(1.0, 0.55, 0.35), 0.55);
check("floor holds", gainFor(1.0, 0.2, 0.35), 0.35);
check("quantised", gainFor(0.8, 0.55, 0.35), 0.7);
check("nonsense reading", gainFor(NaN, 0.55, 0.35), 1);
check("dims at once", decide(1.0, 1, 0.55, 0.35), 0.55);
check("small change ignored", decide(0.95, 0.55, 0.55, 0.35), 0.55);
check("brightens with margin", decide(0.3, 0.55, 0.55, 0.35), 1);
check("below threshold brightens", decide(0.53, 0.55, 0.55, 0.35), 0.95);
check("step edge holds", decide(0.74, 0.7, 0.55, 0.35), 0.7);
check("ramp", ramp(1, 0.55, 4), [0.89, 0.78, 0.66, 0.55]);
check("ramp one step", ramp(0.55, 1, 1), [1]);
check("mean of white+black", Math.round(meanLuma([255, 255, 255, 255, 0, 0, 0, 255]) * 1000) / 1000, 0.5);
check("shader gain clamped", /GAIN = 0\.05;/.test(shader(-3)), true);
check("shader gain printed", /GAIN = 0\.55;/.test(shader(0.55)), true);

const dir = mkdtempSync(join(tmpdir(), "antiflash-"));
const f = join(dir, "s.frag");
writeFileSync(f, shader(0.55));
const r = spawnSync("glslangValidator", ["-S", "frag", f], { encoding: "utf8" });
if (r.error) console.log("note: glslangValidator not installed — shader not compiled");
else check("shader compiles (GLSL ES 3.0)", r.status, 0) || (r.status !== 0 && console.log(r.stdout));

console.log(pass + " passed, " + fail + " failed");
process.exit(fail ? 1 : 0);
