// ── test-cookie.js ────────────────────────────────────────────────────────────
// services/cookie.js — the cookie cover's silhouette and the ring of bars round it.
//
//     bun scripts/test-cookie.js          (or: node scripts/test-cookie.js)
//
// Safe: pure functions.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "cookie.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const C = new Function(src + "\nreturn { radiusAt, edgeDist, barAngle, barLength };")();

let passed = 0, failed = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) passed++;
    else { failed++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`); }
}
const near = (name, got, want, eps = 1e-9) => check(name, Math.abs(got - want) < eps, true);

const R = 40;

// Depth 0 is a circle: the same radius at every angle.
for (const a of [0, 0.7, 2.1, 4, 6])
    near(`circle at ${a}`, C.radiusAt(a, R, 0, 9), R);

// A petal peaks at rMax and bottoms out at rMax − amp, N times round the turn.
near("peak at a=0", C.radiusAt(0, R, 0.2, 9), R);
near("trough half a petal on", C.radiusAt(Math.PI / 9, R, 0.2, 9), R - R * 0.2);
near("peaks every 2π/N", C.radiusAt(2 * Math.PI / 9, R, 0.2, 9), R);
near("never outside rMax", Math.max(...Array.from({ length: 720 }, (_, i) => C.radiusAt(i * Math.PI / 360, R, 0.3, 7))), R);
near("never inside rMax − amp", Math.min(...Array.from({ length: 720 }, (_, i) => C.radiusAt(i * Math.PI / 360, R, 0.3, 7))), R - R * 0.3, 1e-3);

// Fewer than 3 petals is not a shape; Scallop clamps, so must this (else the ring and
// the cookie disagree).
check("points clamped like Scallop", C.radiusAt(0.4, R, 0.2, 1), C.radiusAt(0.4, R, 0.2, 3));

// Turning the cookie by a whole petal changes nothing; by half a petal swaps peak/trough.
near("a whole petal on is the same edge", C.edgeDist(0.3, 2 * Math.PI / 9, R, 0.2, 9), C.edgeDist(0.3, 0, R, 0.2, 9));
near("half a petal swaps peak and trough", C.edgeDist(0, Math.PI / 9, R, 0.2, 9), R - R * 0.2);

// Turning is relative: edge at theta with phase p is the shape's radius at theta − p.
near("edgeDist is radiusAt(theta − phase)", C.edgeDist(1.9, 0.6, R, 0.15, 12), C.radiusAt(1.3, R, 0.15, 12));

// The ring: starts at 12 o'clock (−π/2), goes clockwise, n bars close the turn.
near("first bar at the top", C.barAngle(0, 32), -Math.PI / 2);
near("quarter way is 3 o'clock", C.barAngle(8, 32), 0);
near("last bar is one step short of the start", C.barAngle(31, 32), -Math.PI / 2 + 31 * 2 * Math.PI / 32);

// Bar length: a floor (silence is dots), a ceiling, and no NaN from a missing value.
check("silence is a dot", C.barLength(0, 3, 16), 3);
check("full is the ceiling", C.barLength(1, 3, 16), 16);
check("over 1 clamps", C.barLength(7, 3, 16), 16);
check("half is half", C.barLength(0.5, 3, 16), 8);
check("undefined is silence", C.barLength(undefined, 3, 16), 3);
check("NaN is silence", C.barLength(NaN, 3, 16), 3);
check("negative is silence", C.barLength(-1, 3, 16), 3);

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
