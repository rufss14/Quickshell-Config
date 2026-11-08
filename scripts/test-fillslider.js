// ── test-fillslider.js ────────────────────────────────────────────────────────
// Regression tests for components/fillslider.js, the geometry behind the OSD's slider.
//
//     bun scripts/test-fillslider.js          (or: node scripts/test-fillslider.js)
//
// Pure functions; touches nothing. The file is loaded by stripping its `.pragma library`
// line, so the tests run against the real one.
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "components", "fillslider.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { outline, layout, levelAt } = new Function(
    src + "\nreturn { outline, layout, levelAt };")();

let failed = 0;
function check(name, ok, detail) {
    if (!ok) { failed++; console.log("FAIL", name, detail ?? ""); }
}
const near = (a, b, eps = 1e-6) => Math.abs(a - b) < eps;

const W = 48, H = 120, CAP = 8, GAP = 6, HANDLE = 6;

// ── layout ───────────────────────────────────────────────────────────────────
for (const f of [0, 0.25, 0.5, 1]) {
    const L = layout(H, f, CAP, GAP, HANDLE);
    // fill + gap + handle + gap + rest fill the track exactly
    check(`layout sums at ${f}`, near(L.fillH + GAP + HANDLE + GAP + L.restH, H), JSON.stringify(L));
    check(`layout rest keeps its cap at ${f}`, L.restH >= CAP - 1e-6, L.restH);
    check(`layout fill keeps its stub at ${f}`, L.fillH >= CAP - 1e-6, L.fillH);
}
check("layout clamps above 1", near(layout(H, 3, CAP, GAP, HANDLE).fillH, layout(H, 1, CAP, GAP, HANDLE).fillH));
check("layout clamps below 0", near(layout(H, -2, CAP, GAP, HANDLE).fillH, CAP));

// ── levelAt is the inverse of layout ─────────────────────────────────────────
for (const f of [0, 0.1, 0.5, 0.9, 1]) {
    const L = layout(H, f, CAP, GAP, HANDLE);
    const y = L.handleTop + HANDLE / 2;           // the handle's centre
    check(`levelAt inverts layout at ${f}`, near(levelAt(y, H, CAP, GAP, HANDLE), f, 1e-9),
          levelAt(y, H, CAP, GAP, HANDLE));
}
check("levelAt clamps above the track", levelAt(-50, H, CAP, GAP, HANDLE) === 1);
check("levelAt clamps below the track", levelAt(H + 50, H, CAP, GAP, HANDLE) === 0);

// ── outline ──────────────────────────────────────────────────────────────────
function box(o) {
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    for (let i = 0; i < o.length; i += 2) {
        x0 = Math.min(x0, o[i]); x1 = Math.max(x1, o[i]);
        y0 = Math.min(y0, o[i + 1]); y1 = Math.max(y1, o[i + 1]);
    }
    return { x0, x1, y0, y1 };
}
const TOP = 50;
const flat = outline(W, H, TOP, 0, 0, 4);
const fb = box(flat);
check("outline pairs", flat.length % 2 === 0);
check("outline spans the width", near(fb.x0, 0) && near(fb.x1, W), JSON.stringify(fb));
check("outline top is the top with no wave", near(fb.y0, TOP), fb.y0);
check("outline runs past the bottom (it is clipped there)", fb.y1 > H);
check("outline starts bottom-left", near(flat[0], 0) && flat[1] > H);
check("outline ends bottom-right", near(flat[flat.length - 2], W) && flat[flat.length - 1] > H);

const wavy = outline(W, H, TOP, 2, 1.3, 4);
const wb = box(wavy);
check("wave stays within its amplitude of the top", wb.y0 >= TOP - 2 - 1e-9 && wb.y0 < TOP, wb.y0);
check("wave has more points than the flat edge", wavy.length > flat.length);
// The wave dies at the corners: the first and last top-edge points sit on `top`.
const firstTop = wavy[2 * (1 + 5 + 1) + 1];       // first sample after the top-left corner
check("wave starts on the corner's height", near(firstTop, TOP, 0.2), firstTop);

// A fill shorter than its corner radius must not turn inside out.
const stub = outline(W, H, H - 3, 0, 0, 4);
check("tiny fill stays finite", stub.every(Number.isFinite));
check("tiny fill never rises above its top", box(stub).y0 >= H - 3 - 1e-9, box(stub).y0);

console.log(failed ? `${failed} FAILED` : "all ok");
process.exit(failed ? 1 : 0);
