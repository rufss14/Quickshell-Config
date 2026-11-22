// ── test-masonry.js ───────────────────────────────────────────────────────────
// bun scripts/test-masonry.js — the grouped settings page's column packer
// (components/masonry.js).
//
// Loaded the way test-bentopack.js loads its file: the `.pragma library` line (a QML
// directive, not JS) is stripped and the rest evaluated, so this tests the real file
// rather than a copy.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "components", "masonry.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { pack, columnsFor, columnWidth } =
    new Function(src + "\nreturn { pack, columnsFor, columnWidth };")();

let passed = 0, failed = 0;
function eq(name, got, want) {
    const ok = JSON.stringify(got) === JSON.stringify(want);
    if (ok) passed++; else { failed++; console.log("FAIL", name, "\n  got ", JSON.stringify(got), "\n  want", JSON.stringify(want)); }
}
const cols = r => r.places.map(p => p.col);
const ys = r => r.places.map(p => p.y);

// ── order: each item into the shortest column, in source order ────────────────
{
    const r = pack([100, 50, 30, 40], 2, 10);
    // 100→c0; 50→c1 (0 < 100); 30→c1 (50 < 100), y 60; 40→c1 (90 < 100), y 100.
    eq("order cols", cols(r), [0, 1, 1, 1]);
    eq("order ys",   ys(r),   [0, 0, 60, 100]);
    eq("order total", r.total, 140);
}
{
    // A tall first item does not pull later ones under it while another column is shorter.
    const r = pack([300, 100, 100, 100], 2, 0);
    eq("tall first", cols(r), [0, 1, 1, 1]);
    eq("tall first total", r.total, 300);
}
{
    // Three columns fill left to right first.
    const r = pack([10, 20, 30, 5], 3, 4);
    eq("three cols", cols(r), [0, 1, 2, 0]);
    eq("three cols y", ys(r), [0, 0, 0, 14]);
}

// ── ties go to the leftmost column ────────────────────────────────────────────
eq("tie leftmost", cols(pack([50, 50, 20], 2, 8)), [0, 1, 0]);
eq("all empty tie", cols(pack([10], 3, 8)), [0]);
// Within half a pixel is a tie, so a sub-pixel difference does not flip a column.
eq("near tie", cols(pack([50, 50.3, 20], 2, 0)), [0, 1, 0]);
eq("real difference", cols(pack([51, 50, 20], 2, 0)), [0, 1, 1]);

// ── zero and one column ───────────────────────────────────────────────────────
{
    const r = pack([10, 20, 30], 1, 5);
    eq("one col", cols(r), [0, 0, 0]);
    eq("one col y", ys(r), [0, 15, 40]);
    eq("one col total", r.total, 70);
}
eq("zero cols is one", cols(pack([10, 20], 0, 5)), [0, 0]);
eq("undefined cols is one", cols(pack([10, 20], undefined, 5)), [0, 0]);
eq("empty list", pack([], 2, 5), { places: [], total: 0 });
eq("no list", pack(undefined, 2, 5), { places: [], total: 0 });

// ── hidden items: no place, no gap ────────────────────────────────────────────
{
    const r = pack([10, 0, 20], 1, 5);
    eq("hidden col", cols(r), [0, -1, 0]);
    eq("hidden no gap", ys(r), [0, 0, 15]);
    eq("hidden total", r.total, 35);
}
{
    // A leading hidden item adds no gap above the first shown one.
    const r = pack([0, 0, 40], 2, 12);
    eq("leading hidden", r.places, [{ col: -1, y: 0, span: 0 }, { col: -1, y: 0, span: 0 }, { col: 0, y: 0, span: 1 }]);
    eq("all hidden total", pack([0, -3, NaN], 2, 12).total, 0);
}

// ── stability: same input, same answer; a later change leaves earlier places ──
{
    const a = pack([120, 80, 60, 90, 40], 2, 12);
    const b = pack([120, 80, 60, 90, 40], 2, 12);
    eq("deterministic", a, b);
    // Growing the LAST item moves nothing before it.
    const c = pack([120, 80, 60, 90, 400], 2, 12);
    eq("last grows: earlier unchanged", c.places.slice(0, 4), a.places.slice(0, 4));
    // Hiding an item keeps the others' relative order inside each column.
    const d = pack([120, 0, 60, 90, 40], 2, 12);
    eq("hide keeps order", cols(d), [0, -1, 1, 1, 0]);
}
{
    // A sub-pixel wobble in an early item does not reshuffle later ones.
    const a = pack([100, 100, 50, 50], 2, 10);
    const b = pack([100, 100.2, 50, 50], 2, 10);
    eq("wobble stable", cols(a), cols(b));
}

// ── full-row items ────────────────────────────────────────────────────────────
{
    // A wide card first, then the columns under it.
    const r = pack([60, 100, 50], 2, 10, [true, false, false]);
    eq("full first", r.places, [{ col: 0, y: 0, span: 2 }, { col: 0, y: 70, span: 1 }, { col: 1, y: 70, span: 1 }]);
    eq("full first total", r.total, 170);
}
{
    // Between: it starts under the TALLER column, and both continue under it.
    const r = pack([100, 50, 40, 30, 20], 2, 10, [false, false, true, false, false]);
    eq("full between y", ys(r), [0, 0, 110, 160, 160]);
    eq("full between cols", cols(r), [0, 1, 0, 0, 1]);
    eq("full between total", r.total, 190);
}
{
    // Last, and a hidden full item takes nothing.
    const r = pack([30, 50, 0, 20], 2, 10, [false, false, true, true]);
    eq("full last", r.places[3], { col: 0, y: 60, span: 2 });
    eq("hidden full", r.places[2], { col: -1, y: 0, span: 0 });
    eq("full in one column is a plain item", ys(pack([10, 20], 1, 5, [true, false])), [0, 15]);
    eq("no full list", cols(pack([10, 20], 2, 5)), [0, 1]);
}

// ── columnsFor ────────────────────────────────────────────────────────────────
eq("cf 517 → 1",  columnsFor(517, 340, 12, 3), 1);
eq("cf 692 → 2",  columnsFor(692, 340, 12, 3), 2);
eq("cf 691 → 1",  columnsFor(691, 340, 12, 3), 1);
eq("cf 1166 → 3", columnsFor(1166, 340, 12, 3), 3);
eq("cf cap 2",    columnsFor(1166, 340, 12, 2), 2);
eq("cf no cap",   columnsFor(2000, 340, 12, 0), 5);
eq("cf zero w",   columnsFor(0, 340, 12, 3), 1);
eq("cf tiny",     columnsFor(100, 340, 12, 3), 1);

// ── columnWidth ───────────────────────────────────────────────────────────────
eq("cw 2",  columnWidth(716, 2, 12), 352);
eq("cw 1",  columnWidth(500, 1, 12), 500);
eq("cw 0 cols is one", columnWidth(500, 0, 12), 500);
eq("cw never negative", columnWidth(10, 3, 12), 0);

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
