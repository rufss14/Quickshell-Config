// ── test-settingssearch.js ────────────────────────────────────────────────────
// Regression tests for services/settingssearch.js, the settings search ranking.
//
//     bun scripts/test-settingssearch.js      (or: node scripts/test-settingssearch.js)
//
// Safe to run: pure functions, no I/O beyond reading the real index to sweep it.
//
// The cases that matter most here are the ones that pin ORDER, not the ones that
// pin "is it in the results". A search that returns the right answer eighth is
// broken in exactly the way users report as "search doesn't work", and it is the
// half that silently rots when the weights are touched.
//
// settingssearch.js is loaded by stripping its `.pragma library` line (a QML
// directive that isn't valid JS) and evaluating the rest, so the tests run against
// the real file rather than a copy that can drift — same approach as test-calc.js.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync, existsSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..");
const src = readFileSync(join(repo, "services", "settingssearch.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

const { search, buildEntries, norm, groupResults, splitMatch } =
    new Function(src + "\nreturn { search, buildEntries, norm, groupResults, splitMatch };")();

// A small stand-in catalogue shaped exactly like SettingsCard's `pages`.
const pages = [
    { file: "AppearancePage.qml", label: "Appearance", section: "Look",
      detail: "Type, spacing, corners",
      keywords: "font theme colour color scale density rounding radius shadow opacity accent" },
    { file: "BarPage.qml", label: "Bar", section: "Look",
      detail: "Modules, size, shape",
      keywords: "panel taskbar topbar statusbar modules layout preset height" },
    { file: "NightLightPage.qml", label: "Night light", section: "Desktop",
      detail: "Screen warmth and schedule",
      keywords: "night light blue warmth temperature gamma sunset hyprsunset gammastep" },
    { file: "HyprlandPage.qml", label: "Window manager", section: "Desktop",
      detail: "Keybinds and tuning",
      keywords: "hyprland compositor wm keybind bind shortcut hotkey gaps" },
    { file: "MiscPage.qml", label: "Lyrics & extras", section: "Apps",
      detail: "Lyrics sources and odds and ends",
      keywords: "misc lyrics translate spotify netease lrclib bridge" },
    { file: "NetworkPage.qml", label: "Wi-Fi", section: "Devices",
      detail: "Networks and status",
      keywords: "network wifi wireless internet ethernet ssid password" },
];

const indexEntries = [
    { file: "BarPage.qml", kind: "section", title: "Bar rounding & size" },
    { file: "BarPage.qml", kind: "row", title: "Bar radius", section: "Bar rounding & size" },
    { file: "BarPage.qml", kind: "row", title: "Module height", section: "Bar rounding & size" },
    { file: "AppearancePage.qml", kind: "section", title: "Density & corners" },
    { file: "AppearancePage.qml", kind: "row", title: "Roundness", section: "Density & corners" },
    { file: "AppearancePage.qml", kind: "row", title: "Text scale", section: "Type" },
    { file: "AppearancePage.qml", kind: "row", title: "Font family", section: "Type",
      detail: "Leave blank for the shell's own default." },
    { file: "NightLightPage.qml", kind: "row", title: "Colour temperature", section: "Warmth" },
    // Belongs to a page NOT in `pages` — the gated-hardware case.
    { file: "BatteryPage.qml", kind: "row", title: "Charge limit", section: "Health" },
];

const entries = buildEntries(pages, indexEntries);

let pass = 0, fail = 0;
const failures = [];

function check(name, ok, detail) {
    if (ok) { pass++; return; }
    fail++;
    failures.push(`  ${name}${detail ? "\n      " + detail : ""}`);
}

// `top` — the first result's title must be exactly this.
function top(query, expected) {
    const r = search(entries, query, 20);
    const got = r.length ? r[0].title : "(no results)";
    check(`top("${query}") === "${expected}"`, got === expected,
          `got "${got}"` + (r.length > 1 ? `, then "${r[1].title}"` : ""));
}

// `finds` — expected must appear anywhere in the results.
function finds(query, expected) {
    const r = search(entries, query, 20);
    check(`finds("${query}", "${expected}")`,
          r.some(e => e.title === expected),
          `got [${r.slice(0, 5).map(e => e.title).join(", ")}]`);
}

function none(query) {
    const r = search(entries, query, 20);
    check(`none("${query}")`, r.length === 0,
          r.length ? `got [${r.slice(0, 3).map(e => e.title).join(", ")}]` : "");
}

// ── Exact and prefix matches on a page name ───────────────────────────────────
top("appearance", "Appearance");
top("bar", "Bar");
top("wi-fi", "Wi-Fi");
top("wifi", "Wi-Fi");            // punctuation folded
top("WIFI", "Wi-Fi");            // case folded

// ── The renames must still be findable by their old names ─────────────────────
// This is the case the whole `keywords` field exists for. If these regress, a
// rename has silently stranded everyone who knew the old word.
top("hyprland", "Window manager");
finds("misc", "Lyrics & extras");

// ── Space-insensitive matching ────────────────────────────────────────────────
top("nightlight", "Night light");
top("night light", "Night light");

// ── A row beats the page that contains it when both match ─────────────────────
// "bar radius" names one setting; returning the Bar page first would be answering
// a narrower question with a broader answer.
top("bar radius", "Bar radius");
top("text scale", "Text scale");
top("roundness", "Roundness");

// ── Multi-word queries AND, they do not OR ────────────────────────────────────
// "module height" must not return every row containing "module".
top("module height", "Module height");
check("AND: 'bar radius' does not return Module height",
      !search(entries, "bar radius", 20).some(e => e.title === "Module height"));

// ── Keyword hits find a page that never says the word ─────────────────────────
finds("taskbar", "Bar");
finds("gamma", "Night light");
finds("keybind", "Window manager");
finds("spotify", "Lyrics & extras");

// ── Detail text is searchable, but ranks below a title ────────────────────────
finds("blank", "Font family");

// ── Nothing matches ───────────────────────────────────────────────────────────
none("");
none("   ");
none("zzzzzzz");
none("bar zzzzzzz");     // one token missing kills the whole entry

// ── A page that is not available is not searchable ────────────────────────────
// Its rows are in the generated index but the machine has no battery, so the rail
// has no Battery page and a result pointing at one would navigate nowhere.
none("charge limit");

// ── Order is stable ───────────────────────────────────────────────────────────
const a = search(entries, "scale", 20).map(e => e.title).join("|");
const b = search(entries, "scale", 20).map(e => e.title).join("|");
check("results are stable across identical calls", a === b, `${a}\n      vs ${b}`);

// ── One letter matches the start of a title word, nothing else ────────────────
// "s" used to return two dozen tied hits from details and keywords, in
// alphabetical order. One letter is the start of a name being typed.
finds("n", "Night light");
check("single letter: every hit has a title word starting with it",
      search(entries, "n", 20).every(e => norm(e.title).split(" ").some(w => w.startsWith("n"))),
      `got [${search(entries, "n", 20).map(e => e.title).join(", ")}]`);
check("single letter: a detail-only hit is dropped",
      !search(entries, "b", 20).some(e => e.title === "Font family"));

// ── Grouping by view ──────────────────────────────────────────────────────────
{
    const g = groupResults(search(entries, "bar", 20));
    check("groups: each file appears once",
          new Set(g.map(x => x.file)).size === g.length);
    check("groups: best group first is Bar", g.length > 0 && g[0].file === "BarPage.qml",
          `got ${g.length ? g[0].file : "(none)"}`);
    check("groups: a page result marks the group rather than becoming a row",
          g[0] && g[0].pageHit && g[0].rows.every(r => r.kind !== "page"));
    check("groups: rows carry their titles",
          g[0] && g[0].rows.some(r => r.title === "Bar radius"));
    check("groups: empty input", groupResults([]).length === 0 && groupResults(null).length === 0);
}

// ── Highlight split ───────────────────────────────────────────────────────────
{
    const m = splitMatch("Text scale", "scale");
    check("splitMatch: word", m.before === "Text " && m.match === "scale" && m.after === "",
          JSON.stringify(m));
    const c = splitMatch("Show seconds", "SEC");
    check("splitMatch: case-insensitive, keeps original case", c.match === "sec" && c.before === "Show ",
          JSON.stringify(c));
    const l = splitMatch("Bar radius", "bar radius");
    check("splitMatch: longest token wins", l.match === "radius", JSON.stringify(l));
    const n = splitMatch("Night light", "gamma");
    check("splitMatch: no hit draws plain", n.before === "Night light" && n.match === "",
          JSON.stringify(n));
}

// ── Every result carries what the UI needs to navigate ────────────────────────
check("every result has a file",
      search(entries, "bar", 20).every(e => typeof e.file === "string" && e.file));

// ── Sweep the REAL index ──────────────────────────────────────────────────────
// Not a correctness assertion so much as a canary: it fails if the generator's
// output shape drifts from what the ranking expects, which is the failure that
// would otherwise show up as a silently empty search.
const indexPath = join(repo, "modules", "settings", "settings-index.json");
if (existsSync(indexPath)) {
    const real = JSON.parse(readFileSync(indexPath, "utf8"));
    check("real index has a version", real.version === 1);
    check("real index has entries", Array.isArray(real.entries) && real.entries.length > 0);
    check("every real entry has file/kind/title",
          real.entries.every(e => e.file && e.kind && e.title));

    // A catalogue covering every file the real index mentions. The small stand-in
    // above deliberately omits most pages (it exists to pin ranking), and reusing it
    // here would drop their rows on the availability rule and make this sweep test
    // the stand-in rather than the index.
    const realPages = [...new Set(real.entries.map(e => e.file))].map(file => ({
        file,
        label: file.replace(/Page\.qml$/, ""),
        section: "Sweep",
    }));
    const realEntries = buildEntries(realPages, real.entries);
    // Queries a person would actually type, against the real data.
    for (const q of ["radius", "font", "lyrics", "opacity", "lock", "volume"]) {
        const r = search(realEntries, q, 10);
        check(`real index: "${q}" returns something`, r.length > 0);
    }
} else {
    check("settings-index.json exists (run build-settings-index.py)", false);
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) {
    console.log("\nfailures:\n" + failures.join("\n"));
    process.exit(1);
}
