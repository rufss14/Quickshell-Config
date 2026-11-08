// ── test-kelvin.js ────────────────────────────────────────────────────────────
// Tests for services/kelvin.js, the colour-temperature preview maths.
//
//     bun scripts/test-kelvin.js      (or: node scripts/test-kelvin.js)
//
// Safe to run: pure functions, no I/O. Same contract as test-settingssearch.js —
// the .js is loaded by stripping its `.pragma library` line, so the tests run
// against the real file rather than a copy that can drift.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "kelvin.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

const { rgb, hex, describe } = new Function(src + "\nreturn { rgb, hex, describe };")();

let pass = 0, fail = 0;
const failures = [];
function check(name, ok, detail) {
    if (ok) { pass++; return }
    fail++;
    failures.push(`  ${name}${detail ? "\n      " + detail : ""}`);
}

// ── Daylight is neutral ──────────────────────────────────────────────────────
// 6500K is the "no adjustment" point the page promises, so it must come out as a
// near-grey — if this drifts, the preview claims a warm tint at the setting that
// is supposed to change nothing.
{
    const c = rgb(6500);
    check("6500K is near-neutral",
          Math.abs(c.r - c.g) < 22 && Math.abs(c.g - c.b) < 40, JSON.stringify(c));
}

// ── Warm means red-dominant, and blue drops away ─────────────────────────────
{
    const warm = rgb(2000), mid = rgb(4000), cool = rgb(6500);
    check("2000K is red-dominant", warm.r > warm.g && warm.g > warm.b, JSON.stringify(warm));
    check("blue falls as it warms", cool.b > mid.b && mid.b > warm.b,
          `${cool.b} ${mid.b} ${warm.b}`);
    check("red is pinned at the warm end", warm.r === 255 && mid.r === 255);
}

// ── Monotonic: no kinks in the ramp the swatch draws ─────────────────────────
{
    let ok = true, prev = -1;
    for (let k = 1500; k <= 6500; k += 100) {
        const b = rgb(k).b;
        if (b < prev) { ok = false; break }
        prev = b;
    }
    check("blue rises monotonically from 1500K to 6500K", ok);
}

// ── Bounds hold, whatever it is handed ───────────────────────────────────────
for (const bad of [0, -5, 999999, NaN, undefined, "cheese"]) {
    const c = rgb(bad);
    check(`in range for ${String(bad)}`,
          [c.r, c.g, c.b].every(v => Number.isInteger(v) && v >= 0 && v <= 255),
          JSON.stringify(c));
}

// ── hex() is a real 6-digit colour ───────────────────────────────────────────
check("hex format", /^#[0-9a-f]{6}$/.test(hex(4000)), hex(4000));
check("hex of 6500K matches rgb()", (() => {
    const c = rgb(6500);
    const h = hex(6500);
    return parseInt(h.slice(1, 3), 16) === c.r
        && parseInt(h.slice(3, 5), 16) === c.g
        && parseInt(h.slice(5, 7), 16) === c.b;
})());

// ── The words track the number ───────────────────────────────────────────────
check("6500K reads as neutral", describe(6500).toLowerCase().includes("neutral"));
check("2000K does not read as neutral", !describe(2000).toLowerCase().includes("neutral"));

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) {
    console.log("\nfailures:\n" + failures.join("\n"));
    process.exit(1);
}
