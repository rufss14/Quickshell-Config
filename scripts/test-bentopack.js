// ── test-bentopack.js ─────────────────────────────────────────────────────────
// bun scripts/test-bentopack.js — the bento row packer (services/bentopack.js).
//
// Loaded the way test-settingssearch.js loads its file: the `.pragma library` line (a
// QML directive, not JS) is stripped and the rest evaluated, so this tests the real
// file rather than a copy.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "bentopack.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { pack, baseSpan } = new Function(src + "\nreturn { pack, baseSpan };")();

let passed = 0, failed = 0;
function eq(name, got, want) {
    const ok = JSON.stringify(got) === JSON.stringify(want);
    if (ok) passed++; else { failed++; console.log("FAIL", name, "\n  got ", JSON.stringify(got), "\n  want", JSON.stringify(want)); }
}

// ── baseSpan: page columns → sub-columns ──────────────────────────────────────
eq("1 of 3 cols",  baseSpan(1, 3, 6), 2);
eq("2 of 3 cols",  baseSpan(2, 3, 6), 4);
eq("3 of 3 cols",  baseSpan(3, 3, 6), 6);
eq("1 of 2 cols",  baseSpan(1, 2, 6), 3);
eq("3 of 2 cols clamps", baseSpan(3, 2, 6), 6);
eq("any of 1 col", baseSpan(2, 1, 6), 6);
eq("undefined span is 1", baseSpan(undefined, 3, 6), 2);

// ── a row that already tiles is left alone ────────────────────────────────────
eq("full row",         pack([2, 2, 2], 6), [2, 2, 2]);
eq("2+4",              pack([2, 4], 6), [2, 4]);
eq("whole row",        pack([6], 6), [6]);

// ── leftovers are shared out evenly ───────────────────────────────────────────
eq("two tiles on 3 cols fill the row", pack([2, 2], 6), [3, 3]);
eq("a lone tile takes the row",        pack([2], 6), [6]);
eq("a lone 1-of-2-col tile",           pack([3], 6), [6]);
eq("3 tiles on 2 cols: 3|3 then 6",    pack([3, 3, 3], 6), [3, 3, 6]);
eq("4-wide alone",                     pack([4], 6), [6]);

// ── wrapping follows the grid's own rule ──────────────────────────────────────
// [2,2] then a 4 does not fit → row one is [2,2] (stretched), the 4 starts row two.
eq("wrap leaves no hole",   pack([2, 2, 4, 2], 6), [3, 3, 4, 2]);
eq("wrap, exact",           pack([2, 2, 4, 2, 6], 6), [3, 3, 4, 2, 6]);
eq("four tiles on 3 cols",  pack([2, 2, 2, 2], 6), [2, 2, 2, 6]);

// ── hidden children take no cell ──────────────────────────────────────────────
eq("hidden skipped",        pack([2, 0, 2, undefined, 2], 6), [2, 0, 2, 0, 2]);
eq("hidden makes a pair",   pack([2, 0, 2], 6), [3, 0, 3]);
eq("empty",                 pack([], 6), []);
eq("all hidden",            pack([0, 0], 6), [0, 0]);

// ── never exceeds a row, never leaves one short ──────────────────────────────
function rowsOk(spans, sub) {
    const out = pack(spans, sub);
    let used = 0, ok = true;
    for (let i = 0; i < out.length; i++) {
        if (!out[i]) continue;
        if (used + out[i] > sub) { ok = false; break; }
        used += out[i];
        if (used === sub) used = 0;
    }
    return ok && used === 0;
}
let fuzz = true;
const seeds = [[2,4,2,2,2,2,4,2], [3,3,6,3,3,3], [6,6,6], [2,2,2,2,2,2,2], [2,4,4,2,2], [3,3,3,3,3]];
for (const s of seeds) if (!rowsOk(s, 6)) { fuzz = false; console.log("row overflow/short for", s); }
eq("every row ends flush", fuzz, true);

// An odd sub-column count: remainder goes to the last items.
eq("odd sub remainder", pack([2, 2], 5), [2, 3]);

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
