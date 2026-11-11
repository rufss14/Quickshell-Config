// ── test-look.js ──────────────────────────────────────────────────────────────
// Pins services/look.js: the look bundle's export and, above all, its IMPORT, which reads
// a file someone else wrote.
//
//     bun scripts/test-look.js          (or: node scripts/test-look.js)
//
// Loaded the way test-surfaces.js loads surfaces.js (the `.pragma library` line stripped),
// so this runs the real file. Touches nothing.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "look.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const L = new Function(src + "\nreturn { FORMAT, VERSION, MAX_BYTES, STYLE, styleKeys, cleanStyle, cleanBar, cleanPalette, cleanScheme, cleanName, schemeName, fileName, cleanWallpaper, uniqueName, build, serialize, parse, summary };")();

let pass = 0;
const failures = [];
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function check(name, got, want) {
    if (eq(got, want)) { pass++; return; }
    failures.push(`  ${name}\n      want ${JSON.stringify(want)}\n      got  ${JSON.stringify(got)}`);
}

const hex = n => "#" + (n * 0x111111 % 0x1000000).toString(16).padStart(6, "0");
const palette = () => {
    const p = { special: { background: "#000000", foreground: "#C4C1C1", cursor: "#c4c1c1" }, colors: {} };
    for (let i = 0; i < 16; i++) p.colors["color" + i] = hex(i + 1);
    return p;
};
const good = () => ({
    format: "quicktest-look", version: 1, shell: "0.4.1", name: "Night market", wallpaper: "market.jpg",
    style: { fontScale: 1.05, cornerStyle: "ii", themeMode: "dark", accentRole: "tertiary" },
    bar: { barShape: true, barThickness: 46, layout: { left: ["clock"] }, moduleSettings: { clock: { hero: false } } },
    scheme: { mode: "dark", palette: palette() }
});
const parse = o => L.parse(typeof o === "string" ? o : JSON.stringify(o));

// ── The good file ─────────────────────────────────────────────────────────────
{
    const r = parse(good());
    check("good file parses", r.ok, true);
    check("name", r.look.name, "Night market");
    check("style kept", r.look.style, { fontScale: 1.05, cornerStyle: "ii", themeMode: "dark", accentRole: "tertiary" });
    check("bar kept", r.look.bar.barThickness, 46);
    check("bar objects kept", r.look.bar.layout, { left: ["clock"] });
    check("palette lowercased", r.look.scheme.palette.special.foreground, "#c4c1c1");
    check("nothing skipped", r.skipped, 0);
    check("summary", L.summary(r.look).length, 4);
}

// ── Round trip: build → serialize → parse ─────────────────────────────────────
{
    const values = { fontScale: 1.1, iconShape: "cookie", themeMode: "light", wallFx: true,
                     // not on the list, so never exported:
                     lockAvatar: "/home/me/pic.jpg", weatherPlace: "Town", motionEnabled: false, motionReduced: true };
    const bar = { barShape: false, barThickness: 38, motionEnabled: false, motionScale: 2, layout: { left: ["a"] } };
    const doc = L.build({ name: "  Mine\n", shell: "0.4.1", wallpaper: "/home/me/walls/x.jpg",
                          values, bar, mode: "light", palette: palette() });
    const text = L.serialize(doc);
    check("export carries no personal key", /lockAvatar|weatherPlace|\/home\/me/.test(text), false);
    check("export carries no motion key", /motion/i.test(text), false);
    check("wallpaper is a name, not a path", doc.wallpaper, "x.jpg");
    check("name tidied", doc.name, "Mine");
    const back = L.parse(text);
    check("round trip ok", back.ok, true);
    check("round trip style", back.look.style, { fontScale: 1.1, iconShape: "cookie", themeMode: "light", wallFx: true });
    check("round trip bar", back.look.bar, { barShape: false, barThickness: 38, layout: { left: ["a"] } });
    check("round trip scheme mode", back.look.scheme.mode, "light");
    check("round trip skipped", back.skipped, 0);
}

// A mode without colours is not exported (it would flip the mode and keep the old palette).
{
    const doc = L.build({ name: "x", values: { themeMode: "dark", fontScale: 1 }, bar: null, mode: "dark", palette: { special: {}, colors: {} } });
    check("themeMode left out without a palette", "themeMode" in doc.style, false);
    check("no scheme without a palette", "scheme" in doc, false);
}

// ── Refusals: nothing may throw, everything says why ──────────────────────────
check("empty", parse("").ok, false);
check("whitespace", parse("  \n").ok, false);
check("not json", parse("{nope").error, "Not a look file (not valid JSON)");
check("array", parse("[1,2]").ok, false);
check("wrong format", parse({ format: "other", version: 1, style: { fontScale: 1 } }).ok, false);
check("no version", parse({ format: "quicktest-look", style: { fontScale: 1 } }).ok, false);
check("fractional version", parse({ format: "quicktest-look", version: 1.5, style: { fontScale: 1 } }).ok, false);
check("newer version", parse({ format: "quicktest-look", version: 2, style: { fontScale: 1 } }).error,
      "Made by a newer shell: update, then import it");
check("too big", L.parse("x".repeat(L.MAX_BYTES + 1)).error, "Too big to be a look");
check("empty look", parse({ format: "quicktest-look", version: 1, style: {} }).error, "Nothing in this file can be applied");
check("only unknown keys", parse({ format: "quicktest-look", version: 1, style: { lockAvatar: "/x", motionScale: 2 } }).ok, false);
check("null", L.parse(null).ok, false);

// ── Bad values are dropped and counted; good neighbours survive ───────────────
{
    const doc = good();
    Object.assign(doc.style, { fontScale: 9, densityScale: "1", cornerStyle: "round", iconShape: null,
                               shadowScale: NaN, dockIconSize: 30.5, accentRole: "a b", fontFamily: "x\ny",
                               wallMaterialSeed: -1, colorizeIcons: 1 });
    const r = parse(doc);
    check("still ok", r.ok, true);
    check("good values survive, bad neighbour dropped", [r.look.style.cornerStyle, r.look.style.themeMode], [undefined, "dark"]);
    check("fontScale out of range dropped", "fontScale" in r.look.style, false);
    check("string for a number dropped", "densityScale" in r.look.style, false);
    check("fraction for an int dropped", "dockIconSize" in r.look.style, false);
    check("role with a space dropped", r.look.style.accentRole, undefined);
    check("newline in a font dropped", "fontFamily" in r.look.style, false);
    check("number for a bool dropped", "colorizeIcons" in r.look.style, false);
    check("counted", r.skipped, 10);
}

// ── Motion can never ride in ──────────────────────────────────────────────────
{
    const doc = good();
    Object.assign(doc.style, { motionEnabled: true, motionScale: 1, motionReduced: false });
    Object.assign(doc.bar, { motionEnabled: true, motionScale: 1 });
    const r = parse(doc);
    const text = JSON.stringify(r.look);
    check("no motion in style or bar", /motion(Enabled|Scale|Reduced)/.test(text), false);
}

// ── The bar part ──────────────────────────────────────────────────────────────
check("bar number out of range dropped", L.cleanBar({ barThickness: 5000 }), { value: null, skipped: 1 });
check("bar not an object", L.cleanBar("x"), { value: null, skipped: 0 });
check("unknown bar key ignored", L.cleanBar({ evil: 1, barShape: true }), { value: { barShape: true }, skipped: 0 });
check("object part must be an object", L.cleanBar({ layout: "x", barShape: true }), { value: { barShape: true }, skipped: 1 });
check("hostile key refused", L.cleanBar({ layout: JSON.parse('{"__proto__":{"x":1}}') }).value, null);
check("nested hostile key refused", L.cleanBar({ moduleSettings: JSON.parse('{"a":{"b":{"constructor":1}}}') }).skipped, 1);
{
    let deep = {}; let cur = deep;
    for (let i = 0; i < 12; i++) { cur.n = {}; cur = cur.n; }
    check("too deep refused", L.cleanBar({ layout: deep }).skipped, 1);
    check("too large refused", L.cleanBar({ layout: { a: "x".repeat(50000) } }).skipped, 1);
}
{
    const r = parse({ format: "quicktest-look", version: 1, bar: JSON.parse('{"barShape":true,"layout":{"__proto__":{"polluted":1}}}') });
    check("proto key doesn't pollute", ({}).polluted, undefined);
    check("rest of the bar still applies", r.look.bar, { barShape: true });
}

// ── Palette: all 18 or none ───────────────────────────────────────────────────
{
    const p = palette(); delete p.colors.color7;
    check("missing colour refuses the palette", L.cleanPalette(p), null);
    const q = palette(); q.colors.color3 = "red";
    check("non-hex refuses the palette", L.cleanPalette(q), null);
    const s = palette(); s.special.cursor = "#abc";
    check("short hex refuses the palette", L.cleanPalette(s), null);
    check("bad mode refuses the scheme", L.cleanScheme({ mode: "dim", palette: palette() }), null);
    const doc = good(); doc.scheme.palette.colors.color0 = "nope";
    const r = parse(doc);
    check("bad scheme: file still applies, scheme dropped", [r.ok, r.look.scheme, r.skipped], [true, null, 2]);
    check("…and so does the mode that went with it", "themeMode" in r.look.style, false);
}

// ── Names ─────────────────────────────────────────────────────────────────────
check("name strips controls", L.cleanName("a\u0007b\nc"), "a b c");
check("name caps at 48", L.cleanName("x".repeat(80)).length, 48);
check("name not a string", L.cleanName(5), "");
check("scheme name has no slash, so no traversal", L.schemeName("../etc/passwd"), "..etcpasswd");
check("scheme name empty falls back", L.schemeName("///"), "Look");
check("file name", L.fileName("Night market"), "Night-market.look.json");
check("file name never starts with a dot", L.fileName("..hidden"), "hidden.look.json");
check("file name from nothing", L.fileName(""), "Look.look.json");
check("wallpaper path → name", L.cleanWallpaper("/a/b/c.jpg"), "c.jpg");
check("wallpaper control char", L.cleanWallpaper("a\u0001b"), "");
check("unique name free", L.uniqueName("Dusk", ["Other"]), "Dusk");
check("unique name taken", L.uniqueName("Dusk", ["Dusk", "Dusk 2"]), "Dusk 3");

// ── The whitelist itself ──────────────────────────────────────────────────────
{
    const keys = L.styleKeys();
    check("no motion key is whitelisted", keys.filter(k => /^motion/.test(k)), []);
    check("no path-ish key is whitelisted", keys.filter(k => /(Dir|Path|Avatar|Backdrop$|Target|Library|Lat$|Lon$|Place|User)/.test(k) && k !== "wallMaterialBackdrop"), []);
    check("every spec has a type", keys.every(k => L.STYLE[k].t), true);
}

if (failures.length) {
    console.log(`test-look: ${failures.length} FAILED, ${pass} passed\n` + failures.join("\n"));
    process.exit(1);
}
console.log(`test-look: ${pass} passed`);
