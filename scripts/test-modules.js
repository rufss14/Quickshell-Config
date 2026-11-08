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
const M = new Function(src + "\nreturn { MODULES, forSurface, hasForm };")();

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
