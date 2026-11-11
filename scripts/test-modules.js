// ── test-modules.js ───────────────────────────────────────────────────────────
// Pins config/modules.js: the one module catalogue must hand both surfaces exactly
// the lists they had when the bar's and the sidebar's were two hand-kept arrays.
//
//     bun scripts/test-modules.js          (or: node scripts/test-modules.js)
//
// Pure data; touches nothing. modules.js is loaded the way test-layout.js loads
// layout.js (its `.pragma library` line stripped), so this runs the real file.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "config", "modules.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const M = new Function(src + "\nreturn { MODULES, forSurface, hasForm, CATEGORIES, OPTS, info, hasOpt, matches, shelves };")();

let failed = 0;
const check = (name, ok, detail = "") => {
    if (!ok) { failed++; console.log("FAIL", name, detail); }
};

// Homes are the regions Config's layouts are built from (layout.js REGIONS / SIDE_REGIONS).
const HOMES = { bar: ["left", "centre", "right"], side: ["start", "centre", "end"] };

const ids = M.MODULES.map(m => m.id);
check("ids are unique", new Set(ids).size === ids.length);

for (const surface of ["bar", "side"]) {
    for (const m of M.forSurface(surface)) {
        check(`${surface}/${m.id} has a label`, typeof m.label === "string" && m.label !== "");
        check(`${surface}/${m.id} has a description`, typeof m.description === "string" && m.description !== "");
        check(`${surface}/${m.id} home is a ${surface} region`, HOMES[surface].includes(m.home), m.home);
        if (surface === "side" && m.small)
            check(`side/${m.id} small has cells or is cell-driven`, m.cells === undefined || m.cells > 0);
    }
}
for (const m of M.MODULES)
    check(`${m.id} has at least one form`, !!(m.bar || m.side));

// ── Library metadata (2026-11-08) ─────────────────────────────────────────────
const CATS = M.CATEGORIES.map(c => c.id);
for (const m of M.MODULES) {
    check(`${m.id} has a known category`, CATS.includes(m.category), m.category);
    check(`${m.id} blurb is one plain line`,
          typeof m.blurb === "string" && m.blurb !== "" && !/[<>\n]/.test(m.blurb) && m.blurb.length <= 70,
          JSON.stringify(m.blurb));
    check(`${m.id} native names a form it has`,
          m.native === undefined || (["bar", "side"].includes(m.native) && !!m[m.native]), m.native);
    check(`${m.id} heroable is a bool when given`, m.heroable === undefined || m.heroable === true);
    for (const surface of ["bar", "side"]) {
        const f = m[surface];
        if (!f || f.opts === undefined) continue;
        check(`${surface}/${m.id} opts are known`, Array.isArray(f.opts) && f.opts.every(o => M.OPTS.includes(o)),
              JSON.stringify(f.opts));
    }
    check(`${m.id}: no bar-form hero flag left`, !(m.bar && m.bar.hero !== undefined));
}
for (const c of M.CATEGORIES)
    check(`category ${c.id} has a label and symbol`, !!c.label && !!c.symbol);

// Every module on exactly one shelf, and the shelves in CATEGORIES order.
{
    const all = M.shelves("", "all", () => false);
    const listed = all.flatMap(sh => sh.modules.map(x => x.id));
    check("shelves list every module", JSON.stringify(listed.slice().sort()) === JSON.stringify(ids.slice().sort()));
    check("shelves list each module once", new Set(listed).size === listed.length);
    check("shelves follow CATEGORIES order",
          JSON.stringify(all.map(sh => sh.id)) === JSON.stringify(CATS.filter(c => all.some(sh => sh.id === c))));
}
// Search and the Unused filter.
{
    const flat = (q, f, placed) => M.shelves(q, f, placed).flatMap(sh => sh.modules.map(x => x.id));
    check("search: case-insensitive label", flat("WI-FI", "all").includes("wifi"));
    check("search: blurb word", flat("calendar", "all").includes("clock"));
    check("search: shelf name", flat("media", "all").includes("volume"));
    check("search: every word must hit", flat("clock zzz", "all").length === 0);
    check("search: empty shelves dropped", M.shelves("tesseract-nothing", "all").length === 0);
    const placed = id => id === "clock" || id === "dock";
    const unused = flat("", "unused", placed);
    check("unused: placed modules hidden", !unused.includes("clock") && !unused.includes("dock"));
    check("unused: the rest stay", unused.includes("wifi") && unused.length === ids.length - 2);
}
// info() and hasOpt().
check("info: native defaults to bar", M.info("wifi").native === "bar");
check("info: sidebar-born says side", M.info("timer").native === "side");
check("info: side-only module is side", M.info("dock").native === "side");
check("info: unknown id is null", M.info("nope") === null);
check("hasOpt: bar spacing", M.hasOpt("tray", "bar", "spacing") && !M.hasOpt("tray", "side", "spacing"));
check("hasOpt: side peek", M.hasOpt("timer", "side", "peek") && !M.hasOpt("timer", "bar", "peek"));
check("forSurface carries the library fields",
      M.forSurface("bar").every(m => typeof m.blurb === "string" && typeof m.heroable === "boolean"));

// Optional: compare against a snapshot of the pre-merge lists, when given one
//   bun scripts/test-modules.js old-lists.json
if (process.argv[2]) {
    const old = JSON.parse(readFileSync(process.argv[2], "utf8"));
    for (const surface of ["bar", "side"]) {
        const now = M.forSurface(surface);
        // Same entries, key for key. Order within a surface may differ only where a module
        // moved to its other surface's slot (notifications), so compare by id.
        check(`${surface}: same ids`, JSON.stringify(now.map(m => m.id).sort()) === JSON.stringify(old[surface].map(m => m.id).sort()));
        for (const o of old[surface]) {
            const n = now.find(m => m.id === o.id);
            check(`${surface}/${o.id} identical to before`, n && JSON.stringify(Object.entries(n).sort()) === JSON.stringify(Object.entries(o).sort()));
        }
    }
}

console.log(failed ? `${failed} FAILED` : "all passed");
process.exit(failed ? 1 : 0);
