// ── test-island.js ────────────────────────────────────────────────────────────
// services/island.js — the island card's pages (which, in what order), what the live handle shows, the clock's digits, the card's tabs, the recording timer on the handle, where the handle sits, the month grid, the agenda.
//
//     bun scripts/test-island.js          (or: node scripts/test-island.js)
//
// Safe: pure functions.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "island.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const I = new Function(src + "\nreturn { switchPage, loadTone, TABS, TAB_IDS, tabMeta, pagesOf, stepTab, subject, pageFor, clockText, scaleOf, tabOf, elapsed, alignedX, placeX, monthCells, weekdays, bodyFor, BODY, tabOf, agenda, scaled, forecastDay, isoTime, spanOf, greeting, weatherKind, weatherShape, isTwelveHour, rangeBar };")();

let passed = 0, failed = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) passed++;
    else { failed++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`); }
}

check("four tabs", I.TABS.map(t => t.value), ["today", "media", "system", "weather"]);
check("every tab has a label and an icon", I.TABS.every(t => t.label !== "" && t.icon !== ""), true);
check("a known tab stays", I.tabOf("media"), "media");
check("the weather tab is known", I.tabOf("weather"), "weather");
check("an unknown tab is the first", I.tabOf("clock"), "today");
check("nothing is the first", I.tabOf(undefined), "today");



check("elapsed under a minute", I.elapsed(9), "0:09");
check("elapsed minutes", I.elapsed(65), "1:05");
check("elapsed hours", I.elapsed(3723), "1:02:03");
check("elapsed pads minutes only with hours", I.elapsed(600), "10:00");
check("elapsed negative or junk", I.elapsed(-5) + I.elapsed("x"), "0:000:00");
check("elapsed fractional seconds floor", I.elapsed(59.9), "0:59");


check("centre", I.alignedX("centre", 100, 700, 16), 300);
check("left", I.alignedX("left", 100, 700, 16), 16);
check("right", I.alignedX("right", 100, 700, 16), 584);
check("wider than the window on the right: kept at the margin", I.alignedX("right", 900, 700, 16), 16);
check("unknown align is the centre", I.alignedX("x", 100, 700, 16), 300);

check("placeX centre, no sidebars", I.placeX("centre", 100, 700, 16, 0, 0), 300);
check("placeX left keeps off a left sidebar's face", I.placeX("left", 100, 700, 16, 80, 0), 80);
check("placeX right keeps off a right sidebar's face", I.placeX("right", 100, 700, 16, 0, 80), 520);
check("placeX centre pushed off a face", I.placeX("centre", 100, 400, 16, 200, 0), 200);
check("placeX wider than the room is held at the low bound", I.placeX("right", 900, 700, 16, 0, 0), 16);

const nov = I.monthCells(2026, 10, 1, { y: 2026, m: 10, d: 12 });   // November 2026 starts on a Sunday; Monday first
check("grid is six weeks", nov.length, 42);
check("Monday-first: Nov 1 (Sunday) is the last cell of week one", nov[6].d + "/" + nov[6].off, "1/0");
check("Monday-first: the cells before it are October", nov.slice(0, 6).map(c => c.d + "/" + c.off), ["26/-1", "27/-1", "28/-1", "29/-1", "30/-1", "31/-1"]);
check("today is marked once", nov.filter(c => c.today).map(c => c.d), [12]);
check("the tail is December", nov[41].m + "/" + nov[41].off, "11/1");
const sunFirst = I.monthCells(2026, 10, 0, null);
check("Sunday-first: Nov 1 is the first cell", sunFirst[0].d + "/" + sunFirst[0].off, "1/0");
check("firstDow 7 means Sunday", I.monthCells(2026, 10, 7, null)[0].d, 1);
check("no today given: none marked", sunFirst.some(c => c.today), false);
check("weekend flags", nov[5].weekend + "," + nov[6].weekend + "," + nov[7].weekend, "true,true,false");
check("year rolls over", I.monthCells(2026, 11, 1, null)[41].y, 2027);
check("January grid starts in the old year", I.monthCells(2027, 0, 1, null)[0].y, 2026);
check("weekdays Monday-first", I.weekdays(1), [1, 2, 3, 4, 5, 6, 0]);
check("weekdays Sunday-first", I.weekdays(7), [0, 1, 2, 3, 4, 5, 6]);
check("a bad tab falls back to the first", I.tabOf("nope"), "today");
check("a tab hands over at the larger size", I.bodyFor("media", "weather"), { w: 780, h: 412 });
check("every tab is as wide as the others", new Set(I.TABS.map(t => I.BODY[t.value].w)).size, 1);
check("same tab is its own size", I.bodyFor("media", "media"), I.BODY.media);
check("every tab has a size", I.TABS.every(t => I.BODY[t.value] !== undefined), true);

const T = 1000000;
const evs = [
    { summary: "past",  start: T - 3600000, end: T - 1800000, allDay: false },
    { summary: "later", start: T + 7200000, end: T + 9000000, allDay: false },
    { summary: "now",   start: T - 600000,  end: T + 600000,  allDay: false },
    { summary: "day",   start: T - 40000000, end: T + 40000000, allDay: true },
    { summary: "soon",  start: T + 1800000, end: T + 3600000, allDay: false }
];
check("agenda: all-day first, the live one, then by start; the past is gone", I.agenda(evs, T, 9).map(e => e.summary), ["day", "now", "soon", "later"]);
check("agenda: live flag", I.agenda(evs, T, 9).map(e => e.live), [false, true, false, false]);
check("agenda: capped", I.agenda(evs, T, 2).length, 2);
check("agenda: empty and junk", I.agenda(null, T, 3).length + I.agenda([null], T, 3).length, 0);
check("agenda: a zero-length event at this instant is live", I.agenda([{ summary: "x", start: T, end: T, allDay: false }], T, 3)[0].live, true);

check("scaled: against its own peak", I.scaled([0, 50, 100], 10), [0, 0.5, 1]);
check("scaled: a quiet line stays low", I.scaled([1, 2, 4], 100), [0.01, 0.02, 0.04]);
check("scaled: junk and negatives", I.scaled([-5, "x", null, 10], 10), [0, 0, 0, 1]);
check("scaled: not a list", I.scaled(null, 10), []);

const DN = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], MN = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
check("forecast today", I.forecastDay("2026-11-12", "2026-11-12", DN, MN), { name: "Today", date: "Nov 12", today: true });
check("forecast tomorrow", I.forecastDay("2026-11-13", "2026-11-12", DN, MN), { name: "Fri", date: "Nov 13", today: false });
check("forecast junk", I.forecastDay("x", "2026-11-12", DN, MN).name, "");
check("iso time", I.isoTime("2026-11-12T07:18"), { h: 7, m: 18 });
check("iso time junk", I.isoTime(""), null);

check("spanOf fills the range with headroom", I.spanOf([10, 20, 15], 0.1).norm.map(v => Math.round(v * 100) / 100), [0.1, 0.9, 0.5]);
check("spanOf low and high", [I.spanOf([10, 20, 15], 0).lo, I.spanOf([10, 20, 15], 0).hi], [10, 20]);
check("spanOf flat is the middle", I.spanOf([7, 7, 7], 0.1).norm, [0.5, 0.5, 0.5]);
check("spanOf empty", I.spanOf(null, 0.1), { norm: [], lo: 0, hi: 0 });
check("greeting by the hour", [4, 5, 11, 12, 17, 18, 21, 22].map(I.greeting), ["Good night", "Good morning", "Good morning", "Good afternoon", "Good afternoon", "Good evening", "Good evening", "Good night"]);

check("weather kinds", [0, 2, 45, 61, 73, 95, 80, 10].map(c => I.weatherKind(c, true)), ["clear", "cloud", "fog", "rain", "snow", "storm", "rain", "cloud"]);

check("weather shapes", ["clear", "cloud", "fog", "rain", "snow", "storm", "?"].map(I.weatherShape), ["sunny", "cookie9", "squircle", "clover", "hexagon", "burst", "cookie9"]);

check("12-hour formats", ["h:mm AP", "hh:mm:ss a", "h:mm ap"].map(I.isTwelveHour), [true, true, true]);
check("24-hour formats", ["HH:mm", "HH:mm:ss", "H:mm 'o''clock'"].map(I.isTwelveHour), [false, false, false]);

check("rangeBar in the middle of the week", I.rangeBar(12, 18, 10, 20), { from: 0.2, to: 0.8 });
check("rangeBar of the extremes is full", I.rangeBar(10, 20, 10, 20), { from: 0, to: 1 });
check("rangeBar flat week", I.rangeBar(5, 5, 5, 5), { from: 0, to: 1 });
check("rangeBar clamps", I.rangeBar(0, 30, 10, 20), { from: 0, to: 1 });

check("scaled: keeps the newest", I.scaled([100, 0, 5, 10], 1, 2), [0.5, 1]);
check("scaled: last larger than the list", I.scaled([5, 10], 1, 60), [0.5, 1]);

// ── Pages ─────────────────────────────────────────────────────────────────────
check("every tab has a shape", I.TABS.every(t => typeof t.shape === "string" && t.shape !== ""), true);
check("pages keep their order", I.pagesOf(["weather", "today"]), ["weather", "today"]);
check("pages drop unknown and repeats", I.pagesOf(["media", "clock", "media", 3]), ["media"]);
check("no pages is every page", I.pagesOf([]), ["today", "media", "system", "weather"]);
check("junk pages is every page", I.pagesOf("today"), ["today", "media", "system", "weather"]);
check("a saved tab that is hidden is the first shown", I.tabOf("today", ["weather", "media"]), "weather");
check("a saved tab that is shown stays", I.tabOf("media", ["weather", "media"]), "media");
check("tabMeta of junk is the first", I.tabMeta("x").value, "today");
check("step forward", I.stepTab(["today", "media", "weather"], "media", 1), "weather");
check("step stops at the end", I.stepTab(["today", "media"], "media", 1), "media");
check("step stops at the start", I.stepTab(["today", "media"], "today", -1), "today");
check("step from a hidden page starts at the first", I.stepTab(["media", "weather"], "today", 1), "weather");

// ── The live handle ───────────────────────────────────────────────────────────
check("recording beats everything, live or not", I.subject({ recording: true, timer: true, playing: true, live: false }), "record");
check("live off is the line", I.subject({ timer: true, playing: true, live: false }), "");
check("a timer beats a song", I.subject({ timer: true, playing: true, live: true }), "timer");
check("a song", I.subject({ playing: true, live: true }), "song");
check("nothing is the line", I.subject({ live: true }), "");
check("no state is the line", I.subject(undefined), "");
check("a song opens Media", I.pageFor("song", ["today", "media"]), "media");
check("a song does not open a hidden Media", I.pageFor("song", ["today", "weather"]), "");
check("a timer has no page", I.pageFor("timer", ["today", "media"]), "");
check("an empty rail has no Media", I.pageFor("song", []), "");
check("a rail that is not a list has no Media", I.pageFor("song", undefined), "");

// ── The clock ─────────────────────────────────────────────────────────────────
check("12-hour evening", I.clockText(23, 6, true, "AM", "PM"), { time: "11:06", marker: "PM" });
check("12-hour midnight", I.clockText(0, 5, true, "am", "pm"), { time: "12:05", marker: "am" });
check("12-hour noon", I.clockText(12, 0, true), { time: "12:00", marker: "PM" });
check("24-hour pads the hour", I.clockText(7, 9, false), { time: "07:09", marker: "" });
check("24-hour evening", I.clockText(23, 6, false), { time: "23:06", marker: "" });

check("scale in range", I.scaleOf(1.1), 1.1);
check("scale clamps", [I.scaleOf(3), I.scaleOf(0.2)], [1.25, 0.8]);
check("scale junk is 1", [I.scaleOf("x"), I.scaleOf(undefined), I.scaleOf(-1)], [1, 1, 1]);

check("night light opens its page", I.switchPage("nightlight"), "NightLightPage.qml");
check("lock has no page", I.switchPage("lock"), "");
check("a prototype name has no page", I.switchPage("toString"), "");
check("load tones", [0.2, 0.75, 0.89, 0.9, 1, "x"].map(I.loadTone), ["calm", "busy", "busy", "hot", "hot", "calm"]);

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
