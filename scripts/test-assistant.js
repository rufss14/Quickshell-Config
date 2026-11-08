// ── test-assistant.js ─────────────────────────────────────────────────────────
// Regression tests for services/assistant.js, the overview AI page's action parser.
//
//     bun scripts/test-assistant.js          (or: node scripts/test-assistant.js)
//
// Safe to run: pure functions, touches nothing.
//
// A model's reply is somebody else's output that ends up changing the shell, so the half of
// this that matters is the half that REFUSES: unknown keys, out-of-range values, colours that
// aren't colours. Those are tested with the same weight as the happy path. Loaded the same way
// as test-calc.js: `.pragma library` stripped, the real file evaluated.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "assistant.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const A = new Function(src + "\nreturn { SETTINGS, SHELL, validate, parseReply, systemPrompt, show, match, examples, exampleTurns };")();

let pass = 0, fail = 0;
function check(name, cond, got) {
    if (cond) { pass++; return; }
    fail++;
    console.log("FAIL", name, got === undefined ? "" : JSON.stringify(got));
}

const pal16 = ["#101418", "#e0707a", "#7ac68a", "#e6c07b", "#61afef", "#c678dd", "#56b6c2", "#d6dde4",
               "#5c6370", "#ef8a93", "#98d8a4", "#f0d097", "#82c2f5", "#d699e8", "#78ccd6", "#ffffff"];

// ── set ───────────────────────────────────────────────────────────────────────
let v = A.validate({ do: "set", key: "radiusScale", value: 1.3 });
check("set real", v.do === "set" && v.value === 1.3, v);
v = A.validate({ do: "set", key: "radiusScale", value: 9 });
check("set clamps high", v.do === "set" && v.value === 1.5, v);
v = A.validate({ do: "set", key: "radiusScale", value: "0.1" });
check("set clamps low, from a string", v.do === "set" && v.value === 0.5, v);
v = A.validate({ do: "set", key: "nightLightTemp", value: 3333.7 });
check("set int rounds", v.do === "set" && v.value === 3334, v);
v = A.validate({ do: "set", key: "motionEnabled", value: "off" });
check("set bool from 'off'", v.do === "set" && v.value === false, v);
v = A.validate({ do: "set", key: "motionEnabled", value: "maybe" });
check("set bool refuses junk", v.do === "invalid", v);
v = A.validate({ do: "set", key: "themeMode", value: "light" });
check("set enum", v.do === "set" && v.value === "light", v);
v = A.validate({ do: "set", key: "themeMode", value: "purple" });
check("set enum refuses unknown option", v.do === "invalid", v);
v = A.validate({ do: "set", key: "screenshotDir", value: "/etc" });
check("set refuses a key not on the list", v.do === "invalid", v);
v = A.validate({ do: "set", key: "__proto__", value: 1 });
check("set refuses __proto__", v.do === "invalid", v);
v = A.validate({ do: "set", key: "toString", value: 1 });
check("set refuses inherited names", v.do === "invalid", v);
v = A.validate({ do: "set", key: "fontScale", value: "big" });
check("set refuses a non-number", v.do === "invalid", v);

// ── scheme ────────────────────────────────────────────────────────────────────
v = A.validate({ do: "scheme", name: "Harbour Dusk", background: "#101418", foreground: "#D6DDE4", colors: pal16 });
check("scheme ok", v.do === "scheme" && v.palette.colors.color15 === "#ffffff" && v.palette.special.foreground === "#d6dde4", v);
check("scheme swatch has 8", v.swatch && v.swatch.length === 8, v.swatch);
v = A.validate({ do: "scheme", name: "Eight", colors: pal16.slice(0, 8) });
check("scheme of 8 doubles", v.do === "scheme" && v.palette.colors.color9 === pal16[1], v);
check("scheme defaults bg/fg from 0/7", v.palette && v.palette.special.background === pal16[0] && v.palette.special.foreground === pal16[7], v);
v = A.validate({ do: "scheme", colors: pal16.slice(0, 12) });
check("scheme of 12 refused", v.do === "invalid", v);
v = A.validate({ do: "scheme", colors: pal16.map((c, i) => i === 3 ? "red" : c) });
check("scheme refuses a named colour", v.do === "invalid", v);
v = A.validate({ do: "scheme", colors: pal16.map((c, i) => i === 3 ? "#12345" : c) });
check("scheme refuses short hex", v.do === "invalid", v);
v = A.validate({ do: "scheme", background: "url(x)", colors: pal16 });
check("scheme refuses a bad background", v.do === "invalid", v);
v = A.validate({ do: "scheme", name: "<b>Evil</b>/../../x\n", colors: pal16 });
check("scheme name is cleaned", v.do === "scheme" && !/[<>\/\n.]/.test(v.name), v.name);

// ── anything else ─────────────────────────────────────────────────────────────
check("unknown verb", A.validate({ do: "exec", cmd: "rm -rf ~" }).do === "invalid");
check("not an object", A.validate("set").do === "invalid");
check("an array is not one action", A.validate([1]).do === "invalid");
check("null", A.validate(null).do === "invalid");

// ── the shell's own actions ───────────────────────────────────────────────────
const ctx = { wallpapers: ["Sunset Coast.jpg", "forest.png"], presets: ["Blue Haven", "Crimson Moon"],
              names: { nightlight: "Night light" } };
v = A.validate({ do: "action", id: "nightlight", on: "on" }, ctx);
check("action toggle with on", v.do === "action" && v.on === true && v.label === "Night light → on" && !v.confirm, v);
check("action without on flips", A.validate({ do: "action", id: "dnd" }, ctx).on === undefined);
check("lock asks first", A.validate({ do: "action", id: "lock" }, ctx).confirm === true);
check("reload asks first", A.validate({ do: "action", id: "reload" }, ctx).confirm === true);
check("recording asks first", A.validate({ do: "action", id: "record" }, ctx).confirm === true);
check("the overview isn't an action here", A.validate({ do: "action", id: "overview" }, ctx).do === "invalid");
check("an unknown action id is refused", A.validate({ do: "action", id: "rm" }, ctx).do === "invalid");
check("__proto__ isn't an action", A.validate({ do: "action", id: "__proto__" }, ctx).do === "invalid");
check("on must be a boolean", A.validate({ do: "action", id: "dnd", on: "maybe" }, ctx).do === "invalid");
check("volume clamps", A.validate({ do: "volume", value: 250 }).value === 100);
check("volume 0.4 is 40%", A.validate({ do: "volume", value: 0.4 }).value === 40);
check("brightness rounds", A.validate({ do: "brightness", value: "33.6" }).value === 34);
check("brightness refuses junk", A.validate({ do: "brightness", value: "bright" }).do === "invalid");
check("wallpaper by part of a name", A.validate({ do: "wallpaper", pick: "sunset" }, ctx).name === "Sunset Coast.jpg");
check("wallpaper random", A.validate({ do: "wallpaper", pick: "Random" }, ctx).random === true);
check("wallpaper can't be a path", A.validate({ do: "wallpaper", pick: "/etc/passwd" }, ctx).do === "invalid");
check("preset by name, any case", A.validate({ do: "preset", name: "crimson moon" }, ctx).name === "Crimson Moon");
check("an unknown preset is refused", A.validate({ do: "preset", name: "Nope" }, ctx).do === "invalid");
check("media verbs only", A.validate({ do: "media", command: "next" }).do === "media" && A.validate({ do: "media", command: "delete" }).do === "invalid");
check("workspace range", A.validate({ do: "workspace", id: 3 }).id === 3 && A.validate({ do: "workspace", id: 99 }).do === "invalid");
check("launch takes a name", A.validate({ do: "launch", app: "Firefox" }).app === "Firefox" && A.validate({ do: "launch" }).do === "invalid");
check("timer caps at 10 h", A.validate({ do: "timer", minutes: 9999 }).minutes === 600 && A.validate({ do: "timer", minutes: -1 }).do === "invalid");
check("no shell command verb", A.validate({ do: "run", command: "rm -rf ~" }).do === "invalid");
check("no delete verb", A.validate({ do: "delete", what: "clips" }).do === "invalid");
check("nothing in SHELL deletes", !Object.keys(A.SHELL).some(k => /delete|remove|clear|close|kill/i.test(k)));
const ctx2 = { scenes: ["Neon City", "Rainy Window"] };
check("scene by name", A.validate({ do: "scene", pick: "rainy" }, ctx2).name === "Rainy Window");
check("an unknown scene is refused", A.validate({ do: "scene", pick: "Mars" }, ctx2).do === "invalid");
check("play a track", A.validate({ do: "play", query: "Blinding Lights" }).kind === "track");
check("play a playlist", A.validate({ do: "play", query: "lofi", kind: "playlist" }).kind === "playlist");
check("play's kind is checked", A.validate({ do: "play", query: "x", kind: "podcast" }).kind === "track");
check("open a website", A.validate({ do: "open", url: "https://www.youtube.com/watch?v=x" }).label === "Open www.youtube.com");
check("open refuses file://", A.validate({ do: "open", url: "file:///etc/passwd" }).do === "invalid");
check("open refuses javascript:", A.validate({ do: "open", url: "javascript:alert(1)" }).do === "invalid");
check("open refuses a custom scheme", A.validate({ do: "open", url: "steam://run/1" }).do === "invalid");
check("open refuses spaces", A.validate({ do: "open", url: "https://a b.com" }).do === "invalid");
check("search takes a query", A.validate({ do: "search", query: "weather lisbon" }).do === "search");
check("block prompt has worked examples", A.systemPrompt({}, null, "d", false).includes("Examples (user"));
check("json prompt leaves examples to the turns", !A.systemPrompt({}, null, "d", true).includes("Examples (user"));
const turns = A.exampleTurns();
check("example turns alternate user/model", turns.length % 2 === 0 && turns.every((t, i) => t.role === (i % 2 ? "model" : "user")));
check("example turns are valid JSON replies", turns.filter(t => t.role === "model").every(t => { const d = JSON.parse(t.text); return typeof d.reply === "string" && Array.isArray(d.actions); }));
check("every example action validates", A.examples().every(e => e[2].every(a => A.validate(a, { windowApps: ["kitty"] }).do !== "invalid")));
const now = new Date(2026, 9, 24, 10, 0, 0).getTime();
const cx = { nowMs: now, windowApps: ["discord", "spotify", "kitty"], outputs: ["Speakers", "Headphones"],
             bluetooth: ["Buds Pro"], wallpapers: ["forest.png"], presets: ["Blue Haven"] };
v = A.validate({ do: "remind", text: "Call mum", at: "18:00" }, cx);
check("remind at a time today", v.do === "remind" && new Date(v.due).getHours() === 18 && new Date(v.due).getDate() === 24, v);
v = A.validate({ do: "remind", text: "Stretch", at: "08:00" }, cx);
check("remind at a past time is tomorrow", v.do === "remind" && new Date(v.due).getDate() === 25, v);
check("remind in minutes", A.validate({ do: "remind", text: "Tea", in: 20 }, cx).due === now + 20 * 60000);
check("remind 7pm", new Date(A.validate({ do: "remind", text: "x", at: "7pm" }, cx).due).getHours() === 19);
check("remind needs a when", A.validate({ do: "remind", text: "x" }, cx).do === "invalid");
check("remind needs a what", A.validate({ do: "remind", at: "18:00" }, cx).do === "invalid");
check("todo", A.validate({ do: "todo", text: "Buy milk" }).text === "Buy milk");
check("alarm weekdays", A.validate({ do: "alarm", at: "7:00", days: "weekdays" }).days === 62);
check("alarm daily", A.validate({ do: "alarm", at: "07:00", days: "daily" }).days === 127);
check("alarm mon,wed", A.validate({ do: "alarm", at: "07:00", days: "mon,wed" }).days === (2 | 8));
check("alarm once", A.validate({ do: "alarm", at: "07:00" }).days === 0);
check("alarm refuses bad days", A.validate({ do: "alarm", at: "07:00", days: "someday" }).do === "invalid");
check("alarm refuses 25:00", A.validate({ do: "alarm", at: "25:00" }).do === "invalid");
v = A.validate({ do: "window", app: "Discord", workspace: 2 }, cx);
check("window move", v.do === "window" && v.app === "discord" && v.workspace === 2, v);
check("window needs an op", A.validate({ do: "window", app: "discord" }, cx).do === "invalid");
check("window must be open", A.validate({ do: "window", app: "steam", workspace: 1 }, cx).do === "invalid");
check("window focus leaves", A.validate({ do: "window", app: "kitty", focus: true }, cx).leaves === true);
check("output by name", A.validate({ do: "output", device: "headphones" }, cx).device === "Headphones");
check("output must exist", A.validate({ do: "output", device: "tv" }, cx).do === "invalid");
check("appvolume", A.validate({ do: "appvolume", app: "spotify", value: 50 }).value === 50);
check("bluetooth connect default", A.validate({ do: "bluetooth", device: "buds" }, cx).connect === true);
check("bluetooth must be paired", A.validate({ do: "bluetooth", device: "car" }, cx).do === "invalid");
check("clip seconds capped", A.validate({ do: "clip", seconds: 9999 }).seconds === 600);
check("screenshot leaves", A.validate({ do: "screenshot" }).leaves === true);
v = A.validate({ do: "look", workspaces: [3], wallpaper: "forest", scheme: "blue haven" }, cx);
check("look both", v.do === "look" && v.wallpaper === "forest.png" && v.scheme === "Blue Haven", v);
check("look needs something", A.validate({ do: "look", workspaces: [3] }, cx).do === "invalid");
check("look range", A.validate({ do: "look", workspaces: [42], wallpaper: "forest" }, cx).do === "invalid");
check("discord verbs", A.validate({ do: "discord", command: "mute" }).do === "discord" && A.validate({ do: "discord", command: "kick" }).do === "invalid");
check("findsetting", A.validate({ do: "findsetting", query: "clock format" }).leaves === true);
check("remember", A.validate({ do: "remember", fact: "Likes warm colours" }).fact === "Likes warm colours");
check("forget all", A.validate({ do: "forget", fact: "all" }).label === "Forget everything");
const spn = A.systemPrompt({}, null, "d", true, { now: ["GPU 48°C"], memory: ["Likes warm colours"] });
check("prompt has right-now", spn.includes("Right now") && spn.includes("GPU 48°C"));
check("prompt has memory", spn.includes("Likes warm colours"));
check("appvolume can boost", A.validate({ do: "appvolume", app: "spotify", value: 120 }).value === 120);
check("appvolume caps at the ceiling", A.validate({ do: "appvolume", app: "spotify", value: 400 }).value === 130);
check("appvolume ceiling from ctx", A.validate({ do: "appvolume", app: "x", value: 400 }, { appCeiling: 125 }).value === 125);
check("discord leave", A.validate({ do: "discord", command: "leave" }).label === "Leave the Discord call");
const dcx = { discordUsers: ["Harryzita", "Bob"] };
check("discord mic volume caps at 100", A.validate({ do: "discordvolume", target: "mic", value: 150 }, dcx).value === 100);
check("discord output to 200", A.validate({ do: "discordvolume", target: "output", value: 180 }, dcx).value === 180);
check("discord person volume", A.validate({ do: "discordvolume", target: "harry", value: 50 }, dcx).target === "Harryzita");
check("discord unknown person", A.validate({ do: "discordvolume", target: "zed", value: 50 }, dcx).do === "invalid");
check("discord mute a person", A.validate({ do: "discorduser", user: "bob" }, dcx).mute === true);
check("discord noise suppression", A.validate({ do: "discordsetting", setting: "noise", on: true }).label === "Noise suppression → on");
check("discord setting needs on", A.validate({ do: "discordsetting", setting: "noise" }).do === "invalid");
let rr = A.parseReply("Done.\n```action\n" + JSON.stringify([{ do: "volume", value: 30 }, { do: "wallpaper", pick: "forest" }]) + "\n```", ctx);
check("parseReply passes ctx through", rr.actions.length === 2 && rr.actions[1].name === "forest.png", rr.actions);
const spc = A.systemPrompt({}, null, "2026-10-24", true, { wallpapers: ["a.jpg"], presets: ["Blue Haven"], names: { lock: "Lock screen" }, states: { dnd: "Off" } });
check("prompt lists wallpapers and presets", spc.includes("a.jpg") && spc.includes("Blue Haven"));
check("prompt marks asking actions", spc.includes("lock — Lock screen [asks the user first]"));
check("prompt shows a toggle's state", spc.includes("dnd — dnd (toggle, now Off)"));

// ── parseReply ────────────────────────────────────────────────────────────────
let r = A.parseReply("Here's a calmer one.\n\n```action\n" + JSON.stringify({ do: "scheme", name: "Calm", colors: pal16 }) + "\n```\n");
check("reply: text stripped of the block", r.text === "Here's a calmer one.", r.text);
check("reply: one scheme", r.actions.length === 1 && r.actions[0].do === "scheme", r.actions);

r = A.parseReply("Two things.\n```action\n[" + JSON.stringify({ do: "set", key: "radiusScale", value: 1.2 }) + "," + JSON.stringify({ do: "set", key: "nope", value: 1 }) + "]\n```");
check("reply: array → two, one invalid", r.actions.length === 2 && r.actions[0].do === "set" && r.actions[1].do === "invalid", r.actions);

r = A.parseReply("```action\n{not json}\n```");
check("reply: broken JSON → invalid card", r.actions.length === 1 && r.actions[0].do === "invalid", r.actions);

r = A.parseReply("Use this:\n```json\n{\"do\": \"set\", \"key\": \"cavaBg\", \"value\": true}\n```");
check("reply: a ```json block carrying `do` counts", r.actions.length === 1 && r.actions[0].value === true, r.actions);

r = A.parseReply("Code:\n```json\n{\"a\": 1}\n```");
check("reply: ordinary JSON code is left alone", r.actions.length === 0 && r.text.includes("\"a\": 1"), r);

r = A.parseReply("Plain answer, nothing to do.");
check("reply: no actions", r.actions.length === 0 && r.text === "Plain answer, nothing to do.", r);

let many = "";
for (let i = 0; i < 10; i++) many += "```action\n{\"do\":\"set\",\"key\":\"radiusScale\",\"value\":1}\n```\n";
check("reply: capped at 6", A.parseReply(many).actions.length === 6);

// ── systemPrompt ──────────────────────────────────────────────────────────────
const sp = A.systemPrompt({ radiusScale: 1, motionEnabled: true }, { special: { background: "#000000" }, colors: { color0: "#000000" } }, "2026-10-24");
check("prompt names every key", Object.keys(A.SETTINGS).every(k => sp.includes("- " + k + " ")));
check("prompt shows a current value", sp.includes("[1]") && sp.includes("[on]"));
check("prompt carries the date", sp.includes("2026-10-24"));
check("block form shows a fenced example", sp.includes("```action"));
const spj = A.systemPrompt({}, null, "2026-10-24", true);
check("json form asks for {reply, actions}", spj.includes('"reply"') && spj.includes('"actions"') && !spj.includes("```action"));
check("prompt says no code", sp.includes("Never write code"));

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
