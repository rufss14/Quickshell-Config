// ── test-reminders.js ─────────────────────────────────────────────────────────
// Regression tests for services/reminders.js — the Calendar page's reminders.
//
//     bun scripts/test-reminders.js          (or: node scripts/test-reminders.js)
//
// Safe to run: pure functions, no files. Times are built with the LOCAL Date
// constructor, so the suite passes in any TZ.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "reminders.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const R = new Function(src + "\nreturn { create, presetDue, dueAt, dueToFire, prune, snooze, sorted, normalize, dueLabel };")();

let pass = 0, fail = 0;
function eq(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    fail++;
    console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`);
}

const L = (y, m, d, h = 0, mi = 0) => new Date(y, m - 1, d, h, mi).getTime();
const NOW = L(2026, 9, 13, 14, 7);   // a Sunday afternoon

// ── Create ────────────────────────────────────────────────────────────────────
{
    const r = R.create("  Buy   milk \n", 0, NOW, "a1");
    eq("create trims and collapses", [r.ok, r.item.text, r.item.due, r.item.done, r.item.notified], [true, "Buy milk", 0, false, false]);
    eq("create empty", R.create("   ", 0, NOW, "x").error, "Write what to remember");
    eq("create too long", R.create("x".repeat(201), 0, NOW, "x").ok, false);
    eq("create bad due", R.create("x", -5, NOW, "x").error, "That time isn't valid");
    eq("create keeps id as string", R.create("x", 0, NOW, 42).item.id, "42");
}

// ── Quick times ───────────────────────────────────────────────────────────────
eq("hour rounds up to 5 min", R.presetDue("hour", NOW), L(2026, 9, 13, 15, 10));
eq("hour on a boundary", R.presetDue("hour", L(2026, 9, 13, 14, 5)), L(2026, 9, 13, 15, 5));
eq("evening today", R.presetDue("evening", NOW), L(2026, 9, 13, 20, 0));
eq("evening after 19:30 is tomorrow", R.presetDue("evening", L(2026, 9, 13, 19, 45)), L(2026, 9, 14, 20, 0));
eq("tomorrow morning", R.presetDue("tomorrow", NOW), L(2026, 9, 14, 9, 0));
eq("tomorrow across a month", R.presetDue("tomorrow", L(2026, 9, 30, 23, 0)), L(2026, 10, 1, 9, 0));
eq("unknown preset", R.presetDue("someday", NOW), 0);

// ── Typed times ───────────────────────────────────────────────────────────────
eq("later today", R.dueAt(L(2026, 9, 13), 18, 30, NOW), L(2026, 9, 13, 18, 30));
eq("past today → tomorrow", R.dueAt(L(2026, 9, 13), 8, 0, NOW), L(2026, 9, 14, 8, 0));
eq("another day as asked", R.dueAt(L(2026, 9, 20), 8, 0, NOW), L(2026, 9, 20, 8, 0));
eq("a past day stays past", R.dueAt(L(2026, 9, 10), 8, 0, NOW), L(2026, 9, 10, 8, 0));

// ── State ─────────────────────────────────────────────────────────────────────
{
    const list = [
        { id: "due",      text: "a", due: NOW - 60000, done: false, notified: false },
        { id: "fired",    text: "b", due: NOW - 60000, done: false, notified: true },
        { id: "future",   text: "c", due: NOW + 60000, done: false, notified: false },
        { id: "untimed",  text: "d", due: 0,           done: false, notified: false },
        { id: "doneDue",  text: "e", due: NOW - 60000, done: true,  notified: false },
    ];
    eq("dueToFire", R.dueToFire(list, NOW).map(r => r.id), ["due"]);
}
{
    const list = [
        { id: "old",   done: true, doneAt: NOW - 25 * 3600e3 },
        { id: "fresh", done: true, doneAt: NOW - 3600e3 },
        { id: "open",  done: false },
    ];
    eq("prune drops done after a day", R.prune(list, NOW).map(r => r.id), ["fresh", "open"]);
}
{
    const s = R.snooze({ id: "s", text: "x", due: NOW - 1000, done: true, doneAt: NOW, notified: true }, 10, NOW);
    eq("snooze re-arms", [s.due, s.notified, s.done, s.doneAt], [NOW + 600000, false, false, 0]);
}
{
    const list = [
        { id: "untimed2", due: 0, done: false, created: 2 },
        { id: "later",    due: NOW + 7200e3, done: false },
        { id: "doneOld",  due: 0, done: true, doneAt: NOW - 5000 },
        { id: "overdue",  due: NOW - 600e3, done: false },
        { id: "untimed1", due: 0, done: false, created: 1 },
        { id: "soon",     due: NOW + 600e3, done: false },
        { id: "doneNew",  due: 0, done: true, doneAt: NOW - 1000 },
    ];
    eq("sorted order", R.sorted(list, NOW).map(r => r.id),
       ["overdue", "soon", "later", "untimed1", "untimed2", "doneNew", "doneOld"]);
}

// ── Loading ───────────────────────────────────────────────────────────────────
eq("normalize garbage", R.normalize({ nope: 1 }), []);
eq("normalize filters and coerces", R.normalize([
    null, 7, { id: "", text: "x" }, { id: "n", text: "  " },
    { id: "ok", text: " Call mum ", due: "1789000000000", done: "yes", notified: true, created: -3 },
]), [{ id: "ok", text: "Call mum", due: 1789000000000, done: false, doneAt: 0, notified: true, created: 0 }]);
eq("normalize caps count", R.normalize(Array.from({ length: 600 }, (_, i) => ({ id: "r" + i, text: "t" }))).length, 500);

// ── Words ─────────────────────────────────────────────────────────────────────
eq("label none", R.dueLabel(0, NOW), "");
eq("label minutes", R.dueLabel(NOW + 25 * 60000, NOW), "in 25 min");
eq("label today", R.dueLabel(L(2026, 9, 13, 20, 0), NOW), "Today 20:00");
eq("label tomorrow", R.dueLabel(L(2026, 9, 14, 9, 0), NOW), "Tomorrow 09:00");
eq("label this week", R.dueLabel(L(2026, 9, 17, 9, 0), NOW), "Thu 09:00");
eq("label far", R.dueLabel(L(2026, 10, 12, 9, 0), NOW), "12 Oct 09:00");
eq("label overdue today", R.dueLabel(L(2026, 9, 13, 13, 0), NOW), "Overdue · 13:00");
eq("label overdue yesterday", R.dueLabel(L(2026, 9, 12, 13, 0), NOW), "Overdue · yesterday 13:00");

console.log(`${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
