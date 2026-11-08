// ── test-notifyview.js ────────────────────────────────────────────────────────
// Regression tests for services/notifyview.js: the notification centre's search and
// per-app filter, its by-app and by-day layouts, the app counts, timed Do Not Disturb
// and snooze arithmetic.
//
//     bun scripts/test-notifyview.js          (or: node scripts/test-notifyview.js)
//
// Safe to run: pure functions, touches nothing. Loads the real file by stripping the
// `.pragma library` line. Dates are built from local-time parts so the cases hold in any
// timezone.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "notifyview.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const V = new Function(src + `
    return { appKey, matches, filter, byApp, dayLabel, byDay, appCounts, nextMorning,
             untilLabel, splitSnoozed, toggleIn, toneIndex };`)();

let pass = 0;
const failures = [];
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    failures.push(`  ${name}\n      want ${w}\n      got  ${g}`);
}

const at = (y, mo, d, h = 0, mi = 0) => new Date(y, mo - 1, d, h, mi, 0, 0).getTime();
const rec = (appName, summary, body, time) => ({ key: summary, appName, summary, body, time });

// ── An app's tone ─────────────────────────────────────────────────────────────
check("tone: stable", V.toneIndex("Spotify"), V.toneIndex("Spotify"));
check("tone: in range", ["Spotify", "kitty", "Quickshell", "", undefined, "日本語"].every(n => V.toneIndex(n) >= 0 && V.toneIndex(n) < 3), true);
check("tone: slot count honoured", ["a", "bb", "ccc", "dddd"].every(n => V.toneIndex(n, 5) < 5), true);
check("tone: a long name doesn't overflow the hash", V.toneIndex("x".repeat(5000)) < 3, true);
check("tone: the apps in use don't all share one", new Set(["Spotify", "kitty", "Quickshell", "OpenRazer", "Discord"].map(n => V.toneIndex(n))).size > 1, true);

// ── Search ────────────────────────────────────────────────────────────────────
const r1 = rec("Spotify", "Now playing", "Mai Sakurajima — Instrumental", 1);
check("search: empty matches", V.matches(r1, ""), true);
check("search: whitespace only matches", V.matches(r1, "   "), true);
check("search: summary", V.matches(r1, "playing"), true);
check("search: body", V.matches(r1, "sakurajima"), true);
check("search: app name", V.matches(r1, "spotify"), true);
check("search: case-insensitive", V.matches(r1, "NOW PLAYING"), true);
check("search: words in any order", V.matches(r1, "instrumental spotify"), true);
check("search: every word must match", V.matches(r1, "spotify discord"), false);
check("search: no hit", V.matches(r1, "kitty"), false);
check("search: a record with no body", V.matches(rec("kitty", "Done", undefined, 1), "done"), true);

// ── Filter ────────────────────────────────────────────────────────────────────
const list = [
    rec("Spotify", "Now playing", "a", 5),
    rec("kitty", "Claude Code", "waiting", 4),
    rec("", "Anonymous", "x", 3),
    rec("kitty", "Claude Code", "permission", 2),
];
check("filter: nothing asked", V.filter(list, "", "").length, 4);
check("filter: one app", V.filter(list, "", "kitty").map(r => r.time), [4, 2]);
check("filter: text and app", V.filter(list, "perm", "kitty").map(r => r.time), [2]);
check("filter: the no-app bucket is addressable", V.filter(list, "", "Notifications").map(r => r.time), [3]);
check("filter: text across apps", V.filter(list, "claude", "").map(r => r.time), [4, 2]);
check("filter: order kept (newest-first in, newest-first out)", V.filter(list, "a", "").map(r => r.time), [5, 4, 3, 2]);

// ── By app ────────────────────────────────────────────────────────────────────
const apps = V.byApp(list);
check("byApp: groups in first-seen order", apps.map(g => g.app), ["Spotify", "kitty", "Notifications"]);
check("byApp: items stay newest-first", apps[1].items.map(r => r.time), [4, 2]);
check("byApp: latest is the first item", apps[1].latest.time, 4);
check("byApp: empty", V.byApp([]), []);
check("appCounts", V.appCounts(list).map(c => [c.app, c.count]), [["Spotify", 1], ["kitty", 2], ["Notifications", 1]]);

// ── By day ────────────────────────────────────────────────────────────────────
const now = at(2026, 10, 21, 15, 0);
check("day: 5 minutes ago", V.dayLabel(now - 5 * 60000, now), "Last hour");
check("day: 59 minutes ago", V.dayLabel(now - 59 * 60000, now), "Last hour");
check("day: 2 hours ago, same day", V.dayLabel(at(2026, 10, 21, 13, 0), now), "Earlier today");
check("day: just after midnight", V.dayLabel(at(2026, 10, 21, 0, 1), now), "Earlier today");
check("day: late last night", V.dayLabel(at(2026, 10, 20, 23, 59), now), "Yesterday");
check("day: yesterday morning", V.dayLabel(at(2026, 10, 20, 0, 0), now), "Yesterday");
check("day: the day before", V.dayLabel(at(2026, 10, 19, 12, 0), now), "Earlier");
check("day: an hour ago but across midnight is still the last hour",
      V.dayLabel(at(2026, 10, 21, 0, 30), at(2026, 10, 21, 1, 10)), "Last hour");
const day = V.byDay([
    rec("a", "1", "", now - 60000),
    rec("b", "2", "", at(2026, 10, 21, 9, 0)),
    rec("c", "3", "", at(2026, 10, 21, 8, 0)),
    rec("d", "4", "", at(2026, 10, 20, 12, 0)),
], now);
check("byDay: sections in order", day.map(g => g.app), ["Last hour", "Earlier today", "Yesterday"]);
check("byDay: items per section", day.map(g => g.items.length), [1, 2, 1]);

// ── Timed Do Not Disturb ──────────────────────────────────────────────────────
check("morning: from 06:00 it is today 08:00", V.nextMorning(at(2026, 10, 21, 6, 0)), at(2026, 10, 21, 8, 0));
check("morning: from 23:00 it is tomorrow 08:00", V.nextMorning(at(2026, 10, 21, 23, 0)), at(2026, 10, 22, 8, 0));
check("morning: at exactly 08:00 it is tomorrow", V.nextMorning(at(2026, 10, 21, 8, 0)), at(2026, 10, 22, 8, 0));
check("morning: month end rolls over", V.nextMorning(at(2026, 10, 31, 22, 0)), at(2026, 11, 1, 8, 0));
check("morning: another hour", V.nextMorning(at(2026, 10, 21, 6, 0), 7), at(2026, 10, 21, 7, 0));
check("until: later today", V.untilLabel(at(2026, 10, 21, 15, 40), now), "until 15:40");
check("until: zero-padded", V.untilLabel(at(2026, 10, 21, 16, 5), now), "until 16:05");
check("until: tomorrow", V.untilLabel(at(2026, 10, 22, 8, 0), now), "until tomorrow 08:00");
check("until: none", V.untilLabel(0, now), "");
check("until: already past", V.untilLabel(now - 1, now), "");

// ── Snooze ────────────────────────────────────────────────────────────────────
const sn = [
    { rec: { key: "a" }, wakeAt: now + 1000 },
    { rec: { key: "b" }, wakeAt: now - 5000 },
    { rec: { key: "c" }, wakeAt: now },
    { rec: { key: "d" }, wakeAt: now - 9000 },
];
const sp = V.splitSnoozed(sn, now);
check("snooze: due oldest-first", sp.due.map(s => s.rec.key), ["d", "b", "c"]);
check("snooze: the rest keep waiting", sp.waiting.map(s => s.rec.key), ["a"]);
check("snooze: empty", V.splitSnoozed([], now), { due: [], waiting: [] });

// ── Muted apps ────────────────────────────────────────────────────────────────
check("toggle: adds", V.toggleIn(["a"], "b"), ["a", "b"]);
check("toggle: removes", V.toggleIn(["a", "b"], "a"), ["b"]);
const orig = ["a"];
V.toggleIn(orig, "b");
check("toggle: never mutates its input", orig, ["a"]);

if (failures.length) {
    console.log(`FAILED ${failures.length} of ${pass + failures.length}`);
    console.log(failures.join("\n"));
    process.exit(1);
}
console.log(`notifyview: ${pass} checks passed`);
