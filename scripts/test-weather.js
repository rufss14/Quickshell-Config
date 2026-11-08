// ── test-weather.js ───────────────────────────────────────────────────────────
// Regression tests for services/weather.js — the rain nowcast and the plain-words
// bands.
//
//     bun scripts/test-weather.js          (or: node scripts/test-weather.js)
//
// Safe to run: weather.js is pure functions and touches nothing. Loaded by stripping
// `.pragma library`, like test-calc.js, so the tests run against the real file.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "weather.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const W = new Function(src + "\nreturn { nowcast, bars, isWet, dryWindow, rainSpans, goldenHour, intensity, compass, uvLevel, aqiLevel, aqiRatio, duration, pollen };")();

let pass = 0, fail = 0;
function eq(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    fail++;
    console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`);
}

// ── Nowcast ───────────────────────────────────────────────────────────────────
const T0 = Date.UTC(2026, 8, 12, 12, 0);
const Q = 15 * 60000;
// mm per slot, starting at T0.
const slots = (mms, snow = []) => mms.map((mm, i) => ({ t: T0 + i * Q, mm, snowCm: snow[i] ?? 0 }));
const text = (s, now = T0) => W.nowcast(s, now)?.text ?? null;

eq("all dry, 3h", text(slots(Array(12).fill(0))), "No rain for the next 3 h");
eq("dry, short horizon in minutes", text(slots([0, 0, 0, 0])), "No rain for the next 60 min");
eq("incoming", text(slots([0, 0, 0.2, 0.3, 0])), "Light rain starting in ~30 min");
eq("incoming rounds to 5 min", text(slots([0, 0, 0.2]), T0 + 7 * 60000), "Light rain starting in ~25 min");
eq("incoming soon", text(slots([0, 0.2]), T0 + 12 * 60000), "Light rain starting soon");
eq("moderate by peak", text(slots([0, 0.2, 1.0, 0.1])), "Moderate rain starting in ~15 min");
eq("heavy", text(slots([0, 2.5])), "Heavy rain starting in ~15 min");
eq("wet, stops", text(slots([0.3, 0.2, 0, 0])), "Light rain stopping in ~30 min");
eq("wet throughout", text(slots(Array(12).fill(0.4))), "Light rain for the next 3 h");
eq("snow", W.nowcast(slots([0, 0.3], [0, 0.2]), T0).kind, "snow");
eq("snow words", text(slots([0, 0.3], [0, 0.2])), "Light snow starting in ~15 min");
eq("below threshold is dry", text(slots([0.05, 0.09, 0, 0])), "No rain for the next 60 min");
eq("past slots ignored", text(slots([0.5, 0, 0, 0, 0]), T0 + 20 * 60000), "No rain for the next 55 min");
eq("stale data → null", W.nowcast(slots([0.5]), T0 + Q), null);
eq("no data → null", W.nowcast([], T0), null);
eq("garbage tolerated", W.nowcast([null, { t: NaN, mm: 1 }], T0), null);
eq("incoming minutes", W.nowcast(slots([0, 0, 0.2]), T0).minutes, 30);

// ── The short wording and the bars ────────────────────────────────────────────
eq("short incoming", W.nowcast(slots([0, 0, 0.2]), T0).short, "Rain in ~30 min");
eq("short soon", W.nowcast(slots([0, 0.2]), T0 + 12 * 60000).short, "Rain soon");
eq("short snow", W.nowcast(slots([0, 0.3], [0, 0.2]), T0).short, "Snow in ~15 min");
eq("short ends", W.nowcast(slots([0.3, 0.2, 0, 0]), T0).short, "Rain ends ~30 min");
eq("short wet throughout", W.nowcast(slots(Array(12).fill(0.4)), T0).short, "Rain for 3 h");
eq("short dry", W.nowcast(slots([0, 0, 0, 0]), T0).short, "Dry for 60 min");
eq("bars: dry slots are zero", W.bars(slots([0, 0.05, 0]), T0, 12).map(b => b.v), [0, 0, 0]);
eq("bars: drizzle is a stub, a downpour is full", W.bars(slots([0.1, 5]), T0, 12).map(b => Math.round(b.v * 100) / 100), [0.23, 1]);
eq("bars: capped", W.bars(slots(Array(12).fill(0.4)), T0, 4).length, 4);
eq("bars: past slots dropped", W.bars(slots([0.4, 0.4, 0.4]), T0 + 20 * 60000, 12).length, 2);
eq("bars: snow flagged", W.bars(slots([0.3], [0.2]), T0, 12)[0].snow, true);
eq("bars: garbage tolerated", W.bars([null, { t: NaN, mm: 1 }], T0, 12), []);

// ── The planner ───────────────────────────────────────────────────────────────
const hr = (date, hour, precip = 0, mm = 0) => ({ date, hour, precip, precipMm: mm });
const day = (date, wetHours) => Array.from({ length: 24 }, (_, h) => hr(date, h, wetHours.includes(h) ? 80 : 5));
const D1 = "2026-10-12", D2 = "2026-10-13";
eq("wet at 50 %", W.isWet(hr(D1, 1, 50)), true);
eq("dry at 49 %", W.isWet(hr(D1, 1, 49)), false);
eq("wet by amount alone", W.isWet(hr(D1, 1, 10, 0.3)), true);
eq("a trace is dry", W.isWet(hr(D1, 1, 10, 0.2)), false);
eq("dry until", W.dryWindow([...day(D1, [17, 18]), ...day(D2, [])], D1, 10).text, "Dry until 17:00");
eq("rain until", W.dryWindow([...day(D1, [10, 11, 12]), ...day(D2, [])], D1, 10).text, "Rain until 13:00");
eq("dry until tomorrow", W.dryWindow([...day(D1, []), ...day(D2, [3])], D1, 10).text, "Dry until tomorrow 03:00");
eq("dry until a later weekday", W.dryWindow([...day(D1, []), ...day(D2, []), ...day("2026-10-14", [9])], D1, 10).text, "Dry until Wed 09:00");
eq("no rain at all", W.dryWindow([...day(D1, []), ...day(D2, [])], D1, 10).text, "No rain in the forecast");
eq("rain throughout", W.dryWindow(day(D1, [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]), D1, 10).text, "Rain through the forecast");
eq("state", W.dryWindow(day(D1, [12]), D1, 10).state, "dry");
eq("now not in data", W.dryWindow(day(D1, []), D2, 10), null);
eq("no data", W.dryWindow(null, D1, 10), null);
eq("month end rolls", W.dryWindow([...day("2026-10-31", []), ...day("2026-11-01", [2])], "2026-10-31", 10).text, "Dry until tomorrow 02:00");
eq("dry all day", W.rainSpans(day(D1, [])).text, "Dry all day");
eq("one span", W.rainSpans(day(D1, [14, 15])).text, "Rain 14:00–16:00");
eq("two spans", W.rainSpans(day(D1, [8, 9, 15])).text, "Rain 08:00–10:00 · 15:00–16:00");
eq("three spans trimmed", W.rainSpans(day(D1, [1, 5, 9])).text, "Rain 01:00–02:00 · 05:00–06:00 …");
eq("span to midnight", W.rainSpans(day(D1, [22, 23])).text, "Rain 22:00–24:00");
eq("spans: none given", W.rainSpans(null).text, "Dry all day");
{
    const set = "2026-10-12T18:58", now = (h, m) => new Date(2026, 9, 12, h, m).getTime();
    eq("golden hour range", [W.goldenHour("2026-10-12T07:42", set, now(10, 0)).start, W.goldenHour("2026-10-12T07:42", set, now(10, 0)).end], ["17:58", "18:58"]);
    eq("golden hour not yet", [W.goldenHour(null, set, now(10, 0)).live, W.goldenHour(null, set, now(10, 0)).over], [false, false]);
    eq("golden hour live", W.goldenHour(null, set, now(18, 0)).live, true);
    eq("golden hour over", W.goldenHour(null, set, now(19, 0)).over, true);
    eq("no sunset", W.goldenHour(null, "", now(10, 0)), null);
}

// ── Words ─────────────────────────────────────────────────────────────────────
eq("compass N", W.compass(355), "N");
eq("compass SW", W.compass(225), "SW");
eq("compass W", W.compass(266), "W");
eq("compass negative", W.compass(-45), "NW");
eq("uv bands", [0, 2.9, 3, 6, 8, 11].map(W.uvLevel), ["Low", "Low", "Moderate", "High", "Very high", "Extreme"]);
eq("aqi bands", [0, 20, 21, 55, 70, 90, 140].map(W.aqiLevel), ["Good", "Good", "Fair", "Moderate", "Poor", "Very poor", "Extremely poor"]);
eq("aqi ratio caps", W.aqiRatio(140), 1);
eq("duration", W.duration(46181.41), "12h 50m");
eq("duration pads", W.duration(3 * 3600 + 5 * 60), "3h 05m");
eq("pollen present sorted", W.pollen({ grass_pollen: 3, birch_pollen: 12, alder_pollen: 0 }),
   { covered: true, items: [{ name: "Birch", grains: 12 }, { name: "Grass", grains: 3 }] });
eq("pollen outside Europe", W.pollen({ grass_pollen: null }), { covered: false, items: [] });
eq("pollen covered but none", W.pollen({ grass_pollen: 0 }), { covered: true, items: [] });

console.log(`${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
