// ── test-surfaces.js ──────────────────────────────────────────────────────────
// Pins config/surfaces.js: the rules that span the top bar AND the sidebar.
//
//     bun scripts/test-surfaces.js          (or: node scripts/test-surfaces.js)
//
// Pure functions over plain data; touches nothing. Loaded the way test-layout.js
// loads layout.js (its `.pragma library` line stripped), so this runs the real file.
//
// The hero migration is the one that matters: a config written before Config.barHero
// existed must come out with the hero it already showed, or the clock's chip quietly
// moves after an upgrade.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "config", "surfaces.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const S = new Function(src + "\nreturn { heroFromFlags, stripHeroFlags, moveHero, STYLE_KEYS, cleanStyle, setOverride, clearOverride };")();

let pass = 0;
const failures = [];
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
function check(name, got, want) {
    if (eq(got, want)) { pass++; return; }
    failures.push(`  ${name}\n      want ${JSON.stringify(want)}\n      got  ${JSON.stringify(got)}`);
}

const R = ["left", "centre", "right"];
const HEROABLE = ["clock", "visualizer", "claude", "timer"];
const heroable = id => HEROABLE.includes(id);
const bar = { left: [["volume"], ["visualizer"]], centre: [["workspaces"]], right: [["clock"], ["claude"]] };

// ── heroFromFlags: today's bar rule, exactly ──────────────────────────────────
check("no flags: the clock (default on)", S.heroFromFlags({}, bar, R, heroable), "clock");
check("no document settings at all: the clock", S.heroFromFlags(undefined, bar, R, heroable), "clock");
check("clock explicitly off, nothing else: none",
      S.heroFromFlags({ clock: { hero: false } }, bar, R, heroable), "");
check("visualizer flagged: first in bar order wins over the default clock",
      S.heroFromFlags({ visualizer: { hero: true } }, bar, R, heroable), "visualizer");
check("two flagged: first in bar order",
      S.heroFromFlags({ claude: { hero: true }, visualizer: { hero: true } }, bar, R, heroable), "visualizer");
check("a flag on a non-heroable module is ignored",
      S.heroFromFlags({ volume: { hero: true }, clock: { hero: false } }, bar, R, heroable), "");
check("clock not on the bar, not turned off: still the clock (comes back as hero)",
      S.heroFromFlags({}, { left: [["volume"]], centre: [], right: [] }, R, heroable), "clock");
check("visualizer flagged off, clock default: the clock",
      S.heroFromFlags({ visualizer: { hero: false } }, bar, R, heroable), "clock");

// ── stripHeroFlags ────────────────────────────────────────────────────────────
{
    const ms = { clock: { hero: true }, wifi: { accent: "ramp2", hero: false }, volume: { rightPersist: true } };
    check("strip: hero keys gone, emptied entries dropped",
          S.stripHeroFlags(ms), { wifi: { accent: "ramp2" }, volume: { rightPersist: true } });
    check("strip: input untouched", ms.clock, { hero: true });
    const clean = { wifi: { accent: "ramp2" } };
    check("strip: nothing to strip hands back the SAME object", S.stripHeroFlags(clean) === clean, true);
    check("strip: undefined is {}", S.stripHeroFlags(undefined), {});
}

// ── moveHero ──────────────────────────────────────────────────────────────────
{
    const h = { bar: "clock", side: "claude" };
    check("bar hero to an empty-hero sidebar: it takes the sidebar's",
          S.moveHero({ bar: "clock", side: "" }, "clock", "side", false), { bar: "", side: "clock" });
    check("bar hero to a sidebar that has one: the destination keeps its own",
          S.moveHero(h, "clock", "side", true), { bar: "", side: "claude" });
    check("sidebar hero to the bar, bar's hero not standing there",
          S.moveHero(h, "claude", "bar", false), { bar: "claude", side: "" });
    check("a non-hero moving changes nothing (same object)", S.moveHero(h, "wifi", "side", false) === h, true);
    check("input untouched", h, { bar: "clock", side: "claude" });
}

// ── The sidebar's style overrides ─────────────────────────────────────────────
check("cleanStyle: known keys kept, clamped, rounded",
      S.cleanStyle({ roundness: 25.6, opacity: 0.2, innerPill: false, fontScale: 1.1 }),
      { roundness: 20, opacity: 0.5, innerPill: false, fontScale: 1.1 });
check("cleanStyle: wrong types and unknown keys dropped",
      S.cleanStyle({ roundness: "12", innerPill: 1, musicReact: true, nope: 3, iconScale: NaN }),
      { musicReact: true });
check("cleanStyle: junk is {}", S.cleanStyle([1, 2]), {});
check("cleanStyle: null is {}", S.cleanStyle(null), {});
{
    const st = { opacity: 0.8 };
    check("setOverride: adds, clamped", S.setOverride(st, "roundness", -4), { opacity: 0.8, roundness: 0 });
    check("setOverride: input untouched", st, { opacity: 0.8 });
    check("setOverride: bad value leaves the SAME object", S.setOverride(st, "innerPill", "yes") === st, true);
    check("setOverride: unknown key leaves the SAME object", S.setOverride(st, "nope", 1) === st, true);
    check("clearOverride: relinks", S.clearOverride(st, "opacity"), {});
    check("clearOverride: absent key is the SAME object", S.clearOverride(st, "roundness") === st, true);
}

const total = pass + failures.length;
console.log(`${pass}/${total} passed`);
if (failures.length > 0) {
    console.log("\nFAILED:");
    console.log(failures.join("\n"));
    process.exit(1);
}
