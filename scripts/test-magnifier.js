// ── test-magnifier.js ─────────────────────────────────────────────────────────
// services/magnifier.js — the zoom stops, the toggle, the ease, what reaches Hyprland.
//
//     bun scripts/test-magnifier.js          (or: node scripts/test-magnifier.js)
//
// Safe: pure functions. Nothing is sent to Hyprland.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "magnifier.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const M = new Function(src + "\nreturn { clamp, step, toggle, ramp, parseEvent, lua, label, fraction };")();

let passed = 0, failed = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) passed++;
    else { failed++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`); }
}

check("in from off", M.step(1, 1), 1.25);
check("in from a stop", M.step(2, 1), 2.5);
check("in from between stops", M.step(2.2, 1), 2.5);
check("in at the top stays", M.step(8, 1), 8);
check("out from a stop", M.step(2, -1), 1.5);
check("out from between", M.step(2.2, -1), 2);
check("out at off stays", M.step(1, -1), 1);
check("clamp junk", M.clamp("x"), 1);
check("clamp high", M.clamp(99), 8);
check("toggle off", M.toggle(3, 3), 1);
check("toggle back to last", M.toggle(1, 3), 3);
check("toggle first time = 2", M.toggle(1, 1), 2);
const r = M.ramp(1, 2, 4);
check("ramp ends on target", r[r.length - 1], 2);
check("ramp length", r.length, 4);
check("ramp is even in log space", Math.abs(r[1] / r[0] - r[2] / r[1]) < 0.01, true);
check("ramp one step", M.ramp(1, 4, 0), [4]);
check("event in", M.parseEvent("qs-zoom:in"), "in");
check("event junk", M.parseEvent("qs-zoom:rm"), "");
check("other prefix", M.parseEvent("qs-switch:up"), "");
check("lua is clamped and fixed", M.lua(20), "hl.config({ cursor = { zoom_factor = 8.000 } })");
check("lua from junk", M.lua("1); os.exit(("), "hl.config({ cursor = { zoom_factor = 1.000 } })");
check("label off", M.label(1), "Off");
check("label", M.label(2.5), "2.5×");
check("fraction ends", [M.fraction(1), M.fraction(8)], [0, 1]);

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
