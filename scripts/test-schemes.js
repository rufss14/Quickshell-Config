// ── test-schemes.js ───────────────────────────────────────────────────────────
// services/schemes.js: the classic colour schemes the shell ships.
//
//     bun scripts/test-schemes.js     (or: node ...)
//
// Reads schemes.js and palette.js; writes nothing.
//
// What goes wrong is silent: a mistyped hex makes one slot black-on-black, a variant filed under
// the wrong mode wears the wrong light/dark rules, and a palette short of a slot falls back to
// PaletteRoles' monochrome for just that role. So every variant of every scheme is checked
// whole: all 18 slots present and valid, its mode matching its ground, its text and accents
// legible on that ground.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const load = (f, exports) => new Function(
    readFileSync(join(here, "..", "services", f), "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "")
    + "\nreturn { " + exports + " };")();
const S = load("schemes.js", "list, build");
const P = load("palette.js", "contrast, schemeMode, unpackScheme, packScheme, pickVariant, rampSlots");

let pass = 0, fail = 0;
function ok(name, cond, detail) {
    if (cond) pass++;
    else { fail++; console.log(`  FAIL  ${name}${detail ? "\n          " + detail : ""}`); }
}
const HEX = /^#[0-9a-f]{6}$/i;

const schemes = S.list();
ok("there are schemes", schemes.length >= 7);
ok("ids are unique", new Set(schemes.map(s => s.id)).size === schemes.length);
ok("names are unique", new Set(schemes.map(s => s.name)).size === schemes.length);

for (const s of schemes) {
    const modes = ["dark", "light"].filter(m => s.variants[m]);
    ok(`${s.id}: has at least one variant`, modes.length > 0);

    // palette.js reads a scheme the same way it reads a saved one.
    const packed = P.packScheme(s.variants);
    ok(`${s.id}: packs`, !!packed);
    const round = P.unpackScheme(packed);
    ok(`${s.id}: survives pack → unpack`, modes.every(m => round[m] && round[m].colors.color1 === s.variants[m].colors.color1));

    for (const m of modes) {
        const p = s.variants[m], tag = `${s.id}/${m}`;
        const slots = ["background", "foreground", "cursor"];
        ok(`${tag}: special slots are hex`, slots.every(k => HEX.test(p.special[k])));
        ok(`${tag}: all sixteen ramp slots are hex`, P.rampSlots().every(k => HEX.test(p.colors[k])),
            P.rampSlots().filter(k => !HEX.test(p.colors[k] || "")).join(","));
        ok(`${tag}: filed under its own mode`, P.schemeMode(p) === m, `ground ${p.special.background} reads as ${P.schemeMode(p)}`);

        const bg = p.special.background;
        const text = P.contrast(p.colors.color7, bg);
        ok(`${tag}: text (color7) is at least 4.5:1`, text >= 4.5, text.toFixed(2));
        // primary is color1 and is drawn as text and icons; PaletteRoles lifts a weak one to 4.5,
        // but a scheme that needs the lift is no longer itself. 3:1 is the WCAG bar for a UI colour.
        for (const [slot, role] of [["color1", "primary"], ["color4", "focus"]]) {
            const c = P.contrast(p.colors[slot], bg);
            ok(`${tag}: ${role} (${slot}) is at least 3:1`, c >= 3, c.toFixed(2));
        }
        ok(`${tag}: primary and focus are different colours`, p.colors.color1.toLowerCase() !== p.colors.color4.toLowerCase());
        const muted = P.contrast(p.colors.color8, bg);
        ok(`${tag}: muted (color8) is readable (2.4:1)`, muted >= 2.4, muted.toFixed(2));

        const pick = P.pickVariant(s.variants, m);
        ok(`${tag}: pickVariant finds it exactly`, pick.exact && pick.mode === m);
    }
    if (modes.length === 1) {
        const other = modes[0] === "dark" ? "light" : "dark";
        const pick = P.pickVariant(s.variants, other);
        ok(`${s.id}: a one-mode scheme answers the other mode with its own, not exact`,
            !pick.exact && pick.mode === modes[0] && !!pick.palette);
    }
}

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
