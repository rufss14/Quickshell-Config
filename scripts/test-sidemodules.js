// ── test-sidemodules.js ───────────────────────────────────────────────────────
// Regression tests for services/sidemodules.js, the small sidebar modules' cell
// counts and the colour picker's history rules.
//
//     bun scripts/test-sidemodules.js          (or: node scripts/test-sidemodules.js)
//
// Safe to run: pure functions, touches nothing. Loaded by stripping the
// `.pragma library` line and evaluating the rest, so the tests run the real file.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "sidemodules.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const S = new Function(src + `
    return { MAX_FACES, MAX_SWATCHES, HISTORY, voiceLayout, stackCells, windowCells, parseHex, remember, clean,
             forget, colourCells, MAX_STATS, statsCells, innerRuns };`)();

let pass = 0;
const failures = [];
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    failures.push(`  ${name}\n      want ${w}\n      got  ${g}`);
}

// ── Voice ─────────────────────────────────────────────────────────────────────
check("voice: out of a call, the mic alone", S.voiceLayout(false, 5), { faces: 0, more: 0, stack: 0, cells: 1 });
check("voice: alone in a call, mute and deafen", S.voiceLayout(true, 0), { faces: 0, more: 0, stack: 0, cells: 2 });
check("voice: one face, a cell of stack", S.voiceLayout(true, 1), { faces: 1, more: 0, stack: 1, cells: 3 });
check("voice: two faces share one cell", S.voiceLayout(true, 2), { faces: 2, more: 0, stack: 2, cells: 3 });
check("voice: exactly the cap, no +n, half a cell more", S.voiceLayout(true, 3), { faces: 3, more: 0, stack: 3, cells: 3.5 });
check("voice: past the cap, the last face is +n", S.voiceLayout(true, 7), { faces: 2, more: 5, stack: 3, cells: 3.5 });
check("voice: the cap is a parameter", S.voiceLayout(true, 4, 5), { faces: 4, more: 0, stack: 4, cells: 4 });
check("voice: nonsense counts are none", S.voiceLayout(true, undefined), { faces: 0, more: 0, stack: 0, cells: 2 });
check("voice: stack of none is no cells", S.stackCells(0), 0);
check("voice: stack of nonsense is none", S.stackCells(undefined), 0);

// ── The focused window ────────────────────────────────────────────────────────
check("window: an app not on the dock shows", S.windowCells(true, false, false), 1);
check("window: an app on the dock steps aside", S.windowCells(true, true, false), 0);
check("window: an empty workspace steps aside", S.windowCells(false, false, false), 0);
check("window: arranging always shows", S.windowCells(false, true, true), 1);

// ── The colour picker: what counts as a colour ────────────────────────────────
check("hex: hyprpicker's own output", S.parseHex("#1E1E2E\n"), "#1e1e2e");
check("hex: without the hash", S.parseHex("a0b1c2"), "#a0b1c2");
check("hex: cancelled prints nothing", S.parseHex(""), "");
check("hex: rgb() is not hex", S.parseHex("rgb(1, 2, 3)"), "");
check("hex: short form refused", S.parseHex("#fff"), "");
check("hex: anything around it refused", S.parseHex("#123456; rm -rf /"), "");
check("hex: null", S.parseHex(null), "");

// ── History ───────────────────────────────────────────────────────────────────
check("remember: newest first", S.remember(["#111111"], "#222222"), ["#222222", "#111111"]);
check("remember: a repeat moves to the front", S.remember(["#111111", "#222222"], "#222222"), ["#222222", "#111111"]);
check("remember: capped, the oldest goes", S.remember(["#111111", "#222222"], "#333333", 2), ["#333333", "#111111"]);
check("remember: junk in the list is dropped", S.remember(["#111111", "nope", 7], "#222222"), ["#222222", "#111111"]);
check("remember: a non-colour isn't added", S.remember(["#111111"], "blue"), ["#111111"]);
check("clean: a hand-edited file", S.clean(["#AAAAAA", "#aaaaaa", "x", "bbbbbb"]), ["#aaaaaa", "#bbbbbb"]);
check("clean: not a list", S.clean({ a: 1 }), []);
check("forget: takes one off", S.forget(["#111111", "#222222"], "#111111"), ["#222222"]);
check("cells: the pick cell alone", S.colourCells(0), 1);
check("cells: a swatch per colour", S.colourCells(3), 4);
check("cells: swatches capped", S.colourCells(9), 1 + S.MAX_SWATCHES);

// ── The stats ─────────────────────────────────────────────────────────────────
check("stats: a ring per metric", S.statsCells(3), 3);
check("stats: capped", S.statsCells(9), S.MAX_STATS);
check("stats: nothing readable is still one cell", S.statsCells(0), 1);
check("stats: nonsense is one cell", S.statsCells(undefined), 1);

// ── innerRuns: the sidebar pill split round modules without one ───────────────
// Three cells of 40 with a 4 gap, padded 6 at each end of a 136 pill.
const M = on => [{ at: 6, len: 40, on: on[0] }, { at: 50, len: 40, on: on[1] }, { at: 94, len: 40, on: on[2] }];
check("innerRuns: all on is the whole pill", S.innerRuns(M([true, true, true]), 140), [{ from: 0, to: 140 }]);
check("innerRuns: all off is none", S.innerRuns(M([false, false, false]), 140), []);
check("innerRuns: middle off splits in two, padded, not into it",
      S.innerRuns(M([true, false, true]), 140), [{ from: 0, to: 50 }, { from: 90, to: 140 }]);
check("innerRuns: first off: one piece from its end",
      S.innerRuns(M([false, true, true]), 140), [{ from: 46, to: 140 }]);
check("innerRuns: last off: one piece to its start",
      S.innerRuns(M([true, true, false]), 140), [{ from: 0, to: 94 }]);
check("innerRuns: nothing is none", S.innerRuns(undefined, 10), []);

const total = pass + failures.length;
console.log(`${pass}/${total} passed`);
if (failures.length > 0) {
    console.log("\nFAILED:");
    console.log(failures.join("\n"));
    process.exit(1);
}
