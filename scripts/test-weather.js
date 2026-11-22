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
const W = new Function(src + "\nreturn { nowcast, bars, isWet, dryWindow, rainSpans, goldenHour, intensity, compass, uvLevel, aqiLevel, aqiRatio, duration, pollen, sunArc, dayHours, chanceBars, middayOf, aqiRole, blend, blendCode, median, MODELS, sameCity, cityList, withCity, withoutCity };")();

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

// ── The island's page ─────────────────────────────────────────────────────────
{
    const rise = "2026-11-14T07:18", set = "2026-11-14T17:02", at = (h, m) => new Date(2026, 10, 14, h, m).getTime();
    eq("sun before", [W.sunArc(rise, set, at(6, 0)).state, W.sunArc(rise, set, at(6, 0)).frac], ["before", 0]);
    eq("sun after", [W.sunArc(rise, set, at(18, 0)).state, W.sunArc(rise, set, at(18, 0)).frac, W.sunArc(rise, set, at(18, 0)).leftS], ["after", 1, 0]);
    eq("sun midday", Math.round(W.sunArc(rise, set, at(12, 10)).frac * 100), 50);
    eq("sun length", W.duration(W.sunArc(rise, set, at(12, 10)).lengthS), "9h 44m");
    eq("sun left", Math.round(W.sunArc(rise, set, at(16, 2)).leftS / 60), 60);
    eq("sun without times", [W.sunArc("", set, 0), W.sunArc(set, rise, 0), W.sunArc("x", "y", 0)], [null, null, null]);
}
{
    const mk = (d, h) => ({ date: d, hour: h, precip: h * 4 });
    const all = [];
    for (let h = 0; h < 24; h++) all.push(mk("2026-11-14", h));
    for (let h = 0; h < 24; h++) all.push(mk("2026-11-15", h));
    eq("today runs on from the current hour", [W.dayHours(all, 10, "2026-11-14", "2026-11-14").length, W.dayHours(all, 10, "2026-11-14", "2026-11-14")[0].hour], [24, 10]);
    eq("today near the end of data", W.dayHours(all, 40, "2026-11-14", "2026-11-14").length, 8);
    eq("another day is its own hours", [W.dayHours(all, 10, "2026-11-15", "2026-11-14").length, W.dayHours(all, 10, "2026-11-15", "2026-11-14")[0].date], [24, "2026-11-15"]);
    eq("no hours", W.dayHours(null, 0, "2026-11-14", "2026-11-14"), []);
    eq("midday hour", W.middayOf(W.dayHours(all, 0, "2026-11-15", "2026-11-14")).hour, 12);
    eq("midday of a short day", W.middayOf([mk("d", 20), mk("d", 21), mk("d", 22)]).hour, 21);
    eq("midday of nothing", W.middayOf([]), null);
    eq("chance bars clamp", W.chanceBars([{ precip: 150 }, { precip: -5 }, {}, { precip: 40 }]).map(b => b.v), [1, 0, 0, 0.4]);
    eq("aqi roles", [-1, 10, 40, 41, 60, 61].map(W.aqiRole), ["fgDim", "success", "success", "warning", "warning", "danger"]);
}

// ── Blending models ───────────────────────────────────────────────────────────
{
    eq("median odd", W.median([3, 1, 2]), 2);
    eq("median even", W.median([1, 2, 3, 10]), 2.5);
    eq("median skips nulls", W.median([null, 4, undefined, 6]), 5);
    eq("median of nothing", W.median([null]), null);
    // The afternoon that was wrong: one model calls a storm, the rest are dry and grey.
    eq("one storm is outvoted", W.blendCode([95, 3, 3, 51, 2], 0.1, 77, 0.2), 3);
    eq("most say storm", W.blendCode([95, 96, 99, 3, 2], 0.1, 77, 0.2), 95);
    eq("wet picks the commonest rain", W.blendCode([61, 61, 63, 3, 80], 0.6, 90, 0.2), 61);
    eq("dry by cloud", [10, 30, 60, 90].map(c => W.blendCode([3, 3, 0], 0, c, 0.2)), [0, 1, 2, 3]);
    eq("a day, no cloud figure", W.blendCode([3, 3, 1, 51], 0.2, null, 1), 3);
    eq("fog by majority", W.blendCode([45, 45, 3], 0, 100, 0.2), 45);
    eq("no codes", W.blendCode([], 0, 0, 0.2), 0);

    const M = W.MODELS.slice(0, 3);
    const at = (h, m) => new Date(2026, 10, 14, h, m).getTime();
    const iso = h => "2026-11-14T" + (h < 10 ? "0" : "") + h + ":00";
    const hourly = { time: [iso(14), iso(15), iso(16)] };
    const temps = { [M[0]]: [16, 16, 15], [M[1]]: [18, 17, 16], [M[2]]: [22, 21, 20] };
    const codes = { [M[0]]: [3, 3, 3], [M[1]]: [3, 51, 3], [M[2]]: [95, 95, 95] };
    M.forEach(m => {
        hourly["temperature_2m_" + m] = temps[m];
        hourly["weather_code_" + m] = codes[m];
        hourly["cloud_cover_" + m] = [80, 90, 70];
        hourly["precipitation_" + m] = [0, 0.1, 0];
        hourly["is_day_" + m] = [1, 1, 1];
        hourly["wind_direction_10m_" + m] = m === M[0] ? [350, 350, 350] : [10, 10, 10];
        hourly["wind_speed_10m_" + m] = [10, 10, 10];
    });
    const daily = { time: ["2026-11-14"] };
    M.forEach(m => { daily["temperature_2m_max_" + m] = [m === M[2] ? 25 : 18]; daily["weather_code_" + m] = [3]; daily["sunrise_" + m] = ["2026-11-14T07:19"]; daily["precipitation_sum_" + m] = [0]; });
    const r = W.blend({ hourly, daily }, at(15, 30));
    eq("blended hourly is plain and the middle", r.hourly.temperature_2m, [18, 17, 16]);
    eq("a hot outlier does not drag the middle", r.daily.temperature_2m_max, [18]);
    eq("daily time text kept", r.daily.sunrise, ["2026-11-14T07:19"]);
    eq("the storm model is outvoted", r.hourly.weather_code, [3, 3, 2]);
    eq("directions average round north", r.hourly.wind_direction_10m[0], 3);
    eq("now is read between the hours", r.current.temperature_2m, 16.5);
    eq("now sky is the nearer hour's", r.current.weather_code, 2);
    eq("now has a time", r.current.time, "2026-11-14T15:30");
    eq("single model passes through", W.blend({ hourly: { time: ["x"], temperature_2m: [1] }, current: { a: 1 } }, 0).current, { a: 1 });
    eq("no hourly passes through", W.blend({ current: { a: 1 } }, 0).current, { a: 1 });
    eq("null passes through", W.blend(null, 0), null);
}

// ── Places to switch between ──────────────────────────────────────────────────
{
    const A = { name: "Porto", lat: 41.15, lon: -8.61, countryCode: "PT" };
    const B = { name: "Lisbon", lat: 38.72, lon: -9.14, countryCode: "PT" };
    const C = { name: "Salreu", lat: 40.74, lon: -8.56, countryCode: "PT" };
    eq("same place by position", W.sameCity(A, { name: "Oporto", lat: 41.151, lon: -8.609 }), true);
    eq("different place", W.sameCity(A, B), false);
    eq("nothing is not a place", [W.sameCity(null, A), W.sameCity(A, undefined)], [false, false]);
    eq("the current place is offered last", W.cityList([A, B], C).map(c => c.name), ["Porto", "Lisbon", "Salreu"]);
    eq("not twice", W.cityList([A, B], B).map(c => c.name), ["Porto", "Lisbon"]);
    eq("junk dropped", W.cityList([A, { name: "", lat: 1, lon: 1 }, { name: "X", lat: 0, lon: 0 }, null, "x", { name: "Y", lat: "1", lon: 2 }], null).map(c => c.name), ["Porto"]);
    eq("no list, no place", W.cityList(undefined, null), []);
    eq("an unset place is not offered", W.cityList([], { name: "", lat: 0, lon: 0 }), []);
    eq("add keeps order", W.withCity([A, B], C, 8).map(c => c.name), ["Porto", "Lisbon", "Salreu"]);
    eq("add what is there", W.withCity([A, B], A, 8).map(c => c.name), ["Porto", "Lisbon"]);
    eq("the oldest goes", W.withCity([A, B], C, 2).map(c => c.name), ["Lisbon", "Salreu"]);
    eq("add junk", W.withCity([A], { name: "", lat: 5, lon: 5 }, 8).map(c => c.name), ["Porto"]);
    eq("remove", W.withoutCity([A, B, C], B).map(c => c.name), ["Porto", "Salreu"]);
}

console.log(`${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
