// ── test-desktopwidgets.js ────────────────────────────────────────────────────
// Tests for services/desktopwidgets.js — the rules that REMOVE desktop tiles.
//
//     bun scripts/test-desktopwidgets.js      (or: node scripts/test-desktopwidgets.js)
//
// Safe to run: pure functions, no I/O. Same contract as test-kelvin.js — the .js is
// loaded by stripping its `.pragma library` line, so the tests run against the real
// file rather than a copy that can drift.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "desktopwidgets.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

const { presetFor, dropStacked, fit, expandHome, contractHome, isoDay, dayShift, lastDays, toggleDay, streak, stackSurface, inLayout, uniqueName, wallName } =
    new Function(src + "\nreturn { presetFor, dropStacked, fit, expandHome, contractHome, isoDay, dayShift, lastDays, toggleDay, streak, stackSurface, inLayout, uniqueName, wallName };")();

let pass = 0, fail = 0;
const failures = [];
function check(name, ok, detail) {
    if (ok) { pass++; return }
    fail++;
    failures.push(`  ${name}${detail ? "\n      " + detail : ""}`);
}
const ids = list => list.map(w => w.id).join(",");
const holdsText = t => t === "notes" || t === "reminders";
const tile = (id, type, x, y, screen = "DP-2", opts = {}) => ({ id, type, screen, x, y, size: "small", opts });

// The exact shape the old applyPreset() left on a real desktop: a two-monitor preset
// retargeted onto DP-2, so each type landed twice at one position, the HDMI set last.
const doubled = [
    tile(32, "clock", 16, 16), tile(33, "calendar", 200, 20), tile(34, "sysmon", 1540, 200),
    tile(35, "weather", 1720, 200), tile(36, "updates", 1540, 20), tile(37, "lyrics", 16, 200, "DP-2", { bare: true }),
    tile(38, "clock", 16, 16), tile(39, "calendar", 200, 20), tile(40, "sysmon", 1540, 200),
    tile(41, "weather", 1720, 200), tile(42, "updates", 1540, 20), tile(43, "lyrics", 16, 200),
];

// ── dropStacked ───────────────────────────────────────────────────────────────
{
    const out = dropStacked(doubled, holdsText);
    check("the doubled desktop collapses to one of each", out.length === 6, ids(out));
    // The LATER copy is the one drawn on top — the one that was visible and clickable.
    check("keeps the copy that was on top", ids(out) === "38,39,40,41,42,43", ids(out));
    check("the kept lyrics tile is the top one (framed, not bare)",
          out.find(w => w.type === "lyrics").opts.bare === undefined);
}
{
    // Two deliberate tiles of one type, from before the one-per-type rule, sit at
    // different positions — they are not duplicates and must survive.
    const two = [tile(1, "disk", 16, 16, "DP-2", { mount: "/" }), tile(2, "disk", 200, 16, "DP-2", { mount: "/home" })];
    check("side-by-side tiles of one type are kept", dropStacked(two, holdsText).length === 2);
}
{
    // Same type, same position, DIFFERENT screens: not stacked on each other.
    const across = [tile(1, "clock", 16, 16, "DP-2"), tile(2, "clock", 16, 16, "HDMI-A-1")];
    check("same spot on two screens is kept", dropStacked(across, holdsText).length === 2);
}
{
    // Stacked notes hold typed text — never dropped by a load-time cleanup.
    const notes = [tile(1, "notes", 16, 16, "DP-2", { text: "a" }), tile(2, "notes", 16, 16, "DP-2", { text: "b" })];
    const out = dropStacked(notes, holdsText);
    check("stacked text tiles are never dropped", out.length === 2, ids(out));
    const rem = [tile(1, "reminders", 0, 0), tile(2, "reminders", 0, 0), tile(3, "clock", 0, 0), tile(4, "clock", 0, 0)];
    check("…while a stacked display tile beside them still goes",
          ids(dropStacked(rem, holdsText)) === "1,2,4", ids(dropStacked(rem, holdsText)));
}
{
    check("an empty list stays empty", dropStacked([], holdsText).length === 0);
    const clean = doubled.slice(6);
    check("a clean list is returned unchanged", ids(dropStacked(clean, holdsText)) === ids(clean));
}

// ── presetFor ─────────────────────────────────────────────────────────────────
// The shipped "Quicktest 1#" preset: savePreset() stores the whole desktop, so it is
// two complete layouts, one per monitor — only DP-2's lyrics tile is bare.
const DP = "DP-2", HD = "HDMI-A-1";
const twoMonitor = [
    tile(12, "clock", 16, 16, DP), tile(13, "calendar", 200, 20, DP), tile(15, "sysmon", 1540, 200, DP),
    tile(16, "weather", 1720, 200, DP), tile(17, "updates", 1540, 20, DP), tile(19, "lyrics", 16, 200, DP, { bare: true }),
    tile(20, "clock", 16, 16, HD), tile(21, "calendar", 200, 20, HD), tile(23, "sysmon", 1540, 200, HD),
    tile(24, "weather", 1720, 200, HD), tile(25, "updates", 1540, 20, HD), tile(26, "lyrics", 16, 200, HD),
];
{
    // The bug: applyPreset(name, "DP-2") retargeted all twelve onto DP-2.
    const out = presetFor(twoMonitor, DP);
    check("applied to DP-2: DP-2's own six, not both screens'", ids(out) === "12,13,15,16,17,19", ids(out));
    check("…including DP-2's own (bare) lyrics tile",
          out.find(w => w.type === "lyrics").opts.bare === true);
    check("applied to HDMI-A-1: HDMI's own six", ids(presetFor(twoMonitor, HD)) === "20,21,23,24,25,26",
          ids(presetFor(twoMonitor, HD)));
}
{
    // A monitor the preset never saw still gets a whole layout — ONE screen's, never both.
    const out = presetFor(twoMonitor, "eDP-1");
    check("an unknown screen gets the first screen's layout", ids(out) === "12,13,15,16,17,19", ids(out));
}
{
    const out = presetFor(twoMonitor, undefined);
    check("no screen: every record to its own screen", out.length === 12, ids(out));
}
{
    // A preset SAVED from an already-broken desktop holds the stack itself.
    const out = presetFor(doubled, DP);
    check("a preset saved with a stack applies one of each", out.length === 6, ids(out));
    check("…the top copy of each, in original order", ids(out) === "38,39,40,41,42,43", ids(out));
    check("an empty preset applies nothing", presetFor([], DP).length === 0);
}

// ── fit ───────────────────────────────────────────────────────────────────────
{
    const sizeOf = t => ({ w: t.size === "medium" ? 352 : 168, h: 168 });
    const at = (o, id) => `${o[id].x},${o[id].y}`;
    // The real desktop: right-hand column at x=1540/1720 on a layer that was 1896 wide,
    // now 1836 wide with the dock reserved on the left.
    const desk = doubled.slice(6).map(w => ({ ...w, size: w.type === "updates" || w.type === "lyrics" ? "medium" : "small" }));
    const before = JSON.stringify(desk);
    const wide = fit(desk, 1896, 1000, sizeOf, 16);
    check("a layer that fits changes nothing", at(wide, 41) === "1720,200" && at(wide, 40) === "1540,200", at(wide, 41));
    const narrow = fit(desk, 1836, 1000, sizeOf, 16);
    check("the edge tile is pulled in to the edge", at(narrow, 41) === "1668,200", at(narrow, 41));
    check("…and takes its neighbour with it, spacing kept (12px, not 16)", at(narrow, 40) === "1488,200", at(narrow, 40));
    check("the medium tile above is pulled in by its own overhang", at(narrow, 42) === "1484,20", at(narrow, 42));
    check("tiles that fit stay put", at(narrow, 38) === "16,16" && at(narrow, 43) === "16,200");
    check("no overlap on the far row", narrow[40].x + 168 <= narrow[41].x, `${at(narrow, 40)} ${at(narrow, 41)}`);
    check("the stored records are not touched", JSON.stringify(desk) === before);
    check("no layer yet (0×0) returns stored positions", at(fit(desk, 0, 0, sizeOf, 16), 41) === "1720,200");
    // Bottom edge, same rule on the other axis.
    const col = [tile(1, "a", 20, 700), tile(2, "b", 20, 880)].map(w => ({ ...w, size: "small" }));
    const short = fit(col, 400, 1000, sizeOf, 16);
    check("bottom overflow is pulled up", at(short, 2) === "20,832", at(short, 2));
    check("…with the tile above it, spacing kept (12px)", at(short, 1) === "20,652", at(short, 1));
    check("a tile wider than the layer pins to 0, never negative", at(fit([{ ...tile(1, "a", 50, 0), size: "medium" }], 300, 500, sizeOf, 16), 1) === "0,0");
}

// ── presetFor, a type placed more than once ───────────────────────────────────
{
    const multi = t => t === "photo";
    const two = [tile(1, "photo", 0, 0), tile(2, "photo", 200, 0), tile(3, "clock", 0, 200), tile(4, "clock", 200, 200)]
        .map(w => ({ ...w, screen: "DP-2" }));
    const kept = presetFor(two, "DP-2", multi);
    check("both photo frames are kept", kept.filter(w => w.type === "photo").length === 2, JSON.stringify(kept));
    check("a single-instance type still keeps one", kept.filter(w => w.type === "clock").length === 1);
    check("no predicate = the old one-per-type rule", presetFor(two, "DP-2").filter(w => w.type === "photo").length === 1);
}

// ── ~ paths ───────────────────────────────────────────────────────────────────
{
    const H = "/home/alex";
    check("expand ~/", expandHome("~/Pictures/a.jpg", H) === "/home/alex/Pictures/a.jpg");
    check("expand ~", expandHome("~", H) === H);
    check("absolute untouched", expandHome("/srv/pics", H) === "/srv/pics");
    check("~user untouched", expandHome("~bob/x", H) === "~bob/x");
    check("contract", contractHome("/home/alex/Pictures", H) === "~/Pictures");
    check("contract home", contractHome("/home/alex", H) === "~");
    check("prefix is not a parent", contractHome("/home/alexandra/x", H) === "/home/alexandra/x");
    check("round trip", expandHome(contractHome("/home/alex/a b/c.png", H), H) === "/home/alex/a b/c.png");
    check("no home = as given", contractHome("/home/alex/x", "") === "/home/alex/x" && expandHome("~/x", "") === "~/x");
}

// ── Habits ────────────────────────────────────────────────────────────────────
{
    check("isoDay pads", isoDay(new Date(2026, 0, 5)) === "2026-01-05");
    check("dayShift across a month", dayShift("2026-10-31", 1) === "2026-11-01");
    check("dayShift across a year, backwards", dayShift("2026-01-01", -1) === "2025-12-31");
    check("dayShift leap day", dayShift("2028-02-28", 1) === "2028-02-29");
    // Europe/Lisbon (and most of Europe) leaves summer time on 2026-10-25: still one day per step.
    check("dayShift over a DST change", dayShift("2026-10-24", 1) === "2026-10-25" && dayShift("2026-10-25", 1) === "2026-10-26");
    check("dayShift bad input", dayShift("nope", 1) === "");
    const week = lastDays("2026-10-30", 7);
    check("lastDays oldest first, ends today", week.length === 7 && week[0] === "2026-10-24" && week[6] === "2026-10-30", week.join(","));
    check("toggleDay adds sorted", toggleDay(["2026-10-30"], "2026-10-28").join(",") === "2026-10-28,2026-10-30");
    check("toggleDay removes", toggleDay(["2026-10-28", "2026-10-30"], "2026-10-28").join(",") === "2026-10-30");
    check("toggleDay from nothing", toggleDay(undefined, "2026-10-30").join(",") === "2026-10-30");
    const done = ["2026-10-26", "2026-10-27", "2026-10-28", "2026-10-29"];
    check("streak through yesterday, today open", streak(done, "2026-10-30") === 4, streak(done, "2026-10-30"));
    check("streak including today", streak(done.concat("2026-10-30"), "2026-10-30") === 5);
    check("a gap breaks it", streak(["2026-10-27", "2026-10-29", "2026-10-30"], "2026-10-30") === 2);
    check("nothing recent = 0", streak(["2026-10-20"], "2026-10-30") === 0);
    check("empty = 0", streak([], "2026-10-30") === 0);
}

// ── Smart stack ───────────────────────────────────────────────────────────────
{
    const cards = ["weather", "nowplaying", "timer", "calendar"];
    check("nothing going on: stay", stackSurface(cards, {}) === -1);
    check("music: the media card", stackSurface(cards, { playing: true }) === 1);
    check("timer wins over music", stackSurface(cards, { playing: true, timer: true }) === 2);
    check("no media card: stay", stackSurface(["weather", "clock"], { playing: true }) === -1);
    check("lyrics counts as media", stackSurface(["clock", "lyrics"], { playing: true }) === 1);
    check("no cards", stackSurface(undefined, { playing: true }) === -1);
}

// ── Layouts ───────────────────────────────────────────────────────────────────
{
    // The same tile, copied into a wallpaper's own layout: NOT a stacked duplicate.
    const home = tile(1, "clock", 16, 16);
    const copy = { ...tile(2, "clock", 16, 16), layout: "Furina" };
    const kept = dropStacked([home, copy], () => false);
    check("a layout's copy survives the de-dupe", kept.length === 2, JSON.stringify(kept));
    // …while a real stack inside ONE layout is still cleaned.
    const stacked = [{ ...tile(3, "clock", 40, 40), layout: "Furina" }, { ...tile(4, "clock", 40, 40), layout: "Furina" }];
    check("a stack inside a layout is still dropped", dropStacked(stacked, () => false).length === 1);
    check("inLayout: absent = normal", inLayout(home, "") && inLayout(home, undefined) && !inLayout(home, "Furina"));
    check("inLayout: named", inLayout(copy, "Furina") && !inLayout(copy, ""));
    check("uniqueName free", uniqueName("Furina", ["Other"]) === "Furina");
    check("uniqueName taken", uniqueName("Furina", ["Furina", "Furina 2"]) === "Furina 3");
    check("uniqueName empty", uniqueName("  ", []) === "Layout");
    check("wallName file", wallName("~/wallpapers/walls/Furina.png") === "Furina");
    check("wallName dotted", wallName("/a/b/my.cool.pic.jpg") === "my.cool.pic");
    check("wallName scene", wallName("scene:12345") === "Scene 12345");
    check("wallName empty", wallName("") === "");
}

console.log(`desktopwidgets: ${pass} passed, ${fail} failed`);
if (fail) { console.log(failures.join("\n")); process.exit(1); }
