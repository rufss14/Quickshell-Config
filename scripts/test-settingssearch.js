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
import { readFileSync, existsSync, readdirSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, "..");
const src = readFileSync(join(repo, "services", "settingssearch.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

const { search, buildEntries, norm, groupResults, splitMatch, pageOfEntry, elsewhereEntries } =
    new Function(src + "\nreturn { search, buildEntries, norm, groupResults, splitMatch, pageOfEntry, elsewhereEntries };")();

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
    { file: "WidgetsPage.qml", label: "Widgets", section: "Look", keywords: "desktop" },
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
    { file: "WidgetsPage.qml", part: "WidgetsPage", kind: "row", title: "Weather units",
      values: ["Celsius", "Fahrenheit"] },
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

// ── Choice values and source part ─────────────────────────────────────────────
finds("celsius", "Weather units");
finds("fahrenheit", "Weather units");
{
    const hit = search(entries, "celsius", 20)[0];
    check("values: part and values pass through buildEntries",
          hit && hit.part === "WidgetsPage" && hit.values.length === 2, JSON.stringify(hit));
    const g = groupResults([hit]);
    check("values: rows keep part through groupResults",
          g[0].rows[0].part === "WidgetsPage" && g[0].rows[0].values[0] === "Celsius");
    top("weather units", "Weather units");
    check("values: a title hit beats a value hit",
          (() => { const r = search([{ kind: "row", file: "a", title: "Auto", values: [] },
                                     { kind: "row", file: "a", title: "Mode", values: ["Auto"] }], "auto", 5);
                   return r[0].title === "Auto"; })());
    check("values: single letter ignores values", !search(entries, "c", 20).some(e => e.title === "Weather units"));
    check("values: AND still applies", search(entries, "celsius zzz", 20).length === 0);
}

// ── A shared file: entries land on the page that claims them ─────────────────
// Several rail pages on one file (`file#anchor`). A page claims entries by source part
// or by card title; whatever nobody claims goes to the file's first page.
{
    const wp = [
        { file: "WallpaperPage.qml", key: "WallpaperPage.qml", label: "Gallery", page: "Wallpaper",
          parts: ["WallpaperPage", "WallpaperGalleryView"] },
        { file: "WallpaperPage.qml", anchor: "placement", key: "WallpaperPage.qml#placement",
          label: "Placement & motion", page: "Wallpaper", parts: ["WallpaperAppearanceView"] },
        { file: "WallpaperPage.qml", anchor: "scenes", key: "WallpaperPage.qml#scenes",
          label: "Scenes", page: "Wallpaper", parts: ["WallpaperEngineView", "WallpaperPropertiesView"] },
        { file: "StoragePage.qml", key: "StoragePage.qml", label: "Storage", page: "System" },
        // No `key`: built from file#anchor, as the stand-in shapes above do.
        { file: "StoragePage.qml", anchor: "packages", label: "Packages", page: "System",
          sections: ["Installed on purpose"] },
    ];
    const idx = [
        { file: "WallpaperPage.qml", part: "WallpaperEngineView", kind: "row", title: "V-Sync",
          section: "Playback & rendering" },
        { file: "WallpaperPage.qml", part: "WallpaperAppearanceView", kind: "row", title: "Parallax" },
        { file: "WallpaperPage.qml", part: "WallpaperSomethingNew", kind: "row", title: "Mystery knob" },
        { file: "StoragePage.qml", part: "StoragePage", kind: "section", title: "Installed on purpose" },
        { file: "StoragePage.qml", part: "StoragePage", kind: "row", title: "Show orphans",
          section: "Installed on purpose" },
        { file: "StoragePage.qml", part: "StoragePage", kind: "section", title: "Disks" },
    ];
    const es = buildEntries(wp, idx);
    const keyOf = t => (es.find(e => e.title === t) || {}).key;
    check("claim: a Scenes row opens WallpaperPage.qml#scenes", keyOf("V-Sync") === "WallpaperPage.qml#scenes", keyOf("V-Sync"));
    check("claim: a placement row opens #placement", keyOf("Parallax") === "WallpaperPage.qml#placement", keyOf("Parallax"));
    check("claim: an unclaimed part lands on the file's first page", keyOf("Mystery knob") === "WallpaperPage.qml");
    check("claim: a card claimed by title (the card itself)", keyOf("Installed on purpose") === "StoragePage.qml#packages",
          keyOf("Installed on purpose"));
    check("claim: a row in a claimed card", keyOf("Show orphans") === "StoragePage.qml#packages");
    check("claim: another card of the file stays on the first page", keyOf("Disks") === "StoragePage.qml");
    check("claim: a row takes its page's name", (es.find(e => e.title === "V-Sync") || {}).page === "Scenes");
    check("claim: page records carry their key",
          es.filter(e => e.kind === "page").map(e => e.key).join(",")
          === "WallpaperPage.qml,WallpaperPage.qml#placement,WallpaperPage.qml#scenes,StoragePage.qml,StoragePage.qml#packages");
    check("claim: a card claim beats a part claim",
          pageOfEntry([{ file: "f", label: "A", parts: ["P"] }, { file: "f", label: "B", sections: ["Card"] }],
                      { kind: "row", part: "P", section: "Card" }).label === "B");
    check("claim: no pages for the file, no page", pageOfEntry(undefined, { part: "P" }) === undefined);

    // One file, four pages: four groups, not one.
    const g = groupResults(search(es, "wallpaper", 20).concat(es.filter(e => e.title === "V-Sync" || e.title === "Parallax")));
    check("groups: by key, so pages of one file stay apart",
          g.some(x => x.key === "WallpaperPage.qml#scenes") && g.some(x => x.key === "WallpaperPage.qml#placement")
          && new Set(g.map(x => x.key)).size === g.length, g.map(x => x.key).join(","));
    const sg = groupResults([es.find(e => e.title === "V-Sync")])[0];
    check("groups: a row group is named for its page", sg.page === "Scenes" && sg.group === "Wallpaper", JSON.stringify(sg));
}

// ── Elsewhere: settings that live in a panel or an island ─────────────────────
// The list is hand-written in services/SettingsIndex.qml as a plain literal; read it
// out of the file (bracket matched) so the tests pin the real thing.
function literalAfter(text, marker) {
    const at = text.indexOf(marker);
    if (at < 0) return null;
    let i = text.indexOf("[", at), depth = 0, inStr = null;
    const start = i;
    for (; i < text.length; i++) {
        const c = text[i];
        if (inStr) { if (c === "\\") i++; else if (c === inStr) inStr = null; continue; }
        if (c === '"' || c === "'") inStr = c;
        else if (c === "/" && text[i + 1] === "/") i = text.indexOf("\n", i);
        else if (c === "[") depth++;
        else if (c === "]" && --depth === 0) return text.slice(start, i + 1);
    }
    return null;
}
{
    const qml = readFileSync(join(repo, "services", "SettingsIndex.qml"), "utf8");
    const lit = literalAfter(qml, "readonly property var elsewhere:");
    let list = [];
    try { list = new Function("return " + lit)(); } catch (e) { check("elsewhere: the list is a plain literal", false, String(e)); }
    check("elsewhere: 30 or more entries", list.length >= 30, `got ${list.length}`);

    // Every place it opens must exist: an island page (config/islands.js) on a part that page
    // reads, a bar panel, or the overview.
    const isl = readFileSync(join(repo, "config", "islands.js"), "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "");
    const I = new Function(isl + "\nreturn { META, PAGE_META, OWN_META };")();
    const pages = Object.assign({}, I.META, I.PAGE_META, I.OWN_META);
    // The parts each page's panel reads (UiState.islandPartFor in its onCompleted).
    const PARTS = { wallpaper: ["images", "engine", "material"], colorScheme: ["edit", "slots", "library", "album"],
                    equalizer: ["apps", "devices", "mic", "options"], tablet: ["map", "profiles", "test"] };
    for (const x of list) {
        const o = x.open || {};
        const ok = o.overview === true
            || (typeof o.panel === "string" && I.META[o.panel] !== undefined)
            || (typeof o.page === "string" && pages[o.page] !== undefined
                && (o.part === undefined || (PARTS[o.page] || []).indexOf(o.part) >= 0));
        check(`elsewhere: "${x.title}" opens a real place`, ok, JSON.stringify(o));
        check(`elsewhere: "${x.title}" has a where and keywords`, !!x.where && !!x.keywords);
    }
    check("elsewhere: titles are unique", new Set(list.map(x => x.title)).size === list.length);

    // Through the same scorer as everything else.
    const ew = entries.concat(elsewhereEntries(list));
    const topOf = q => { const r = search(ew, q, 20); return r.length ? r[0] : null; };
    for (const [q, title, where] of [
        ["romanize", "Romanize lyrics", "Now Playing"],
        ["boost", "Boost past 100%", "Equalizer"],
        ["world clock", "World clocks", "Clock"],
        ["karaoke mods", "Karaoke mods", "Now Playing"],
        ["album scope", "Where the album colours go", "Colour scheme"],
        ["sort wallpapers", "Sort wallpapers", "Wallpaper"],
        ["silence notifications", "Silence notifications", "Gaming"],
        ["app labels", "App labels", "overview"],
    ]) {
        const t = topOf(q);
        check(`elsewhere: top("${q}") is "${title}" in the ${where}`,
              t && t.title === title && t.kind === "elsewhere" && t.where === where && t.open,
              t ? `${t.kind} "${t.title}"` : "(none)");
    }
    check("elsewhere: the place's name finds its settings",
          search(ew, "gaming", 40).filter(e => e.kind === "elsewhere").length >= 8);
    check("elsewhere: not searched unless they are in the list",
          !search(entries, "romanize", 20).some(e => e.kind === "elsewhere"));
    // On an equal match, a row inside the app beats an elsewhere result.
    const tie = search([{ kind: "row", key: "a", file: "a", title: "Mute" },
                        ...elsewhereEntries([{ title: "Mute", where: "X", open: { page: "gaming" } }])], "mute", 5);
    check("elsewhere: a settings row wins a tie", tie[0].kind === "row");
    const g = groupResults(search(ew, "romanize", 20));
    check("elsewhere: they fold into one group, marked", g.filter(x => x.elsewhere).length === 1
          && g.find(x => x.elsewhere).rows.every(r => r.kind === "elsewhere"));
    check("elsewhere: an entry with no place is dropped",
          elsewhereEntries([{ title: "x", where: "y" }, null, { title: "z", where: "w", open: {} }]).length === 1);
}

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

    // The REAL catalogue over the real index: a row of a shared file lands on the page
    // that claims it. The catalogue's hardware gates read `root` and `Net`; stubbed on.
    const qml = readFileSync(join(repo, "services", "SettingsIndex.qml"), "utf8");
    let cat = [];
    try {
        cat = new Function("root", "Net", "return " + literalAfter(qml, "readonly property var _catalogue:"))(
            { hasWifi: true, hasBluetooth: true, hasBattery: true }, { hasWired: true });
    } catch (e) { check("real catalogue: a plain literal", false, String(e)); }
    const catPages = [];
    for (const sec of cat) for (const v of sec.views) catPages.push(Object.assign({ page: sec.label }, v));
    const catEntries = buildEntries(catPages, real.entries);
    const landsOn = (title, key) => {
        const hit = catEntries.find(e => e.kind !== "page" && e.title === title);
        check(`real catalogue: "${title}" opens ${key}`, hit && hit.key === key, hit ? hit.key : "(not in the index)");
    };
    landsOn("V-Sync", "WallpaperPage.qml#scenes");
    landsOn("Parallax", "WallpaperPage.qml#placement");
    landsOn("Per workspace", "WallpaperPage.qml#placement");
    landsOn("Sound map", "WallpaperPage.qml#music");
    landsOn("Installed on purpose", "StoragePage.qml#packages");
    landsOn("Disks", "StoragePage.qml");
    // A claimed part is a source file stem: a typo would silently claim nothing.
    const sub = d => existsSync(d) ? readdirSync(d, { withFileTypes: true }).filter(x => x.isDirectory()).map(x => join(d, x.name)) : [];
    const settingsDir = join(repo, "modules", "settings");
    const dirs = [settingsDir, join(settingsDir, "pages"), ...sub(join(settingsDir, "pages")), join(repo, "components")];
    for (const p of catPages)
        for (const pt of (p.parts || []))
            check(`real catalogue: part "${pt}" of ${p.label} is a source file`,
                  dirs.some(d => existsSync(join(d, pt + ".qml"))));
} else {
    check("settings-index.json exists (run build-settings-index.py)", false);
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) {
    console.log("\nfailures:\n" + failures.join("\n"));
    process.exit(1);
}
