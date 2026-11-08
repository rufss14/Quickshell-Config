// ── test-cursoreffects.js ─────────────────────────────────────────────────────
// Tests for services/cursoreffects.js, which builds the Lua handed to
// `hyprctl eval` to configure the hypr-dynamic-cursors plugin.
//
//     bun scripts/test-cursoreffects.js      (or: node scripts/test-cursoreffects.js)
//
// Safe to run: pure functions, no I/O, nothing near a compositor. The .js is loaded by
// stripping its `.pragma library` line, so the tests run against the real file.
//
// The thing worth testing is the trust boundary: the values come from a user-editable
// JSON file and end up as Lua executed inside Hyprland.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "cursoreffects.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { lua, MODES } = new Function(src + "\nreturn { lua, MODES };")();

let pass = 0, fail = 0;
function check(label, ok, detail) {
    if (ok) pass++;
    else { fail++; console.log("FAIL  " + label + (detail ? "  " + detail : "")); }
}
const has = (s, needle) => s.includes(needle);

// ── the defaults are the plugin's own ───────────────────────────────────────
const d = lua({ enabled: true, mode: "tilt", sensitivity: 100, shake: true });
check("guarded by the plugin table", d.startsWith("if hl.plugin.dynamic_cursors then"), d);
check("closes the guard", d.endsWith(" end"), d);
check("100% = plugin default tilt limit", has(d, "tilt = { limit = 5000 }"), d);
check("100% = plugin default stretch limit", has(d, "stretch = { limit = 3000 }"), d);
check("enabled true", has(d, "enabled = true, mode"), d);
check("shake on", has(d, "shake = { enabled = true }"), d);

// ── every mode ──────────────────────────────────────────────────────────────
for (const m of MODES)
    check("mode " + m, has(lua({ enabled: true, mode: m }), 'mode = "' + m + '"'));

// ── off means off, whatever else is set ─────────────────────────────────────
const off = lua({ enabled: false, mode: "stretch", shake: true });
check("disabled → enabled = false", has(off, "enabled = false, mode"), off);
check("missing enabled is off, never on", has(lua({}), "enabled = false, mode"));
check("truthy non-boolean is not on", has(lua({ enabled: "yes" }), "enabled = false, mode"));
check("shake defaults off", has(lua({ enabled: true }), "shake = { enabled = false }"));

// ── sensitivity scales both limits, inversely ───────────────────────────────
const hi = lua({ enabled: true, sensitivity: 200 });
check("200% halves the tilt limit", has(hi, "limit = 2500 }"), hi);
check("200% halves the stretch limit", has(hi, "limit = 1500 }"), hi);
const lo = lua({ enabled: true, sensitivity: 50 });
check("50% doubles the tilt limit", has(lo, "limit = 10000 }"), lo);
check("clamped high", has(lua({ enabled: true, sensitivity: 9999 }), "limit = 2500 }"));
check("clamped low", has(lua({ enabled: true, sensitivity: 1 }), "limit = 10000 }"));
check("NaN → default", has(lua({ enabled: true, sensitivity: "abc" }), "limit = 5000 }"));
check("undefined → default", has(lua({ enabled: true }), "limit = 5000 }"));

// ── the trust boundary ──────────────────────────────────────────────────────
const evil = [
    'tilt"}) os.execute("touch /tmp/pwned") --',
    "tilt\nos.execute('x')",
    'tilt", enabled = true, x = "',
    "",
    null,
    42,
    "TILT",
];
for (const e of evil) {
    const s = lua({ enabled: true, mode: e });
    check("bad mode " + JSON.stringify(e) + " falls back to tilt", has(s, 'mode = "tilt"'), s);
    check("bad mode " + JSON.stringify(e) + " injects nothing", !has(s, "os.execute") && !has(s, "pwned"), s);
}
for (const e of ['1) os.execute("x") --', "1e309", {}, [], NaN, Infinity]) {
    const s = lua({ enabled: true, sensitivity: e });
    check("bad sensitivity " + JSON.stringify(e) + " stays numeric",
        /tilt = \{ limit = \d+ \}, stretch = \{ limit = \d+ \}/.test(s) && !has(s, "os.execute"), s);
}

console.log(pass + " passed, " + fail + " failed");
process.exit(fail ? 1 : 0);
