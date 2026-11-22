// ── test-hyprcurves.js ────────────────────────────────────────────────────────
// services/hyprcurves.js — an animation's duration, curve and kind, for the motion stage.
//
//     bun scripts/test-hyprcurves.js          (or: node scripts/test-hyprcurves.js)
//
// Safe: pure functions.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "hyprcurves.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const H = new Function(src + "\nreturn { curveFor, durationMs, kindFor, leaving };")();

let passed = 0, failed = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) passed++;
    else { failed++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`); }
}

const WIND = [0.05, 0.7, 0.1, 1, 1, 1];
check("wind is the shell's curve", H.curveFor("wind", WIND), WIND);
check("winIn overshoots", H.curveFor("winIn", WIND), [0.1, 1.1, 0.1, 1.1, 1, 1]);
check("winOut", H.curveFor("winOut", WIND), [0.3, -0.3, 0, 1, 1, 1]);
check("liner is straight", H.curveFor("liner", WIND), [1, 1, 1, 1, 1, 1]);
check("an unknown curve is drawn as wind", H.curveFor("mine", WIND), WIND);
check("no curve (the leaf has none): wind", H.curveFor("", WIND), WIND);

check("6 is 600 ms", H.durationMs(6, true), 600);
check("6.4 is 640 ms", H.durationMs(6.4, true), 640);
check("disabled is instant", H.durationMs(6, false), 0);
check("0 is instant", H.durationMs(0, true), 0);
check("a string speed", H.durationMs("5", true), 500);
check("nonsense is instant", H.durationMs("fast", true), 0);
check("negative is instant", H.durationMs(-3, true), 0);

check("windows", H.kindFor("windows"), "window");
check("windowsIn", H.kindFor("windowsIn"), "window");
check("windowsMove slides", H.kindFor("windowsMove"), "slide");
check("fadeOut", H.kindFor("fadeOut"), "fade");
check("fade", H.kindFor("fade"), "fade");
check("workspaces", H.kindFor("workspaces"), "slide");
check("specialWorkspaceIn", H.kindFor("specialWorkspaceIn"), "slide");
check("border", H.kindFor("border"), "border");
check("borderangle", H.kindFor("borderangle"), "border");
check("layersIn fades", H.kindFor("layersIn"), "fade");
check("an unknown leaf is a window", H.kindFor("zoom"), "window");
check("nothing", H.kindFor(undefined), "window");

check("windowsOut leaves", H.leaving("windowsOut"), true);
check("windowsIn arrives", H.leaving("windowsIn"), false);
check("fade is not Out", H.leaving("fade"), false);

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
