// ── test-snap.js ──────────────────────────────────────────────────────────────
// services/snap.js — which zone a pointer is in, where a window goes, what reaches
// Hyprland.
//
//     bun scripts/test-snap.js          (or: node scripts/test-snap.js)
//
// Safe: pure functions. Nothing is dispatched.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "snap.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const S = new Function(src + "\nreturn { usable, zoneAt, rectFor, dispatches, label, gridPoint };")();

let passed = 0, failed = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) passed++;
    else { failed++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`); }
}

// A 2560×1440 monitor right of another, a 48px bar on top and a 68px sidebar on the left.
const area = S.usable({ x: 1920, y: 0, w: 2560, h: 1440 }, [68, 48, 0, 0]);
check("usable", area, { x: 1988, y: 48, w: 2492, h: 1392 });

check("middle: nothing", S.zoneAt(3200, 700, area), "");
check("on the bar: nothing (the pill's)", S.zoneAt(3200, 20, area), "");
check("just under the bar: fill", S.zoneAt(3200, 60, area), "max");
check("left edge", S.zoneAt(1990, 700, area), "left");
check("over the sidebar counts as left", S.zoneAt(1925, 700, area), "left");
check("right edge", S.zoneAt(4478, 700, area), "right");
check("top band near the left: top-left", S.zoneAt(2050, 55, area), "tl");
check("left edge near the top: top-left", S.zoneAt(1990, 100, area), "tl");
check("bottom-right corner", S.zoneAt(4470, 1430, area), "br");
check("bottom edge middle: nothing", S.zoneAt(3200, 1435, area), "");
check("bottom-left via the bottom band", S.zoneAt(2100, 1430, area), "bl");
check("no area", S.zoneAt(0, 0, null), "");

const g = S.rectFor("max", area, 8, 4);
check("fill with gaps", g, { x: 1996, y: 56, w: 2476, h: 1376 });
const l = S.rectFor("left", area, 8, 4), r = S.rectFor("right", area, 8, 4);
check("halves meet with gaps_in between", r.x - (l.x + l.w), 4);
check("halves fill the width", (r.x + r.w) - l.x, 2476);
const tl = S.rectFor("tl", area, 8, 4), br = S.rectFor("br", area, 8, 4);
check("quarters tile", [br.x - (tl.x + tl.w), br.y - (tl.y + tl.h)], [4, 4]);
check("no zone", S.rectFor("", area, 8, 4), null);
check("unknown zone", S.rectFor("diag", area, 8, 4), null);

check("dispatches", S.dispatches("562d73b1be60", { x: 1, y: 2, w: 3, h: 4 }), [
    'hl.dsp.window.resize({ x = 3, y = 4, window = "address:0x562d73b1be60" })',
    'hl.dsp.window.move({ x = 1, y = 2, window = "address:0x562d73b1be60" })']);
check("bad address: nothing", S.dispatches('0x1" }) os.exit(1) --', { x: 1, y: 2, w: 3, h: 4 }), []);
check("no rect: nothing", S.dispatches("0x1", null), []);
// ── Grid snap (the desktop widgets' grid) ────────────────────────────────────
// Second monitor: origin (1920, 0). The widget dots sit at origin + k * grid.
const org = { x: 1920, y: 0 };
const win = (x, y, w = 600, h = 400) => ({ x, y, w, h });
check("grid: rounds to the nearest dot", S.gridPoint(win(2951, 413), org, area, 40), { x: 2960, y: 400 });
check("grid: already on it -> null", S.gridPoint(win(2960, 400), org, area, 40), null);
check("grid: a point is measured from the monitor origin, not 0",
      (S.gridPoint(win(2953, 413), org, area, 40).x - org.x) % 40, 0);
// Under the bar (area.y = 48): 0 is a dot but not a legal one, so the next dot down.
check("grid: kept under the bar", S.gridPoint(win(3000, 10), org, area, 40), { x: 3000, y: 80 });
check("grid: kept off the sidebar", S.gridPoint(win(1930, 400), org, area, 40).x, 2000);
// Right edge: area ends at 4480; a 600 wide window must start at or before 3880 -> dot 3880.
check("grid: kept inside the right edge", S.gridPoint(win(4300, 400), org, area, 40).x, 3880);
check("grid: bottom edge", S.gridPoint(win(3000, 1300), org, area, 40).y, 1040);
check("grid: window bigger than the area is only clamped", S.gridPoint(win(1900, 40, 3000, 1500), org, area, 40), { x: 1988, y: 48 });
check("grid: no gridded spot -> clamp, not NaN", S.gridPoint(win(2000, 60, 2490, 1390), org, area, 1000), { x: 1990, y: 50 });
check("grid: bad grid size falls back to 1px", S.gridPoint(win(2951, 413), org, area, 0), null);
check("grid: no area", S.gridPoint(win(1, 2), org, null, 40), null);
check("grid dispatch is a bare move", S.dispatches("562d73b1be60", { x: 2960, y: 400 }),
    ['hl.dsp.window.move({ x = 2960, y = 400, window = "address:0x562d73b1be60" })']);

check("label", S.label("tr"), "Top-right quarter");
check("label of nothing", S.label(""), "");

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
