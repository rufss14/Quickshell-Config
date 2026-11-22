// ── test-calmspot.js ──────────────────────────────────────────────────────────
// services/calmspot.js — the energy of a picture's cells and the quietest (or busiest) block
// of them.
//
//     bun scripts/test-calmspot.js          (or: node scripts/test-calmspot.js)
//
// Safe: pure functions.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "calmspot.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const C = new Function(src + "\nreturn { energy, best, cellsFor, blockOf };")();

let passed = 0, failed = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) passed++;
    else { failed++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`); }
}
const near = (a, b) => Math.abs(a - b) < 1e-6;

// A w × h picture from a function (x, y) -> grey.
function picture(w, h, f) {
    const px = new Uint8ClampedArray(w * h * 4);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const v = f(x, y), i = (y * w + x) * 4;
        px[i] = px[i + 1] = px[i + 2] = v; px[i + 3] = 255;
    }
    return px;
}

// energy(): a flat grey picture has none; a checkerboard has plenty.
check("flat: no energy", C.energy(picture(8, 8, () => 100), 8, 8, 2, 2), [0, 0, 0, 0]);
const check4 = C.energy(picture(8, 8, (x, y) => ((x + y) % 2) * 200), 8, 8, 2, 2);
check("checkerboard: every cell busy", check4.every(v => v > 100), true);
check("cell count", check4.length, 4);

// Left half flat, right half stripes: the right cells carry the energy.
const half = C.energy(picture(8, 4, x => x < 4 ? 50 : (x % 2) * 255), 8, 4, 2, 1);
check("flat left cell is quiet", half[0] < 1, true);
check("striped right cell is busy", half[1] > 100, true);
check("a single step edge lands in the cell it is in", (() => {
    const e = C.energy(picture(4, 4, x => x < 2 ? 0 : 200), 4, 4, 4, 1);
    return e[2] > 0 && e[0] === 0 && e[1] === 0;
})(), true);

// best(): a 4 × 2 grid, busy at the left, quiet at the right.
const g = [9, 9, 1, 1,
           9, 9, 1, 1];
check("calm: the quiet side", C.best(g, 4, 2, 2, 2, "calm"), { cx: 2, cy: 0, score: 1 });
check("busy: the busy side", C.best(g, 4, 2, 2, 2, "busy"), { cx: 0, cy: 0, score: 9 });
check("a block wider than the grid is clamped", C.best(g, 4, 2, 9, 9, "calm").score, 5);
check("avoid: not on another widget", C.best(g, 4, 2, 2, 2, "calm", [{ cx: 2, cy: 0, w: 2, h: 2 }]), { cx: 0, cy: 0, score: 9 });
check("avoid: nothing left", C.best(g, 4, 2, 2, 2, "calm", [{ cx: 0, cy: 0, w: 4, h: 2 }]), null);
check("bad grid", C.best([1, 2], 4, 2, 1, 1, "calm"), null);
check("no grid", C.best(null, 4, 2, 1, 1, "calm"), null);

// A tie goes to the middle: a flat 5 × 1 grid, one cell wide -> the middle cell.
check("tie: nearest the middle", C.best([2, 2, 2, 2, 2], 5, 1, 1, 1, "calm").cx, 2);
// Mean, not the single quietest cell: a 2-wide block over [0, 9, 4, 4] prefers the 4,4 pair.
check("scored by the mean over the block", C.best([0, 9, 4, 4], 4, 1, 2, 1, "calm").cx, 2);

// cellsFor / blockOf
check("cellsFor: a 480 × 270 tile on 1920 × 1080, 32 × 18", C.cellsFor(480, 270, 1920, 1080, 32, 18), { w: 8, h: 5 });
check("cellsFor: a tiny tile is one cell", C.cellsFor(10, 10, 1920, 1080, 32, 18), { w: 1, h: 1 });
check("blockOf: a tile at 120, 60", C.blockOf({ x: 120, y: 60, w: 480, h: 270 }, 1920, 1080, 32, 18), { cx: 2, cy: 1, w: 8, h: 5 });
check("blockOf: clipped at the screen's edge", C.blockOf({ x: 1800, y: 1000, w: 480, h: 270 }, 1920, 1080, 32, 18).w, 2);
check("blockOf: off the screen has no cells", C.blockOf({ x: 5000, y: 0, w: 10, h: 10 }, 1920, 1080, 32, 18).w, 0);

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
