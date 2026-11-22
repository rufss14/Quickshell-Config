// ── test-streammode.js ────────────────────────────────────────────────────────
// Tests for services/streammode.js: the Lua stream mode sends to Hyprland and how it
// reads the answer.
//
//     bun scripts/test-streammode.js
//
// Pure functions, touches nothing. The Lua is only checked as text here: whether
// `set_enabled` works on a live compositor is something only a running Hyprland answers.
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "streammode.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { lua, failed, status, capturers, mask } = new Function(src + "\nreturn { lua, failed, status, capturers, mask };")();

let bad = 0;
function eq(name, got, want) {
    if (got === want) return;
    bad++;
    console.log(`FAIL ${name}\n  got  ${JSON.stringify(got)}\n  want ${JSON.stringify(want)}`);
}

// ── lua(): on/off, and only literals ──────────────────────────────────────────
eq("on sets true", /set_enabled\(true\)/.test(lua(true)), true);
eq("off sets false", /set_enabled\(false\)/.test(lua(false)), true);
// Anything that is not exactly `true` is OFF — a truthy string must not turn hiding on,
// and nothing passed in may reach the Lua text.
for (const v of [undefined, null, 0, 1, "true", "x'); os.execute('x", {}]) {
    eq("non-boolean is off: " + JSON.stringify(v), /set_enabled\(false\)/.test(lua(v)), true);
    eq("no leak: " + JSON.stringify(v), lua(v).includes("os.execute"), false);
}
// Never defines a rule or a bind at runtime (the crash class).
eq("no runtime definition", /hl\.(layer_rule|window_rule|bind)/.test(lua(true)), false);
// Missing block is an error the shell can read, not a silent no-op.
eq("errors when the table is missing", /error\("qs_stream missing"\)/.test(lua(true)), true);

// ── failed() ──────────────────────────────────────────────────────────────────
eq("exit 0 and ok", failed(0, "ok"), false);
eq("non-zero exit", failed(1, ""), true);
eq("lua error text", failed(0, "[string]:1: qs_stream missing\nerror"), true);
eq("syntax error text", failed(0, "')' expected near 'x'"), true);
eq("undefined output", failed(0, undefined), false);

// ── status() ──────────────────────────────────────────────────────────────────
eq("off", status(false, "ok"), "Off");
eq("off, rules missing", status(false, "missing"), "Off");
eq("on, unknown", status(true, "unknown"), "On");
eq("on, ok", status(true, "ok"), "On · hidden from capture");
eq("on, missing", status(true, "missing"), "On · capture hiding not installed");
eq("paused", status(false, "ok", true), "Paused · visible to viewers");
eq("paused wins over missing rules", status(false, "missing", true), "Paused · visible to viewers");
eq("not paused", status(true, "ok", false), "On · hidden from capture");

// ── capturers(): which nodes are capturing the SCREEN ─────────────────────────
// Shapes taken from a real pw-dump while Discord shared the screen (2026-11-14).
const portal = { id: 134, p: { "media.class": "Video/Source", "node.name": "xdg-desktop-portal-hyprland", "media.name": "xdph-streaming-683329" } };
const discord = { id: 145, p: { "media.class": "Stream/Input/Video", "media.role": "Screen", "node.name": "Discord", "node.target": 134 } };
const cam = { id: 150, p: { "media.class": "Stream/Input/Video", "media.role": "Camera", "node.name": "Firefox" } };
const v4l = { id: 90, p: { "media.class": "Video/Source", "node.name": "v4l2_input.pci-0000" } };
const mic = { id: 60, p: { "media.class": "Stream/Input/Audio", "media.role": "Screen", "node.name": "Discord" } };
const same = (name, got, want) => eq(name, JSON.stringify(got), JSON.stringify(want));
same("nothing", capturers([]), []);
same("portal source alone is not a capture", capturers([portal]), []);
same("discord share found", capturers([portal, discord]), [1]);
same("webcam is not a screen", capturers([v4l, cam]), []);
same("webcam beside a share", capturers([portal, cam, discord]), [2]);
same("audio stream with role Screen is not video", capturers([mic]), []);
// Found by role alone (no portal node seen yet) and by target alone (no role set).
same("role alone", capturers([discord]), [0]);
same("target alone", capturers([portal, { id: 151, p: { "media.class": "Stream/Input/Video", "node.name": "obs", "node.target": "134" } }]), [1]);
same("camera role beats a portal target", capturers([portal, { id: 152, p: { "media.class": "Stream/Input/Video", "media.role": "Camera", "node.target": 134 } }]), []);
// One entry per app: Discord can hold two video streams.
same("one per app", capturers([portal, discord, { id: 146, p: { ...discord.p } }]), [1]);
same("two apps", capturers([portal, discord, { id: 160, p: { "media.class": "Stream/Input/Video", "media.role": "Screen", "node.name": "obs" } }]), [1, 2]);
same("other portal name", capturers([{ id: 7, p: { "media.class": "Video/Source", "node.name": "xdg-desktop-portal-gnome" } },
    { id: 8, p: { "media.class": "Stream/Input/Video", "node.name": "app", "node.target": 7 } }]), [1]);
same("a node with no properties at all", capturers([{ id: 1, p: {} }]), []);

// ── mask() ────────────────────────────────────────────────────────────────────
eq("off passes text through", mask("hunter2", false, "Hidden"), "hunter2");
eq("anything but true is off", mask("hunter2", "true", "Hidden"), "hunter2");
eq("on says the word", mask("hunter2", true, "Hidden"), "Hidden");
eq("on uses the translated word", mask("hunter2", true, "Oculto"), "Oculto");
eq("no word given falls back", mask("hunter2", true), "Hidden");
eq("on hides without the text", mask("hunter2", true, "Hidden").includes("hunter"), false);
// The length is a leak too: a short and a long secret look the same.
eq("fixed length", mask("a", true, "Hidden"), mask("a very long street name, 12345", true, "Hidden"));
eq("empty stays empty (on)", mask("", true, "Hidden"), "");
eq("null stays empty", mask(null, true, "Hidden"), "");
eq("undefined stays empty", mask(undefined, false), "");
eq("numbers are text", mask(42, false), "42");

console.log(bad === 0 ? "streammode: all passed" : `streammode: ${bad} FAILED`);
process.exit(bad === 0 ? 0 : 1);
