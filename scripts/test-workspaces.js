// ── test-workspaces.js ────────────────────────────────────────────────────────
// Regression tests for services/workspaces.js, the bar's workspace arithmetic.
//
//     bun scripts/test-workspaces.js          (or: node scripts/test-workspaces.js)
//
// Safe to run: workspaces.js is pure functions and touches nothing.
//
// The cases that matter are the boundaries, because every one of them fails
// SILENTLY on screen rather than throwing: a run that starts at slot 0, a run of
// length 1, a fully-occupied page, and the page flip itself. A misplaced pill
// looks like a rendering glitch, not like arithmetic, which is exactly why this
// arithmetic lives in a file a test can reach.
//
// Loaded by stripping the `.pragma library` line (a QML directive that isn't
// valid JS) and evaluating the rest, so the tests run against the real file
// rather than a copy that can drift.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "workspaces.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

const { runs, page } = new Function(src + "\nreturn { runs, page };")();

let pass = 0;
let fail = 0;

function check(name, got, want) {
    const g = JSON.stringify(got);
    const w = JSON.stringify(want);
    if (g === w) {
        pass++;
    } else {
        fail++;
        console.log(`  FAIL  ${name}\n          got  ${g}\n          want ${w}`);
    }
}

// ── runs ──────────────────────────────────────────────────────────────────────
const F = false, T = true;

check("runs: empty page",        runs([F, F, F, F, F]), []);
check("runs: no array at all",   runs(null),            []);
check("runs: zero-length",       runs([]),              []);

check("runs: all occupied merge into one",
      runs([T, T, T, T, T]), [{ start: 0, length: 5 }]);

// The two ends are where an off-by-one shows up, so both are pinned explicitly.
check("runs: single at the left edge",
      runs([T, F, F, F, F]), [{ start: 0, length: 1 }]);
check("runs: single at the right edge",
      runs([F, F, F, F, T]), [{ start: 4, length: 1 }]);

check("runs: two runs split by one gap",
      runs([T, T, F, T, T]), [{ start: 0, length: 2 }, { start: 3, length: 2 }]);

// The merge case: this is the state the widget animates INTO when the gap fills.
check("runs: gap of one closes into a single run",
      runs([T, T, T, T, F]), [{ start: 0, length: 4 }]);

check("runs: alternating never merges",
      runs([T, F, T, F, T]),
      [{ start: 0, length: 1 }, { start: 2, length: 1 }, { start: 4, length: 1 }]);

check("runs: leading gap",
      runs([F, T, T, F, F]), [{ start: 1, length: 2 }]);

// Not five-specific: the widget's `shown` count is configurable in principle.
check("runs: ten slots",
      runs([T, F, T, T, F, F, T, T, T, F]),
      [{ start: 0, length: 1 }, { start: 2, length: 2 }, { start: 6, length: 3 }]);

// ── page ──────────────────────────────────────────────────────────────────────
check("page: first slot of page 1",  page(1, 5),  { start: 1, index: 0 });
check("page: middle of page 1",      page(3, 5),  { start: 1, index: 2 });
check("page: last slot of page 1",   page(5, 5),  { start: 1, index: 4 });

// The boundary the old `currentWs <= 5 ? 1 : 6` literal encoded by hand.
check("page: first slot of page 2",  page(6, 5),  { start: 6, index: 0 });
check("page: last slot of page 2",   page(10, 5), { start: 6, index: 4 });
check("page: page 3 exists",         page(11, 5), { start: 11, index: 0 });

// ...and the reason it was a bug: it is wrong for every other page size.
check("page: perPage 10, id 10",     page(10, 10), { start: 1,  index: 9 });
check("page: perPage 10, id 11",     page(11, 10), { start: 11, index: 0 });
check("page: perPage 3, id 7",       page(7, 3),   { start: 7,  index: 0 });
check("page: perPage 1",             page(4, 1),   { start: 4,  index: 0 });

// Degenerate inputs must produce a usable page, not NaN — a NaN x/width is an
// indicator that silently disappears rather than an error anyone would see.
check("page: perPage 0 is treated as 1", page(3, 0),         { start: 3, index: 0 });
check("page: negative perPage",          page(3, -5),        { start: 3, index: 0 });
check("page: id 0 clamps to 1",          page(0, 5),         { start: 1, index: 0 });
check("page: undefined id",              page(undefined, 5), { start: 1, index: 0 });

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
