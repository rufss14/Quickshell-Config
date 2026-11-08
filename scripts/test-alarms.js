// ── test-alarms.js ────────────────────────────────────────────────────────────
// Regression tests for services/alarms.js. `bun scripts/test-alarms.js` (any TZ; the dates are
// built with the LOCAL constructor). "Now" is Monday 12 October 2026, 10:00.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "alarms.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const A = new Function(src + "\nreturn { nextOccurrence, nextPreset, repeatLabel, cleanMask, WEEKDAYS, WEEKENDS, EVERY_DAY };")();

let pass = 0, fail = 0;
function eq(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    fail++;
    console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`);
}
const L = (mo, d, h = 0, mi = 0) => new Date(2026, mo - 1, d, h, mi).getTime();
const NOW = L(10, 12, 10, 0);                  // Monday

eq("once, later today", A.nextOccurrence(11, 30, 0, NOW), L(10, 12, 11, 30));
eq("once, already past is tomorrow", A.nextOccurrence(9, 0, 0, NOW), L(10, 13, 9, 0));
eq("exactly now is tomorrow", A.nextOccurrence(10, 0, 0, NOW), L(10, 13, 10, 0));
eq("every day", A.nextOccurrence(11, 0, A.EVERY_DAY, NOW), L(10, 12, 11, 0));
eq("weekdays on a weekday", A.nextOccurrence(7, 0, A.WEEKDAYS, NOW), L(10, 13, 7, 0));
eq("weekdays from a Friday evening skips the weekend", A.nextOccurrence(7, 0, A.WEEKDAYS, L(10, 16, 20, 0)), L(10, 19, 7, 0));
eq("weekends from Monday", A.nextOccurrence(9, 0, A.WEEKENDS, NOW), L(10, 17, 9, 0));
eq("a single day: Wednesday", A.nextOccurrence(8, 0, 1 << 3, NOW), L(10, 14, 8, 0));
eq("the same weekday, already past, is next week", A.nextOccurrence(8, 0, 1 << 1, NOW), L(10, 19, 8, 0));
eq("garbage mask", Number.isNaN(A.nextOccurrence(8, 0, 1 << 9, NOW)), true);
eq("preset cycle", [0, A.WEEKDAYS, A.EVERY_DAY, A.WEEKENDS, 0].map((m, i, a) => i < 4 ? A.nextPreset(m) : null).slice(0, 4), [A.WEEKDAYS, A.EVERY_DAY, A.WEEKENDS, 0]);
eq("an odd mask goes to the first preset", A.nextPreset(5), 0);
eq("labels", [0, A.EVERY_DAY, A.WEEKDAYS, A.WEEKENDS, (1 << 1) | (1 << 3) | (1 << 5), 1 << 0].map(A.repeatLabel),
   ["Once", "Every day", "Weekdays", "Weekends", "Mon Wed Fri", "Sun"]);
eq("clean mask", [A.cleanMask(5), A.cleanMask(0), A.cleanMask(-1), A.cleanMask(200), A.cleanMask(1.5), A.cleanMask("3"), A.cleanMask(undefined)], [5, 0, 0, 0, 0, 0, 0]);

console.log(`${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
