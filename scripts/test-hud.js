// ── test-hud.js ───────────────────────────────────────────────────────────────
// Tests for services/hud.js (the HUD layout rules) and services/mangohud.js (the
// fps_limit line).
//
//     bun scripts/test-hud.js      (or: node scripts/test-hud.js)
//
// Safe to run: pure functions, no I/O.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const load = (f, names) => new Function(
    readFileSync(join(here, "..", "services", f), "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "")
    + `\nreturn { ${names} };`)();
const H = load("hud.js", "ids, info, normalise, set, clampCentre, visible, interactive, anyPinned, snapCentre, snapPlace, setHome, homeScreen, CATALOG, ANCHORS, perfVerdict, INPUT_LAYOUTS");
const IK = load("inputkeys.js", "LAYOUT_IDS");
const M = load("mangohud.js", "readLimit, parseLimit, setLimit");

let pass = 0, fail = 0;
const failures = [];
function check(name, ok, detail) {
    if (ok) { pass++; return }
    fail++;
    failures.push(`  ${name}${detail ? "\n      " + detail : ""}`);
}
const eq = (name, got, want) =>
    check(name, JSON.stringify(got) === JSON.stringify(want), `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);

// ── normalise ────────────────────────────────────────────────────────────────
{
    const n = H.normalise(null);
    eq("every widget exists on an empty doc", Object.keys(n.widgets), H.ids());
    eq("nothing is pinned by default", H.ids().some(id => n.widgets[id].pinned), false);
    eq("click-through by default", n.widgets.stats.clickthrough, true);
    eq("voice keeps its default place", [n.widgets.voice.cx, n.widgets.voice.cy], [0.1, 0.2]);
    eq("cards carry an opacity only", n.widgets.stats.opts, { opacity: 0.9 });
}
{
    const n = H.normalise({ widgets: {
        voice: { pinned: "yes", cx: 7, cy: -3, opts: { opacity: "glass" } },
        crosshair: { pinned: true, cx: 0.5, cy: 0.5, opts: { style: "cross" } },
        bogus: { pinned: true },
        stats: "nope"
    } });
    eq("unknown widgets are dropped", "bogus" in n.widgets, false);
    eq("a crosshair from before 2026-10-20 is dropped", "crosshair" in n.widgets, false);
    eq("old files: pinned but never shown stays unpinned",
       H.normalise({ widgets: { stats: { shown: false, pinned: true } } }).widgets.stats.pinned, false);
    eq("old files: shown and pinned stays pinned",
       H.normalise({ widgets: { stats: { shown: true, pinned: true } } }).widgets.stats.pinned, true);
    eq("new files: pinned alone is pinned",
       H.normalise({ widgets: { stats: { pinned: true } } }).widgets.stats.pinned, true);
    eq("pinned must be exactly true", n.widgets.voice.pinned, false);
    eq("clickthrough only false when false", H.normalise({ widgets: { stats: { clickthrough: false } } }).widgets.stats.clickthrough, false);
    eq("fractions are clamped", [n.widgets.voice.cx, n.widgets.voice.cy], [1, 0]);
    eq("a bad opacity falls back", n.widgets.voice.opts.opacity, 0.9);
    eq("a non-object entry is the default", n.widgets.stats.pinned, false);
}
eq("garbage doc", Object.keys(H.normalise("x").widgets).length, H.ids().length);

// ── snapCentre ───────────────────────────────────────────────────────────────
eq("within the threshold snaps", H.snapCentre(0.5 + 10 / 1920, 1920), 0.5);
eq("past it does not", H.snapCentre(0.5 + 20 / 1920, 1920), 0.5 + 20 / 1920);
eq("below centre too", H.snapCentre(0.5 - 12 / 1080, 1080), 0.5);
eq("a custom threshold", H.snapCentre(0.52, 100, 1), 0.52);
eq("no screen size: unchanged", H.snapCentre(0.49, 0), 0.49);
eq("every catalogue entry has a blurb", H.CATALOG.every(c => typeof c.blurb === "string" && c.blurb !== ""), true);

// ── set ──────────────────────────────────────────────────────────────────────
{
    const a = H.normalise(null);
    const b = H.set(a, "stats", { pinned: true, cx: 0.2 });
    eq("set changes the field", [b.widgets.stats.pinned, b.widgets.stats.cx], [true, 0.2]);
    eq("set leaves the argument alone", a.widgets.stats.pinned, false);
    eq("set merges options", H.set(a, "input", { opts: { scale: 1.5 } }).widgets.input.opts,
       { scale: 1.5, opacity: 0.85, layout: "wasd", mouse: true, stats: true });
    check("an unknown id changes nothing", H.set(a, "nope", { pinned: true }) === a);
    eq("set goes through the same gate", H.set(a, "stats", { cx: 5 }).widgets.stats.cx, 1);
}

// ── the input overlay's size ─────────────────────────────────────────────────
{
    const a = H.normalise(null);
    eq("the input overlay starts at its own size", a.widgets.input.opts, { scale: 1, opacity: 0.85, layout: "wasd", mouse: true, stats: true });
    const scaleOf = v => H.set(a, "input", { opts: { scale: v } }).widgets.input.opts.scale;
    eq("a scale in range is kept (to 2 places)", scaleOf(1.234), 1.23);
    eq("too small clamps", scaleOf(0.1), 0.5);
    eq("too big clamps", scaleOf(9), 2);
    eq("garbage on disk gives the default",
       [H.normalise({ widgets: { input: { opts: { scale: "huge" } } } }).widgets.input.opts.scale,
        H.normalise({ widgets: { input: { opts: { scale: -1 } } } }).widgets.input.opts.scale], [1, 1]);
    eq("a widget with no size has no scale", "scale" in a.widgets.stats.opts, false);
    const opOf = v => H.set(a, "input", { opts: { opacity: v } }).widgets.input.opts.opacity;
    eq("transparency in range is kept", opOf(0.4), 0.4);
    eq("float steps don't drift (0.85 - 0.1)", opOf(0.85 - 0.1), 0.75);
    eq("transparency clamps both ways", [opOf(0), opOf(3)], [0.1, 1]);
    eq("garbage transparency gives the default", opOf("clear"), 0.85);
    eq("changing one option keeps the other",
       H.set(H.set(a, "input", { opts: { scale: 1.5 } }), "input", { opts: { opacity: 0.5 } }).widgets.input.opts,
       { scale: 1.5, opacity: 0.5, layout: "wasd", mouse: true, stats: true });
}

// ── clampCentre ──────────────────────────────────────────────────────────────
{
    eq("inside stays", H.clampCentre(0.5, 0.5, 100, 100, 1000, 1000), { cx: 0.5, cy: 0.5 });
    eq("off the left edge is pulled in by half its width", H.clampCentre(0, 0.5, 100, 100, 1000, 1000), { cx: 0.05, cy: 0.5 });
    eq("off the bottom-right is pulled in", H.clampCentre(1, 1, 200, 100, 1000, 1000), { cx: 0.9, cy: 0.95 });
    eq("bigger than the screen centres", H.clampCentre(0.1, 0.1, 2000, 100, 1000, 1000), { cx: 0.5, cy: 0.1 });
    eq("no screen yet centres", H.clampCentre(0.3, 0.3, 10, 10, 0, 0), { cx: 0.5, cy: 0.5 });
}

// ── what is drawn / clickable over a game ──────────────────────────────────
{
    const e = (o) => Object.assign({ pinned: false, clickthrough: true }, o);
    check("unpinned isn't drawn", !H.visible(e({})));
    check("pinned is", H.visible(e({ pinned: true })));
    check("click-through is not interactive", !H.interactive(e({ pinned: true })));
    check("a pinned, clickable one is", H.interactive(e({ pinned: true, clickthrough: false })));
    check("an unpinned one never is", !H.interactive(e({ clickthrough: false })));
}
{
    let l = H.normalise(null);
    check("nothing pinned", !H.anyPinned(l));
    l = H.set(l, "stats", { pinned: true });
    check("a pinned one counts", H.anyPinned(l));
}
// ── where it shows: over games, or always (on the home monitor) ──────────────
{
    const n = H.normalise(null);
    eq("over games by default", n.widgets.stats.where, "games");
    eq("no home by default", n.home, "");
    eq("a bad where falls back", H.normalise({ widgets: { stats: { where: "moon" } } }).widgets.stats.where, "games");
    eq("always is kept", H.normalise({ widgets: { stats: { where: "always" } } }).widgets.stats.where, "always");
    eq("a monitor name is kept", H.normalise({ home: "DP-2" }).home, "DP-2");
    eq("a home that isn't a monitor name is dropped", [H.normalise({ home: "a b" }).home, H.normalise({ home: 3 }).home,
       H.normalise({ home: "x".repeat(65) }).home], ["", "", ""]);
    const g = { pinned: true, clickthrough: true, where: "games" };
    const a = { pinned: true, clickthrough: false, where: "always" };
    check("games: drawn over a game", H.visible(g, { game: true, home: false }));
    check("games: not on the desktop", !H.visible(g, { game: false, home: true }));
    check("always: on its home, game or not", H.visible(a, { game: false, home: true }) && H.visible(a, { game: true, home: true }));
    check("always: not on another monitor", !H.visible(a, { game: true, home: false }));
    check("unpinned: never", !H.visible({ pinned: false, where: "always" }, { game: true, home: true }));
    check("always and clickable takes the mouse on its home", H.interactive(a, { home: true }));
    check("…and nowhere else", !H.interactive(a, { home: false, game: true }));
    let l = H.set(H.normalise(null), "input", { pinned: true, where: "always" });
    check("anyPinned with a context", H.anyPinned(l, { home: true }) && !H.anyPinned(l, { game: true }));
    eq("set keeps the home", H.set(H.setHome(l, "DP-2"), "stats", { pinned: true }).home, "DP-2");
    check("setHome ignores garbage", H.setHome(l, "") === l && H.setHome(l, "a b") === l);
    eq("home: the saved one while connected", H.homeScreen("DP-2", ["DP-1", "DP-2"], "DP-1"), "DP-2");
    eq("home: the focused one when it's gone", H.homeScreen("DP-2", ["eDP-1"], "eDP-1"), "eDP-1");
    eq("home: the focused one when none was saved", H.homeScreen("", ["DP-1"], "DP-1"), "DP-1");
}
// ── snapPlace (dragging on the real screen) ─────────────────────────────────
{
    const sp = (cx, cy) => H.snapPlace(cx, cy, 200, 100, 1920, 1080, 24);
    eq("near the centre snaps to it, on both axes", sp(0.5 + 8 / 1920, 0.5 - 5 / 1080), { cx: 0.5, cy: 0.5, guides: { x: "centre", y: "centre" } });
    eq("an edge near the left margin lands on it", sp((24 + 100 + 9) / 1920, 0.3).cx, (24 + 100) / 1920);
    eq("…and says so", sp((24 + 100 + 9) / 1920, 0.3).guides, { x: "start", y: "" });
    eq("the bottom margin", sp(0.3, (1080 - 24 - 50 - 4) / 1080).guides.y, "end");
    eq("away from everything, it stays", sp(0.3, 0.3), { cx: 0.3, cy: 0.3, guides: { x: "", y: "" } });
    eq("still kept on screen", sp(0, 1).cx, 100 / 1920);
    eq("garbage centres", sp("x", null).guides, { x: "", y: "" });
}
eq("every anchor is a fraction pair", Object.values(H.ANCHORS).every(a => a.length === 2 && a.every(v => v >= 0 && v <= 1)), true);
eq("nine anchors", Object.keys(H.ANCHORS).length, 9);

// ── mangohud.js ─────────────────────────────────────────────────────────────
{
    const conf = "# my hud\nfps\nfps_limit=60\nposition=top-left\n";
    eq("read", M.readLimit(conf), 60);
    eq("read the first of a list", M.readLimit("fps_limit=144,60"), 144);
    eq("a commented one is not active", M.readLimit("#fps_limit=60\n"), null);
    eq("no line", M.readLimit("fps\n"), null);
    eq("empty text", M.readLimit(""), null);
    eq("set rewrites in place", M.setLimit(conf, 90), "# my hud\nfps\nfps_limit=90\nposition=top-left\n");
    eq("set appends when absent", M.setLimit("fps\n", 60), "fps\nfps_limit=60\n");
    eq("set on empty text", M.setLimit("", 60), "fps_limit=60\n");
    eq("set leaves a commented one alone", M.setLimit("#fps_limit=30\n", 60), "#fps_limit=30\nfps_limit=60\n");
    eq("zero is a limit (no limit)", M.setLimit("fps_limit=60", 0), "fps_limit=0");
    eq("a trailing comment on the old line goes with it", M.setLimit("fps_limit=60 # cap\n", 75), "fps_limit=75\n");
    eq("an invalid number changes nothing", M.setLimit(conf, "abc"), conf);
    eq("negative changes nothing", M.setLimit(conf, "-5"), conf);
    eq("over the cap changes nothing", M.setLimit(conf, "5000"), conf);
    eq("a float isn't accepted", M.parseLimit("59.9"), null);
    eq("whitespace is trimmed", M.parseLimit(" 120 "), 120);
    eq("a line that merely contains the word isn't matched", M.readLimit("my_fps_limit=5"), null);
}

// ── perfVerdict: the Performance card's sentence ────────────────────────────
const idle = { cpu: 0.1, gpu: 0.05, ram: 0.4, cpuTemp: 50, gpuTemp: 45, swap: 0 };
eq("verdict: fine", H.perfVerdict(idle).key, "ok");
eq("verdict: fine is level 0", H.perfVerdict(idle).level, 0);
eq("verdict: hot cpu beats everything", H.perfVerdict({ ...idle, cpuTemp: 91, ram: 0.95 }).key, "hot");
eq("verdict: hot gpu", H.perfVerdict({ ...idle, gpuTemp: 88 }).key, "hot");
eq("verdict: full memory is level 2", H.perfVerdict({ ...idle, ram: 0.93 }).level, 2);
eq("verdict: warm", H.perfVerdict({ ...idle, cpuTemp: 82 }).key, "warm");
eq("verdict: busy cpu", H.perfVerdict({ ...idle, cpu: 0.9 }).key, "cpu");
eq("verdict: busy gpu", H.perfVerdict({ ...idle, gpu: 0.95 }).key, "gpu");
eq("verdict: memory filling", H.perfVerdict({ ...idle, ram: 0.85 }).key, "ram");
eq("verdict: no sensors is not hot", H.perfVerdict({ ...idle, cpuTemp: -1, gpuTemp: -1 }).key, "ok");
eq("verdict: missing temps tolerated", H.perfVerdict({ cpu: 0.1, gpu: 0, ram: 0.2 }).key, "ok");

// ── The input overlay's options ──────────────────────────────────────────────
eq("input layouts match the key tables", H.INPUT_LAYOUTS, IK.LAYOUT_IDS);
const inp = L => H.normalise({ widgets: { input: { opts: L } } }).widgets.input.opts;
eq("defaults: wasd, mouse and rates on", [inp({}).layout, inp({}).mouse, inp({}).stats], ["wasd", true, true]);
eq("a known layout is kept", inp({ layout: "full" }).layout, "full");
eq("an unknown layout falls back", inp({ layout: "dvorak-ish" }).layout, "wasd");
eq("mouse off, stats off", [inp({ mouse: false }).mouse, inp({ stats: false }).stats], [false, false]);
eq("anything else than false stays on", [inp({ mouse: "no" }).mouse, inp({ stats: 0 }).stats], [true, true]);
eq("a set() goes through the same gate", H.set(H.normalise({}), "input", { opts: { layout: "tkl", mouse: false } }).widgets.input.opts.layout, "tkl");
eq("other widgets have no layout", H.normalise({}).widgets.stats.opts.layout, undefined);

if (fail) {
    console.log(`FAIL  ${fail} failed, ${pass} passed`);
    console.log(failures.join("\n"));
    process.exit(1);
}
console.log(`ok  ${pass} checks`);
