// ── test-ics.js ───────────────────────────────────────────────────────────────
// Regression tests for services/ics.js, the calendar feed parser.
//
//     bun scripts/test-ics.js          (or: node scripts/test-ics.js)
//
// Safe to run: ics.js is pure functions and touches nothing.
//
// Expected times are built with the LOCAL Date constructor, the same way the parser
// reads floating/TZID times, so the suite passes in any TZ. Run it under a DST zone
// (`TZ=Europe/London bun scripts/test-ics.js`) to exercise the wall-clock stepping.
//
// Loaded by stripping `.pragma library`, like test-calc.js, so the tests run against
// the real file rather than a copy.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "ics.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const Ics = new Function(src + "\nreturn { parse, parseDate, parseDuration, expand, onDay, dayCounts, daySources, nextDay, nextUp, feedUrl, dayKey, serialize, rruleString, parseTime, validateEvent, newUid };")();

let pass = 0, fail = 0;
function eq(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    fail++;
    console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`);
}

const L = (y, m, d, h = 0, mi = 0) => new Date(y, m - 1, d, h, mi).getTime();
const cal = (...events) => "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"
    + events.map(e => "BEGIN:VEVENT\r\n" + e.trim().split("\n").map(s => s.trim()).join("\r\n") + "\r\nEND:VEVENT\r\n").join("")
    + "END:VCALENDAR\r\n";
const starts = (occ) => occ.map(o => o.start);
const YEAR = [L(2026, 1, 1), L(2027, 1, 1)];

// ── Values ────────────────────────────────────────────────────────────────────
eq("date floating", Ics.parseDate("20260519T083000"), { ms: L(2026, 5, 19, 8, 30), allDay: false });
eq("date utc", Ics.parseDate("20260519T083000Z"), { ms: Date.UTC(2026, 4, 19, 8, 30), allDay: false });
eq("date all-day", Ics.parseDate("20260519"), { ms: L(2026, 5, 19), allDay: true });
eq("date garbage", Ics.parseDate("2026-05-19"), null);
eq("date month 13", Ics.parseDate("20261319"), null);
eq("duration", Ics.parseDuration("PT1H30M"), 5400000);
eq("duration week", Ics.parseDuration("P1W"), 604800000);
eq("duration bare P", Ics.parseDuration("P"), null);

// ── Parsing ───────────────────────────────────────────────────────────────────
{
    const text = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:a\r\nSUMMARY:Eco SL/HL\\, room\r\n  KD107\r\n"
        + "LOCATION:Building \\;B\r\nDESCRIPTION:line1\\nline2\r\n"
        + "DTSTART;TZID=\"Europe/Paris\":20260519T083000\r\nDTEND;TZID=Europe/Paris:20260519T100000\r\n"
        + "BEGIN:VALARM\r\nSUMMARY:alarm must not win\r\nEND:VALARM\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
    const [e] = Ics.parse(text);
    eq("unfold + escapes", e.summary, "Eco SL/HL, room KD107");
    eq("location escape", e.location, "Building ;B");
    eq("description newline", e.description, "line1\nline2");
    eq("TZID read as local", [e.start, e.end], [L(2026, 5, 19, 8, 30), L(2026, 5, 19, 10)]);
    eq("VALARM ignored", Ics.parse(text).length, 1);
}
eq("garbage doesn't throw", Ics.parse("\u0000not ics\nBEGIN:VEVENT\nDTSTART:nope\nEND:VEVENT"), []);
eq("null input", Ics.parse(null), []);
{
    const [e] = Ics.parse(cal("UID:d\nDTSTART:20260519T090000\nDURATION:PT45M"));
    eq("DURATION end", e.end, L(2026, 5, 19, 9, 45));
    const [a] = Ics.parse(cal("UID:ad\nDTSTART;VALUE=DATE:20260519"));
    eq("all-day default end", [a.allDay, a.end], [true, L(2026, 5, 20)]);
}

// ── Recurrence ────────────────────────────────────────────────────────────────
{
    // A timetable: Mon + Wed, 4 lessons, starting on a Monday.
    const ev = Ics.parse(cal("UID:w\nDTSTART:20260518T083000\nDTEND:20260518T100000\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4"));
    eq("weekly BYDAY COUNT", starts(Ics.expand(ev, ...YEAR)),
       [L(2026, 5, 18, 8, 30), L(2026, 5, 20, 8, 30), L(2026, 5, 25, 8, 30), L(2026, 5, 27, 8, 30)]);
    // COUNT must count occurrences before the window too.
    eq("COUNT counts before window", starts(Ics.expand(ev, L(2026, 5, 21), L(2026, 6, 30))),
       [L(2026, 5, 25, 8, 30), L(2026, 5, 27, 8, 30)]);
}
{
    const ev = Ics.parse(cal("UID:u\nDTSTART:20260501T120000\nRRULE:FREQ=DAILY;INTERVAL=2;UNTIL=20260507"));
    eq("daily interval until(date)", starts(Ics.expand(ev, ...YEAR)),
       [L(2026, 5, 1, 12), L(2026, 5, 3, 12), L(2026, 5, 5, 12), L(2026, 5, 7, 12)]);
}
{
    const ev = Ics.parse(cal("UID:x\nDTSTART:20260504T090000\nRRULE:FREQ=WEEKLY;COUNT=3\nEXDATE:20260511T090000"));
    eq("EXDATE", starts(Ics.expand(ev, ...YEAR)), [L(2026, 5, 4, 9), L(2026, 5, 18, 9)]);
}
{
    const ev = Ics.parse(cal(
        "UID:r\nSUMMARY:Phy\nDTSTART:20260504T090000\nDTEND:20260504T100000\nRRULE:FREQ=WEEKLY;COUNT=3",
        "UID:r\nSUMMARY:Phy (moved)\nRECURRENCE-ID:20260511T090000\nDTSTART:20260512T140000\nDTEND:20260512T150000"));
    eq("RECURRENCE-ID override", Ics.expand(ev, ...YEAR).map(o => [o.start, o.summary]),
       [[L(2026, 5, 4, 9), "Phy"], [L(2026, 5, 12, 14), "Phy (moved)"], [L(2026, 5, 18, 9), "Phy"]]);
}
{
    const ev = Ics.parse(cal(
        "UID:c1\nDTSTART:20260504T090000\nRRULE:FREQ=WEEKLY;COUNT=2",
        "UID:c1\nRECURRENCE-ID:20260511T090000\nDTSTART:20260511T090000\nSTATUS:CANCELLED"));
    eq("cancelled instance removes occurrence", starts(Ics.expand(ev, ...YEAR)), [L(2026, 5, 4, 9)]);
}
{
    const ev = Ics.parse(cal("UID:m\nDTSTART:20260113T180000\nRRULE:FREQ=MONTHLY;BYDAY=2TU;COUNT=3"));
    eq("monthly 2nd Tuesday", starts(Ics.expand(ev, ...YEAR)),
       [L(2026, 1, 13, 18), L(2026, 2, 10, 18), L(2026, 3, 10, 18)]);
    const last = Ics.parse(cal("UID:mf\nDTSTART:20260130T180000\nRRULE:FREQ=MONTHLY;BYDAY=-1FR;COUNT=2"));
    eq("monthly last Friday", starts(Ics.expand(last, ...YEAR)), [L(2026, 1, 30, 18), L(2026, 2, 27, 18)]);
    const d31 = Ics.parse(cal("UID:31\nDTSTART:20260131T080000\nRRULE:FREQ=MONTHLY;COUNT=3"));
    eq("monthly 31st skips short months", starts(Ics.expand(d31, ...YEAR)),
       [L(2026, 1, 31, 8), L(2026, 3, 31, 8), L(2026, 5, 31, 8)]);
}
{
    const ev = Ics.parse(cal("UID:y\nDTSTART;VALUE=DATE:20240229\nRRULE:FREQ=YEARLY"));
    eq("yearly Feb 29 skips non-leap", starts(Ics.expand(ev, L(2024, 1, 1), L(2029, 1, 1))),
       [L(2024, 2, 29), L(2028, 2, 29)]);
}
{
    // Unbounded daily from 1900: must be bounded AND still reach the window.
    const ev = Ics.parse(cal("UID:old\nDTSTART:19000101T070000\nRRULE:FREQ=DAILY"));
    const occ = Ics.expand(ev, L(2026, 5, 18), L(2026, 5, 21));
    eq("ancient unbounded daily reaches window", starts(occ),
       [L(2026, 5, 18, 7), L(2026, 5, 19, 7), L(2026, 5, 20, 7)]);
    const wk = Ics.parse(cal("UID:oldw\nDTSTART:19000101T070000\nRRULE:FREQ=WEEKLY;BYDAY=TU"));
    eq("ancient unbounded weekly reaches window", starts(Ics.expand(wk, L(2026, 5, 18), L(2026, 5, 25))),
       [L(2026, 5, 19, 7)]);
    const mo = Ics.parse(cal("UID:oldm\nDTSTART:19000115T070000\nRRULE:FREQ=MONTHLY"));
    eq("ancient unbounded monthly reaches window", starts(Ics.expand(mo, L(2026, 5, 1), L(2026, 7, 1))),
       [L(2026, 5, 15, 7), L(2026, 6, 15, 7)]);
    const cnt = Ics.parse(cal("UID:cap\nDTSTART:19000101T070000\nRRULE:FREQ=DAILY;COUNT=999999999"));
    eq("huge COUNT is capped, not hung", Ics.expand(cnt, L(2026, 5, 18), L(2026, 5, 21)).length, 0);
}

// ── Queries ───────────────────────────────────────────────────────────────────
{
    const occ = Ics.expand(Ics.parse(cal(
        "UID:trip\nSUMMARY:Trip\nDTSTART;VALUE=DATE:20260518\nDTEND;VALUE=DATE:20260521",
        "UID:eco\nSUMMARY:Eco\nDTSTART:20260519T083000\nDTEND:20260519T100000",
        "UID:his\nSUMMARY:His\nDTSTART:20260519T103000\nDTEND:20260519T120000")), ...YEAR);
    eq("dayCounts multi-day", Ics.dayCounts(occ),
       { "2026-05-18": 1, "2026-05-19": 3, "2026-05-20": 1 });
    eq("onDay", Ics.onDay(occ, 2026, 4, 19).map(o => o.summary), ["Trip", "Eco", "His"]);
    eq("onDay excludes end day", Ics.onDay(occ, 2026, 4, 21).length, 0);
    // 11:00 on the 19th: Eco has ended, Trip and His haven't.
    const nx = Ics.nextDay(occ, L(2026, 5, 19, 11));
    eq("nextDay drops finished", [nx.day, nx.items.map(o => o.summary)], [L(2026, 5, 19), ["Trip", "His"]]);
    const later = Ics.nextDay(occ, L(2026, 5, 21, 0));
    eq("nextDay none left", later, null);
}

// ── Sources ───────────────────────────────────────────────────────────────────
{
    const a = Ics.parse(cal("UID:same\nSUMMARY:A\nDTSTART:20260504T090000\nRRULE:FREQ=WEEKLY;COUNT=2",
                            "UID:same\nRECURRENCE-ID:20260511T090000\nDTSTART:20260511T090000\nSTATUS:CANCELLED"))
        .map(e => Object.assign(e, { source: "feedA" }));
    const b = Ics.parse(cal("UID:same\nSUMMARY:B\nDTSTART:20260504T090000\nRRULE:FREQ=WEEKLY;COUNT=2"))
        .map(e => Object.assign(e, { source: "feedB" }));
    const occ = Ics.expand(a.concat(b), ...YEAR);
    eq("override stays in its own source", occ.map(o => [o.source, o.start]),
       [["feedA", L(2026, 5, 4, 9)], ["feedB", L(2026, 5, 4, 9)], ["feedB", L(2026, 5, 11, 9)]]);
    eq("occurrence carries uid + recurring", [occ[0].uid, occ[0].recurring], ["same", true]);
    eq("daySources distinct, capped", Ics.daySources([
        { start: L(2026, 5, 4, 9), end: L(2026, 5, 4, 10), source: "a" },
        { start: L(2026, 5, 4, 11), end: L(2026, 5, 4, 12), source: "a" },
        { start: L(2026, 5, 4, 13), end: L(2026, 5, 4, 14), source: "b" },
        { start: L(2026, 5, 4, 15), end: L(2026, 5, 4, 16), source: "c" },
        { start: L(2026, 5, 4, 17), end: L(2026, 5, 4, 18), source: "d" }], 3),
       { "2026-05-04": ["a", "b", "c"] });
}

// ── Writing: round trips ──────────────────────────────────────────────────────
{
    const STAMP = Date.UTC(2026, 8, 13, 10, 0, 0);
    const events = [
        { uid: "t1@x", summary: "Eco; SL, HL \\ room\nsecond line", location: "KD107", description: "",
          start: L(2026, 5, 19, 8, 30), end: L(2026, 5, 19, 10), allDay: false,
          rrule: { freq: "WEEKLY", interval: 1, count: 0, until: L(2026, 6, 30, 23, 59), byday: [{ n: 0, wd: 2 }] },
          exdates: [L(2026, 5, 26, 8, 30)] },
        { uid: "d1@x", summary: "Trip", location: "", description: "",
          start: L(2026, 5, 20), end: L(2026, 5, 23), allDay: true, rrule: null, exdates: [] },
    ];
    const text = Ics.serialize(events, STAMP);
    eq("serialize uses CRLF", text.includes("\r\n") && !/[^\r]\n/.test(text), true);
    eq("serialize DTSTAMP is UTC", text.includes("DTSTAMP:20260913T100000Z"), true);
    const back = Ics.parse(text);
    eq("round trip summary escapes", back[0].summary, "Eco; SL, HL \\ room\nsecond line");
    eq("round trip timed", [back[0].start, back[0].end, back[0].allDay], [L(2026, 5, 19, 8, 30), L(2026, 5, 19, 10), false]);
    eq("round trip rrule", [back[0].rrule.freq, back[0].rrule.until, back[0].rrule.byday], ["WEEKLY", L(2026, 6, 30, 23, 59), [{ n: 0, wd: 2 }]]);
    eq("round trip exdate", back[0].exdates, [L(2026, 5, 26, 8, 30)]);
    eq("round trip all-day", [back[1].start, back[1].end, back[1].allDay], [L(2026, 5, 20), L(2026, 5, 23), true]);
    eq("round trip expands", starts(Ics.expand(back, L(2026, 5, 18), L(2026, 6, 10))),
       [L(2026, 5, 19, 8, 30), L(2026, 6, 2, 8, 30), L(2026, 6, 9, 8, 30)].slice(0, 0).concat(
        [L(2026, 5, 19, 8, 30), L(2026, 5, 20), L(2026, 6, 2, 8, 30), L(2026, 6, 9, 8, 30)]));
}
{
    // Folding: every physical line ≤ 75 octets, multi-byte characters intact.
    const long = "Réunion 📅 ".repeat(20);
    const text = Ics.serialize([{ uid: "f@x", summary: long, start: L(2026, 5, 1, 9), end: L(2026, 5, 1, 10) }], 0);
    const enc = new TextEncoder();
    eq("fold ≤ 75 octets", text.split("\r\n").every(l => enc.encode(l).length <= 75), true);
    eq("fold round trip", Ics.parse(text)[0].summary, long.trim());
}
eq("rruleString none", Ics.rruleString(null), "");
eq("rruleString count", Ics.rruleString({ freq: "DAILY", interval: 2, count: 5, until: null, byday: [] }), "FREQ=DAILY;INTERVAL=2;COUNT=5");
eq("rruleString bad freq", Ics.rruleString({ freq: "HOURLY" }), "");
eq("uid strips unsafe", Ics.newUid(1000, "a b\nc!"), "rs-abc@quickshell-quicktest");
eq("uid line break can't split a property", Ics.serialize([{ uid: "x\r\nSUMMARY:evil", summary: "s", start: 0, end: 0 }], 0).includes("\r\nSUMMARY:evil"), false);

// ── Editor input ──────────────────────────────────────────────────────────────
eq("time forms", ["8", "08", "830", "0830", "8:30", "8.30", "8h30", "20h", " 23:59 "].map(Ics.parseTime),
   [{ h: 8, m: 0 }, { h: 8, m: 0 }, { h: 8, m: 30 }, { h: 8, m: 30 }, { h: 8, m: 30 }, { h: 8, m: 30 }, { h: 8, m: 30 }, { h: 20, m: 0 }, { h: 23, m: 59 }]);
eq("time rejects", ["24", "8:60", "8:3", "", "noon", "12:00pm", null].map(Ics.parseTime), [null, null, null, null, null, null, null]);
{
    const day = L(2026, 5, 19);
    const ok = Ics.validateEvent({ summary: "  Phy HL ", location: "KC112", day, startTime: "12:30", endTime: "14", repeat: "WEEKLY" });
    eq("validate ok", [ok.ok, ok.event.summary, ok.event.start, ok.event.end, ok.event.rrule.freq, ok.event.source],
       [true, "Phy HL", L(2026, 5, 19, 12, 30), L(2026, 5, 19, 14), "WEEKLY", "local"]);
    const night = Ics.validateEvent({ summary: "Party", day, startTime: "22:00", endTime: "01:00" });
    eq("validate past midnight", night.event.end, L(2026, 5, 20, 1));
    const all = Ics.validateEvent({ summary: "Holiday", day, allDay: true, startTime: "garbage" });
    eq("validate all-day ignores times", [all.ok, all.event.start, all.event.end], [true, day, L(2026, 5, 20)]);
    eq("validate needs title", Ics.validateEvent({ summary: "   ", day, startTime: "9", endTime: "10" }).error, "Give it a title");
    eq("validate bad start", Ics.validateEvent({ summary: "x", day, startTime: "9pm", endTime: "10" }).error, "Start time isn't a time");
    eq("validate bad repeat", Ics.validateEvent({ summary: "x", day, startTime: "9", endTime: "10", repeat: "HOURLY" }).error, "Unknown repeat");
    eq("validate long title", Ics.validateEvent({ summary: "x".repeat(501), day, startTime: "9", endTime: "10" }).error, "The title is too long");
    eq("validate no day", Ics.validateEvent({ summary: "x", day: NaN, startTime: "9", endTime: "10" }).error, "Pick a day");
}

// ── Next up ───────────────────────────────────────────────────────────────────
{
    const now = L(2026, 5, 19, 10, 0);
    const H = 36 * 3600000;
    const ev = (summary, s, e, allDay = false) => ({ summary, start: s, end: e, allDay });
    const nu = (occ) => Ics.nextUp(occ, now, H);
    eq("nextUp in minutes", nu([ev("Standup", L(2026, 5, 19, 10, 25), L(2026, 5, 19, 10, 40))]).when, "in 25 min");
    eq("nextUp rounds up", nu([ev("x", now + 60001, now + 3600000)]).minutes, 2);
    eq("nextUp later today", nu([ev("Gym", L(2026, 5, 19, 15, 30), L(2026, 5, 19, 16, 30))]).when, "at 15:30");
    eq("nextUp tomorrow", nu([ev("Dentist", L(2026, 5, 20, 9), L(2026, 5, 20, 10))]).when, "tomorrow 09:00");
    eq("nextUp tomorrow morning is a calendar day, not 24 h", nu([ev("Early", L(2026, 5, 20, 7), L(2026, 5, 20, 8))]).when, "tomorrow 07:00");
    eq("nextUp weekday", Ics.nextUp([ev("Later", L(2026, 5, 21, 9), L(2026, 5, 21, 10))], now, 72 * 3600000).when, "Thu 09:00");
    eq("nextUp live", nu([ev("Review", L(2026, 5, 19, 9, 30), L(2026, 5, 19, 11))]).when, "now \u00b7 until 11:00");
    eq("nextUp live wins over a later one", nu([ev("Long", L(2026, 5, 19, 9), L(2026, 5, 19, 12)), ev("Soon", L(2026, 5, 19, 10, 5), L(2026, 5, 19, 10, 30))]).summary, "Long");
    eq("nextUp skips all-day", nu([ev("Holiday", L(2026, 5, 19), L(2026, 5, 20), true)]), null);
    eq("nextUp skips finished", nu([ev("Done", L(2026, 5, 19, 8), L(2026, 5, 19, 9))]), null);
    eq("nextUp beyond the horizon", nu([ev("Far", L(2026, 5, 22, 9), L(2026, 5, 22, 10))]), null);
    eq("nextUp finds the first timed one past an all-day", nu([ev("Holiday", L(2026, 5, 19), L(2026, 5, 20), true), ev("Gym", L(2026, 5, 19, 18), L(2026, 5, 19, 19))]).summary, "Gym");
    eq("nextUp nothing", Ics.nextUp([], now, H), null);
    eq("nextUp garbage tolerated", Ics.nextUp(null, now, H), null);
}

// ── Feed addresses ────────────────────────────────────────────────────────────
eq("feed https", Ics.feedUrl("https://calendar.google.com/calendar/ical/x/basic.ics"), { ok: true, url: "https://calendar.google.com/calendar/ical/x/basic.ics" });
eq("feed webcal becomes https", Ics.feedUrl("webcal://example.com/a.ics").url, "https://example.com/a.ics");
eq("feed trimmed", Ics.feedUrl("  https://example.com/a.ics \n").url, "https://example.com/a.ics");
eq("feed http allowed", Ics.feedUrl("http://example.com/a.ics").ok, true);
eq("feed empty", Ics.feedUrl("  ").ok, false);
eq("feed file: refused", Ics.feedUrl("file:///etc/passwd").ok, false);
eq("feed ftp refused", Ics.feedUrl("ftp://example.com/a.ics").ok, false);
eq("feed option smuggling refused", Ics.feedUrl("--output=/tmp/x").ok, false);
eq("feed no host refused", Ics.feedUrl("https://").ok, false);
eq("feed space refused", Ics.feedUrl("https://example.com/a b.ics").ok, false);
eq("feed too long", Ics.feedUrl("https://example.com/" + "a".repeat(2000)).ok, false);
eq("feed undefined", Ics.feedUrl(undefined).ok, false);

console.log(`${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
