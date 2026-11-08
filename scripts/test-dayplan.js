// ── test-dayplan.js ───────────────────────────────────────────────────────────
// Regression tests for services/dayplan.js — the Calendar page's day strip.
//
//     bun scripts/test-dayplan.js          (or: node scripts/test-dayplan.js)
//
// Pure functions; loaded by stripping `.pragma library`, like the other test-*.js.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "dayplan.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const P = new Function(src + "\nreturn { dayBounds, layout, laneCount, nowFraction, status };")();

let pass = 0, fail = 0;
function eq(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    fail++;
    console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`);
}

const L = (h, mi = 0, d = 12) => new Date(2026, 9, d, h, mi).getTime();
const day = P.dayBounds(2026, 9, 12);
const ev = (summary, s, e, extra = {}) => Object.assign({ summary, start: s, end: e, allDay: false }, extra);
const round = (items) => items.map(i => ({ ...i, start: Math.round(i.start * 1000) / 1000, end: Math.round(i.end * 1000) / 1000 }));

// ── layout ────────────────────────────────────────────────────────────────────
eq("one event", round(P.layout([ev("a", L(12), L(18))], day.start, day.end)),
   [{ start: 0.5, end: 0.75, lane: 0, summary: "a", uid: "", source: "" }]);
eq("overlap goes to lane 1", P.layout([ev("a", L(9), L(11)), ev("b", L(10), L(12))], day.start, day.end).map(i => i.lane), [0, 1]);
eq("back to back share a lane", P.layout([ev("a", L(9), L(10)), ev("b", L(10), L(11))], day.start, day.end).map(i => i.lane), [0, 0]);
eq("a freed lane is reused", P.layout([ev("a", L(9), L(12)), ev("b", L(10), L(11)), ev("c", L(11, 30), L(13))], day.start, day.end).map(i => i.lane), [0, 1, 1]);
eq("lane cap", P.layout([ev("a", L(9), L(12)), ev("b", L(9), L(12)), ev("c", L(9), L(12))], day.start, day.end, 2).map(i => i.lane), [0, 1, 1]);
eq("all-day left out", P.layout([ev("h", L(0), L(0, 0, 13), { allDay: true })], day.start, day.end), []);
eq("clipped to the day", round(P.layout([ev("n", L(22), L(2, 0, 13))], day.start, day.end)).map(i => [i.start, i.end]), [[0.917, 1]]);
eq("starts before the day", round(P.layout([ev("n", L(22, 0, 11), L(2))], day.start, day.end)).map(i => [i.start, i.end]), [[0, 0.083]]);
eq("another day dropped", P.layout([ev("x", L(9, 0, 13), L(10, 0, 13))], day.start, day.end), []);
eq("zero length kept", P.layout([ev("p", L(9), L(9))], day.start, day.end).length, 1);
eq("sorted by start", P.layout([ev("b", L(15), L(16)), ev("a", L(9), L(10))], day.start, day.end).map(i => i.summary), ["a", "b"]);
eq("garbage tolerated", P.layout([null, undefined], day.start, day.end), []);
eq("lane count", P.laneCount(P.layout([ev("a", L(9), L(11)), ev("b", L(10), L(12))], day.start, day.end)), 2);
eq("lane count, none", P.laneCount([]), 1);
// A 25-hour day (clocks back): the fractions are against ITS length, so noon is not 0.5.
{
    const d = P.dayBounds(2026, 9, 25);          // Europe/London DST end; elsewhere an ordinary day
    const len = (d.end - d.start) / 3600000;
    const it = P.layout([ev("a", d.start, d.end)], d.start, d.end)[0];
    eq("whole day is 0..1 in a " + len + "h day", [it.start, it.end], [0, 1]);
}

// ── now ───────────────────────────────────────────────────────────────────────
eq("now at noon", Math.round(P.nowFraction(L(12), day.start, day.end) * 100) / 100, 0.5);
eq("now on another day", P.nowFraction(L(12, 0, 13), day.start, day.end), -1);
eq("now before", P.nowFraction(L(12, 0, 11), day.start, day.end), -1);

// ── free / busy ───────────────────────────────────────────────────────────────
eq("free until the next", P.status([ev("a", L(14), L(15))], L(10)), { busy: false, until: L(14) });
eq("busy until it ends", P.status([ev("a", L(9), L(11))], L(10)), { busy: true, until: L(11) });
eq("back-to-back chain", P.status([ev("a", L(9), L(10)), ev("b", L(10), L(11)), ev("c", L(11, 30), L(12))], L(9, 30)), { busy: true, until: L(11) });
eq("overlap chain", P.status([ev("a", L(9), L(11)), ev("b", L(10), L(12))], L(9, 30)), { busy: true, until: L(12) });
eq("free with nothing more", P.status([ev("a", L(9), L(10))], L(11)), { busy: false, until: null });
eq("free with nothing at all", P.status([], L(11)), { busy: false, until: null });
eq("all-day does not make you busy", P.status([ev("h", L(0), L(0, 0, 13), { allDay: true })], L(11)), { busy: false, until: null });
eq("an event ending exactly now is over", P.status([ev("a", L(9), L(10))], L(10)), { busy: false, until: null });
eq("garbage tolerated", P.status(null, L(10)), { busy: false, until: null });

console.log(`${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
