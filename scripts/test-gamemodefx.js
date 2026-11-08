// ── test-gamemodefx.js ────────────────────────────────────────────────────────
// Tests for services/gamemodefx.js — the Lua Game Mode sends to put blur, shadows and
// animations out and back.
//
//     bun scripts/test-gamemodefx.js      (or: node scripts/test-gamemodefx.js)
//
// Safe to run: pure functions, no I/O. The getoption lines are REAL `hyprctl -j getoption`
// output (Hyprland 0.57.1 here): note `"set": false` on an option the config never set.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "gamemodefx.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const F = new Function(src + "\nreturn { OPTIONS, snapshotFrom, cleanSnapshot, offLua, restoreLua };")();

let pass = 0, fail = 0;
const failures = [];
function check(name, ok, detail) {
    if (ok) { pass++; return }
    fail++;
    failures.push(`  ${name}${detail ? "\n      " + detail : ""}`);
}
const J = v => JSON.stringify(v);

const real = [
    '{"option": "animations:enabled", "bool": true, "set": false }',
    '{"option": "decoration:blur:enabled", "bool": true, "set": true }',
    '{"option": "decoration:shadow:enabled", "bool": false, "set": true }',
].join("\n\n");
const snap = F.snapshotFrom(real);
check("snapshot reads every option's boolean", J(snap) === J({
    "animations:enabled": true, "decoration:blur:enabled": true, "decoration:shadow:enabled": false }), J(snap));

check("garbage, blanks and a failed option are skipped",
      J(F.snapshotFrom('nope\n\n{"option": "animations:enabled", "bool": false}\n{"error":"x"}\n'))
      === J({ "animations:enabled": false }));
check("an option that is not on the list is ignored",
      J(F.snapshotFrom('{"option": "general:gaps_in", "bool": true}')) === "{}");
check("a non-boolean answer is ignored",
      J(F.snapshotFrom('{"option": "animations:enabled", "int": 1}')) === "{}");
check("empty and undefined are empty", J(F.snapshotFrom("")) === "{}" && J(F.snapshotFrom(undefined)) === "{}");

check("off turns all three off, merged under shared tables",
      F.offLua() === "hl.config({ animations = { enabled = false }, decoration = { blur = { enabled = false }, shadow = { enabled = false } } })",
      F.offLua());
check("restore puts back exactly what was read (shadow stays off)",
      F.restoreLua(snap) === "hl.config({ animations = { enabled = true }, decoration = { blur = { enabled = true }, shadow = { enabled = false } } })",
      F.restoreLua(snap));
check("a partial snapshot restores only what it has",
      F.restoreLua({ "decoration:blur:enabled": true }) === "hl.config({ decoration = { blur = { enabled = true } } })");
check("nothing to restore is empty Lua", F.restoreLua({}) === "" && F.restoreLua(null) === "" && F.restoreLua("x") === "");

// What comes back off disk is untrusted: only listed options, only booleans.
const dirty = F.cleanSnapshot({ "animations:enabled": "true", "decoration:blur:enabled": true,
                                "evil": true, "decoration:shadow:enabled": 1 });
check("a hand-edited file keeps only listed booleans", J(dirty) === J({ "decoration:blur:enabled": true }), J(dirty));
check("restore never emits an unlisted key",
      !/evil/.test(F.restoreLua({ evil: true, "animations:enabled": false })));

console.log(`gamemodefx: ${pass} passed, ${fail} failed`);
if (fail) { console.log(failures.join("\n")); process.exit(1); }
