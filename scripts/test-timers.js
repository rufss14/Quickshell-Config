// ── test-timers.js ────────────────────────────────────────────────────────────
// services/timers.js — the focus cycle, stopwatch laps, extending a countdown.
//
//     bun scripts/test-timers.js          (or: node scripts/test-timers.js)
//
// Safe: pure functions. Loaded by stripping the `.pragma library` line, as test-clips.js does.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "timers.js"), "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "");
const T = new Function(src + "\nreturn { pomoClean, pomoNext, pomoStart, pomoSession, pomoNotice, lapSplits, lapExtremes, lapsText, extend, endsAt, POMO_DEFAULTS };")();

let pass = 0, fail = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) pass++;
    else { fail++; console.log(`  FAIL  ${name}\n          got  ${g}\n          want ${w}`); }
}

// ── the focus cycle ──
const cfg = { focus: 25, short: 5, long: 15, every: 4 };
check("start: focus first", T.pomoStart(cfg), { phase: "focus", cycle: 0, seconds: 1500, label: "Focus" });
check("after focus: a short break", T.pomoNext("focus", 0, cfg), { phase: "short", cycle: 1, seconds: 300, label: "Short break" });
check("after a short break: focus", T.pomoNext("short", 1, cfg), { phase: "focus", cycle: 1, seconds: 1500, label: "Focus" });
check("the 4th focus session earns the long break", T.pomoNext("focus", 3, cfg), { phase: "long", cycle: 4, seconds: 900, label: "Long break" });
check("after the long break: focus, and the round restarts", T.pomoNext("long", 4, cfg).phase, "focus");
// Run a whole day: the long break lands exactly every 4th.
let ph = "focus", cy = 0; const seq = [];
for (let i = 0; i < 16; i++) { const n = T.pomoNext(ph, cy, cfg); seq.push(n.phase); ph = n.phase; cy = n.cycle; }
check("a long round, in order", seq.join(","), "short,focus,short,focus,short,focus,long,focus,short,focus,short,focus,short,focus,long,focus");
check("every = 2 means a long break every other session", T.pomoNext("focus", 1, { ...cfg, every: 2 }).phase, "long");
check("clean: defaults", T.pomoClean(null), T.POMO_DEFAULTS);
check("clean: clamps", T.pomoClean({ focus: 0, short: 999, long: -3, every: 99 }), { focus: 1, short: 60, long: 1, every: 8 });
check("clean: junk falls back", T.pomoClean({ focus: "x", short: NaN }), { focus: 25, short: 5, long: 15, every: 4 });
check("a clamped config drives the plan", T.pomoNext("focus", 0, { focus: 1, short: 999 }).seconds, 3600);
check("session: during focus it is the next one", T.pomoSession("focus", 0, 4), 1);
check("session: the 3rd focus", T.pomoSession("focus", 2, 4), 3);
check("session: in a break it is the one just done", T.pomoSession("short", 2, 4), 2);
check("session: in the long break it is the last of the round", T.pomoSession("long", 4, 4), 4);
check("notice: break", T.pomoNotice(T.pomoNext("focus", 0, cfg)), { title: "Short break", body: "Focus session done — 5 minutes off." });
check("notice: back to focus", T.pomoNotice(T.pomoNext("short", 1, cfg)), { title: "Back to focus", body: "Break over — 25 minutes." });

// ── laps ──
const laps = [5000, 3000, 1000];                        // newest first: splits 2000, 2000, 1000
check("splits", T.lapSplits(laps), [2000, 2000, 1000]);
check("splits: none", T.lapSplits([]), []);
check("splits: junk", T.lapSplits(null), []);
// splits of [7000,4000,1000] are 3000, 3000, 1000: the fastest is the oldest lap, the slowest the first of the ties.
check("extremes: fastest and slowest", T.lapExtremes([7000, 4000, 1000]), { best: 2, worst: 0 });
check("extremes: one lap says nothing", T.lapExtremes([5000]), { best: -1, worst: -1 });
check("extremes: equal laps say nothing", T.lapExtremes([4000, 2000]), { best: -1, worst: -1 });
// splits 4000, 1000, 4000, 1000: best = the first minimum, worst = the first maximum.
check("extremes: ties take the first", T.lapExtremes([10000, 6000, 5000, 1000]), { best: 1, worst: 0 });
check("text: oldest first", T.lapsText([5000, 3000, 1000], ms => (ms / 1000) + "s"), "Lap 1  1s  +1s\nLap 2  3s  +2s\nLap 3  5s  +2s");
check("text: none", T.lapsText([], ms => ms), "");

// ── extending ──
check("extend: both grow", T.extend(300, 120, 60), { span: 360, remain: 180 });
check("extend: nothing negative", T.extend(300, 120, -60), { span: 300, remain: 120 });
check("extend: junk", T.extend("x", null, 60), { span: 60, remain: 60 });

// ── ends at ──
const noon = new Date(2026, 9, 18, 12, 0, 0).getTime();
check("ends: today", T.endsAt(noon, 90 * 60), "Ends 13:30");
check("ends: zero is now", T.endsAt(noon, 0), "Ends 12:00");
check("ends: past midnight says tomorrow", T.endsAt(new Date(2026, 9, 18, 23, 30).getTime(), 3600), "Ends tomorrow 00:30");
check("ends: junk remain", T.endsAt(noon, null), "Ends 12:00");

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail > 0 ? 1 : 0);
