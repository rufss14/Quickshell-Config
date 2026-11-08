// ── test-snip.js ──────────────────────────────────────────────────────────────
// Tests for services/snip.js, the snip tool's geometry.
//
//     bun scripts/test-snip.js      (or: node scripts/test-snip.js)
//
// Safe to run: pure functions, no I/O.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const S = new Function(
    readFileSync(join(here, "..", "services", "snip.js"), "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "")
    + "\nreturn { rectFromPoints, clampRect, movedEnough, windowAt, toPixels, geom, cropArgs, toGlobal, safeName, fullRect, handlePoints, hitHandle, moveRect, resizeRect, cursorFor, ratioFromAnchor, resizeRatio, fitRatio, sizeRect, ratioLabel, matchWindow, livePlace, overlaps };")();

let pass = 0, fail = 0;
const failures = [];
function check(name, ok, detail) { if (ok) { pass++; return } fail++; failures.push(`  ${name}${detail ? "\n      " + detail : ""}`) }
const eq = (name, got, want) => check(name, JSON.stringify(got) === JSON.stringify(want), `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);

// ── dragging in any direction gives the same box ─────────────────────────────
eq("down-right", S.rectFromPoints({ x: 10, y: 20 }, { x: 40, y: 80 }), { x: 10, y: 20, w: 30, h: 60 });
eq("up-left",    S.rectFromPoints({ x: 40, y: 80 }, { x: 10, y: 20 }), { x: 10, y: 20, w: 30, h: 60 });
eq("mixed",      S.rectFromPoints({ x: 40, y: 20 }, { x: 10, y: 80 }), { x: 10, y: 20, w: 30, h: 60 });

// ── clamping to the screen ───────────────────────────────────────────────────
eq("inside stays", S.clampRect({ x: 10, y: 10, w: 50, h: 50 }, 100, 100), { x: 10, y: 10, w: 50, h: 50 });
eq("hanging off the right and bottom", S.clampRect({ x: 80, y: 90, w: 50, h: 50 }, 100, 100), { x: 80, y: 90, w: 20, h: 10 });
eq("hanging off the top-left", S.clampRect({ x: -20, y: -5, w: 50, h: 30 }, 100, 100), { x: 0, y: 0, w: 30, h: 25 });
eq("entirely outside", S.clampRect({ x: 200, y: 200, w: 10, h: 10 }, 100, 100), null);
eq("a sliver under a pixel", S.clampRect({ x: 99.5, y: 10, w: 5, h: 10 }, 100, 100), null);

// ── click vs drag ────────────────────────────────────────────────────────────
check("a tremor is not a drag", !S.movedEnough({ x: 10, y: 10 }, { x: 12, y: 13 }));
check("four px is", S.movedEnough({ x: 10, y: 10 }, { x: 14, y: 10 }));

// ── which window a click means ───────────────────────────────────────────────
{
    const big = { id: "big", x: 0, y: 0, w: 1000, h: 800 };
    const small = { id: "small", x: 100, y: 100, w: 300, h: 200 };
    eq("the smaller of two", S.windowAt([big, small], 150, 150).id, "small");
    eq("only the big one there", S.windowAt([big, small], 600, 600).id, "big");
    eq("order doesn't matter", S.windowAt([small, big], 150, 150).id, "small");
    eq("nothing there", S.windowAt([small], 5, 5), null);
    eq("no windows", S.windowAt([], 5, 5), null);
    eq("the far edge is outside", S.windowAt([small], 400, 150), null);
}

// ── logical → pixels ─────────────────────────────────────────────────────────
eq("scale 1", S.toPixels({ x: 10, y: 20, w: 30, h: 40 }, 1), { x: 10, y: 20, w: 30, h: 40 });
eq("scale 2", S.toPixels({ x: 10, y: 20, w: 30, h: 40 }, 2), { x: 20, y: 40, w: 60, h: 80 });
eq("fractional scale keeps the edge", S.toPixels({ x: 10, y: 10, w: 11, h: 11 }, 1.5), { x: 15, y: 15, w: 17, h: 17 });
eq("never empty", S.toPixels({ x: 3, y: 3, w: 0.1, h: 0.1 }, 1), { x: 3, y: 3, w: 1, h: 1 });
eq("a bad scale is 1", S.toPixels({ x: 4, y: 4, w: 8, h: 8 }, 0), { x: 4, y: 4, w: 8, h: 8 });

// ── the crop command ─────────────────────────────────────────────────────────
eq("geom", S.geom({ x: 10.4, y: 20.6, w: 30.2, h: 40.7 }), "30x41+10+21");
eq("crop argv", S.cropArgs("/tmp/a b.png", { x: 1, y: 2, w: 3, h: 4 }, "/tmp/o.png"),
   ["magick", "/tmp/a b.png", "-crop", "3x4+1+2", "+repage", "/tmp/o.png"]);
check("a hostile path stays one argv entry",
      S.cropArgs("/tmp/x; rm -rf ~", { x: 0, y: 0, w: 1, h: 1 }, "/o.png").length === 6);

// ── global coordinates ───────────────────────────────────────────────────────
eq("second monitor", S.toGlobal({ x: 10, y: 20, w: 30, h: 40 }, 1920, 0), { x: 1930, y: 20, w: 30, h: 40 });
eq("negative origin", S.toGlobal({ x: 10, y: 20, w: 30, h: 40 }, -1280, 100), { x: -1270, y: 120, w: 30, h: 40 });

// ── file-name-safe output names ──────────────────────────────────────────────
eq("a normal name", S.safeName("DP-1"), "DP-1");
eq("slashes and spaces", S.safeName("../my screen"), ".._my_screen");
eq("null", S.safeName(null), "");


// ── handles, move, resize ────────────────────────────────────────────────────
{
    const r = { x: 100, y: 100, w: 200, h: 100 };
    eq("full screen", S.fullRect(1920, 1080), { x: 0, y: 0, w: 1920, h: 1080 });
    eq("handle points", S.handlePoints(r).se, { x: 300, y: 200 });
    eq("handle centre of the top edge", S.handlePoints(r).n, { x: 200, y: 100 });
    eq("a corner", S.hitHandle(r, 102, 98, 8), "nw");
    eq("an edge", S.hitHandle(r, 200, 103, 8), "n");
    eq("inside is a move", S.hitHandle(r, 200, 150, 8), "move");
    eq("outside is nothing", S.hitHandle(r, 50, 50, 8), "");
    eq("just outside a corner still grabs it", S.hitHandle(r, 306, 206, 8), "se");
    // A tiny box: its corners must stay separate from each other.
    const tiny = { x: 100, y: 100, w: 10, h: 10 };
    eq("tiny box, top-left corner", S.hitHandle(tiny, 100, 100, 6), "nw");
    eq("tiny box, bottom-right corner", S.hitHandle(tiny, 110, 110, 6), "se");

    eq("move", S.moveRect(r, 50, 20, 1000, 1000), { x: 150, y: 120, w: 200, h: 100 });
    eq("move is stopped at the right edge", S.moveRect(r, 5000, 0, 1000, 1000), { x: 800, y: 100, w: 200, h: 100 });
    eq("move is stopped at the top-left", S.moveRect(r, -5000, -5000, 1000, 1000), { x: 0, y: 0, w: 200, h: 100 });

    eq("east edge grows", S.resizeRect(r, "e", 40, 0, 1000, 1000), { x: 100, y: 100, w: 240, h: 100 });
    eq("west edge moves the left side", S.resizeRect(r, "w", -30, 0, 1000, 1000), { x: 70, y: 100, w: 230, h: 100 });
    eq("corner moves two edges", S.resizeRect(r, "se", 10, 20, 1000, 1000), { x: 100, y: 100, w: 210, h: 120 });
    eq("north edge ignores dx", S.resizeRect(r, "n", 99, -10, 1000, 1000), { x: 100, y: 90, w: 200, h: 110 });
    eq("dragging past the opposite edge flips the box", S.resizeRect(r, "e", -250, 0, 1000, 1000), { x: 50, y: 100, w: 50, h: 100 });
    eq("stays on screen", S.resizeRect(r, "se", 5000, 5000, 1000, 1000), { x: 100, y: 100, w: 900, h: 900 });
    eq("never thinner than the minimum", S.resizeRect(r, "e", -199, 0, 1000, 1000), { x: 100, y: 100, w: 8, h: 100 });
    eq("the minimum at the screen edge", S.resizeRect({ x: 990, y: 0, w: 10, h: 50 }, "w", 100, 0, 1000, 1000), { x: 992, y: 0, w: 8, h: 50 });
    eq("the argument is untouched", r, { x: 100, y: 100, w: 200, h: 100 });

    eq("cursor for a corner", S.cursorFor("nw"), "sizeFDiag");
    eq("cursor for the other diagonal", S.cursorFor("sw"), "sizeBDiag");
    eq("cursor for an edge", S.cursorFor("e"), "sizeHor");
    eq("cursor for a move", S.cursorFor("move"), "sizeAll");
    eq("cursor for nothing", S.cursorFor(""), "cross");
}

// ── a locked aspect ratio ────────────────────────────────────────────────────
{
    const R = 16 / 9, W = 1000, H = 1000;
    const near = (name, got, want) => check(name, Math.abs(got.x - want.x) < 1e-6 && Math.abs(got.y - want.y) < 1e-6
        && Math.abs(got.w - want.w) < 1e-6 && Math.abs(got.h - want.h) < 1e-6, `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
    const ratioOf = r => r.w / r.h;

    near("drag down-right: the wider direction wins", S.ratioFromAnchor({ x: 100, y: 100 }, { x: 420, y: 150 }, R, W, H), { x: 100, y: 100, w: 320, h: 180 });
    near("drag down-right: the taller direction wins", S.ratioFromAnchor({ x: 100, y: 100 }, { x: 150, y: 400 }, R, W, H), { x: 100, y: 100, w: 300 * R, h: 300 });
    near("drag up-left keeps the anchor at the bottom-right", S.ratioFromAnchor({ x: 500, y: 500 }, { x: 180, y: 480 }, R, W, H), { x: 180, y: 320, w: 320, h: 180 });
    {
        const r = S.ratioFromAnchor({ x: 900, y: 900 }, { x: 5000, y: 5000 }, R, W, H);
        check("shrinks to stay on screen", r.x + r.w <= W + 1e-6 && r.y + r.h <= H + 1e-6 && Math.abs(ratioOf(r) - R) < 1e-9, JSON.stringify(r));
    }
    eq("a click without a drag is nothing", S.ratioFromAnchor({ x: 5, y: 5 }, { x: 5, y: 5 }, R, W, H).w, 0);

    const r = { x: 100, y: 100, w: 320, h: 180 };
    near("a corner holds the opposite corner", S.resizeRatio(r, "se", 160, 0, R, W, H), { x: 100, y: 100, w: 480, h: 270 });
    near("nw corner holds the south-east corner, shrunk to the screen's edge", S.resizeRatio(r, "nw", -160, 0, R, W, H), { x: 0, y: 280 - 236.25, w: 420, h: 236.25 });
    near("nw corner inside the screen", S.resizeRatio({ x: 500, y: 500, w: 320, h: 180 }, "nw", -160, 0, R, W, H), { x: 340, y: 410, w: 480, h: 270 });
    {
        const e = S.resizeRatio(r, "e", 160, 0, R, W, H);
        near("the east edge holds the west edge and grows about the middle", e, { x: 100, y: 190 - 135, w: 480, h: 270 });
        const s = S.resizeRatio(r, "s", 0, 90, R, W, H);
        near("the south edge holds the top and widens about the middle", s, { x: 260 - 240, y: 100, w: 480, h: 270 });
        const n = S.resizeRatio(r, "n", 0, -90, R, W, H);
        near("the north edge holds the bottom", n, { x: 20, y: 10, w: 480, h: 270 });
        check("an edge never leaves the ratio", [e, s, n].every(b => Math.abs(ratioOf(b) - R) < 1e-9));
    }
    {
        const b = S.resizeRatio({ x: 0, y: 400, w: 160, h: 90 }, "s", 0, 9000, R, W, H);
        check("an edge near the side stays on screen", b.x >= -1e-6 && b.x + b.w <= W + 1e-6 && b.y + b.h <= H + 1e-6 && Math.abs(ratioOf(b) - R) < 1e-9, JSON.stringify(b));
        const t = S.resizeRatio({ x: 100, y: 100, w: 320, h: 180 }, "e", -5000, 0, R, W, H);
        check("an edge never gets thinner than the minimum", t.w >= 8 - 1e-9, JSON.stringify(t));
    }
    eq("the argument is untouched", r, { x: 100, y: 100, w: 320, h: 180 });

    near("fit: a wide box is cut down to the ratio about its middle", S.fitRatio({ x: 0, y: 0, w: 400, h: 100 }, 1), { x: 150, y: 0, w: 100, h: 100 });
    near("fit: a tall box likewise", S.fitRatio({ x: 0, y: 0, w: 100, h: 400 }, 1), { x: 0, y: 150, w: 100, h: 100 });
    near("fit: already in ratio stays", S.fitRatio(r, R), r);

    eq("a typed size at scale 2 is half as many logical px", S.sizeRect({ x: 10, y: 10, w: 5, h: 5 }, 800, 600, 2, 1000, 1000), { x: 10, y: 10, w: 400, h: 300 });
    eq("a typed size is pushed back on screen", S.sizeRect({ x: 900, y: 900, w: 5, h: 5 }, 400, 300, 1, 1000, 1000), { x: 600, y: 700, w: 400, h: 300 });
    eq("a typed size is capped to the screen", S.sizeRect({ x: 0, y: 0, w: 5, h: 5 }, 99999, 99999, 1, 1000, 800), { x: 0, y: 0, w: 1000, h: 800 });
    eq("a typed zero is one pixel", S.sizeRect({ x: 0, y: 0, w: 5, h: 5 }, 0, 0, 1, 1000, 800), { x: 0, y: 0, w: 1, h: 1 });

    eq("label 16:9", S.ratioLabel(16 / 9), "16:9");
    eq("label 9:16", S.ratioLabel(9 / 16), "9:16");
    eq("label free", S.ratioLabel(0), "");
}

// ── a live pin ───────────────────────────────────────────────────────────────
{
    const W = 1920, H = 1080;
    const wins = [{ id: "big", x: 0, y: 0, w: 1920, h: 1080 }, { id: "term", x: 100, y: 100, w: 800, h: 600 }, { id: "term2", x: 101, y: 100, w: 800, h: 600 }];
    eq("a selection that is a window finds it", S.matchWindow(wins, { x: 100, y: 100, w: 800, h: 600 }, 3).id, "term");
    eq("within the tolerance", S.matchWindow(wins, { x: 103, y: 98, w: 798, h: 603 }, 3).id, "term");
    eq("outside the tolerance is a region", S.matchWindow(wins, { x: 110, y: 100, w: 800, h: 600 }, 3), null);
    eq("a box inside a window is not the window", S.matchWindow(wins, { x: 150, y: 150, w: 300, h: 200 }, 3), null);

    const src = { x: 100, y: 100, w: 400, h: 300 };
    eq("beside it, on the right", S.livePlace(src, W, H, 16), { x: 516, y: 100, w: 400, h: 300 });
    const right = { x: 1500, y: 100, w: 400, h: 300 };
    eq("no room on the right: the left", S.livePlace(right, W, H, 16), { x: 1084, y: 100, w: 400, h: 300 });
    {
        const wide = { x: 0, y: 0, w: 1920, h: 400 };
        const p = S.livePlace(wide, W, H, 16);
        check("a full-width strip goes below", p.y === 416 && p.x >= 0 && p.x + p.w <= W, JSON.stringify(p));
        const q = S.livePlace({ x: 0, y: 700, w: 1920, h: 380 }, W, H, 16);
        check("a full-width strip at the bottom goes above", q.y + q.h <= 700 - 16 + 1e-9 && q.y >= 0, JSON.stringify(q));
    }
    {
        const big = S.livePlace({ x: 0, y: 0, w: 1920, h: 1080 }, W, H, 16);
        check("a whole screen is shown at most 45% each way", Math.abs(big.w - 864) < 1e-9 && Math.abs(big.h - 486) < 1e-9, JSON.stringify(big));
        check("…and, with nowhere beside it, in the corner", big.x === W - big.w - 16 && big.y === H - big.h - 16, JSON.stringify(big));
        check("a pin that fits beside never overlaps its source", !S.overlaps(src, S.livePlace(src, W, H, 16)));
        check("the corner fallback does overlap, and overlaps() says so", S.overlaps({ x: 0, y: 0, w: 1920, h: 1080 }, big));
    }
    check("touching edges are not an overlap", !S.overlaps({ x: 0, y: 0, w: 10, h: 10 }, { x: 10, y: 0, w: 10, h: 10 }));
}

if (fail) { console.log(`FAIL  ${fail} failed, ${pass} passed`); console.log(failures.join("\n")); process.exit(1) }
console.log(`ok  ${pass} checks`);
