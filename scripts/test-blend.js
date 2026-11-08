// ── test-blend.js ────────────────────────────────────────────────────────────
// Guards config/Blend.qml's parser — the regex that reads ~/.config/hypr/blend.lua
// (the file hypr and this shell share). A parse miss here is silent on screen:
// the shell just falls back to defaults and stops tracking the hypr config.
//
//     bun scripts/test-blend.js        (or: node scripts/test-blend.js)
//
// The `_parse` body is lifted straight out of Blend.qml so the test can't drift
// from the real code.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { homedir } from "os";

const here = dirname(fileURLToPath(import.meta.url));
const qml = readFileSync(join(here, "..", "config", "Blend.qml"), "utf8");

const m = qml.match(/function _parse\(text\)\s*\{([\s\S]*?)\n    \}/);
if (!m) { console.error("could not extract _parse from Blend.qml"); process.exit(1); }
const _parse = new Function("text", m[1]);

let pass = 0, fail = 0;
function ok(cond, msg) { cond ? pass++ : (fail++, console.error("FAIL:", msg)); }

// ── Synthetic input: every shape blend.lua uses ──────────────────────────────
const sample = `
return {
    rounding       = 16,   -- ⇢ Tokens.radiusCard
    rounding_power = 2,
    active_opacity   = 0.97,
    border_active_wal   = 4,
    curve_points = { 0.05, 0.7, 0.1, 1.0 },
}
`;
const p = _parse(sample);
ok(p.rounding === 16, "int with trailing comma + comment");
ok(p.rounding_power === 2, "bare int");
ok(p.active_opacity === 0.97, "float");
ok(p.border_active_wal === 4, "key that is a substring of another line's key");
ok(Array.isArray(p.curve_points) && p.curve_points.length === 4, "number list");
ok(p.curve_points[1] === 0.7, "list element parsed");
ok(!("return" in p), "the `return {` line is not mistaken for a key");

// ── The real file, if present ───────────────────────────────────────────────
try {
    const real = _parse(readFileSync(join(homedir(), ".config/hypr/blend.lua"), "utf8"));
    for (const k of ["rounding", "border_size", "active_opacity", "blur_size"])
        ok(typeof real[k] === "number", `real blend.lua has numeric ${k}`);
    ok(Array.isArray(real.curve_points) && real.curve_points.length === 4,
       "real blend.lua curve_points is a 4-list");
} catch (e) {
    console.log("(skipped real blend.lua:", e.code || e.message, ")");
}

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
