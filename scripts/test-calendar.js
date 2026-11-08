// ── test-calendar.js ──────────────────────────────────────────────────────────
// Regression tests for services/calendar.js (the Calendar tile's week numbers, year
// progress and "in N days").
//
//     bun scripts/test-calendar.js
//
// Pure functions, touches nothing. The week-number cases are the ones that go wrong:
// the year boundaries, where ISO week 1 can start in the previous December and week
// 52/53 can run into January. Loaded by stripping `.pragma library`, as test-calc.js
// does, so it runs the real file.
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "calendar.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const C = new Function(src + "\nreturn { daysBetween, daysInYear, dayOfYear, isoWeek, relative, nextDate };")();

const d = (y, m, day) => new Date(y, m - 1, day);
let pass = 0, fail = 0;
const eq = (name, got, want) => {
    if (got === want) pass++;
    else { fail++; console.log(`FAIL ${name}: got ${got}, want ${want}`); }
};

// ISO weeks — known values from the standard.
eq("2026-01-01 is W1",      C.isoWeek(d(2026, 1, 1)), 1);
eq("2021-01-03 is W53",     C.isoWeek(d(2021, 1, 3)), 53);   // Sunday of 2020's last week
eq("2020-12-31 is W53",     C.isoWeek(d(2020, 12, 31)), 53);
eq("2024-12-30 is W1",      C.isoWeek(d(2024, 12, 30)), 1);  // belongs to 2025's week 1
eq("2026-10-09 is W41",     C.isoWeek(d(2026, 10, 9)), 41);
eq("2016-01-03 is W53",     C.isoWeek(d(2016, 1, 3)), 53);
eq("2026-06-15 is W25",     C.isoWeek(d(2026, 6, 15)), 25);

// Year progress.
eq("2026-01-01 day 1",      C.dayOfYear(d(2026, 1, 1)), 1);
eq("2026-12-31 day 365",    C.dayOfYear(d(2026, 12, 31)), 365);
eq("2024-03-01 day 61",     C.dayOfYear(d(2024, 3, 1)), 61);   // leap year
eq("2024 has 366",          C.daysInYear(2024), 366);
eq("2100 has 365",          C.daysInYear(2100), 365);          // century, not leap
eq("2000 has 366",          C.daysInYear(2000), 366);

// Day differences — across both daylight-saving changes of a northern year, where a
// raw Date subtraction is 23 or 25 hours.
eq("across spring DST",     C.daysBetween(d(2026, 3, 28), d(2026, 3, 30)), 2);
eq("across autumn DST",     C.daysBetween(d(2026, 10, 24), d(2026, 10, 26)), 2);
eq("negative",              C.daysBetween(d(2026, 10, 9), d(2026, 10, 4)), -5);
eq("across a year",         C.daysBetween(d(2026, 12, 31), d(2027, 1, 1)), 1);

// Wording.
eq("today",                 C.relative(0), "Today");
eq("tomorrow",              C.relative(1), "Tomorrow");
eq("yesterday",             C.relative(-1), "Yesterday");
eq("future",                C.relative(5), "in 5 days");
eq("past",                  C.relative(-3), "3 days ago");

// Countdown targets.
const now = d(2026, 10, 9);
const ymd = x => x === null ? null : `${x.getFullYear()}-${x.getMonth() + 1}-${x.getDate()}`;
eq("fixed date",            ymd(C.nextDate("2026-12-25", false, now)), "2026-12-25");
eq("fixed date in past",    ymd(C.nextDate("2025-03-01", false, now)), "2025-3-1");   // not rolled
eq("recurring, later",      ymd(C.nextDate("1990-12-25", true, now)), "2026-12-25");
eq("recurring, passed",     ymd(C.nextDate("1990-03-01", true, now)), "2027-3-1");
eq("recurring, today",      ymd(C.nextDate("1990-10-09", true, now)), "2026-10-9");   // today counts
eq("not a date",            C.nextDate("soon", false, now), null);
eq("empty",                 C.nextDate("", false, now), null);

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
