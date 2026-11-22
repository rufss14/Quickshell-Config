// ── test-workout.js ───────────────────────────────────────────────────────────
// Tests for services/workout.js, the workout log's rules.
//
//     bun scripts/test-workout.js      (or: node scripts/test-workout.js)
//
// Safe to run: pure functions, no I/O. Dates are built from local calendar parts, so the day maths is
// exercised in whatever zone the test runs in (try TZ=Pacific/Auckland and TZ=America/Los_Angeles too).
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "workout.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const W = new Function(src + `
return { empty, clean, normalise, startWorkout, togglePause, elapsed, logSets, planSets, toggleSet, tweakSet, addSetLike, removeSet, removeEntry, finish,
         discard, removeWorkout, setUnit, stats, recents, dayKey, dayStart, byDay, heat, summary, clock, lasted,
         weightText, setText, setRestGoal, parseQuick, quickSpec, suggest, score, bests, isRecord, startFrom, LIBRARY };`)();

let pass = 0, fail = 0;
const failures = [];
function check(name, ok, detail) {
    if (ok) { pass++; return }
    fail++;
    failures.push(`  ${name}${detail ? "\n      " + detail : ""}`);
}
const eq = (name, got, want) =>
    check(name, JSON.stringify(got) === JSON.stringify(want), `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);

const at = (y, m, d, h = 12, min = 0) => new Date(y, m - 1, d, h, min).getTime();
const MIN = 60000;
const bench = { name: "Bench press", kind: "reps", reps: 8, weight: 60, secs: 0 };

// ── start, log, merge ────────────────────────────────────────────────────────
{
    let s = W.startWorkout(W.empty(), 1000);
    check("start makes an active session", s.active && s.active.start === 1000 && s.active.entries.length === 0);
    check("starting twice changes nothing", W.startWorkout(s, 5000) === s);

    const noName = W.logSets(s, { ...bench, name: "   " }, 1, 1100);
    check("a nameless set is a no-op", noName === s);
    check("a rep set with no reps is a no-op", W.logSets(s, { ...bench, reps: 0 }, 1, 1100) === s);
    check("a time set with no seconds is a no-op", W.logSets(s, { name: "Plank", kind: "time", secs: 0 }, 1, 1100) === s);
    check("logging with no workout is a no-op", W.logSets(W.empty(), bench, 1, 1) .active === null);

    s = W.logSets(s, bench, 3, 2000);
    eq("three sets make one exercise", [s.active.entries.length, s.active.entries[0].sets.length], [1, 3]);
    s = W.logSets(s, { ...bench, name: "bench PRESS", weight: 62.5 }, 1, 3000);
    eq("the same name in another case joins the exercise", [s.active.entries.length, s.active.entries[0].sets.length], [1, 4]);
    eq("the joined set keeps its own weight", s.active.entries[0].sets[3].weight, 62.5);
    s = W.logSets(s, { name: "Plank", kind: "time", secs: 45, weight: 0 }, 1, 4000);
    eq("a different exercise is its own entry", s.active.entries.map(e => e.name), ["Bench press", "Plank"]);
    s = W.logSets(s, { name: "Plank", kind: "reps", reps: 5 }, 1, 4500);
    eq("the same name as another KIND is separate", s.active.entries.length, 3);
    eq("at most 20 sets at once", W.logSets(W.startWorkout(W.empty(), 1), bench, 99, 2).active.entries[0].sets.length, 20);
    const ids = s.active.entries.map(e => e.id);
    check("entry ids are unique", new Set(ids).size === ids.length);
    const before = JSON.stringify(s);
    W.logSets(s, bench, 2, 9000);
    check("logging does not mutate its argument", JSON.stringify(s) === before);
}


// ── the checklist: plan, tick, tweak, finish ─────────────────────────────────
{
    let s = W.startWorkout(W.empty(), 1000);
    s = W.planSets(s, bench, 3, 1100);
    const id = s.active.entries[0].id;
    eq("planned sets are not done", s.active.entries[0].sets.map(x => x.done), [false, false, false]);
    eq("planned sets do not count", W.stats(s.active), { sets: 0, reps: 0, volume: 0, secs: 0, exercises: 1, total: 3 });

    s = W.toggleSet(s, id, 1, 2000);
    eq("ticking a set marks it done, now", [s.active.entries[0].sets[1].done, s.active.entries[0].sets[1].at], [true, 2000]);
    eq("and it counts", [W.stats(s.active).sets, W.stats(s.active).volume], [1, 480]);
    s = W.toggleSet(s, id, 1, 3000);
    eq("ticking again takes it back", [s.active.entries[0].sets[1].done, s.active.entries[0].sets[1].at], [false, 0]);
    check("an unknown set is a no-op", W.toggleSet(s, id, 9, 1) === s && W.toggleSet(s, 99, 0, 1) === s);

    s = W.tweakSet(s, id, 0, { reps: 12, weight: 62.5 });
    eq("tweak changes the numbers", [s.active.entries[0].sets[0].reps, s.active.entries[0].sets[0].weight], [12, 62.5]);
    eq("and nothing else", [s.active.entries[0].sets[0].done, s.active.entries[0].sets[1].reps], [false, 8]);
    check("tweaking to the same numbers is a no-op", W.tweakSet(s, id, 0, { reps: 12 }) === s);
    eq("a set never drops below one rep", W.tweakSet(s, id, 0, { reps: 0 }).active.entries[0].sets[0].reps, 1);
    eq("weight is clamped", W.tweakSet(s, id, 0, { weight: -5 }).active.entries[0].sets[0].weight, 0);
    const timed = W.planSets(W.startWorkout(W.empty(), 1), { name: "Plank", kind: "time", secs: 30 }, 1, 2);
    eq("a time set keeps a second", W.tweakSet(timed, timed.active.entries[0].id, 0, { secs: 0 }).active.entries[0].sets[0].secs, 1);

    s = W.addSetLike(s, id);
    eq("one more like the last, still to do", [s.active.entries[0].sets.length, s.active.entries[0].sets[3].done, s.active.entries[0].sets[3].reps], [4, false, 8]);
    check("addSetLike on an unknown exercise is a no-op", W.addSetLike(s, 99) === s);

    // Finishing keeps only what was done.
    s = W.toggleSet(W.toggleSet(s, id, 0, 4000), id, 2, 5000);
    const fin = W.finish(s, 6000);
    eq("finish keeps the done sets only", fin.history[0].entries[0].sets.map(x => x.done), [true, true]);
    eq("the log counts them", W.stats(fin.history[0]).sets, 2);
    const none = W.finish(W.planSets(W.startWorkout(W.empty(), 1), bench, 2, 2), 3);
    eq("a workout with nothing ticked is not kept", [none.active, none.history.length], [null, 0]);
    const two = W.planSets(W.logSets(W.startWorkout(W.empty(), 1), bench, 1, 2), { name: "Row", kind: "reps", reps: 8 }, 2, 3);
    eq("an exercise with nothing ticked is dropped", W.finish(two, 9).history[0].entries.map(e => e.name), ["Bench press"]);

    // Old logs: no `done` field means done.
    const old = W.normalise({ history: [{ id: 1, start: 5, end: 9, entries: [{ id: 2, name: "Old", sets: [{ reps: 5, weight: 10 }] }] }] });
    eq("a set with no done field is done", old.history[0].entries[0].sets[0].done, true);
    eq("and it counts", W.stats(old.history[0]).sets, 1);
    const rec = W.recents(W.planSets(W.logSets(W.startWorkout(W.empty(), 10), bench, 1, 20), { ...bench, reps: 99, weight: 99 }, 1, 30), 3);
    eq("recents read the last DONE set, not a plan", [rec[0].reps, rec[0].weight], [8, 60]);
}

// ── remove ───────────────────────────────────────────────────────────────────
{
    let s = W.logSets(W.startWorkout(W.empty(), 1), bench, 2, 2);
    const id = s.active.entries[0].id;
    s = W.removeSet(s, id, 0);
    eq("removing a set leaves the other", s.active.entries[0].sets.length, 1);
    s = W.removeSet(s, id, 0);
    eq("removing the last set removes the exercise", s.active.entries.length, 0);
    check("an unknown set is a no-op", W.removeSet(s, 999, 0) === s);
    let t = W.logSets(W.startWorkout(W.empty(), 1), bench, 2, 2);
    t = W.removeEntry(t, t.active.entries[0].id);
    eq("remove an exercise", t.active.entries.length, 0);
    check("an unknown exercise is a no-op", W.removeEntry(t, 5) === t);
}

// ── the clock, pauses ────────────────────────────────────────────────────────
{
    let s = W.startWorkout(W.empty(), 0);
    eq("elapsed runs from the start", W.elapsed(s.active, 90 * 1000), 90000);
    s = W.togglePause(s, 60 * 1000);
    eq("a pause stops the clock", W.elapsed(s.active, 500 * 1000), 60000);
    s = W.togglePause(s, 120 * 1000);
    eq("resuming drops the time paused", W.elapsed(s.active, 180 * 1000), 120000);
    eq("pausedMs is the sum of pauses", s.active.pausedMs, 60000);
    eq("elapsed of nothing is 0", W.elapsed(null, 5), 0);

    // Finishing while paused counts the pause, not as work.
    s = W.logSets(s, bench, 1, 130 * 1000);
    s = W.togglePause(s, 200 * 1000);
    const done = W.finish(s, 500 * 1000);
    eq("finish moves it to the history", [done.active, done.history.length], [null, 1]);
    eq("finish ends a running pause", done.history[0].pausedAt, 0);
    eq("a finished session's time ignores the pauses", W.elapsed(done.history[0], 99999999), 500000 - 60000 - 300000);
}

// ── finish, discard ──────────────────────────────────────────────────────────
{
    const empty = W.finish(W.startWorkout(W.empty(), 1), 2);
    eq("a workout with nothing in it is not kept", [empty.active, empty.history.length], [null, 0]);
    let s = W.logSets(W.startWorkout(W.empty(), 1000), bench, 1, 1500);
    s = W.finish(s, 2000);
    let t = W.logSets(W.startWorkout(s, 5000), bench, 1, 5500);
    t = W.finish(t, 6000);
    eq("newest first", t.history.map(x => x.start), [5000, 1000]);
    eq("discard drops the active one", W.discard(W.startWorkout(W.empty(), 1)).active, null);
    check("discard with none is a no-op", W.discard(t) === t);
    eq("remove a workout", W.removeWorkout(t, t.history[0].id).history.length, 1);
    check("an unknown workout is a no-op", W.removeWorkout(t, 12345) === t);
    eq("the unit", [W.setUnit(t, "lb").unit, W.setUnit(t, "stone").unit], ["lb", "kg"]);
}

// ── stats ────────────────────────────────────────────────────────────────────
{
    let s = W.startWorkout(W.empty(), 1);
    s = W.logSets(s, bench, 3, 2);                                           // 3 × 8 × 60 = 1440
    s = W.logSets(s, { name: "Plank", kind: "time", secs: 45, weight: 0 }, 2, 3);
    eq("stats", W.stats(s.active), { sets: 5, reps: 24, volume: 1440, secs: 90, exercises: 2, total: 5 });
    eq("stats of nothing", W.stats(null), { sets: 0, reps: 0, volume: 0, secs: 0, exercises: 0, total: 0 });
}

// ── the disk is a trust boundary ─────────────────────────────────────────────
{
    eq("nothing read gives an empty log", W.normalise(null), W.empty());
    eq("garbage gives an empty log", W.normalise("x"), W.empty());
    const doc = {
        unit: "lb", seq: 2,
        history: [
            { id: 1, start: at(2026, 11, 1), end: at(2026, 11, 1) + MIN * 30, pausedMs: -5,
              entries: [{ id: 1, name: " Squat \n", kind: "time", sets: [{ reps: "12", weight: "100", secs: 1e9 }] },
                        { id: 1, name: "", sets: [{ reps: 1 }] },
                        { id: 2, name: "Empty", sets: [] }, 7, null] },
            { id: 1, start: 0, end: 5, entries: [] },
            { id: 3, start: at(2026, 11, 3), end: 0, entries: [{ name: "Open", sets: [{ reps: 5 }] }] },
            null, "no"
        ],
        active: { id: 9, start: at(2026, 11, 5), end: 77, entries: [{ name: "Row", sets: [{ reps: 10, weight: 40 }] }] }
    };
    const n = W.normalise(doc);
    eq("junk sessions are dropped (no start, no end, no entries)", n.history.length, 1);
    eq("an entry is rebuilt", [n.history[0].entries.length, n.history[0].entries[0].name, n.history[0].entries[0].kind],
       [1, "Squat", "time"]);
    eq("numbers are clamped", [n.history[0].entries[0].sets[0].secs, n.history[0].pausedMs], [86400, 0]);
    eq("the unit is read", n.unit, "lb");
    check("the active session survives, still open", n.active && n.active.end === 0 && n.active.entries[0].name === "Row");
    const all = [n.history[0].id, n.history[0].entries[0].id, n.active.id, n.active.entries[0].id];
    check("every id is unique", new Set(all).size === all.length, JSON.stringify(all));
    check("seq is past every id", n.seq >= Math.max(...all));
    check("a long name is capped", W.clean("x".repeat(200)).length <= 60);
    const again = W.startWorkout(W.finish(W.discard(n), 1), 5);
    check("a new id after normalise is fresh", again.active.id > Math.max(...all));
}

// ── recents ──────────────────────────────────────────────────────────────────
{
    let s = W.logSets(W.startWorkout(W.empty(), at(2026, 11, 1)), bench, 1, at(2026, 11, 1));
    s = W.logSets(s, { name: "Squat", kind: "reps", reps: 5, weight: 100 }, 1, at(2026, 11, 1, 12, 5));
    s = W.finish(s, at(2026, 11, 1, 13));
    let t = W.logSets(W.startWorkout(s, at(2026, 11, 3)), { ...bench, reps: 6, weight: 65 }, 1, at(2026, 11, 3));
    const r = W.recents(t, 5);
    eq("most recent first, one per exercise", r.map(x => x.name), ["Bench press", "Squat"]);
    eq("it carries the newest values", [r[0].reps, r[0].weight, r[0].uses], [6, 65, 2]);
    eq("limit", W.recents(t, 1).length, 1);
}

// ── dates ────────────────────────────────────────────────────────────────────
{
    eq("dayKey is local and padded", W.dayKey(at(2026, 1, 5, 23, 59)), "2026-01-05");
    eq("just after midnight is the new day", W.dayKey(at(2026, 1, 6, 0, 1)), "2026-01-06");
    const mk = (y, m, d, h) => ({ id: d, start: at(y, m, d, h), end: at(y, m, d, h) + MIN, pausedMs: 0, pausedAt: 0, entries: [] });
    const hist = [mk(2026, 11, 16, 19), mk(2026, 11, 16, 7), mk(2026, 11, 15, 12), mk(2026, 11, 13, 12)];
    eq("byDay groups", Object.keys(W.byDay(hist)).sort(), ["2026-11-13", "2026-11-15", "2026-11-16"]);
    eq("two on one day", W.byDay(hist)["2026-11-16"].length, 2);

    // 2026-11-16 is a Monday.
    const now = at(2026, 11, 18, 10);                                        // a Wednesday
    const grid = W.heat(hist, now, 4, 0);
    eq("heat: weeks and days", [grid.length, grid[0].length], [4, 7]);
    eq("heat: the last column starts on the Monday of this week", grid[3][0].key, "2026-11-16");
    eq("heat: the count on a day", [grid[3][0].count, grid[2][6].count], [2, 1]);
    eq("heat: Friday the 13th", [grid[2][4].key, grid[2][4].count], ["2026-11-13", 1]);
    eq("heat: Thursday is in the future, today is not", [grid[3][3].future, grid[3][2].future], [true, false]);
    eq("heat: the first column is three weeks before", grid[0][0].key, "2026-10-26");
    const back = W.heat(hist, now, 4, 1);
    eq("heat: one week back shifts the window", back[3][0].key, "2026-11-09");
    eq("heat: no future days a week back", back[3].some(c => c.future), false);
    // Seven columns of seven distinct days, in order, across a clock change.
    for (const [y, m, d] of [[2026, 3, 29], [2026, 10, 25], [2026, 11, 8]]) {
        const g = W.heat([], at(y, m, d, 12), 8, 0).flat().map(c => c.key);
        check(`heat: ${g.length} distinct days around ${y}-${m}-${d}`, new Set(g).size === 56);
    }

    eq("summary: week, total, streak", W.summary(hist, now), { week: 4, total: 4, streak: 0 });
    eq("summary: streak counts back from today", W.summary(hist, at(2026, 11, 16, 22)).streak, 2);
    eq("summary: or from yesterday while today is open", W.summary(hist, at(2026, 11, 17, 9)).streak, 2);
    eq("summary: empty", W.summary([], now), { week: 0, total: 0, streak: 0 });
}

// ── typing an exercise ───────────────────────────────────────────────────────
{
    const P = (t, u = "kg") => { const p = W.parseQuick(t, u); return [p.name, p.kind, p.sets, p.reps, p.secs, p.weight]; };
    eq("name only", P("pull-ups"), ["pull-ups", null, 0, 0, 0, -1]);
    eq("3x8 and a weight", P("bench 3x8 60kg"), ["bench", null, 3, 8, 0, 60]);
    eq("@ weight", P("squat 5x5 @ 100"), ["squat", null, 5, 5, 0, 100]);
    eq("× sign", P("curl 3×12 15kg"), ["curl", null, 3, 12, 0, 15]);
    eq("sets and reps in words", P("pull-ups 4 sets 10 reps"), ["pull-ups", "reps", 4, 10, 0, -1]);
    eq("seconds", P("plank 45s"), ["plank", "time", 0, 0, 45, -1]);
    eq("sets of seconds", P("plank 3x45s"), ["plank", "time", 3, 0, 45, -1]);
    eq("sets of minutes:seconds", P("plank 3x1:30"), ["plank", "time", 3, 0, 90, -1]);
    eq("minutes", P("wall sit 2 min"), ["wall sit", "time", 0, 0, 120, -1]);
    eq("a lone number at the end is reps", P("push-ups 15"), ["push-ups", "reps", 0, 15, 0, -1]);
    eq("a weight alone", P("deadlift 100kg"), ["deadlift", null, 0, 0, 0, 100]);
    eq("quantities first, name after", P("3x8 bench press 60kg"), ["bench press", null, 3, 8, 0, 60]);
    eq("decimal weight, comma", P("press 3x5 42,5kg"), ["press", null, 3, 5, 0, 42.5]);
    eq("a weighted time set", P("farmer's carry 30s 24kg"), ["farmer's carry", "time", 0, 0, 30, 24]);
    eq("lb typed while the unit is kg converts", P("bench 135lb")[5], 61.23);
    eq("kg typed while the unit is lb converts", P("bench 60kg", "lb")[5], 132.28);
    eq("a bare weight uses the unit", P("bench @ 135", "lb")[5], 135);
    eq("a leftover number after reps is the weight", P("bench 5x3 70"), ["bench", null, 5, 3, 0, 70]);
    eq("nothing typed", P(""), ["", null, 0, 0, 0, -1]);
    eq("the tail keeps what was typed", W.parseQuick("bench 3x8 60kg").tail, "3x8 60kg");
    eq("any", [W.parseQuick("bench").any, W.parseQuick("bench 3x8").any], [false, true]);
    eq("sets are capped", W.parseQuick("x 99x5").sets, 20);
    check("garbage does not throw", ["@@@", "x x x", "1:", "99999999999999999999 reps", "3x", "kg"].every(t => W.parseQuick(t) !== null));

    // quickSpec: typed, then last time, then the steppers.
    const d = { kind: "reps", sets: 3, reps: 10, weight: 0, secs: 45 };
    let s = W.logSets(W.startWorkout(W.empty(), 1), { name: "Bench press", kind: "reps", reps: 6, weight: 65 }, 1, 2);
    s = W.finish(s, 3);
    eq("a new exercise takes the steppers", (({ name, kind, sets, reps, weight }) => [name, kind, sets, reps, weight])(W.quickSpec(s, "Cable fly", "kg", d)), ["Cable fly", "reps", 3, 10, 0]);
    eq("a known one takes its last numbers, in its own case", (({ name, sets, reps, weight, known }) => [name, sets, reps, weight, known])(W.quickSpec(s, "bench PRESS", "kg", d)), ["Bench press", 3, 6, 65, true]);
    eq("what was typed wins", (({ sets, reps, weight }) => [sets, reps, weight])(W.quickSpec(s, "bench press 5x3 70", "kg", d)), [5, 3, 70]);
    eq("a library exercise knows it is timed", W.quickSpec(s, "plank", "kg", d).kind, "time");
    eq("the library's casing", W.quickSpec(s, "plank", "kg", d).name, "Plank");
    eq("a typed time makes it timed", W.quickSpec(s, "bridge 30s", "kg", d).kind, "time");
    eq("said", W.quickSpec(s, "bench 3x8", "kg", d).said, { sets: true, reps: true, secs: false, weight: false });

    // suggest
    eq("nothing typed: what you did", W.suggest(s, "", 5).map(r => r.name), ["Bench press"]);
    eq("a prefix first, then a word that starts with it", W.suggest(s, "pul", 3).map(r => r.name), ["Pull-ups", "Face pull", "Lat pulldown"]);
    eq("yours first, then the list", W.suggest(s, "press", 4).map(r => r.name), ["Bench press", "Incline bench press", "Leg press", "Overhead press"]);
    eq("a word inside", W.suggest(s, "raise", 9).map(r => r.name).sort(), ["Calf raise", "Lateral raise", "Leg raise"]);
    eq("two words", W.suggest(s, "bench pr", 5).map(r => r.name), ["Bench press", "Incline bench press"]);
    eq("numbers do not count", W.suggest(s, "bench 3x8", 1).map(r => r.name), ["Bench press"]);
    eq("no match", W.suggest(s, "zzzz", 5), []);
    eq("limit", W.suggest(s, "e", 2).length, 2);
    check("the library has no duplicates", new Set(W.LIBRARY.map(l => l.name.toLowerCase())).size === W.LIBRARY.length);
}

// ── records ──────────────────────────────────────────────────────────────────
{
    eq("score: loaded, bodyweight, timed", [W.score("reps", { reps: 30, weight: 100 }), W.score("reps", { reps: 12, weight: 0 }), W.score("time", { secs: 90, weight: 0 })], [200, 12, 90]);
    let s = W.logSets(W.startWorkout(W.empty(), 1), bench, 2, 2);
    s = W.finish(s, 3);
    const best = W.bests(s.history);
    check("bests are per exercise and kind", Object.keys(best).join() === "reps:bench press");
    check("heavier is a record", W.isRecord(best, "reps", "Bench press", { reps: 8, weight: 62.5 }));
    check("the same is not", !W.isRecord(best, "reps", "Bench press", { reps: 8, weight: 60 }));
    check("lighter is not", !W.isRecord(best, "reps", "bench press", { reps: 8, weight: 50 }));
    check("more reps at the same weight is", W.isRecord(best, "reps", "bench press", { reps: 10, weight: 60 }));
    check("the first time ever is not a record", !W.isRecord(best, "reps", "Squat", { reps: 5, weight: 100 }));
    check("undone sets do not set a bar", Object.keys(W.bests([{ entries: [{ name: "X", kind: "reps", sets: [{ reps: 5, weight: 9, done: false }] }] }])).length === 0);
}

// ── do it again ──────────────────────────────────────────────────────────────
{
    let s = W.logSets(W.startWorkout(W.empty(), 1), bench, 2, 2);
    s = W.logSets(s, { name: "Plank", kind: "time", secs: 45 }, 1, 3);
    s = W.finish(s, 9);
    const again = W.startFrom(s, s.history[0], 100);
    eq("the same exercises, nothing done", [again.active.entries.map(e => e.name), again.active.entries.map(e => e.sets.every(x => x.done === false))], [["Bench press", "Plank"], [true, true]]);
    eq("and the same numbers", [again.active.entries[0].sets.length, again.active.entries[0].sets[0].weight], [2, 60]);
    const ids = [again.active.id, ...again.active.entries.map(e => e.id), ...again.history.map(h => h.id)];
    check("ids stay unique", new Set(ids).size === ids.length, JSON.stringify(ids));
    check("it does not touch the old one", s.history[0].entries[0].sets[0].done === true);
    check("not while one is running", W.startFrom(again, s.history[0], 5) === again);
    check("nothing to copy is a no-op", W.startFrom(s, null, 5) === s);
}

// ── the rest goal ────────────────────────────────────────────────────────────
{
    const s = W.empty();
    eq("the default rest", s.restGoal, 90);
    eq("set, rounded to 5 s", W.setRestGoal(s, 62).restGoal, 60);
    eq("clamped", [W.setRestGoal(s, 1).restGoal, W.setRestGoal(s, 99999).restGoal], [15, 600]);
    check("the same goal is a no-op", W.setRestGoal(s, 90) === s);
    eq("read from disk, clamped", [W.normalise({ restGoal: 120 }).restGoal, W.normalise({ restGoal: "x" }).restGoal, W.normalise({ restGoal: 5 }).restGoal], [120, 90, 15]);
}

// ── words ────────────────────────────────────────────────────────────────────
{
    eq("clock under an hour", W.clock(754000), "12:34");
    eq("clock over an hour", W.clock(4521000), "1:15:21");
    eq("clock never negative", W.clock(-5), "00:00");
    eq("lasted", [W.lasted(2880000), W.lasted(3900000), W.lasted(1000)], ["48 min", "1 h 05 min", "1 min"]);
    eq("weightText", [W.weightText(20), W.weightText(22.5), W.weightText("20.00")], ["20", "22.5", "20"]);
    eq("setText reps", [W.setText("reps", { reps: 12, weight: 20 }, "kg"), W.setText("reps", { reps: 12, weight: 0 }, "kg")],
       ["12 × 20 kg", "12 reps"]);
    eq("setText time", [W.setText("time", { secs: 45, weight: 0 }, "kg"), W.setText("time", { secs: 90, weight: 10 }, "lb")],
       ["45 s", "1:30 · 10 lb"]);
}

console.log(`${pass} passed, ${fail} failed`);
if (fail) { console.log(failures.join("\n")); process.exit(1); }
