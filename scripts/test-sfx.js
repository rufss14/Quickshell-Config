// ── test-sfx.js ───────────────────────────────────────────────────────────────
// Regression tests for services/sfx.js, the sound effects' decisions: which key makes
// which sound, what a panel changing hands means, loudness and rate limits.
//
//     bun scripts/test-sfx.js          (or: node scripts/test-sfx.js)
//
// Safe to run: pure functions, touches nothing. Loaded by stripping the
// `.pragma library` line and evaluating the rest, so the tests run the real file.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "sfx.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const S = new Function(src + `
    return { CUES, GROUPS, allFiles, ducked, announces, typingCue, panelCue, chooseFile, volumeFor, allowed, shouldPlay };`)();

let pass = 0;
const failures = [];
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    failures.push(`  ${name}\n      want ${w}\n      got  ${g}`);
}

// ── Typing ────────────────────────────────────────────────────────────────────
check("a letter", S.typingCue(0x61, "a", false), "key");
check("a digit", S.typingCue(0x31, "1", false), "key");
check("a non-latin letter (layout-independent)", S.typingCue(0x1000000, "ç", false), "key");
check("space", S.typingCue(0x20, " ", false), "space");
check("return", S.typingCue(0x01000004, "\r", false), "enter");
check("keypad enter", S.typingCue(0x01000005, "\r", false), "enter");
check("backspace", S.typingCue(0x01000003, "\b", false), "back");
check("delete", S.typingCue(0x01000007, "\x7f", false), "back");
check("shift alone is silent", S.typingCue(0x01000020, "", false), "");
check("escape is silent", S.typingCue(0x01000000, "\x1b", false), "");
check("an arrow is silent", S.typingCue(0x01000012, "", false), "");
check("tab is silent", S.typingCue(0x01000001, "\t", false), "");
check("ctrl+a is a shortcut, silent", S.typingCue(0x61, "\x01", true), "");
check("a key with no text is silent", S.typingCue(0x01000030, "", false), "");
check("missing text is silent", S.typingCue(0x41, undefined, false), "");

// ── Panels ────────────────────────────────────────────────────────────────────
check("empty → panel opens", S.panelCue("", "wallpaper"), "open");
check("panel → empty closes", S.panelCue("wallpaper", ""), "close");
check("panel → another is one open", S.panelCue("wallpaper", "colors"), "open");
check("no change is silent", S.panelCue("wallpaper", "wallpaper"), "");
check("empty → empty is silent", S.panelCue("", ""), "");
check("null/undefined are empty", S.panelCue(undefined, null), "");
check("undefined → panel opens", S.panelCue(undefined, "mixer"), "open");

// ── Choosing a file ───────────────────────────────────────────────────────────
check("single-file cue", S.chooseFile("open", "", 0.9), "open");
check("an unknown cue", S.chooseFile("nope", "", 0.5), "");
for (let i = 0; i < 40; i++) {
    const last = "key" + (1 + (i % 4));
    const got = S.chooseFile("key", last, i / 40);
    if (got === last || !S.CUES.key.files.includes(got)) check("never repeats " + last, got, "≠" + last);
    else pass++;
}
check("pick of exactly 1 stays in range", S.CUES.key.files.includes(S.chooseFile("key", "", 1)), true);
check("a negative pick stays in range", S.CUES.key.files.includes(S.chooseFile("key", "", -3)), true);

// ── Volume ────────────────────────────────────────────────────────────────────
check("100% is the ceiling × the cue's gain", S.volumeFor("timer", 1), 0.6);
check("the slider is squared: 50% is a quarter", S.volumeFor("timer", 0.5), 0.15);
check("monotonic in the slider", S.volumeFor("open", 0.6) > S.volumeFor("open", 0.5), true);
check("a swoosh is subtler than a key", S.volumeFor("open", 0.5) < S.volumeFor("key", 0.5), true);
check("clamped above 1", S.volumeFor("open", 5), S.volumeFor("open", 1));
check("a group level scales it, squared", S.volumeFor("timer", 1, { alerts: 0.5 }), 0.15);
check("a group at 0 is silent", S.volumeFor("open", 1, { panels: 0 }), 0);
check("another group's level doesn't touch it", S.volumeFor("timer", 1, { typing: 0 }), 0.6);
check("an unset group is at full", S.volumeFor("timer", 1, {}), 0.6);
check("a notification takes the notify level", S.volumeFor("notify", 1, { notify: 0.5 }), 0.15);
check("switch cues share the switches level", S.volumeFor("on", 1, { switches: 0.5 }) === 0.6 * 0.25 * 0.8, true);
check("never reaches full scale", S.volumeFor("open", 1) < 1, true);
check("zero master is silent", S.volumeFor("open", 0), 0);
check("garbage master is silent", S.volumeFor("open", "loud"), 0);
check("unknown cue is silent", S.volumeFor("nope", 1), 0);
check("no cue gain exceeds 1", Object.values(S.CUES).every(c => c.gain > 0 && c.gain <= 1), true);

// ── Rate ──────────────────────────────────────────────────────────────────────
check("first play is allowed", S.allowed("open", 1000, undefined), true);
check("a swoosh twice in a frame is not", S.allowed("open", 1030, 1000), false);
check("…but after the gap it is", S.allowed("open", 1080, 1000), true);
check("typing may repeat at key-repeat speed", S.allowed("key", 1033, 1000), true);
check("notifications are spaced out", S.allowed("notify", 1100, 1000), false);

// ── The switches ──────────────────────────────────────────────────────────────
const on = { enabled: true, panels: true, typing: true, switches: true, notify: true,
             alerts: true, capture: true };
check("everything on", S.shouldPlay("open", on), true);
check("master off beats every group", S.shouldPlay("open", { ...on, enabled: false }), false);
check("typing off, panels still sound", S.shouldPlay("open", { ...on, typing: false }), true);
check("typing off silences keys", S.shouldPlay("key", { ...on, typing: false }), false);
check("typing off silences space/enter/back",
      ["space", "enter", "back"].some(id => S.shouldPlay(id, { ...on, typing: false })), false);
check("panels off silences open and close",
      ["open", "close"].some(id => S.shouldPlay(id, { ...on, panels: false })), false);
check("switches off silences the blips only",
      ["on", "off", "tick"].some(id => S.shouldPlay(id, { ...on, switches: false })), false);
check("…and leaves notifications", S.shouldPlay("notify", { ...on, switches: false }), true);
check("notify off silences the chime only", S.shouldPlay("notify", { ...on, notify: false }), false);
check("…and leaves the switches", S.shouldPlay("on", { ...on, notify: false }), true);
check("an unknown cue never plays", S.shouldPlay("nope", on), false);
check("no prefs never plays", S.shouldPlay("open", undefined), false);
check("a group not set to true is off", S.shouldPlay("open", { enabled: true }), false);

// ── The catalogue ─────────────────────────────────────────────────────────────
check("every cue has a known group",
      Object.values(S.CUES).every(c => S.GROUPS.includes(c.group)), true);
check("every group has a cue", S.GROUPS.every(g => Object.values(S.CUES).some(c => c.group === g)), true);
check("allFiles has no duplicates", new Set(S.allFiles()).size, S.allFiles().length);
check("allFiles covers all 17 sounds", S.allFiles().length, 17);

// ── Alerts, capture ───────────────────────────────────────────────────────────
check("a finished timer is an alert", S.CUES.timer.group, "alerts");
check("an alarm is an alert", S.CUES.alarm.group, "alerts");
check("alerts off silences both", ["timer", "alarm"].some(id => S.shouldPlay(id, { ...on, alerts: false })), false);
check("…and leaves the shutter", S.shouldPlay("shutter", { ...on, alerts: false }), true);
check("capture off silences shutter and clip", ["shutter", "clipsaved"].some(id => S.shouldPlay(id, { ...on, capture: false })), false);
check("an alarm is not rate-limited like a key", S.allowed("alarm", 1100, 1000), false);
check("the swoosh sits well under the alerts", S.volumeFor("open", 1) < S.volumeFor("timer", 1) * 0.7, true);

// ── The notification that follows an alert ───────────────────────────────────
check("a chime right after a timer is ducked", S.ducked("notify", 1500, 1000), true);
check("…but not once the hold has passed", S.ducked("notify", 4000, 1000), false);
check("nothing is ducked with no alert before it", S.ducked("notify", 1500, undefined), false);
check("alerts and captures announce themselves", [S.announces("timer"), S.announces("alarm"), S.announces("clipsaved")].every(Boolean), true);
check("a key or a swoosh does not", [S.announces("key"), S.announces("open"), S.announces("notify")].some(Boolean), false);
check("only the notification chime is ducked", S.ducked("open", 1500, 1000), false);

if (failures.length) {
    console.log(`FAIL ${failures.length}, pass ${pass}\n` + failures.join("\n"));
    process.exit(1);
}
console.log(`ok ${pass}`);
