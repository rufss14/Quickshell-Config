// ── test-dayfacts.js ──────────────────────────────────────────────────────────
// Regression tests for services/dayfacts.js — ISO week, day of year, the moon.
//
//     bun scripts/test-dayfacts.js          (or: node scripts/test-dayfacts.js)
//
// Safe to run: pure arithmetic. Days are built with the LOCAL Date constructor;
// the moon checks use published UTC new/full moon times.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "dayfacts.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const F = new Function(src + "\nreturn { isoWeek, dayOfYear, daysInYear, daysLeft, moon };")();

let pass = 0, fail = 0;
function eq(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    fail++;
    console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`);
}
const near = (name, got, want, tol) => eq(name, Math.abs(got - want) <= tol, true);
const L = (y, m, d, h = 12) => new Date(y, m - 1, d, h).getTime();

// ── ISO week ──────────────────────────────────────────────────────────────────
eq("mid-September", F.isoWeek(L(2026, 9, 13)), 37);
eq("Thursday 1 Jan is week 1", F.isoWeek(L(2026, 1, 1)), 1);
eq("Friday 1 Jan belongs to week 53", F.isoWeek(L(2021, 1, 1)), 53);
eq("late December can be week 1", F.isoWeek(L(2024, 12, 30)), 1);
eq("Sunday ends the week", [F.isoWeek(L(2026, 9, 13)), F.isoWeek(L(2026, 9, 14))], [37, 38]);

// ── Day of year ───────────────────────────────────────────────────────────────
eq("day of year", F.dayOfYear(L(2026, 9, 13)), 256);
eq("first day", F.dayOfYear(L(2026, 1, 1)), 1);
eq("leap last day", F.dayOfYear(L(2024, 12, 31)), 366);
eq("days left", F.daysLeft(L(2026, 9, 13)), 109);
eq("leap years", [2024, 2026, 1900, 2000].map(F.daysInYear), [366, 365, 365, 366]);

// ── The moon ──────────────────────────────────────────────────────────────────
{
    const nm = F.moon(Date.UTC(2024, 0, 11, 11, 57));   // new moon
    near("new moon phase", Math.min(nm.phase, 1 - nm.phase), 0, 0.03);
    eq("new moon name", nm.name, "New moon");
    near("new moon dark", nm.illumination, 0, 0.02);

    const fm = F.moon(Date.UTC(2024, 0, 25, 17, 54));   // full moon
    near("full moon phase", fm.phase, 0.5, 0.03);
    eq("full moon name", fm.name, "Full moon");
    near("full moon lit", fm.illumination, 1, 0.02);

    const wax = F.moon(Date.UTC(2024, 0, 15, 12));      // four days after new
    eq("waxing crescent", [wax.name, wax.waxing], ["Waxing crescent", true]);
    const wan = F.moon(Date.UTC(2024, 1, 7, 12));       // three days before new
    eq("waning crescent", [wan.name, wan.waxing], ["Waning crescent", false]);
    eq("before the reference still works", F.moon(Date.UTC(1990, 0, 1)).phase >= 0, true);
}

console.log(`${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
