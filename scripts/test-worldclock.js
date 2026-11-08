// ── test-worldclock.js ────────────────────────────────────────────────────────
// Regression tests for services/worldclock.js. `bun scripts/test-worldclock.js`
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "worldclock.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const Z = new Function(src + "\nreturn { windowStart, bands, pointAt, WINDOW_MS, validZone, parseOffset, cityName, regionName, zoneTime, dayWord, diffLabel, isDay, search };")();

let pass = 0, fail = 0;
function eq(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    fail++;
    console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`);
}

// ── names ─────────────────────────────────────────────────────────────────────
eq("valid zones", ["Europe/London", "UTC", "America/Argentina/Buenos_Aires", "Etc/GMT+5", "Asia/Kolkata"].map(Z.validZone), [true, true, true, true, true]);
eq("invalid zones", ["", "../etc/passwd", "a b", "-x", "Europe/", "A/B/C/D", "x".repeat(61), "Europe/London;rm", null, 5, "$(id)"].map(Z.validZone), Array(11).fill(false));
eq("city", Z.cityName("America/Argentina/Buenos_Aires"), "Buenos Aires");
eq("city, bare", Z.cityName("UTC"), "UTC");
eq("region", Z.regionName("America/Argentina/Buenos_Aires"), "America · Argentina");
eq("region of a bare name", Z.regionName("UTC"), "");

// ── offsets ───────────────────────────────────────────────────────────────────
eq("offsets", ["+0000", "+0530", "-0300", "+1245", "-0930"].map(Z.parseOffset), [0, 330, -180, 765, -570]);
eq("bad offsets", ["", "BST", "+5", "0530", undefined].map(x => Number.isNaN(Z.parseOffset(x))), Array(5).fill(true));

// ── the clock in a zone ───────────────────────────────────────────────────────
const UTC = (y, mo, d, h, mi) => Date.UTC(y, mo - 1, d, h, mi);
// 12 Oct 2026, 19:45 in Lisbon (UTC+1 in summer): that instant is 18:45 UTC.
const NOW = UTC(2026, 10, 12, 18, 45);
eq("same zone", Z.zoneTime(NOW, 60, 60), { h: 19, m: 45, dayShift: 0 });
eq("ahead, next day", Z.zoneTime(NOW, 540, 60), { h: 3, m: 45, dayShift: 1 });          // Tokyo
eq("behind, same day", Z.zoneTime(NOW, -240, 60), { h: 14, m: 45, dayShift: 0 });        // New York
eq("behind, previous day", Z.zoneTime(UTC(2026, 10, 12, 0, 30), -480, 0), { h: 16, m: 30, dayShift: -1 });
eq("half-hour zone", Z.zoneTime(NOW, 330, 60), { h: 0, m: 15, dayShift: 1 });            // Kolkata
eq("quarter-hour zone", Z.zoneTime(NOW, 765, 60), { h: 7, m: 30, dayShift: 1 });         // Chatham
eq("across a month end", Z.zoneTime(UTC(2026, 10, 31, 23, 0), 600, 0), { h: 9, m: 0, dayShift: 1 });
eq("across a year end", Z.zoneTime(UTC(2026, 12, 31, 23, 0), 600, 0), { h: 9, m: 0, dayShift: 1 });
eq("day words", [-1, 0, 1].map(Z.dayWord), ["Yesterday", "Today", "Tomorrow"]);
eq("diff labels", [[60, 60], [540, 60], [-240, 60], [330, 60], [330, 0], [-570, 0]].map(a => Z.diffLabel(a[0], a[1])),
   ["same time", "+8 h", "−5 h", "+4:30 h", "+5:30 h", "−9:30 h"]);
eq("day and night", [5, 6, 12, 17, 18, 23].map(Z.isDay), [false, true, true, true, false, false]);

// ── search ────────────────────────────────────────────────────────────────────
const ZONES = ["America/New_York", "America/Los_Angeles", "Europe/London", "Europe/Lisbon", "Asia/Tokyo", "America/Argentina/Buenos_Aires", "Asia/Kolkata", "America/Sao_Paulo", "UTC", "Australia/Sydney", "America/Santiago"];
eq("exact city first", Z.search(ZONES, "london", 6), ["Europe/London"]);
eq("prefix", Z.search(ZONES, "lis", 6), ["Europe/Lisbon"]);
eq("a later word", Z.search(ZONES, "york", 6), ["America/New_York"]);
eq("two words", Z.search(ZONES, "new y", 6), ["America/New_York"]);
eq("underscore typed", Z.search(ZONES, "new_york", 6), ["America/New_York"]);
eq("region", Z.search(ZONES, "australia", 6), ["Australia/Sydney"]);
eq("ranked: city prefix before containing", Z.search(ZONES, "sa", 6), ["America/Santiago", "America/Sao_Paulo"]);
eq("a containing match ranks last", Z.search(["Europe/Paris", "Asia/Tashkent", "Europe/Aarhus"], "ar", 6), ["Europe/Aarhus", "Europe/Paris"]);
eq("capped", Z.search(ZONES, "a", 2).length, 2);
eq("no match", Z.search(ZONES, "zzz", 6), []);
eq("empty query", Z.search(ZONES, "  ", 6), []);
eq("no zones", Z.search(null, "lon", 6), []);

// ── The planner ribbon ────────────────────────────────────────────────────────
{
    const H = 3600000;
    const now = UTC(2026, 10, 12, 18, 45);                       // 18:45 UTC
    const ws = Z.windowStart(now);
    eq("window starts six hours before the hour", ws, UTC(2026, 10, 12, 12, 0));
    eq("window is stable within the hour", Z.windowStart(now + 10 * 60000), ws);
    eq("window moves on the hour", Z.windowStart(now + 20 * 60000), ws + H);
    const hrs = (bs) => bs.map(b => [Math.round(b.a * 24 * 100) / 100, Math.round(b.b * 24 * 100) / 100]);
    // A viewer in UTC: daylight 06–18 in a UTC zone, over the window 12:00 → 12:00 next day.
    eq("daylight in the viewer's own zone", hrs(Z.bands(ws, 0, 6, 18)), [[0, 6], [18, 24]]);
    eq("office hours in the viewer's own zone: this afternoon, then tomorrow's morning", hrs(Z.bands(ws, 0, 9, 17)), [[0, 5], [21, 24]]);
    // Tokyo (+9): its 09–17 is 00:00–08:00 UTC the next day: 12 to 20 hours into the window.
    eq("another zone shifts", hrs(Z.bands(ws, 540, 9, 17)), [[12, 20]]);
    eq("a zone behind", hrs(Z.bands(ws, -300, 9, 17)), [[2, 10]]);       // New York EST: 14:00–22:00 UTC
    eq("half-hour zone (Kolkata: 03:30–11:30 UTC, tomorrow)", hrs(Z.bands(ws, 330, 9, 17)), [[15.5, 23.5]]);
    eq("never outside the window", Z.bands(ws, 540, 0, 24).every(b => b.a >= 0 && b.b <= 1 && b.b > b.a), true);
    eq("point at the middle", Z.pointAt(ws, 0.5), ws + 12 * H);
    eq("point snaps to a quarter hour", Z.pointAt(ws, 0.5 + 7 / (24 * 60)) % 900000, 0);
    eq("point is clamped", [Z.pointAt(ws, -1), Z.pointAt(ws, 2)], [ws, ws + 24 * H]);
}

console.log(`${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
