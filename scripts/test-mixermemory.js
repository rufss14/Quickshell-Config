// ── test-mixermemory.js ───────────────────────────────────────────────────────
// Tests for services/mixermemory.js — the mixer's per-app memory.
//
//     bun scripts/test-mixermemory.js      (or: node scripts/test-mixermemory.js)
//
// Pure functions, no I/O.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "mixermemory.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const M = new Function(src + "\nreturn { MAX_APPS, keyOf, cleanMemory, remember, forget, clampLevel };")();

let pass = 0, fail = 0;
function check(name, ok, detail) {
    if (ok) pass++; else { fail++; console.log("FAIL", name, detail === undefined ? "" : JSON.stringify(detail)); }
}
const J = JSON.stringify;

// ── keys ──
check("a key is lower-cased and trimmed", M.keyOf("  Spotify ") === "spotify");
check("nothing usable is an empty key", M.keyOf("") === "" && M.keyOf(null) === "" && M.keyOf(undefined) === "" && M.keyOf("x".repeat(81)) === "");
check("levels clamp to 0..1.3", M.clampLevel(5) === 1.3 && M.clampLevel(-1) === 0 && M.clampLevel("x") === 1 && M.clampLevel(0.4) === 0.4);

// ── memory ──
const t0 = 1_700_000_000_000;
let mem = M.remember({}, "Spotify", { level: 0.4, sink: "alsa_output.usb", name: "Spotify" }, t0);
check("remember stores a record under the lower-case key", mem.spotify && mem.spotify.level === 0.4 && mem.spotify.sink === "alsa_output.usb" && mem.spotify.muted === false, mem);
mem = M.remember(mem, "spotify", { muted: true }, t0 + 5);
check("a patch is laid over the old record", mem.spotify.level === 0.4 && mem.spotify.muted === true && mem.spotify.at === t0 + 5, mem);
check("an unusable key changes nothing", M.remember(mem, "", { level: 1 }, t0) === mem);
check("forget removes one", !("spotify" in M.forget(mem, "Spotify")) && M.forget(mem, "nope") === mem);
check("forget does not mutate", "spotify" in mem);

let big = {};
for (let i = 0; i < 50; i++) big = M.remember(big, "app" + i, { level: 0.5 }, t0 + i);
check("memory is capped, oldest dropped", Object.keys(big).length === M.MAX_APPS && "app49" in big && !("app0" in big), Object.keys(big).length);

const clean = M.cleanMemory({ apps: {
    good: { level: 0.5, muted: true, sink: "s", name: "G", at: 5 },
    "Bad Key": { level: 0.5 },
    nolevel: { muted: true },
    junk: 7, nul: null,
    loud: { level: 9, sink: 5, name: "x".repeat(200) }
} });
check("cleanMemory keeps well-formed records only", Object.keys(clean).sort().join() === "good,loud", clean);
check("cleanMemory clamps and tidies fields", clean.loud.level === 1.3 && clean.loud.sink === "" && clean.loud.name.length === 60 && clean.good.muted === true, clean);
check("cleanMemory of nothing is empty", J(M.cleanMemory(null)) === "{}" && J(M.cleanMemory({})) === "{}" && J(M.cleanMemory({ apps: 3 })) === "{}" && J(M.cleanMemory("x")) === "{}");

console.log(`mixermemory: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
