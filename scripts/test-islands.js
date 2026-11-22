// ── test-islands.js ───────────────────────────────────────────────────────────
// config/islands.js — the bar's three islands: which panel is on which rail and which open alone,
// the rails' order, placement overrides, stepping, and that every panel has a name, an icon the
// bundled font carries and a shape that exists.
//
//     bun scripts/test-islands.js          (or: node scripts/test-islands.js)
//
// Safe: pure functions, reads two files.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const load = (rel, names) => new Function(
    readFileSync(join(here, "..", rel), "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "")
    + `\nreturn { ${names} };`)();
const I = load("config/islands.js",
    "SIDES, COLUMNS, BOTTOM, BOTTOM_COLUMN, ALIAS, PAGE_META, rowOf, hOf, pageFor, SIDE_META, ISLANDS, OFF_RAIL, META, OWN, OWN_META, RAILS, LOCKED, meta, pageMeta, offRail, defaultSide, sideOf, railSide, placeable, defaults, pagesOf, step, "
    + "railable, hasColumn, railDefault, allPages, layoutOf, railOf, snapshot, defaultRails, move, OPTIONS, overrides, optionOf, withOverride, overrideCount");
const T = load("services/island.js", "TABS");
const icons = readFileSync(join(here, "..", "services", "icons.js"), "utf8");
const shapes = readFileSync(join(here, "..", "components", "shapes.js"), "utf8");

let passed = 0, failed = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) passed++;
    else { failed++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`); }
}

const rail = I.SIDES.flatMap(s => I.ISLANDS[s]).filter(k => I.META[k]);
const alone = Object.keys(I.OFF_RAIL);
const all = rail.concat(alone);

// ── The grouping ─────────────────────────────────────────────────────────────
check("six islands, top row first", I.SIDES, ["left", "center", "right", "bottomLeft", "bottomCenter", "bottomRight"]);
check("the columns are the top row", I.COLUMNS, ["left", "center", "right"]);
check("rows", I.SIDES.map(I.rowOf), ["top", "top", "top", "bottom", "bottom", "bottom"]);
check("along the edge", I.SIDES.map(I.hOf), ["left", "center", "right", "left", "center", "right"]);
check("bottom left is your day", I.pagesOf("bottomLeft", {}), ["desk", "timer", "files", "workout", "tablet"]);
check("bottom middle is clips and the call", I.pagesOf("bottomCenter", { clips: "left" }), ["clips", "voice", "captures", "assistant"]);
check("bottom right is screen time and Claude", I.pagesOf("bottomRight", {}), ["screentime", "claude", "power"]);
check("Desk is a page, not a panel", [I.META.desk, I.pageMeta("desk").label, I.hasColumn("desk"), I.railable("desk")], [undefined, "Desk", false, true]);
check("Desk's icon is in the font", new RegExp(`["\\s]${I.PAGE_META.desk.icon}"?:`).test(icons), true);
check("23 panels, none twice", [all.length, new Set(all).size], [23, 23]);
check("left is look and sound", I.pagesOf("left", {}), ["wallpaper", "colorScheme", "equalizer", "window", "layout"]);
check("the middle carries clock, notifications and the agenda", I.pagesOf("center", {}), ["clock", "notifications", "agenda"]);
check("right is the system", I.pagesOf("right", {}), ["wifi", "bluetooth", "brightness", "gaming", "network", "displays", "update"]);
check("an unknown side has no pages", I.pagesOf("top", {}), []);
check("no placement map is no overrides", I.pagesOf("left"), I.pagesOf("left", {}));

// ── On a rail, or alone ──────────────────────────────────────────────────────
check("wifi is on the right rail", I.railSide("wifi", {}), "right");
check("clock is on the middle rail", I.railSide("clock", {}), "center");
check("the launcher is on no rail", I.railSide("launcher", {}), "");
check("an update is a page on the right rail", I.railSide("update", {}), "right");
check("…whose column stays the middle", I.sideOf("update", {}), "center");
check("…and placement does not move its rail", I.railSide("update", { update: "left" }), "right");
check("now playing is on no rail", I.railSide("media", {}), "");
check("the sidebar's panels are on no top rail",
    ["stats", "clipboard", "timer", "claude", "screentime", "inactivity", "tasks", "clips"].map(k => I.railSide(k, {})).join(""), "");
check("an unknown key is on no rail", I.railSide("nope", {}), "");
check("no rail page is also off-rail", rail.filter(k => I.offRail(k)), []);
check("a panel that opens alone is on no strip", I.SIDES.flatMap(s => I.pagesOf(s, { stats: "left", media: "center" })).filter(k => I.offRail(k)), []);

// ── Every panel can be drawn ─────────────────────────────────────────────────
check("every panel has meta", all.filter(k => !I.META[k]), []);
check("meta has no panel that is nowhere", Object.keys(I.META).filter(k => !all.includes(k)), []);
check("every label and icon is set", all.filter(k => !I.META[k].label || !I.META[k].icon), []);
check("every icon is in the bundled font's table",
    all.filter(k => !new RegExp(`["\\s]${I.META[k].icon}"?:`).test(icons)).map(k => I.META[k].icon), []);
check("every shape exists",
    all.filter(k => {
        const s = I.META[k].shape;
        return !(s === "circle" || /^cookie\d+$/.test(s) || shapes.includes(`case "${s}"`));
    }).map(k => I.META[k].shape), []);
check("a page built for an island has a real size",
    all.filter(k => I.META[k].body && !(I.META[k].body.w > 0 && I.META[k].body.h > 0)), []);
check("an unknown key still draws", I.meta("nope"), { label: "nope", icon: "square", shape: "circle" });
check("nothing still draws", I.meta(undefined).icon, "square");

// ── Sides and overrides ──────────────────────────────────────────────────────
check("clock opens in the middle", I.sideOf("clock", {}), "center");
check("wifi opens on the right", I.sideOf("wifi", {}), "right");
check("now playing opens on the left", I.sideOf("media", {}), "left");
check("a sidebar panel opens on the right", I.sideOf("stats", {}), "right");
check("a bottom page's panel opens in the right column", I.sideOf("timer", {}), "right");
check("a bottom island is no column", I.sideOf("timer", { timer: "bottomLeft" }), "right");
check("an unknown key opens on the left", I.sideOf("nope", {}), "left");
check("an override moves a page", I.sideOf("clock", { clock: "right" }), "right");
check("an override moves a panel that opens alone", I.sideOf("stats", { stats: "left" }), "left");
check("a bad override is ignored", I.sideOf("clock", { clock: "top" }), "center");
check("a null placement is no overrides", I.sideOf("clock", null), "center");
check("the launcher cannot be moved", I.sideOf("launcher", { launcher: "left" }), "center");
check("an update cannot be moved", I.sideOf("update", { update: "right" }), "center");
check("a moved page leaves its island", I.pagesOf("center", { clock: "right" }), ["notifications", "agenda"]);
check("…and lands at the end of the other", I.pagesOf("right", { clock: "right" }).slice(-2), ["update", "clock"]);
check("every rail page is on exactly one rail",
    rail.map(k => I.SIDES.filter(s => I.pagesOf(s, { clock: "left", wifi: "center" }).includes(k)).length)
        .every(n => n === 1), true);
check("an island can be emptied", I.pagesOf("center", { clock: "left", notifications: "right", agenda: "right" }), []);
check("placeable leaves out the launcher", I.placeable().length, 22);
check("defaults name every placeable panel", Object.keys(I.defaults()), I.placeable());
check("defaults agree with defaultSide", I.placeable().every(k => I.defaults()[k] === I.defaultSide(k)), true);

// ── Stepping ─────────────────────────────────────────────────────────────────
const strip = I.pagesOf("left", {});
check("a step forward", I.step(strip, "wallpaper", 1), "colorScheme");
check("a step back", I.step(strip, "colorScheme", -1), "wallpaper");
check("it stops at the start", I.step(strip, "wallpaper", -1), "wallpaper");
check("it stops at the end", I.step(strip, "layout", 1), "layout");
check("a page off the rail stays", I.step(strip, "launcher", 1), "launcher");
check("no rail stays", I.step(undefined, "clock", 1), "clock");


// ── The layout ───────────────────────────────────────────────────────────────
const D = I.layoutOf({}, {}, undefined);
check("an untouched shell has today's rails", [D.rails.left, D.rails.center, D.rails.right], [
    ["wallpaper", "colorScheme", "equalizer", "window", "layout"],
    ["today", "media", "system", "weather", "clock", "notifications", "agenda"],
    ["wifi", "bluetooth", "brightness", "gaming", "network", "displays", "update"]]);
check("…the bottom row's defaults", [D.rails.bottomLeft, D.rails.bottomCenter, D.rails.bottomRight],
    [["desk", "timer", "files", "workout", "tablet"], ["clips", "voice", "captures", "assistant"], ["screentime", "claude", "power"]]);
check("…and the rest open alone where they did", [D.alone.left, D.alone.center, D.alone.right],
    [[], ["launcher"], ["stats", "clipboard", "inactivity", "tasks"]]);
check("…and no bottom island has a column", I.BOTTOM.map(s => D.alone[s]), [undefined, undefined, undefined]);
check("…and nothing is hidden", D.hidden, []);
check("every known page is in exactly one place", (() => {
    const L = I.layoutOf({}, { clock: "right" }, ["weather"]);
    const places = I.allPages().map(k => I.SIDES.filter(s => L.rails[s].includes(k) || (L.alone[s] || []).includes(k)).length + (L.hidden.includes(k) ? 1 : 0));
    return places.every(n => n === 1);
})(), true);
check("own pages mirror services/island.js", I.OWN.map(k => I.OWN_META[k]), T.TABS.map(t => ({ label: t.label, icon: t.icon, shape: t.shape })));
check("every own icon is in the font", I.OWN.filter(k => !new RegExp(`["\\s]${I.OWN_META[k].icon}"?:`).test(icons)), []);
check("every island's icon is in the font", I.SIDES.filter(s => !new RegExp(`["\\s]${I.SIDE_META[s].icon}"?:`).test(icons)), []);
check("Media is drawn as the page, not Now Playing", I.pageMeta("media").label, "Media");

// Before the board was used: the older settings decide.
const legacy = I.layoutOf({}, { clock: "right", wifi: "left" }, ["weather", "today"]);
check("legacy: kept own pages in their order", legacy.rails.center, ["weather", "today", "notifications", "agenda"]);
check("legacy: dropped own pages are hidden, Media opens alone", [legacy.hidden, legacy.alone.left], [["system"], ["media"]]);
check("legacy: a moved panel lands at the end", [legacy.rails.right.slice(-1), legacy.rails.left.slice(-1)], [["clock"], ["wifi"]]);
check("legacy: junk own pages are all four", I.layoutOf({}, {}, "today").rails.center.slice(0, 4), I.OWN);
check("a junk rails map is never saved", I.layoutOf([1, 2], {}, []).rails.left, D.rails.left);

// Saved by the board.
const saved = I.layoutOf({ left: ["stats", "wifi", "nope", "wifi"], center: ["media"], right: [], off: ["wallpaper", "colorScheme", "equalizer", "window", "layout", "today", "system", "weather", "clock", "notifications", "bluetooth", "brightness", "gaming", "network", "displays", "update"] }, { stats: "left" }, []);
check("saved: order kept, junk and repeats dropped", saved.rails.left, ["stats", "wifi"]);
check("saved: an island can be emptied", saved.rails.right, []);
check("saved: own pages taken off are hidden", saved.hidden, ["today", "system", "weather", "network", "displays"]);
check("saved: panels taken off open alone in their column", saved.alone.right.includes("bluetooth") && saved.alone.center.includes("clock"), true);
check("saved: the launcher cannot be put on a rail", I.layoutOf({ left: ["launcher"], center: [], right: [] }, {}, []).alone.center.slice(0, 1), ["launcher"]);
check("saved: a page a later build adds stands at its default",
    I.layoutOf({ left: [], center: [], right: [], off: ["today"] }, {}, []).rails.center, ["media", "system", "weather", "clock", "notifications", "agenda"]);
check("saved before the bottom row: its pages come to their islands", [saved.rails.bottomLeft, saved.rails.bottomRight], [["desk", "timer", "files", "workout", "tablet"], ["screentime", "claude", "power"]]);
const oldOff = I.layoutOf({ left: [], center: ["today"], right: ["claude"], off: ["timer", "clips", "desk"] }, {}, []);
check("…even listed under off then", [oldOff.rails.bottomLeft, oldOff.rails.bottomCenter], [["desk", "timer", "files", "workout", "tablet"], ["clips", "voice", "captures", "assistant"]]);
check("…but not one put on a top rail", [oldOff.rails.right[0], oldOff.rails.bottomRight], ["claude", ["screentime", "power"]]);
const newOff = I.layoutOf({ left: [], center: [], right: [], bottomLeft: [], bottomCenter: [], bottomRight: [], off: ["timer", "desk", "files"] }, {}, []);
// (Workout and Tablet are in no saved list: a page a later build adds stands at its default, so they are the ones left on the rail.)
check("saved with the bottom row: off stays off", [newOff.rails.bottomLeft, newOff.alone.right.includes("timer"), newOff.hidden.includes("desk")], [["workout", "tablet"], true, true]);
check("railOf finds a page", [I.railOf("wifi", saved), I.railOf("clock", saved), I.railOf("x", null)], ["left", "", ""]);
check("a snapshot reads back as the same layout", JSON.stringify(I.layoutOf(I.snapshot(saved), { stats: "left" }, [])), JSON.stringify(saved));
check("defaultRails reads back as the defaults", JSON.stringify(I.layoutOf(I.defaultRails(), {}, [])), JSON.stringify(D));

// Moving.
const m1 = I.move(D, "clock", "rail", "left", 1);
check("move onto another rail at a place", I.layoutOf(m1.rails, {}, []).rails.left.slice(0, 3), ["wallpaper", "clock", "colorScheme"]);
check("…leaves the old one", I.layoutOf(m1.rails, {}, []).rails.center.includes("clock"), false);
check("…and writes no column", m1.column, "");
check("move within a rail", I.layoutOf(I.move(D, "weather", "rail", "center", 0).rails, {}, []).rails.center.slice(0, 2), ["weather", "today"]);
check("an index past the end is last", I.layoutOf(I.move(D, "wifi", "rail", "right", 99).rails, {}, []).rails.right.slice(-1), ["wifi"]);
check("a sidebar panel goes onto a rail", I.layoutOf(I.move(D, "timer", "rail", "center", 2).rails, {}, []).rails.center[2], "timer");
const m2 = I.move(D, "wifi", "alone", "left", 0);
check("move to open alone writes its column", [m2.column, I.layoutOf(m2.rails, { wifi: "left" }, []).alone.left], ["left", ["wifi"]]);
const m3 = I.move(D, "today", "alone", "left", 0);
check("an own page sent alone is hidden", [m3.column, I.layoutOf(m3.rails, {}, []).hidden], ["", ["today"]]);
const m4 = I.move(D, "bluetooth", "hidden", "", 0);
check("a panel hidden opens alone where it was", [m4.column, I.layoutOf(m4.rails, {}, []).alone.right.includes("bluetooth")], ["", true]);
check("the launcher does not move", I.move(D, "launcher", "rail", "left", 0), null);
check("an unknown page does not move", I.move(D, "nope", "rail", "left", 0), null);
check("a bad side does not move", I.move(D, "wifi", "rail", "top", 0), null);
check("a page goes onto a bottom rail", I.layoutOf(I.move(D, "wifi", "rail", "bottomCenter", 0).rails, {}, []).rails.bottomCenter, ["wifi", "clips", "voice", "captures", "assistant"]);
check("a bottom island has no column to open alone in", I.move(D, "timer", "alone", "bottomLeft", 0), null);
const m5 = I.move(D, "timer", "alone", "right", 0);
check("a bottom page sent alone opens in a column", [m5.column, I.layoutOf(m5.rails, {}, []).alone.right.includes("timer")], ["right", true]);

// ── Pages that do a panel's job ──────────────────────────────────────────────
check("stats opens Performance", I.pageFor("stats", D), "system");
check("the small three open Desk", ["tasks", "clipboard", "inactivity"].map(k => I.pageFor(k, D)), ["desk", "desk", "desk"]);
check("a page on a rail is itself", [I.pageFor("timer", D), I.pageFor("wifi", D)], ["timer", "wifi"]);
check("a panel that opens alone and has no stand-in is nothing", I.pageFor("launcher", D), "");
const noDesk = I.layoutOf(I.move(D, "desk", "hidden", "", 0).rails, {}, []);
check("Desk off every rail gives the buttons back", I.pageFor("tasks", noDesk), "");
const tasksOn = I.layoutOf(I.move(D, "tasks", "rail", "bottomRight", 0).rails, {}, []);
check("a panel put on a rail itself wins over its stand-in", I.pageFor("tasks", tasksOn), "tasks");
check("every stand-in is a real page", Object.values(I.ALIAS).filter(v => !I.railable(v)), []);
check("a bad zone does not move", I.move(D, "wifi", "sky", "left", 0), null);

// ── Per-island options ───────────────────────────────────────────────────────
const G = { openBy: "hover", delay: 180, linger: 450, handle: 56, scale: 1, effects: true };
check("no override is the shared value", I.optionOf("left", "delay", G, {}), 180);
check("an override wins", I.optionOf("left", "delay", G, { left: { delay: 300 } }), 300);
check("…only on its island", I.optionOf("right", "delay", G, { left: { delay: 300 } }), 180);
check("an override is kept to its range", I.optionOf("left", "scale", G, { left: { scale: 9 } }), 1.25);
check("a junk override is the shared value", [I.optionOf("left", "openBy", G, { left: { openBy: "wave" } }), I.overrides("left", "openBy", { left: { openBy: "wave" } })], ["hover", false]);
check("a junk shared value is the fallback", I.optionOf("left", "handle", { handle: "x" }, {}), 56);
check("false is a real override", I.optionOf("center", "effects", G, { center: { effects: false } }), false);
check("an unknown option is nothing", I.optionOf("left", "colour", G, {}), undefined);
check("withOverride sets one", I.withOverride({}, "left", "delay", 240), { left: { delay: 240 } });
check("withOverride clears one and the empty island", I.withOverride({ left: { delay: 240 } }, "left", "delay", undefined), {});
check("withOverride keeps the others", I.withOverride({ right: { linger: 600 } }, "left", "delay", 0), { right: { linger: 600 }, left: { delay: 0 } });
check("withOverride drops junk sides", I.withOverride({ top: { delay: 1 }, left: 3 }, "right", "effects", false), { right: { effects: false } });
check("withOverride ignores an invalid value", I.withOverride({}, "left", "openBy", "wave"), {});
check("overrideCount", I.overrideCount("left", { left: { delay: 1, scale: 1, nope: 2 } }), 2);

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
