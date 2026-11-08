// ── test-palette-scheme.js ────────────────────────────────────────────────────
// services/palette.js unpackScheme() / packScheme() / pickVariant() — a saved colour scheme that
// can hold a dark AND a light palette, in a file the old single-palette readers still understand.
//
//     bun scripts/test-palette-scheme.js     (or: node ...)
//
// Reads palette.js and every file in colorschemes/; writes nothing.
//
// ── Why this needs a test ─────────────────────────────────────────────────────
// The failure is silent and happens later: a scheme saved in the new shape that an older shell (or
// check-contrast.py) cannot read, or a bundled legacy scheme that stops loading after an update. So
// the two promises are checked against the REAL shipped library, not a fixture: every bundled scheme
// unpacks to exactly one variant, and packing it again leaves the old top-level palette byte-identical.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync, readdirSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "palette.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const P = new Function(src + "\nreturn { schemeMode, unpackScheme, packScheme, pickVariant, schemeDistance, findScheme };")();

let pass = 0, fail = 0;
function ok(name, cond, detail) {
    if (cond) pass++;
    else { fail++; console.log(`  FAIL  ${name}${detail ? "\n          " + detail : ""}`); }
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const mk = (bg, c7) => ({ special: { background: bg, foreground: c7, cursor: c7 },
                          colors: { color0: bg, color1: "#aa5555", color4: "#5555aa", color7: c7 } });
const DARK = mk("#101014", "#e6e1e5"), LIGHT = mk("#f6f1ec", "#1c1b1f");

// ── mode, read off the background ─────────────────────────────────────────────
ok("a dark ground is a dark scheme", P.schemeMode(DARK) === "dark");
ok("a light ground is a light scheme", P.schemeMode(LIGHT) === "light");

// ── a legacy file ─────────────────────────────────────────────────────────────
{
    const u = P.unpackScheme(DARK);
    ok("legacy dark: dark set, light empty", same(u.dark, DARK) && u.light === null);
    const l = P.unpackScheme(LIGHT);
    ok("legacy light: light set, dark empty", same(l.light, LIGHT) && l.dark === null);
}
ok("nothing unpacks to nothing", same(P.unpackScheme(null), { dark: null, light: null }));
ok("an object with no palette unpacks to nothing", same(P.unpackScheme({ foo: 1 }), { dark: null, light: null }));

// ── packing ───────────────────────────────────────────────────────────────────
{
    const both = P.packScheme({ dark: DARK, light: LIGHT });
    ok("packed: the top level is the dark palette (what an old reader sees)",
       same(both.special, DARK.special) && same(both.colors, DARK.colors));
    ok("packed: both variants are present", same(both.variants.dark, DARK) && same(both.variants.light, LIGHT));
    const lightOnly = P.packScheme({ dark: null, light: LIGHT });
    ok("light only: the top level is the light palette", same(lightOnly.colors, LIGHT.colors));
    ok("light only: no dark variant", lightOnly.variants.dark === undefined && !!lightOnly.variants.light);
    ok("nothing to pack", P.packScheme({}) === null && P.packScheme(null) === null);
    ok("a variant carries nothing but the palette",
       same(Object.keys(P.packScheme({ dark: Object.assign({ extra: 1 }, DARK) }).variants.dark).sort(), ["colors", "special"]));
}

// ── round trip ────────────────────────────────────────────────────────────────
{
    const back = P.unpackScheme(JSON.parse(JSON.stringify(P.packScheme({ dark: DARK, light: LIGHT }))));
    ok("pack → JSON → unpack gives both back", same(back.dark, DARK) && same(back.light, LIGHT));
    // A saved scheme with a variants key must NOT also be read as a legacy one from its top level.
    const only = P.unpackScheme(P.packScheme({ dark: null, light: LIGHT }));
    ok("light only stays light only (its top level is not a second, dark variant)", only.dark === null && !!only.light);
}

// ── pickVariant ───────────────────────────────────────────────────────────────
{
    const v = { dark: DARK, light: LIGHT };
    ok("picks the mode asked for", P.pickVariant(v, "light").palette === LIGHT && P.pickVariant(v, "light").exact);
    ok("picks dark", P.pickVariant(v, "dark").palette === DARK);
    const d = P.pickVariant({ dark: DARK, light: null }, "light");
    ok("a missing mode falls back to the other, and says so",
       d.palette === DARK && d.mode === "dark" && d.exact === false);
    ok("an empty scheme has no palette", P.pickVariant({ dark: null, light: null }, "dark").palette === null);
    ok("an unknown mode is read as dark", P.pickVariant(v, "banana").palette === DARK);
}

// ── the bundled library, untouched ────────────────────────────────────────────
{
    const dir = join(here, "..", "colorschemes");
    let n = 0, bad = [];
    for (const f of readdirSync(dir).filter(f => f.endsWith(".json"))) {
        const obj = JSON.parse(readFileSync(join(dir, f), "utf8"));
        if (obj.variants) continue;              // a scheme saved in the new shape: not what this checks
        n++;
        const u = P.unpackScheme(obj);
        const held = [u.dark, u.light].filter(Boolean);
        if (held.length !== 1) { bad.push(`${f}: ${held.length} variants`); continue; }
        const packed = P.packScheme(u);
        if (!same(packed.special, obj.special) || !same(packed.colors, obj.colors))
            bad.push(`${f}: top level changed when re-saved`);
    }
    ok(`every bundled legacy scheme (${n}) unpacks to one variant and re-saves with its top level intact`,
       bad.length === 0, bad.join("; "));
    ok("there ARE bundled schemes to check", n > 0);
}

// ── findScheme: which saved scheme the live palette is ──
{
    const mk = (bg, fg, seed) => ({ special: { background: bg, foreground: fg, cursor: fg },
        colors: Object.fromEntries(Array.from({ length: 16 }, (_, i) => ["color" + i,
            "#" + [0, 1, 2].map(k => ((seed * 37 + i * 11 + k * 53) % 256).toString(16).padStart(2, "0")).join("")])) });
    const a = mk("#101010", "#eeeeee", 1), b = mk("#202830", "#dddddd", 2), c = mk("#f0f0f0", "#111111", 3);
    const lib = [{ name: "A", variants: { dark: a, light: null } }, { name: "B", variants: { dark: b, light: c } }];
    ok("the live palette is the scheme it was applied from", P.findScheme(a, lib, "dark") === "A");
    ok("…and the other one", P.findScheme(b, lib, "dark") === "B");
    ok("a scheme wears its light variant in light mode", P.findScheme(c, lib, "light") === "B");
    ok("a palette that is nobody's twin is none", P.findScheme(mk("#305020", "#aaaaaa", 9), lib, "dark") === "");
    const nudged = JSON.parse(JSON.stringify(a)); nudged.colors.color3 = "#" + a.colors.color3.slice(1).replace(/^../, h => ((parseInt(h, 16) + 2) % 256).toString(16).padStart(2, "0"));
    ok("a slot nudged a little by the pipeline still matches", P.findScheme(nudged, lib, "dark") === "A");
    ok("an unfinished palette matches nothing", P.findScheme({ special: {}, colors: {} }, lib, "dark") === "" && P.findScheme(null, lib, "dark") === "");
    ok("no library, no match", P.findScheme(a, [], "dark") === "" && P.findScheme(a, null, "dark") === "");
    ok("the nearest wins when two are within reach", P.findScheme(a, [{ name: "Far", variants: { dark: nudged } }, { name: "A", variants: { dark: a } }], "dark") === "A");
    ok("distance is 0 for the same palette", P.schemeDistance(a, a) === 0);
}

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
