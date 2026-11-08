// ── test-volumeprofiles.js ────────────────────────────────────────────────────
// services/volumeprofiles.js: which named level a pair of volumes is, and what picking one
// changes. The rules worth pinning: soft/medium/max set the player and leave its stream alone
// (unless undoing a boost), boost over-amplifies the stream to the ceiling and no further,
// and leaving boost gives the stream back what it was.
//
//     bun scripts/test-volumeprofiles.js          (or: node scripts/test-volumeprofiles.js)
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "volumeprofiles.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { PROFILES, CEILING, detect, plan } =
    new Function(src + "; return { PROFILES, CEILING, detect, plan }")();

let failed = 0;
const eq = (name, got, want) => {
    if (JSON.stringify(got) === JSON.stringify(want)) return;
    failed++; console.log(`FAIL ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
};
const idx = k => PROFILES.findIndex(p => p.key === k);

// ── detect ───────────────────────────────────────────────────────────────────
eq("soft",            detect(0.35, 1.0), idx("soft"));
eq("medium",          detect(0.65, 1.0), idx("medium"));
eq("max",             detect(1.0,  1.0), idx("max"));
eq("boost",           detect(1.0,  1.3), idx("boost"));
eq("within tolerance", detect(0.37, 0.4), idx("soft"));        // the stream level is irrelevant below unity
eq("a custom level lights nothing", detect(0.5, 1.0), -1);
eq("rounding noise over unity is not a boost", detect(1.0, 1.0000004), idx("max"));
eq("full player, stream lifted = boost", detect(0.99, 1.15), idx("boost"));
eq("quiet player, stream lifted = its own profile", detect(0.35, 1.3), idx("soft"));
eq("muted lights nothing", detect(0, 1.0), -1);

// ── plan ─────────────────────────────────────────────────────────────────────
// soft, medium, max: the player only.
for (const k of ["soft", "medium", "max"]) {
    const p = plan(idx(k), 0.6, -1);
    eq(`${k} leaves the stream`, p.stream, null);
    eq(`${k} remembers nothing`, p.remember, null);
}
eq("soft sets the player", plan(idx("soft"), 0.6, -1).player, 0.35);

// boost: player full, stream up, and the stream's old level kept.
eq("boost from 60%", plan(idx("boost"), 0.6, -1), { player: 1, stream: CEILING, remember: 0.6 });
eq("boost again does not remember the boost", plan(idx("boost"), 1.3, 0.6),
   { player: 1, stream: CEILING, remember: null });

// leaving boost: the stream goes back.
eq("leave boost gives the stream back", plan(idx("medium"), 1.3, 0.6),
   { player: 0.65, stream: 0.6, remember: -1 });
eq("leave boost with nothing remembered goes to full, not louder", plan(idx("max"), 1.3, -1),
   { player: 1, stream: 1, remember: -1 });
eq("a remembered level over unity is not trusted", plan(idx("max"), 1.3, 1.4),
   { player: 1, stream: 1, remember: -1 });

// the ceiling: 130%, and boost never asks for more
eq("ceiling is 130%", CEILING, 1.3);
eq("boost asks for the ceiling, no more", plan(idx("boost"), 1.0, -1).stream, CEILING);

// bad input
eq("unknown profile", plan(99, 1, -1), { player: 1, stream: null, remember: null });

if (failed) { console.log(`${failed} failed`); process.exit(1); }
console.log("volumeprofiles: ok");
