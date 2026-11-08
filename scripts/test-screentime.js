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
return { dayKey, nextMidnight, appKey, credit, clean, prune, total, top, lastDays, duration, short };`)();

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
