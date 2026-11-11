// ── test-screentime.js ────────────────────────────────────────────────────────
// services/screentime.js — crediting time to apps, midnight splits, the file's
// cleaning, pruning and the summaries.
//
//     TZ=Europe/Lisbon bun scripts/test-screentime.js
//
// Safe: pure functions, no file touched. Days are LOCAL, so the test builds its times
// with local Date constructors and pins a timezone with a DST change in it.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

process.env.TZ = process.env.TZ || "Europe/Lisbon";
const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "screentime.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const S = new Function(src + `
return { dayKey, nextMidnight, appKey, credit, clean, prune, total, top, lastDays, duration, short, topAcross, segments, versus, heat, streak, creditHours, cleanHours, hoursOf, paceVs };`)();

let passed = 0, failed = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) passed++;
    else { failed++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`); }
}

const at = (y, mo, d, h, mi = 0, s = 0) => new Date(y, mo - 1, d, h, mi, s).getTime();

check("day key", S.dayKey(at(2026, 10, 4, 9)), "2026-10-04");
check("app key lowercased", S.appKey("Firefox"), "firefox");
check("app key with dots", S.appKey("org.kde.dolphin"), "org.kde.dolphin");
check("app key refuses junk", S.appKey("a b/../c"), "");
check("app key refuses __proto__", S.appKey("__proto__"), "");

let d = S.credit({}, "kitty", at(2026, 10, 4, 9), at(2026, 10, 4, 9, 1));
check("one minute", d, { "2026-10-04": { kitty: 60 } });
d = S.credit(d, "kitty", at(2026, 10, 4, 10), at(2026, 10, 4, 10, 0, 30));
check("adds up", d["2026-10-04"].kitty, 90);
check("returns a new object", S.credit(d, "zen", 1, 2) !== d, true);

d = S.credit({}, "zen", at(2026, 10, 4, 23, 59), at(2026, 10, 5, 0, 1));
check("split at midnight", d, { "2026-10-04": { zen: 60 }, "2026-10-05": { zen: 60 } });

d = S.credit({}, "zen", at(2026, 10, 4, 9), at(2026, 10, 4, 11), 60000);
check("a gap is clipped to its last maxSpan", d["2026-10-04"].zen, 60);
check("bad app credits nothing", S.credit({}, "../x", 0, 1000), {});
check("backwards credits nothing", S.credit({}, "a", 2000, 1000), {});

// DST: Lisbon goes back an hour on 2026-10-25; that day is 25 h long.
d = S.credit({}, "a", at(2026, 10, 25, 0), at(2026, 10, 26, 0));
check("a 25-hour day stays one day", Object.keys(d), ["2026-10-25"]);
check("…and counts 25 h", d["2026-10-25"].a, 25 * 3600);

check("clean drops junk", S.clean({ days: {
    "2026-10-04": { kitty: 59.6, "bad key": 5, zen: -3, spotify: "x", code: Infinity },
    "yesterday": { kitty: 5 }, "2026-10-03": [] } }), { "2026-10-04": { kitty: 60 } });
check("clean of nonsense", S.clean("x"), {});
check("clean takes a bare days object too", S.clean({ "2026-10-04": { a: 1 } }), { "2026-10-04": { a: 1 } });

const many = {};
for (let i = 0; i < 40; i++) many[S.dayKey(at(2026, 10, 4, 12) - i * 86400000)] = { a: 1 };
check("prune keeps `keep` days", Object.keys(S.prune(many, 30, at(2026, 10, 4, 12))).length, 30);
check("prune floor is a week", Object.keys(S.prune(many, 1, at(2026, 10, 4, 12))).length, 7);

const day = { kitty: 3600, zen: 7200, code: 7200, spotify: 60 };
check("total", S.total(day), 18060);
check("top: longest first, ties by name", S.top(day, 3).map(r => r.app), ["code", "zen", "kitty"]);

const week = S.lastDays({ "2026-10-04": { a: 100 }, "2026-09-28": { a: 5 } }, at(2026, 10, 4, 15), 7);
check("seven days", week.length, 7);
check("oldest first, today last", [week[0].key, week[6].key, week[6].today], ["2026-09-28", "2026-10-04", true]);
check("totals", [week[0].seconds, week[3].seconds, week[6].seconds], [5, 0, 100]);
check("weekday label", week[6].label, "Sun");

check("duration none", S.duration(0), "");
check("duration seconds", S.duration(30), "under a minute");
check("duration minutes", S.duration(45 * 60), "45 m");
check("duration hours", S.duration(3 * 3600 + 12 * 60), "3 h 12 m");
check("duration whole hours", S.duration(7200), "2 h");
check("short", [S.short(45 * 60), S.short(3.25 * 3600), S.short(12 * 3600)], ["45m", "3.3h", "12h"]);

// ── Ranking, stacks, the comparison, the heat strip ───────────────────────────
const rd = { "2026-10-01": { a: 100, b: 50 }, "2026-10-02": { a: 10, c: 70, d: 5 } };
check("topAcross sums the days", S.topAcross(rd, ["2026-10-01", "2026-10-02"], 2), [{ app: "a", seconds: 110 }, { app: "c", seconds: 70 }]);
check("topAcross skips missing days", S.topAcross(rd, ["2026-09-01"], 3), []);
check("segments stack bottom first", S.segments(rd["2026-10-02"], [{ app: "a" }, { app: "c" }]),
      [{ rank: 0, seconds: 10, from: 0 }, { rank: 1, seconds: 70, from: 10 }, { rank: 3, seconds: 5, from: 80 }]);
check("segments skips an app the day lacks", S.segments(rd["2026-10-01"], [{ app: "c" }, { app: "b" }]),
      [{ rank: 1, seconds: 50, from: 0 }, { rank: 3, seconds: 100, from: 50 }]);
check("segments: other stays rank 3 with fewer apps", S.segments({ a: 5, z: 7 }, [{ app: "a" }]),
      [{ rank: 0, seconds: 5, from: 0 }, { rank: 3, seconds: 7, from: 5 }]);
check("segments of nothing", S.segments({}, [{ app: "a" }]), []);
const vw = (t, ...o) => [...o.map(s => ({ seconds: s, today: false })), { seconds: t, today: true }];
check("versus above", S.versus(vw(150, 100, 100)), { pct: 50, dir: 1 });
check("versus below", S.versus(vw(50, 100, 100)), { pct: 50, dir: -1 });
check("versus level within 5%", S.versus(vw(103, 100)), { pct: 3, dir: 0 });
check("versus ignores empty days", S.versus(vw(100, 0, 100, 0)), { pct: 0, dir: 0 });
check("versus nothing to compare", S.versus(vw(100, 0, 0)), null);
check("versus no days", S.versus([]), null);
check("heat", [S.heat(0, 100), S.heat(1, 100), S.heat(25, 100), S.heat(26, 100), S.heat(100, 100), S.heat(500, 100), S.heat(5, 0)], [0, 1, 1, 2, 4, 4, 0]);

const sd = (...v) => v.map(x => ({ seconds: x }));
check("streak any", S.streak(sd(0, 5, 5, 5), "any", 0), 3);
check("streak any breaks on a gap", S.streak(sd(5, 0, 5, 5), "any", 0), 2);
check("streak skips an empty today", S.streak(sd(5, 5, 0), "any", 0), 2);
check("streak under", S.streak(sd(5, 50, 5, 5), "under", 10), 2);
check("streak today over breaks", S.streak(sd(5, 5, 50), "under", 10), 0);
check("streak under with no limit is any", S.streak(sd(5, 50), "under", 0), 2);
check("streak of nothing", S.streak([], "any", 0), 0);
check("streak all empty", S.streak(sd(0, 0), "any", 0), 0);

// ── Hours ─────────────────────────────────────────────────────────────────────
let h = S.creditHours({}, at(2026, 10, 4, 9, 30), at(2026, 10, 4, 9, 45));
check("hours: inside one hour", h["2026-10-04"][9], 900);
check("hours: 24 slots", h["2026-10-04"].length, 24);
h = S.creditHours({}, at(2026, 10, 4, 9, 50), at(2026, 10, 4, 10, 20));
check("hours: split at the hour", [h["2026-10-04"][9], h["2026-10-04"][10]], [600, 1200]);
h = S.creditHours({}, at(2026, 10, 4, 23, 50), at(2026, 10, 5, 0, 10));
check("hours: split at midnight", [h["2026-10-04"][23], h["2026-10-05"][0]], [600, 600]);
h = S.creditHours({}, at(2026, 10, 4, 9), at(2026, 10, 4, 15), 70 * 1000);
check("hours: clipped like credit", h["2026-10-04"].reduce((a, b) => a + b, 0), 70);
const before = { "2026-10-04": [1, ...Array(23).fill(0)] };
const after = S.creditHours(before, at(2026, 10, 4, 9), at(2026, 10, 4, 9, 1));
check("hours: input untouched", [before["2026-10-04"][9], after["2026-10-04"][9], after !== before], [0, 60, true]);
check("hours: nothing to credit", S.creditHours(before, 5, 5), before);
// The two ledgers agree on the same span, DST day included (Lisbon: clocks forward 2026-03-29, back 2026-10-25).
for (const [a, b] of [[at(2026, 3, 29, 0, 30), at(2026, 3, 29, 4)], [at(2026, 10, 25, 0, 30), at(2026, 10, 25, 4)]]) {
  const dsum = Object.values(S.credit({}, "x", a, b)).reduce((s, d) => s + d.x, 0);
  const hsum = Object.values(S.creditHours({}, a, b)).reduce((s, arr) => s + arr.reduce((x, y) => x + y, 0), 0);
  check("hours: same total as credit across DST", Math.round(hsum), Math.round(dsum));
}
check("cleanHours", S.cleanHours({ hours: { "2026-10-04": [5, "x", -1, 99999, ...Array(30).fill(1)], "bad": [1], "2026-10-05": [0, 0], "2026-10-06": "no" } }),
      { "2026-10-04": [5, 0, 0, 3600, ...Array(20).fill(1)] });
check("cleanHours: none", [S.cleanHours({ days: {} }), S.cleanHours(null), S.cleanHours({ hours: [1] })], [{}, {}, {}]);
check("hoursOf pads", [S.hoursOf({}, "x").length, S.hoursOf({ x: [0, 7] }, "x")[1]], [24, 7]);

// Pace. Two earlier days, 100 s in each of hours 8 and 9; it is 09:30 and today has had 150 s.
const hrs = (m) => { const a = Array(24).fill(0); for (const k in m) a[k] = m[k]; return a };
const ph = { "d1": hrs({ 8: 600, 9: 600 }), "d2": hrs({ 8: 600, 9: 600 }), "t": hrs({ 8: 600, 9: 300 }) };
// by 09:30 an average day had 600 + 600*0.5 = 900; today 900 -> level
check("pace level", S.paceVs(ph, "t", ["d1", "d2"], at(2026, 10, 4, 9, 30)), { ahead: 0, expected: 900, dir: 0 });
ph.t = hrs({ 8: 600, 9: 900 });
check("pace ahead", S.paceVs(ph, "t", ["d1", "d2"], at(2026, 10, 4, 9, 30)).dir, 1);
ph.t = hrs({ 8: 100 });
check("pace behind", S.paceVs(ph, "t", ["d1", "d2"], at(2026, 10, 4, 9, 30)), { ahead: -800, expected: 900, dir: -1 });
check("pace: nothing before", S.paceVs({ t: hrs({ 8: 600 }) }, "t", ["d1"], at(2026, 10, 4, 9, 30)), null);
check("pace: too early in the day", S.paceVs(ph, "t", ["d1", "d2"], at(2026, 10, 4, 3, 0)), null);
check("pace ignores days without hours", S.paceVs(ph, "t", ["gone", "d1"], at(2026, 10, 4, 9, 30)).expected, 900);

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);

// ── Steam game names ──────────────────────────────────────────────────────────
const manifests = [
  '/home/u/.local/share/Steam/steamapps/appmanifest_730.acf:\t"name"\t\t"Counter-Strike 2"',
  '/mnt/games/steamapps/appmanifest_1245620.acf:\t"name"\t\t"ELDEN RING"',
  '/mnt/games/steamapps/appmanifest_9.acf:\t"name"\t\t""',
  "garbage",
].join("\n");
check("steamNames", S.steamNames(manifests), { "730": "Counter-Strike 2", "1245620": "ELDEN RING" });
check("steamNames empty", S.steamNames(""), {});
check("steamId", [S.steamId("steam_app_730"), S.steamId("steam_app_"), S.steamId("steam"), S.steamId("steam_app_7a")], ["730", "", "", ""]);
check("gameName known", S.gameName("steam_app_730", { "730": "Counter-Strike 2" }), "Counter-Strike 2");
check("gameName unknown", S.gameName("steam_app_55", {}), "Steam game 55");
check("gameName proton", S.gameName("steam_proton", {}), "Game (Proton)");
check("gameName ordinary", S.gameName("firefox", {}), "");
