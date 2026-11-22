// ── test-tablet.js ────────────────────────────────────────────────────────────
// Tests for services/tablet.js: the saved document, the area maths, the Lua handed to
// `hyprctl eval`, and the express-key bindings.
//
//     bun scripts/test-tablet.js      (or: node scripts/test-tablet.js)
//
// Safe to run: pure functions, no I/O, nothing near a compositor. The .js is loaded by
// stripping its `.pragma library` line, so the tests run against the real file.
//
// The part worth the most care is the trust boundary: a profile comes from a
// user-editable JSON file and ends up as Lua executed inside Hyprland, and a binding
// ends up as an argv.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "tablet.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const T = new Function(src + `
return { hyprName, parseProbe, padKeyCodes, fullArea, clampArea, areaIsFull, areaRatio,
         fitRatio, resizeKeeping, targetSize, cleanOutput, defaultProfile, normaliseProfile, lua, chordArgv,
         normaliseBinding, emptyState, normalise, deviceState, activeProfile, setProfile, selectProfile,
         cycleProfile, addProfile, renameProfile, removeProfile, setKey };`)();

let pass = 0, fail = 0;
function check(label, ok, detail) {
    if (ok) pass++;
    else { fail++; console.log("FAIL  " + label + (detail !== undefined ? "  " + JSON.stringify(detail) : "")); }
}
const eq = (label, got, want) => check(label, JSON.stringify(got) === JSON.stringify(want), { got, want });
const has = (s, needle) => s.includes(needle);

const DEV = { widthMm: 152, heightMm: 95 };
const NAME = "wacom-intuos-s-pen";

// ── names and the device list ───────────────────────────────────────────────
eq("hyprland name", T.hyprName("Wacom Intuos S Pen"), "wacom-intuos-s-pen");
eq("hyprland name, no input", T.hyprName(undefined), "");

const probe = {
    udev: true,
    tablets: [{ name: "Wacom Intuos S Pen", hypr: "wacom-intuos-s-pen", model: "Intuos S", pen: "/dev/input/event25",
                pad: "/dev/input/event26", widthMm: 152, heightMm: 95, keys: 4, access: false }]
};
const pr = T.parseProbe(JSON.stringify(probe));
check("probe ok", pr.ok && pr.tablets.length === 1, pr);
eq("probe fields", [pr.tablets[0].hypr, pr.tablets[0].widthMm, pr.tablets[0].keys, pr.tablets[0].access], ["wacom-intuos-s-pen", 152, 4, false]);
eq("probe: no udevadm is reported", T.parseProbe({ udev: false, tablets: [] }).reason, "udevadm");
eq("probe: node outside /dev/input is dropped", T.parseProbe({ tablets: [{ ...probe.tablets[0], pen: "/etc/passwd" }] }).tablets, []);
eq("probe: node with a suffix is dropped", T.parseProbe({ tablets: [{ ...probe.tablets[0], pen: "/dev/input/event25/../../x" }] }).tablets, []);
eq("probe: zero size is dropped", T.parseProbe({ tablets: [{ ...probe.tablets[0], widthMm: 0 }] }).tablets, []);
eq("probe: a bad pad node is only dropped", T.parseProbe({ tablets: [{ ...probe.tablets[0], pad: "x" }] }).tablets[0].pad, "");
eq("probe: name falls back to the Hyprland spelling", T.parseProbe({ tablets: [{ ...probe.tablets[0], hypr: "" }] }).tablets[0].hypr, "wacom-intuos-s-pen");
eq("probe: garbage", T.parseProbe("{").ok, false);
eq("probe: keys are capped", T.parseProbe({ tablets: [{ ...probe.tablets[0], keys: 999 }] }).tablets[0].keys, 16);

// ── pad keys from the capabilities bitmap ───────────────────────────────────
eq("Intuos S pad: four keys, BTN_STYLUS is not one", T.padKeyCodes("800 f 0 0 0 0"), [256, 257, 258, 259]);
eq("eight keys", T.padKeyCodes("800 ff 0 0 0 0").length, 8);
eq("a pen has none", T.padKeyCodes("1e01 0 0 0 0 0"), []);
eq("BTN_A is a key", T.padKeyCodes("0 1000000000000 0 0 0 0"), [0x130]);
eq("empty", T.padKeyCodes(""), []);
eq("garbage", T.padKeyCodes("zz qq"), []);
eq("short bitmap", T.padKeyCodes("f"), []);

// ── area ────────────────────────────────────────────────────────────────────
eq("full area", T.fullArea(DEV), { x: 0, y: 0, w: 152, h: 95 });
eq("area is pulled inside", T.clampArea({ x: 200, y: -4, w: 80, h: 40 }, DEV), { x: 72, y: 0, w: 80, h: 40 });
eq("area is no bigger than the tablet", T.clampArea({ x: 0, y: 0, w: 999, h: 999 }, DEV), { x: 0, y: 0, w: 152, h: 95 });
eq("area has a floor", T.clampArea({ x: 0, y: 0, w: 0, h: 1 }, DEV), { x: 0, y: 0, w: 5, h: 5 });
eq("area from nothing is the whole tablet", T.clampArea(undefined, DEV), { x: 0, y: 0, w: 152, h: 95 });
eq("area from NaN is the whole tablet", T.clampArea({ x: "a", y: NaN, w: "b", h: null }, DEV), { x: 0, y: 0, w: 152, h: 95 });
check("full is full", T.areaIsFull(T.fullArea(DEV), DEV));
check("a corner is not full", !T.areaIsFull({ x: 0, y: 0, w: 100, h: 60 }, DEV));
check("half a millimetre short is still full", T.areaIsFull({ x: 0.3, y: 0.2, w: 151.6, h: 94.7 }, DEV));
eq("16:9 screen", T.areaRatio(1920, 1080, 0), 1920 / 1080);
eq("a quarter turn swaps the axes", T.areaRatio(1920, 1080, 90), 1080 / 1920);
eq("a half turn does not", T.areaRatio(1920, 1080, 180), 1920 / 1080);
eq("no screen, no ratio", T.areaRatio(0, 1080, 0), 0);
const wide = T.fitRatio(T.fullArea(DEV), DEV, 16 / 9);
check("16:9 fills the width", wide.w === 152 && Math.abs(wide.h - 152 * 9 / 16) < 0.06, wide);
check("16:9 is centred", Math.abs(wide.y - (95 - wide.h) / 2) < 0.06, wide);
const tall = T.fitRatio(T.fullArea(DEV), DEV, 9 / 16);
check("9:16 fills the height", tall.h === 95 && Math.abs(tall.w - 95 * 9 / 16) < 0.06, tall);
check("the fit stays inside", tall.x >= 0 && tall.x + tall.w <= 152.05, tall);
eq("no ratio keeps the area", T.fitRatio({ x: 1, y: 2, w: 30, h: 40 }, DEV, 0), { x: 1, y: 2, w: 30, h: 40 });
const rs = T.resizeKeeping({ x: 10, y: 10, w: 80, h: 45 }, DEV, 40, 16 / 9);
check("resize keeps the shape", Math.abs(rs.w / rs.h - 16 / 9) < 0.05, rs);
check("resize cannot pass the tablet's height", T.resizeKeeping({ x: 0, y: 0, w: 30, h: 30 }, DEV, 400, 1).h <= 95);
eq("resize without a ratio changes the width only", T.resizeKeeping({ x: 0, y: 0, w: 30, h: 20 }, DEV, 50, 0), { x: 0, y: 0, w: 50, h: 20 });

const SCREENS = [{ name: "DP-2", x: 0, y: 0, width: 1920, height: 1080 }, { name: "HDMI-A-1", x: 1920, y: 0, width: 1280, height: 1024 }];
eq("one output", T.targetSize(SCREENS, "DP-2"), { w: 1920, h: 1080 });
eq("every output is the box around them", T.targetSize(SCREENS, ""), { w: 3200, h: 1080 });
eq("an output that is not there", T.targetSize(SCREENS, "eDP-1"), { w: 0, h: 0 });
eq("no outputs", T.targetSize([], ""), { w: 0, h: 0 });
eq("not a list", T.targetSize(null, ""), { w: 0, h: 0 });
eq("a screen with no size is ignored", T.targetSize([{ name: "a", width: 0, height: 5 }, SCREENS[0]], ""), { w: 1920, h: 1080 });
eq("a screen below another", T.targetSize([SCREENS[0], { name: "b", x: 0, y: 1080, width: 1920, height: 1080 }], ""), { w: 1920, h: 2160 });

// ── profiles ────────────────────────────────────────────────────────────────
const dp = T.defaultProfile(DEV);
eq("default profile", dp, { name: "Default", output: "", area: { x: 0, y: 0, w: 152, h: 95 }, lockRatio: true, rotation: 0, relative: false, pressure: { min: 0, max: 1 } });
eq("garbage becomes the default shape", T.normaliseProfile("x", DEV).area, { x: 0, y: 0, w: 152, h: 95 });
eq("an odd rotation is none", T.normaliseProfile({ rotation: 45 }, DEV).rotation, 0);
eq("a string rotation is none", T.normaliseProfile({ rotation: "90" }, DEV).rotation, 0);
eq("a quarter turn stays", T.normaliseProfile({ rotation: 270 }, DEV).rotation, 270);
eq("relative only for true", [T.normaliseProfile({ relative: "yes" }, DEV).relative, T.normaliseProfile({ relative: true }, DEV).relative], [false, true]);
eq("ratio lock is on unless it is false", [T.normaliseProfile({}, DEV).lockRatio, T.normaliseProfile({ lockRatio: false }, DEV).lockRatio], [true, false]);
eq("pressure keeps a span", T.normaliseProfile({ pressure: { min: 0.9, max: 0.9 } }, DEV).pressure, { min: 0.9, max: 0.95 });
eq("pressure clamps", T.normaliseProfile({ pressure: { min: -3, max: 7 } }, DEV).pressure, { min: 0, max: 1 });
eq("pressure from nothing is the stock range", T.normaliseProfile({}, DEV).pressure, { min: 0, max: 1 });
eq("a name is trimmed and capped", T.normaliseProfile({ name: "  " + "x".repeat(60) }, DEV).name.length, 24);
eq("an empty name falls back", T.normaliseProfile({ name: "   " }, DEV).name, "Profile");
eq("control characters leave a name", T.normaliseProfile({ name: "a\nb" }, DEV).name, "a b");

// ── the output name ─────────────────────────────────────────────────────────
for (const ok of ["DP-2", "HDMI-A-1", "eDP-1", "desc:Dell U2720Q"]) eq("output " + ok, T.cleanOutput(ok), ok);
for (const bad of ['DP-2"', "DP-2\n", "a\\b", "", "-x", 'x"}) os.execute("id") --', 5, null, "x".repeat(65)])
    eq("output refused: " + JSON.stringify(bad), T.cleanOutput(bad), "");

// ── the Lua ─────────────────────────────────────────────────────────────────
const stock = T.lua(dp, DEV);
check("opens one hl.config", stock.startsWith("hl.config({ input = { tablet = { "), stock);
check("closes it", stock.endsWith("} } })"), stock);
check("the whole tablet is sent as unset", has(stock, "active_area_size = { 0, 0 }"), stock);
check("the stock pressure is sent as unset", has(stock, "pressure_range_min = -1, pressure_range_max = -1"), stock);
check("whole desktop is an empty output", has(stock, 'output = "", '), stock);
check("absolute by default", has(stock, "relative_input = false"), stock);
check("no turn is transform 0", has(stock, "transform = 0"), stock);
const mine = T.lua({ ...dp, output: "DP-2", area: { x: 10.3, y: 5, w: 80, h: 45 }, rotation: 90, relative: true, pressure: { min: 0.1, max: 0.8 } }, DEV);
check("output", has(mine, 'output = "DP-2"'), mine);
check("area position", has(mine, "active_area_position = { 10.3, 5 }"), mine);
eq("an area is kept to a tenth of a millimetre", T.clampArea({ x: 10.26, y: 5.04, w: 80, h: 45 }, DEV).x, 10.3);
check("area size", has(mine, "active_area_size = { 80, 45 }"), mine);
check("a quarter turn is transform 1", has(mine, "transform = 1"), mine);
check("relative", has(mine, "relative_input = true"), mine);
check("pressure range", has(mine, "pressure_range_min = 0.1, pressure_range_max = 0.8"), mine);
check("a half turn is 2, three quarters 3", has(T.lua({ ...dp, rotation: 180 }, DEV), "transform = 2") && has(T.lua({ ...dp, rotation: 270 }, DEV), "transform = 3"));
check("only a custom min is enough to send pressure", has(T.lua({ ...dp, pressure: { min: 0.2, max: 1 } }, DEV), "pressure_range_min = 0.2, pressure_range_max = 1"));

// the trust boundary: nothing but numbers and a vetted name reaches the string
const evil = T.lua({
    name: 'x"}) os.execute("id") --', output: 'DP-2"}) os.execute("id") --',
    area: { x: '1}) os.execute("id") --', y: NaN, w: Infinity, h: "9; os.exit()" },
    rotation: '90"}) x', relative: '"}) os.execute("id") --', pressure: { min: "}) x", max: { toString() { return "}) y"; } } }
}, DEV);
check("injection: no call survives", !/os\.|execute|exit/.test(evil), evil);
check("injection: still one hl.config", (evil.match(/hl\.config/g) || []).length === 1, evil);
check("injection: quotes are the two output ones only", (evil.match(/"/g) || []).length === 2, evil);
check("injection: braces balance", (evil.match(/\{/g) || []).length === (evil.match(/\}/g) || []).length, evil);
check("injection: vectors are two numbers", /active_area_position = \{ -?[0-9.]+, -?[0-9.]+ \}/.test(evil) && /active_area_size = \{ -?[0-9.]+, -?[0-9.]+ \}/.test(evil), evil);

// ── express keys ────────────────────────────────────────────────────────────
eq("chord", T.chordArgv("ctrl+z"), ["wtype", "-M", "ctrl", "-k", "z", "-m", "ctrl"]);
eq("chord with two modifiers releases in reverse", T.chordArgv("ctrl+shift+Z"), ["wtype", "-M", "ctrl", "-M", "shift", "-k", "Z", "-m", "shift", "-m", "ctrl"]);
eq("a bare key", T.chordArgv("F5"), ["wtype", "-k", "F5"]);
eq("super is logo", T.chordArgv("super+Return"), ["wtype", "-M", "logo", "-k", "Return", "-m", "logo"]);
eq("modifier names are case blind", T.chordArgv("CTRL+z")[2], "ctrl");
eq("a repeated modifier counts once", T.chordArgv("ctrl+ctrl+z"), ["wtype", "-M", "ctrl", "-k", "z", "-m", "ctrl"]);
for (const bad of ["", "ctrl+", "+z", "ctrl+z; rm -rf ~", "ctrl+$(id)", "hyper+z", "ctrl+a+b", "a b", "ctrl+shift+alt+super+x+y", null, undefined])
    eq("chord refused: " + JSON.stringify(bad), T.chordArgv(bad), null);
eq("binding: none", T.normaliseBinding(undefined), { kind: "none", value: "" });
eq("binding: unknown kind", T.normaliseBinding({ kind: "exec", value: "id" }), { kind: "none", value: "" });
eq("binding: a chord", T.normaliseBinding({ kind: "chord", value: "ctrl+z" }), { kind: "chord", value: "ctrl+z" });
eq("binding: a bad chord is none", T.normaliseBinding({ kind: "chord", value: "ctrl+z; id" }), { kind: "none", value: "" });
eq("binding: an empty command is none", T.normaliseBinding({ kind: "command", value: "  " }), { kind: "none", value: "" });
eq("binding: a command", T.normaliseBinding({ kind: "command", value: "notify-send hi" }), { kind: "command", value: "notify-send hi" });
eq("binding: profile next", T.normaliseBinding({ kind: "profile", value: "next" }), { kind: "profile", value: "next" });
eq("binding: profile by name", T.normaliseBinding({ kind: "profile", value: "Drawing" }), { kind: "profile", value: "Drawing" });
eq("binding: profile with nothing", T.normaliseBinding({ kind: "profile", value: "" }), { kind: "none", value: "" });
eq("binding: a long value is cut", T.normaliseBinding({ kind: "command", value: "x".repeat(500) }).value.length, 200);
eq("binding: none drops its value", T.normaliseBinding({ kind: "none", value: "ctrl+z" }), { kind: "none", value: "" });

// ── the saved document ──────────────────────────────────────────────────────
const s0 = T.emptyState();
eq("a new tablet has one profile, active", [T.deviceState(s0, NAME, DEV).profiles.length, T.deviceState(s0, NAME, DEV).active], [1, "Default"]);
eq("sixteen key slots, all none", [T.deviceState(s0, NAME, DEV).keys.length, T.deviceState(s0, NAME, DEV).keys.every(k => k.kind === "none")], [16, true]);
eq("garbage document", T.normalise("x"), s0);
eq("document without devices", T.normalise({ devices: [] }), s0);
eq("a device that is not an object is dropped", Object.keys(T.normalise({ devices: { a: 5, b: {} } }).devices), ["b"]);
eq("devices are capped", Object.keys(T.normalise({ devices: Object.fromEntries(Array.from({ length: 40 }, (_, i) => ["d" + i, {}])) }).devices).length, 16);

const s1 = T.setProfile(s0, NAME, DEV, { output: "DP-2", rotation: 90, area: { x: 5, y: 5, w: 60, h: 30 } });
eq("set merges into the active profile", [T.activeProfile(s1, NAME, DEV).output, T.activeProfile(s1, NAME, DEV).rotation, T.activeProfile(s1, NAME, DEV).area.w], ["DP-2", 90, 60]);
eq("set does not touch the input", s0, T.emptyState());
eq("set cannot rename", T.activeProfile(T.setProfile(s0, NAME, DEV, { name: "Hacked" }), NAME, DEV).name, "Default");
eq("set cleans what it was given", T.activeProfile(T.setProfile(s0, NAME, DEV, { rotation: 7, output: '"' }), NAME, DEV).rotation, 0);

const s2 = T.addProfile(s1, NAME, DEV, "Drawing", true);
eq("a fresh profile is active and plain", [T.activeProfile(s2, NAME, DEV).name, T.activeProfile(s2, NAME, DEV).output], ["Drawing", ""]);
eq("the first one is kept", T.deviceState(s2, NAME, DEV).profiles[0].output, "DP-2");
const s3 = T.addProfile(s2, NAME, DEV, undefined, false);
eq("a copy carries the settings and says so", [T.activeProfile(s3, NAME, DEV).name, T.activeProfile(s3, NAME, DEV).output], ["Drawing copy", ""]);
const s3b = T.addProfile(s3, NAME, DEV, "Drawing", true);
eq("a taken name gets a number", T.activeProfile(s3b, NAME, DEV).name, "Drawing 2");
let many = s0;
for (let i = 0; i < 20; i++) many = T.addProfile(many, NAME, DEV, "P", true);
eq("profiles are capped", T.deviceState(many, NAME, DEV).profiles.length, 12);

eq("select", T.deviceState(T.selectProfile(s2, NAME, DEV, "Default"), NAME, DEV).active, "Default");
eq("select an unknown name is a no-op", T.selectProfile(s2, NAME, DEV, "Nope"), s2);
eq("cycle next wraps", T.deviceState(T.cycleProfile(T.selectProfile(s3, NAME, DEV, "Drawing copy"), NAME, DEV, "next"), NAME, DEV).active, "Default");
eq("cycle prev wraps", T.deviceState(T.cycleProfile(T.selectProfile(s3, NAME, DEV, "Default"), NAME, DEV, "prev"), NAME, DEV).active, "Drawing copy");
eq("cycle with one profile stays", T.deviceState(T.cycleProfile(s0, NAME, DEV, "next"), NAME, DEV).active, "Default");

const s4 = T.renameProfile(s2, NAME, DEV, "Drawing", "Art");
eq("rename follows the active one", [T.deviceState(s4, NAME, DEV).active, T.deviceState(s4, NAME, DEV).profiles.map(p => p.name)], ["Art", ["Default", "Art"]]);
eq("rename to a taken name is numbered", T.deviceState(T.renameProfile(s2, NAME, DEV, "Drawing", "Default"), NAME, DEV).profiles[1].name, "Default 2");
eq("rename to itself is kept", T.deviceState(T.renameProfile(s2, NAME, DEV, "Drawing", "Drawing"), NAME, DEV).profiles[1].name, "Drawing");

eq("remove the active one moves on", T.deviceState(T.removeProfile(s2, NAME, DEV, "Drawing"), NAME, DEV).active, "Default");
eq("the last profile stays", T.removeProfile(s0, NAME, DEV, "Default"), s0);
eq("remove an unknown name is a no-op", T.removeProfile(s2, NAME, DEV, "Nope"), s2);

const s5 = T.setKey(s0, NAME, DEV, 1, { kind: "chord", value: "ctrl+z" });
eq("a key is set", T.deviceState(s5, NAME, DEV).keys[1], { kind: "chord", value: "ctrl+z" });
eq("the others are not", T.deviceState(s5, NAME, DEV).keys[0].kind, "none");
eq("a bad key index is a no-op", [T.setKey(s0, NAME, DEV, 99, { kind: "chord", value: "a" }) === s0, T.setKey(s0, NAME, DEV, -1, {}) === s0], [true, true]);
eq("a bad binding is stored as none", T.deviceState(T.setKey(s0, NAME, DEV, 0, { kind: "chord", value: "a;b" }), NAME, DEV).keys[0].kind, "none");

// a document written for a bigger tablet, read for a smaller one
const big = { devices: { [NAME]: { active: "Default", profiles: [{ name: "Default", area: { x: 100, y: 100, w: 300, h: 200 } }] } } };
eq("an area from another size is pulled in", T.activeProfile(T.normalise(big), NAME, DEV).area, { x: 0, y: 0, w: 152, h: 95 });
eq("an active name that is gone falls to the first", T.deviceState({ devices: { [NAME]: { active: "Gone", profiles: [{ name: "A" }, { name: "B" }] } } }, NAME, DEV).active, "A");
eq("two profiles of one name are numbered", T.deviceState({ devices: { [NAME]: { profiles: [{ name: "A" }, { name: "A" }] } } }, NAME, DEV).profiles.map(p => p.name), ["A", "A 2"]);

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
