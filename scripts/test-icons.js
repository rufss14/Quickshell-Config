// ── test-icons.js ─────────────────────────────────────────────────────────────
// Checks services/icons.js against the bundled fonts in assets/fonts/.
//
//     bun scripts/test-icons.js          (or: node scripts/test-icons.js)
//
// Safe to run: reads files and touches nothing.
//
// ── What it guards ────────────────────────────────────────────────────────────
// The icons are cut fonts, carrying ONLY what the tree used when they were cut. So
// a new icon — a `symbol:` nobody generated, a glyph pasted into a widget — has no
// font to draw from until someone reruns `material-symbols-map.py --emit`. It shows
// as a help-circle (or a Qt fallback glyph), on every machine, and nothing logs it.
// The coverage checks below scan the live tree for both kinds. And the map and the
// fonts are one artifact: BUILD must match the files' hashes, or the codepoints
// point into a font they were not read from and draw the WRONG icon.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync, readdirSync, statSync } from "fs";
import { createHash } from "crypto";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..");

const src = readFileSync(join(repo, "services", "icons.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { BUILD, SYMBOL, symbol, NAME, nameOf, GLYPHS, isGlyph } =
    new Function(src + "\nreturn { BUILD, SYMBOL, symbol, NAME, nameOf, GLYPHS, isGlyph };")();

let pass = 0, fail = 0;
function ok(name, cond, detail) {
    if (cond) pass++;
    else { fail++; console.log(`  FAIL  ${name}${detail ? "\n          " + detail : ""}`); }
}

const names = Object.keys(SYMBOL);
const isPua = cp => (cp >= 0xE000 && cp <= 0xF8FF) || (cp >= 0xF0000 && cp <= 0x10FFFD);

// ── The map and the fonts are one artifact ────────────────────────────────────
for (const [key, file] of [["symbols", "QuicktestSymbols.ttf"], ["glyphs", "QuicktestGlyphs.otf"]]) {
    let sha = "";
    try { sha = createHash("sha256").update(readFileSync(join(repo, "assets", "fonts", file))).digest("hex").slice(0, 16); }
    catch (e) { sha = "(missing)"; }
    ok(`assets/fonts/${file} is the file icons.js was generated with`, sha === BUILD[key],
       `hash ${sha}, icons.js says ${BUILD[key]} — rerun material-symbols-map.py --emit`);
}

// ── Shape of the generated map ────────────────────────────────────────────────
ok("map is not empty", names.length > 0);

const badNames = names.filter(n => !/^[a-z0-9_]+$/.test(n));
ok("every key is a legal symbol name", badNames.length === 0, badNames.join(", "));

const badValues = names.filter(n => [...SYMBOL[n]].length !== 1 || !isPua(SYMBOL[n].codePointAt(0)));
ok("every value is one Private Use codepoint", badValues.length === 0, badValues.join(", "));

ok("the unknown-name mark (help) is in the map", "help" in SYMBOL);

// ── symbol() contract ─────────────────────────────────────────────────────────
// "" and never undefined, so a caller's `|| fallback` works instead of rendering
// the string "undefined" — the trap Quickshell.env() sets elsewhere in this repo.
ok("symbol() returns the codepoint for a known name", symbol(names[0]) === SYMBOL[names[0]]);
ok("symbol() returns '' for an unknown name", symbol("no_such_icon_anywhere") === "");
ok("symbol() returns '' and not undefined", symbol("nope") !== undefined);
ok("symbol() survives an empty name", symbol("") === "");

// ── Coverage: every name used in the tree is in the map ───────────────────────
function treeFiles(dir, exts, out = []) {
    for (const entry of readdirSync(dir)) {
        if (entry === ".git" || entry === "node_modules") continue;
        const full = join(dir, entry);
        const st = statSync(full);
        if (st.isDirectory()) {
            if (full.includes(join("config", "settings"))) continue;
            treeFiles(full, exts, out);
        } else if (exts.some(e => entry.endsWith(e))) out.push(full);
    }
    return out;
}
const qmlFiles = dir => treeFiles(dir, [".qml"]);

const used = new Map();
// A LITERAL assignment, and every string literal in a COMPUTED one.
//
// The literal-only form used to be the whole check, and it has a blind spot that
// shipped a real bug: `symbol: cond ? "a" : "b"` matches nothing, because the
// character after the colon is not a quote. Every state-dependent icon in the
// shell is written that way, so the pills most likely to carry an unmapped name
// were exactly the ones never scanned. An unmapped name renders the literal WORD
// in the bar on any machine without the AUR font — prose in the middle of the
// bar, which is the whole reason this map exists.
const SYMBOL_RE = /\b(?:symbol|trailingSymbol)\s*:\s*"([a-z0-9_]+)"/g;
// The computed form: take everything after the colon to the end of the line and
// collect its string literals. Deliberately line-scoped — a multi-line ternary
// contributes its first line only, which is a miss, not a false alarm.
const SYMBOL_EXPR_RE = /\b(?:symbol|trailingSymbol)\s*:\s*([^\n]*)/g;
const STRING_RE = /"([a-z0-9_]+)"/g;
const NAME_RE = /\bname\s*:\s*"([a-z0-9_]+)"/g;

for (const file of qmlFiles(repo)) {
    const text = readFileSync(file, "utf8");
    for (const m of text.matchAll(SYMBOL_RE)) used.set(m[1], file);
    for (const m of text.matchAll(SYMBOL_EXPR_RE)) {
        // `kind === "service"` is a comparison, not an icon name.
        const expr = m[1].replace(/[!=]==?\s*"[^"]*"/g, "");
        for (const s of expr.matchAll(STRING_RE)) used.set(s[1], file);
    }
    // `name:` only counts inside a MaterialIcon block — a cheap proximity check
    // rather than a QML parser, which is enough because `name:` is rare.
    if (text.includes("MaterialIcon")) {
        for (const m of text.matchAll(NAME_RE)) {
            const at = m.index ?? 0;
            const before = text.slice(Math.max(0, at - 400), at);
            if (before.lastIndexOf("MaterialIcon") > before.lastIndexOf("}")) {
                used.set(m[1], file);
            }
        }
    }
}

const missing = [...used.entries()].filter(([n]) => !(n in SYMBOL));
ok(`every symbol used in the tree is in the map (${used.size} in use)`,
   missing.length === 0,
   missing.map(([n, f]) => `${n}  (${f.replace(repo + "/", "")})`).join("\n          "));

// ── The reverse map: a glyph the shell already spells -> its Symbols name ──────
// MaterialIcon { glyph: … } depends on this, and a wrong entry is silent: the icon
// still draws, just a different one.
ok("nameOf: a mapped glyph resolves", nameOf("\u{F0349}") === "search");
ok("nameOf: every mapped glyph's name is in the symbols font",
   Object.entries(NAME).every(([hex, nm]) => nm in SYMBOL),
   Object.entries(NAME).filter(([, nm]) => !(nm in SYMBOL)).map(([h, nm]) => `${h}→${nm}`).join(", "));
ok("nameOf: a brand mark stays unmapped (Discord)", nameOf("\u{F066F}") === "");
ok("nameOf: plain text is unmapped", nameOf("A") === "" && nameOf("Hello") === "");
ok("nameOf: glyph + text is unmapped", nameOf("\u{F0349} Search") === "");
ok("nameOf: empty / undefined are unmapped", nameOf("") === "" && nameOf(undefined) === "");
ok("nameOf: every key is an uppercase hex codepoint in the MDI block",
   Object.keys(NAME).every(k => /^[0-9A-F]+$/.test(k) && parseInt(k, 16) >= 0xF0000 && parseInt(k, 16) <= 0xF0FFF));

// ── Every glyph the tree spells is in the glyph font ──────────────────────────
// Raw characters AND escapes (`\u{F0214}`, `\uF005`), in .qml AND .js — the same
// net the generator casts. A glyph outside it draws from whatever installed font Qt
// falls back to, which is the dependency the bundle exists to remove.
const carried = new Set(GLYPHS.split(" ").filter(Boolean).map(h => parseInt(h, 16)));
const ESC = /\\u\{([0-9A-Fa-f]{4,6})\}|\\u([0-9A-Fa-f]{4})/g;
const stray = new Map();
for (const file of treeFiles(repo, [".qml", ".js"])) {
    if (file.endsWith(join("services", "icons.js"))) continue;
    const text = readFileSync(file, "utf8");
    const cps = [...text].map(c => c.codePointAt(0));
    for (const m of text.matchAll(ESC)) cps.push(parseInt(m[1] || m[2], 16));
    for (const cp of cps) if (isPua(cp) && !carried.has(cp)) stray.set(cp, file);
}
ok(`every glyph the tree spells is in the glyph font (${carried.size} carried)`,
   stray.size === 0,
   [...stray].map(([cp, f]) => `U+${cp.toString(16).toUpperCase()}  (${f.replace(repo + "/", "")})`).join("\n          "));

// ── isGlyph(): which face a string wants ──────────────────────────────────────
ok("isGlyph: an MDI glyph", isGlyph("\u{F066F}"));
ok("isGlyph: a BMP Private Use glyph (Font Awesome star)", isGlyph("\uF005"));
ok("isGlyph: prose is not", !isGlyph("A") && !isGlyph("Hello"));
ok("isGlyph: empty / undefined are not", !isGlyph("") && !isGlyph(undefined) && !isGlyph(null));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
