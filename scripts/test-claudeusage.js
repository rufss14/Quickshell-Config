// ── test-claudeusage.js ───────────────────────────────────────────────────────
// Regression tests for services/claudeusage.js, how the Claude panel words the rate limit.
//
//     bun scripts/test-claudeusage.js          (or: node scripts/test-claudeusage.js)
//
// Safe to run: pure functions, no I/O. The case that matters is the window that has
// RESET since the figures were saved: it must read as empty, never as its old percentage.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "claudeusage.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const U = new Function(src + `\nreturn { span, clock, limit, stale };`)();

let pass = 0, fail = 0;
function eq(name, got, want) {
    if (JSON.stringify(got) === JSON.stringify(want)) pass++;
    else { fail++; console.log(`FAIL ${name}\n  got:  ${JSON.stringify(got)}\n  want: ${JSON.stringify(want)}`); }
}

const MIN = 60000, HOUR = 60 * MIN, DAY = 24 * HOUR;
// A local-time anchor, so "13:40" doesn't depend on the machine's zone.
const NOW = new Date(2026, 9, 3, 11, 0, 0).getTime();            // Sat 3 Oct 2026, 11:00 local
const sec = (ms) => Math.round(ms / 1000);

// span
eq("under a minute", U.span(20000), "under a minute");
eq("minutes", U.span(42 * MIN), "42m");
eq("exact hour", U.span(2 * HOUR), "2h");
eq("hours and minutes", U.span(2 * HOUR + 14 * MIN), "2h 14m");
eq("rounds to the nearest minute", U.span(91 * 1000), "2m");
eq("still hours at 47h", U.span(47 * HOUR), "47h");
eq("days", U.span(3 * DAY + 4 * HOUR), "3d 4h");
eq("whole days", U.span(2 * DAY), "2d");

// clock
eq("today", U.clock(NOW + 2 * HOUR + 40 * MIN, NOW), "13:40");
eq("zero-padded", U.clock(NOW + 5 * HOUR + 5 * MIN, NOW), "16:05");
eq("tomorrow-ish names the day", U.clock(NOW + 30 * HOUR, NOW), "Sun 17:00");
eq("a week out names the day", U.clock(NOW + 4 * DAY, NOW), "Wed 11:00");

// window
const w = U.limit({ pct: 83.4, resetsAt: sec(NOW + 2 * HOUR + 14 * MIN) }, NOW);
eq("window pct rounds", w.pct, 83);
eq("window ratio", Math.round(w.ratio * 1000), 834);
eq("window left", w.left, "2h 14m");
eq("window when", w.when, "13:14");
eq("window not reset", w.reset, false);
const old = U.limit({ pct: 83, resetsAt: sec(NOW - MIN) }, NOW);
eq("a window past its reset reads empty", [old.reset, old.pct, old.ratio], [true, 0, 0]);
eq("reset exactly now", U.limit({ pct: 50, resetsAt: sec(NOW) }, NOW).reset, true);
eq("over 100 is clamped", U.limit({ pct: 140, resetsAt: sec(NOW + HOUR) }, NOW).pct, 100);
eq("negative is clamped", U.limit({ pct: -3, resetsAt: sec(NOW + HOUR) }, NOW).pct, 0);
eq("no window", U.limit(null, NOW), null);
eq("garbage window", U.limit({ pct: "a", resetsAt: 1 }, NOW), null);

// stale
eq("fresh says nothing", U.stale(NOW - 5 * MIN, NOW), "");
eq("old says how old", U.stale(NOW - 3 * HOUR, NOW), "3h ago");
eq("never seen says nothing", U.stale(0, NOW), "");

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
