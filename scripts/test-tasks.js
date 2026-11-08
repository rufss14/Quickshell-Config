// ── test-tasks.js ─────────────────────────────────────────────────────────────
// Tests for services/tasks.js, the to-do list's rules.
//
//     bun scripts/test-tasks.js      (or: node scripts/test-tasks.js)
//
// Safe to run: pure functions, no I/O.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "tasks.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const T = new Function(src + "\nreturn { empty, clean, normalise, add, toggle, rename, remove, clearDone, view, openCount };")();

let pass = 0, fail = 0;
const failures = [];
function check(name, ok, detail) {
    if (ok) { pass++; return }
    fail++;
    failures.push(`  ${name}${detail ? "\n      " + detail : ""}`);
}
const eq = (name, got, want) =>
    check(name, JSON.stringify(got) === JSON.stringify(want), `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);

// ── add ──────────────────────────────────────────────────────────────────────
{
    const s0 = T.empty();
    const s1 = T.add(s0, "  buy milk  ", 100);
    eq("add trims and appends", s1.items.map(i => i.text), ["buy milk"]);
    eq("add leaves the old state alone", s0.items.length, 0);
    eq("ids count up", T.add(s1, "b", 101).items.map(i => i.id), [1, 2]);
    check("empty text is refused", T.add(s0, "   ", 1) === s0);
    check("null text is refused", T.add(s0, null, 1) === s0);
    eq("newlines flatten", T.add(s0, "a\n\nb", 1).items[0].text, "a b");
    check("long text is capped", T.add(s0, "x".repeat(900), 1).items[0].text.length <= 200);
}

// ── ids are never reused ─────────────────────────────────────────────────────
{
    let s = T.add(T.add(T.empty(), "a", 1), "b", 2);
    s = T.remove(s, 2);
    eq("a removed id isn't handed out again", T.add(s, "c", 3).items.map(i => i.id), [1, 3]);
}

// ── toggle / rename / remove ────────────────────────────────────────────────
{
    const s = T.add(T.empty(), "a", 1);
    const d = T.toggle(s, 1, 50);
    eq("toggle marks done with the moment", [d.items[0].done, d.items[0].doneAt], [true, 50]);
    eq("toggle back clears the moment", [T.toggle(d, 1, 60).items[0].done, T.toggle(d, 1, 60).items[0].doneAt], [false, 0]);
    check("toggle of a missing id changes nothing", T.toggle(s, 99, 1) === s);
    eq("rename", T.rename(s, 1, "  z ").items[0].text, "z");
    check("rename to nothing is refused", T.rename(s, 1, " ") === s);
    check("remove of a missing id changes nothing", T.remove(s, 99) === s);
    eq("remove", T.remove(s, 1).items.length, 0);
    eq("the argument is never mutated", s.items[0].done, false);
}

// ── clearDone, view, openCount ──────────────────────────────────────────────
{
    let s = T.empty();
    for (const t of ["a", "b", "c", "d"]) s = T.add(s, t, 1);
    s = T.toggle(s, 2, 10);
    s = T.toggle(s, 4, 20);
    eq("open first in order, then done newest-first", T.view(s).map(i => i.text), ["a", "c", "d", "b"]);
    eq("openCount", T.openCount(s), 2);
    eq("clearDone drops the finished", T.clearDone(s).items.map(i => i.text), ["a", "c"]);
    check("clearDone with none done changes nothing", (x => T.clearDone(x) === x)(T.add(T.empty(), "a", 1)));
}

// ── normalise: the file on disk ─────────────────────────────────────────────
eq("garbage in, empty out", T.normalise("nope"), { items: [], seq: 0 });
eq("null doc", T.normalise(null), { items: [], seq: 0 });
eq("items not an array", T.normalise({ items: 5 }), { items: [], seq: 0 });
{
    const n = T.normalise({ seq: 2, items: [
        { id: 1, text: "ok", done: true, at: 5, doneAt: 9 },
        { id: 1, text: "duplicate id" },
        { id: "x", text: "bad id" },
        { id: 3, text: "   " },
        { id: 4, text: "kept\nclean", done: "yes" },
        null, 7
    ] });
    eq("duplicates, bad ids, blanks and junk dropped", n.items.map(i => i.id), [1, 4]);
    eq("text is cleaned on load", n.items[1].text, "kept clean");
    eq("done must be exactly true", n.items[1].done, false);
    eq("seq moves past the highest id", n.seq, 4);
    eq("a finished item keeps its moment", n.items[0].doneAt, 9);
}
check("load is capped", T.normalise({ items: Array.from({ length: 900 }, (_, i) => ({ id: i + 1, text: "t" })) }).items.length === 500);

if (fail) {
    console.log(`FAIL  ${fail} failed, ${pass} passed`);
    console.log(failures.join("\n"));
    process.exit(1);
}
console.log(`ok  ${pass} checks`);
