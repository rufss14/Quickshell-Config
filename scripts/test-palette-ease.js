// ── test-palette-ease.js ──────────────────────────────────────────────────────
// services/palette.js lerpPalette() — the blend a screen's colours ease through when
// its workspace changes to another wallpaper.
//
//     bun scripts/test-palette-ease.js     (or: node ...)
//
// Safe: pure functions.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "palette.js"), "utf8").replace(/^\.pragma.*$/m, "");
const P = new Function(src + "\nreturn { lerpPalette };")();

let passed = 0, failed = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) passed++; else { failed++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`); }
}

const A = { special: { background: "#000000" }, colors: { color1: "#ff0000", color2: "#00ff00" } };
const B = { special: { background: "#ffffff" }, colors: { color1: "#0000ff", color3: "#123456" } };

check("t=0 is a", P.lerpPalette(A, B, 0).colors.color1, "#ff0000");
check("t=1 is b", P.lerpPalette(A, B, 1).colors.color1, "#0000ff");
check("halfway", P.lerpPalette(A, B, 0.5).special.background, "#808080");
check("a slot only a has is kept", P.lerpPalette(A, B, 0.3).colors.color2, "#00ff00");
check("a slot only b has is taken", P.lerpPalette(A, B, 0.3).colors.color3, "#123456");
check("t clamps low", P.lerpPalette(A, B, -4).colors.color1, "#ff0000");
check("t clamps high", P.lerpPalette(A, B, 9).colors.color1, "#0000ff");
check("not a hex colour: b wins", P.lerpPalette({ special: { x: "red" }, colors: {} }, { special: { x: "blue" }, colors: {} }, 0.5).special.x, "blue");
check("empty a", P.lerpPalette(null, B, 0.5).colors.color3, "#123456");
check("inputs untouched", [A.colors.color1, B.colors.color1], ["#ff0000", "#0000ff"]);

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
