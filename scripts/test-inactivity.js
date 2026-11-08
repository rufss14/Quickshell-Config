// ── test-inactivity.js ────────────────────────────────────────────────────────
// Regression tests for services/inactivity.js: the Inactivity panel's rules — what
// survives a hand-edited config.json, what a custom command parses to, and how the old
// Lock › auto-lock setting becomes a rule.
//
//     bun scripts/test-inactivity.js          (or: node scripts/test-inactivity.js)
//
// Safe to run: pure functions, touches nothing. Loaded by stripping the
// `.pragma library` line and evaluating the rest, so the tests run the real file.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "inactivity.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const I = new Function(src + `
    return { MIN_MINUTES, MAX_MINUTES, MAX_RULES, ACTIONS, ACTION_ORDER, clampMinutes, normalizeRule,
             normalizeRules, newRule, WARN_SECONDS, warns, monitorSeconds, warningTitle, fromLegacyLock, parseCommand, duration, describe, actionLabel };`)();

let pass = 0;
const failures = [];
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    failures.push(`  ${name}\n      want ${w}\n      got  ${g}`);
}
const rule = (o) => Object.assign({ id: "a", enabled: true, minutes: 10, action: "lock", command: "" }, o);

// ── Minutes: never trusted ────────────────────────────────────────────────────
check("minutes: in range is kept", I.clampMinutes(10), 10);
check("minutes: rounds", I.clampMinutes(9.6), 10);
check("minutes: zero → floor", I.clampMinutes(0), 1);
check("minutes: negative → floor", I.clampMinutes(-5), 1);
check("minutes: NaN → floor (never 'idle at once')", I.clampMinutes(NaN), 1);
check("minutes: a string number", I.clampMinutes("15"), 15);
check("minutes: undefined → floor", I.clampMinutes(undefined), 1);
check("minutes: huge → ceiling", I.clampMinutes(1e9), 720);
check("minutes: Infinity → floor", I.clampMinutes(Infinity), 1);

// ── A rule ────────────────────────────────────────────────────────────────────
check("rule: unknown action dropped", I.normalizeRule(rule({ action: "format-disk" })), null);
check("rule: __proto__ is not an action", I.normalizeRule(rule({ action: "__proto__" })), null);
check("rule: toString is not an action", I.normalizeRule(rule({ action: "toString" })), null);
check("rule: null", I.normalizeRule(null), null);
check("rule: a string", I.normalizeRule("lock"), null);
check("rule: enabled defaults on", I.normalizeRule({ id: "x", minutes: 5, action: "suspend" }).enabled, true);
check("rule: enabled false is kept", I.normalizeRule(rule({ enabled: false })).enabled, false);
check("rule: command must be a string", I.normalizeRule(rule({ action: "command", command: 42 })).command, "");

// ── The list ──────────────────────────────────────────────────────────────────
check("list: not an array", I.normalizeRules({}), []);
check("list: undefined", I.normalizeRules(undefined), []);
check("list: junk dropped, rest kept",
      I.normalizeRules([null, rule({ id: "a" }), { action: "nope" }, 7]).map(r => r.id), ["a"]);
check("list: duplicate ids renamed",
      I.normalizeRules([rule({ id: "a", minutes: 5 }), rule({ id: "a", minutes: 6, action: "suspend" })]).map(r => r.id),
      ["a", "r1"]);
check("list: missing id gets one",
      I.normalizeRules([rule({ id: "" })]).map(r => r.id), ["r1"]);
check("list: ordered by timeout",
      I.normalizeRules([rule({ id: "b", minutes: 30 }), rule({ id: "a", minutes: 5 })]).map(r => r.id), ["a", "b"]);
check("list: equal timeouts keep their order",
      I.normalizeRules([rule({ id: "x", minutes: 5 }), rule({ id: "y", minutes: 5, action: "suspend" })]).map(r => r.id),
      ["x", "y"]);
check("list: capped",
      I.normalizeRules(Array.from({ length: 20 }, (_, i) => rule({ id: "i" + i, minutes: i + 1 }))).length, I.MAX_RULES);
check("list: idempotent",
      I.normalizeRules(I.normalizeRules([rule({ id: "b", minutes: 30 }), rule({ id: "a", minutes: 5 })])),
      I.normalizeRules([rule({ id: "b", minutes: 30 }), rule({ id: "a", minutes: 5 })]));

// ── Adding one ────────────────────────────────────────────────────────────────
check("new: first rule is Lock at 10", I.newRule([]), { id: "r1", enabled: true, minutes: 10, action: "lock", command: "" });
check("new: after lock@10 → screen off at 20",
      (r => [r.action, r.minutes])(I.newRule([rule({ id: "r1" })])), ["screenoff", 20]);
check("new: never defaults to a custom command",
      I.newRule(I.ACTION_ORDER.filter(a => a !== "command").map((a, i) => rule({ id: "r" + (i + 1), action: a, minutes: i + 1 }))).action,
      "lock");
check("new: id is unused", I.newRule([rule({ id: "r1" }), rule({ id: "r2", minutes: 20 })]).id, "r3");

// ── The old Lock › auto-lock setting ──────────────────────────────────────────
check("legacy: on, 10 min", I.fromLegacyLock(true, 10), [rule({ id: "r1" })]);
check("legacy: off stays off", I.fromLegacyLock(false, 25)[0].enabled, false);
check("legacy: minutes clamped", I.fromLegacyLock(true, 0)[0].minutes, 1);
check("legacy: result is already normal", I.normalizeRules(I.fromLegacyLock(true, 15)), I.fromLegacyLock(true, 15));

// ── Custom command → argv ─────────────────────────────────────────────────────
check("cmd: words", I.parseCommand("notify-send hello"), ["notify-send", "hello"]);
check("cmd: extra whitespace", I.parseCommand("  a   b\t c "), ["a", "b", "c"]);
check("cmd: double quotes", I.parseCommand('notify-send "two words" x'), ["notify-send", "two words", "x"]);
check("cmd: single quotes are literal", I.parseCommand("echo 'a \\ b $HOME'"), ["echo", "a \\ b $HOME"]);
check("cmd: escaped space", I.parseCommand("ls my\\ dir"), ["ls", "my dir"]);
check("cmd: escaped quote inside double", I.parseCommand('echo "say \\"hi\\""'), ["echo", 'say "hi"']);
check("cmd: empty quotes are an argument", I.parseCommand('echo ""'), ["echo", ""]);
check("cmd: adjacent quoting joins", I.parseCommand("a\"b c\"'d e'"), ["ab cd e"]);
check("cmd: nothing", I.parseCommand(""), null);
check("cmd: only spaces", I.parseCommand("   "), null);
check("cmd: unterminated double", I.parseCommand('echo "oops'), null);
check("cmd: unterminated single", I.parseCommand("echo 'oops"), null);
check("cmd: not text", I.parseCommand(undefined), null);
check("cmd: shell syntax is just text, never run", I.parseCommand("echo a; rm -rf /"), ["echo", "a;", "rm", "-rf", "/"]);
check("cmd: a variable is not expanded", I.parseCommand("echo $HOME"), ["echo", "$HOME"]);

// ── Words ─────────────────────────────────────────────────────────────────────
check("duration: minutes", I.duration(5), "5 min");
check("duration: whole hours", I.duration(120), "2 h");
check("duration: hours and minutes", I.duration(90), "1 h 30 min");
check("describe: lock", I.describe(rule({ minutes: 10 })), "Lock after 10 min");
check("describe: command names the program", I.describe(rule({ action: "command", command: "notify-send hi", minutes: 3 })),
      "notify-send after 3 min");
check("describe: empty command", I.describe(rule({ action: "command", command: "", minutes: 3 })),
      "Run command after 3 min");
check("every action has a label and a symbol",
      I.ACTION_ORDER.every(a => I.ACTIONS[a] && I.ACTIONS[a].label && I.ACTIONS[a].symbol), true);
check("ACTION_ORDER lists exactly ACTIONS",
      [...I.ACTION_ORDER].sort(), Object.keys(I.ACTIONS).sort());

// ── Warning before a destructive action ───────────────────────────────────────
check("warns: log out and power off", ["logout", "poweroff"].map(I.warns), [true, true]);
check("warns: the gentle ones don't", ["lock", "screenoff", "suspend", "hibernate", "command"].map(I.warns),
      [false, false, false, false, false]);
check("warns: junk", I.warns("nope"), false);
check("monitor: lock trips at its timeout", I.monitorSeconds(rule({ minutes: 10 })), 600);
check("monitor: power off trips early by the warning", I.monitorSeconds(rule({ action: "poweroff", minutes: 10 })), 570);
check("monitor: shortest warning rule stays positive", I.monitorSeconds(rule({ action: "logout", minutes: 1 })) > 0, true);
check("warning text", I.warningTitle(rule({ action: "poweroff" })), "Powering off in 30 s");
check("warning text: log out", I.warningTitle(rule({ action: "logout" })), "Logging out in 30 s");

if (failures.length) {
    console.log(`FAILED ${failures.length} of ${pass + failures.length}`);
    console.log(failures.join("\n"));
    process.exit(1);
}
console.log(`inactivity: ${pass} checks passed`);
