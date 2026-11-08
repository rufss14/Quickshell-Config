// ── test-quickadd.js ──────────────────────────────────────────────────────────
// Regression tests for services/quickadd.js — the clock panel's natural-language quick-add.
//
//     bun scripts/test-quickadd.js          (or: node scripts/test-quickadd.js)
//
// Every date is built with the LOCAL Date constructor, so the suite passes in any timezone.
// "Now" is fixed: Monday 12 October 2026, 10:00.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "quickadd.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const Q = new Function(src + "\nreturn { parse, describe };")();

let pass = 0, fail = 0;
function eq(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    fail++;
    console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`);
}

const L = (mo, d, h = 0, mi = 0, y = 2026) => new Date(y, mo - 1, d, h, mi).getTime();
const NOW = L(10, 12, 10, 0);                  // Monday
const p = (t, now = NOW) => Q.parse(t, now);
const when = (t) => { const r = p(t); return [r.summary, r.start, r.end, r.allDay]; };

// ── days ──────────────────────────────────────────────────────────────────────
eq("tomorrow + time", when("dentist tomorrow 9am"), ["dentist", L(10, 13, 9), L(10, 13, 10), false]);
eq("order does not matter", when("tomorrow at 9am dentist"), ["dentist", L(10, 13, 9), L(10, 13, 10), false]);
eq("tmrw", p("call mum tmrw 18:30").start, L(10, 13, 18, 30));
eq("today later", p("gym today 5pm").start, L(10, 12, 17));
eq("tonight defaults to 20:00", p("film tonight").start, L(10, 12, 20));
eq("tonight with a time", p("film tonight 9pm").start, L(10, 12, 21));
eq("weekday", p("standup friday 9:30").start, L(10, 16, 9, 30));
eq("weekday abbreviation", p("lunch fri 12:30").start, L(10, 16, 12, 30));
eq("today's weekday is next week", p("review monday 11:00").start, L(10, 19, 11));
eq("next weekday", p("party next sat 8pm").start, L(10, 17, 20));
eq("on a weekday", p("lunch on thursday at noon").start, L(10, 15, 12));
eq("in N days", p("renew passport in 3 days").start, L(10, 15));
eq("in N weeks", p("follow up in 2 weeks").start, L(10, 26));
eq("12 oct", p("meet Sam 20 oct 3pm").start, L(10, 20, 15));
eq("oct 12", p("meet Sam oct 20 3pm").start, L(10, 20, 15));
eq("ordinal and of", p("trip 3rd of november").start, L(11, 3));
eq("a past date this year is next year's", p("birthday 5 mar").start, L(3, 5, 0, 0, 2027));
eq("today's date is today", p("x 12 oct 11am").start, L(10, 12, 11));
eq("explicit year", p("conf 5 mar 2028").start, L(3, 5, 0, 0, 2028));
eq("d/m", p("dentist 15/11 10:00").start, L(11, 15, 10));
eq("d/m/y", p("dentist 15/11/27 10:00").start, L(11, 15, 10, 0, 2027));
eq("iso date", p("launch 2027-01-09 14:00").start, L(1, 9, 14, 0, 2027));
eq("31 feb is not a date", p("thing 31 feb").hasDate, false);

// ── times ─────────────────────────────────────────────────────────────────────
eq("am/pm with minutes", p("tea tomorrow 4:15pm").start, L(10, 13, 16, 15));
eq("12am is midnight", p("x tomorrow 12am").start, L(10, 13, 0));
eq("12pm is noon", p("x tomorrow 12pm").start, L(10, 13, 12));
eq("noon", p("lunch tomorrow noon").start, L(10, 13, 12));
eq("midnight", p("x tomorrow midnight").start, L(10, 13, 0));
eq("at 9", p("x tomorrow at 9").start, L(10, 13, 9));
eq("at 3 reads as the afternoon", p("x tomorrow at 3").start, L(10, 13, 15));
eq("24h", p("x tomorrow 21:45").start, L(10, 13, 21, 45));
eq("a time alone, still ahead, is today", p("call at 5pm").start, L(10, 12, 17));
eq("a time alone, already past, is tomorrow", p("call at 8am").start, L(10, 13, 8));
eq("a time exactly now is tomorrow", p("call 10:00").start, L(10, 13, 10));

// ── lengths ───────────────────────────────────────────────────────────────────
eq("range with suffixes", when("workshop tomorrow 9am-10:30am"), ["workshop", L(10, 13, 9), L(10, 13, 10, 30), false]);
eq("24 h range", p("x tomorrow 9:00-17:00").end, L(10, 13, 17));
eq("from to", when("class tomorrow from 9 to 10"), ["class", L(10, 13, 9), L(10, 13, 10), false]);
eq("one suffix covers both", p("x tomorrow from 9 to 10pm").start, L(10, 13, 21));
eq("11-1pm is 11am", p("x tomorrow from 11 to 1pm").start, L(10, 13, 11));
eq("across midnight", p("x tomorrow 22:00-01:00").end, L(10, 14, 1));
eq("for 2h", p("x tomorrow 9am for 2h").end, L(10, 13, 11));
eq("for 90 min", p("x tomorrow 9am for 90 min").end, L(10, 13, 10, 30));
eq("a bare range is not a time", when("meeting 9-10"), ["meeting 9-10", null, null, false]);
eq("all day", when("conference friday all day"), ["conference", L(10, 16), L(10, 17), true]);
eq("a day alone is all day", p("holiday friday").allDay, true);
eq("default length is an hour", p("x tomorrow 9am").end - p("x tomorrow 9am").start, 3600000);

// ── in N minutes ──────────────────────────────────────────────────────────────
eq("in 20 min", [p("tea in 20 min").summary, p("tea in 20 min").start, p("tea in 20 min").relative], ["tea", NOW + 20 * 60000, true]);
eq("in 2 hours", p("call in 2 hours").start, NOW + 2 * 3600000);

// ── repeat ────────────────────────────────────────────────────────────────────
eq("every monday", [p("gym every monday 7am").repeat, p("gym every monday 7am").start], ["WEEKLY", L(10, 19, 7)]);
eq("every day", p("meds every day 8am").repeat, "DAILY");
eq("daily", [p("meds daily 8am").summary, p("meds daily 8am").repeat], ["meds", "DAILY"]);
eq("monthly alone is all day, from today", [p("pay rent monthly").repeat, p("pay rent monthly").start, p("pay rent monthly").allDay], ["MONTHLY", L(10, 12), true]);
eq("every year", p("birthday 5 mar every year").repeat, "YEARLY");

// ── titles ────────────────────────────────────────────────────────────────────
eq("plain text is only a title", p("buy milk"), { ok: true, summary: "buy milk", hasDate: false, hasTime: false, allDay: false, start: null, end: null, repeat: "", relative: false });
eq("a bare number is not a time", p("table for 2").hasTime, false);
eq("room number", p("room 101 tomorrow").summary, "room 101");
eq("words keep their order", p("lunch with Sam at the cafe tomorrow 12:30").summary, "lunch with Sam at the cafe");
eq("a stranded connective goes", p("lunch with Sam on friday").summary, "lunch with Sam");
eq("nothing left is not ok", p("tomorrow 9am").ok, false);
eq("empty", p("").ok, false);
eq("undefined", p(undefined).ok, false);
eq("a month word that is a name", p("may i 3 things").hasDate, false);
eq("march as a verb, no number", p("march with the band").hasDate, false);
eq("sat as a word with a number", p("sat 5 people down").hasDate, true);   // read as Saturday — documented ambiguity

// ── describe ──────────────────────────────────────────────────────────────────
eq("describe tomorrow", Q.describe(p("dentist tomorrow 9am"), NOW), "Tomorrow, 09:00–10:00");
eq("describe far", Q.describe(p("x 20 oct 3pm"), NOW), "Tue 20 Oct, 15:00–16:00");
eq("describe all day", Q.describe(p("x friday"), NOW), "Fri 16 Oct (all day)");
eq("describe in", Q.describe(p("tea in 20 min"), NOW), "in 20 min · 10:20");
eq("describe repeat", Q.describe(p("gym every monday 7am"), NOW), "Mon 19 Oct, 07:00–08:00 · every week");
eq("describe nothing", Q.describe(p("buy milk"), NOW), "");

console.log(`${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
