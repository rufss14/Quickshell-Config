// ── test-powermenu.js ─────────────────────────────────────────────────────────
// services/powermenu.js — the action table the power menu reads.
//
//     bun scripts/test-powermenu.js          (or: node scripts/test-powermenu.js)
//
// Safe: pure functions. Nothing is powered off.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "powermenu.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const P = new Function(src + "\nreturn { ACTIONS, available, indexForLetter, step, buttonSize };")();

let passed = 0, failed = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) passed++;
    else { failed++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`); }
}

const both = { hibernate: true, firmware: true };
const none = { hibernate: false, firmware: false };
const keys = P.ACTIONS.map(a => a.key);

// ── the table ──
check("four actions — the important ones only", P.ACTIONS.map(a => a.key), ["lock", "logout", "reboot", "shutdown"]);
check("keys are unique", new Set(keys).size, keys.length);
check("letters are unique", new Set(P.ACTIONS.map(a => a.letter)).size, P.ACTIONS.length);
check("every letter is one uppercase character", P.ACTIONS.every(a => /^[A-Z]$/.test(a.letter)), true);
check("every action has a glyph, label and hint", P.ACTIONS.every(a => a.glyph && a.label && a.hint), true);
// The safety rule: anything that asks twice must say what it asks and how loudly — an armed
// button can't carry its warning in colour alone.
check("confirm actions ask a question and carry a tone", P.ACTIONS.filter(a => a.confirm).every(a => /\?$/.test(a.ask) && (a.tone === "warning" || a.tone === "danger")), true);
check("only lock fires on the first press", P.ACTIONS.filter(a => !a.confirm).map(a => a.key), ["lock"]);
check("everything that ends the session asks twice", P.ACTIONS.filter(a => a.ends).every(a => a.confirm), true);
check("log out and shut down are the loud ones", P.ACTIONS.filter(a => a.tone === "danger").map(a => a.key), ["logout", "shutdown"]);
check("order: lock first, shut down last", [keys[0], keys[keys.length - 1]], ["lock", "shutdown"]);

// The gating (`needs`) is no longer exercised by the real table — nothing in it needs a
// capability now — so it is tested against a synthetic one shaped like the old seven.
const FULL = [
    { key: "lock", letter: "L" }, { key: "suspend", letter: "S" },
    { key: "hibernate", letter: "H", needs: "hibernate" }, { key: "logout", letter: "E" },
    { key: "reboot", letter: "R" }, { key: "firmware", letter: "F", needs: "firmware" },
    { key: "shutdown", letter: "P" }
];
const hib = FULL[2], fw = FULL[5];

// ── available ──
check("hibernate needs the capability", [P.available(hib, both), P.available(hib, none)], [true, false]);
check("firmware needs the capability", [P.available(fw, both), P.available(fw, none)], [true, false]);
check("no caps at all hides the gated ones", [P.available(hib, undefined), P.available(hib, {})], [false, false]);
check("a plain action needs nothing", P.available(P.ACTIONS[0], undefined), true);
check("truthy-but-not-true does not count", P.available(hib, { hibernate: "yes" }), false);
check("nothing in the real table needs a capability", P.ACTIONS.every(a => a.needs === undefined), true);

// ── letters ──
check("L is lock", P.indexForLetter("L", none), 0);
check("lowercase works", P.indexForLetter("p", none), 3);
check("every action is reachable by its letter", P.ACTIONS.map(a => P.indexForLetter(a.letter, none)), [0, 1, 2, 3]);
check("a letter that was cut does nothing", [P.indexForLetter("S", none), P.indexForLetter("H", none), P.indexForLetter("F", none)], [-1, -1, -1]);
check("an unknown letter", P.indexForLetter("Z", both), -1);
check("a word is not a shortcut", P.indexForLetter("LOCK", both), -1);
check("empty is not a shortcut", P.indexForLetter("", both), -1);
check("non-string is not a shortcut", P.indexForLetter(undefined, both), -1);
check("a gated action's letter does nothing when unavailable", [P.indexForLetter("H", none, FULL), P.indexForLetter("F", none, FULL)], [-1, -1]);
check("…and works when available", [P.indexForLetter("H", both, FULL), P.indexForLetter("F", both, FULL)], [2, 5]);

// ── step (the real table) ──
check("forward from none is the first", P.step(-1, 1, none), 0);
check("backward from none is the last", P.step(-1, -1, none), 3);
check("forward wraps", P.step(3, 1, none), 0);
check("backward wraps", P.step(0, -1, none), 3);
check("a full lap visits all four", (() => { let c = -1, seen = []; for (let i = 0; i < 4; i++) { c = P.step(c, 1, none); seen.push(c); } return seen; })(), [0, 1, 2, 3]);

// ── step (gating, synthetic) ──
check("forward skips an unavailable one", P.step(1, 1, none, FULL), 3);        // suspend → (hibernate skipped) → logout
check("backward skips an unavailable one", P.step(3, -1, none, FULL), 1);
check("forward skips the gated one before the last", P.step(4, 1, none, FULL), 6);
check("a full lap with everything available visits all seven", (() => { let c = -1, seen = []; for (let i = 0; i < 7; i++) { c = P.step(c, 1, both, FULL); seen.push(c); } return seen; })(), [0, 1, 2, 3, 4, 5, 6]);
check("a full lap with the gated ones off visits five", (() => { let c = -1, seen = []; for (let i = 0; i < 5; i++) { c = P.step(c, 1, none, FULL); seen.push(c); } return seen; })(), [0, 1, 3, 4, 6]);
check("nothing available at all is -1", P.step(-1, 1, none, [hib, fw]), -1);

// ── buttonSize ──
check("plenty of room keeps the design size", P.buttonSize(4, 1000, 16, 16, 80), 80);
check("a short screen shrinks it just enough", P.buttonSize(7, 600, 16, 16, 80), Math.floor((600 - 32 - 96) / 7));
check("the stack then fits exactly or under", (() => { const b = P.buttonSize(7, 600, 16, 16, 80); return b * 7 + 6 * 16 + 32 <= 600; })(), true);
check("never zero or negative", P.buttonSize(7, 10, 16, 16, 80), 1);
check("no buttons is the design size", P.buttonSize(0, 600, 16, 16, 80), 80);

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
