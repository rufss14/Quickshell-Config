// ── test-calc.js ──────────────────────────────────────────────────────────────
// Regression tests for services/calc.js, the launcher's calculator.
//
//     bun scripts/test-calc.js          (or: node scripts/test-calc.js)
//
// Safe to run: calc.js is pure functions and touches nothing.
//
// This exists because the parser is the one piece of real logic in the launcher, and
// the half of it that MATTERS is the half that must decline — a calculator that
// answers "firefox" has broken app search. Those cases are as load-bearing as the
// arithmetic, so they are tested with the same weight.
//
// calc.js is loaded by stripping its `.pragma library` line (a QML directive that
// isn't valid JS) and evaluating the rest, so the tests run against the real file
// rather than a copy that can drift.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "calc.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

const evaluate = new Function(src + "\nreturn evaluate;")();

// [input, expected display] — null means "must NOT be treated as an expression".
const cases = [
    // ── Arithmetic ────────────────────────────────────────────────────────────
    ["2+3", "5"],
    ["2 + 3 * 4", "14"],
    ["(2+3)*4", "20"],
    ["-5 + 3", "-2"],
    ["10 % 3", "1"],
    ["10 / 4", "2.5"],
    // Float noise must not reach the UI.
    ["0.1+0.2", "0.3"],

    // ── Precedence and associativity ──────────────────────────────────────────
    ["2^10", "1024"],
    ["2^3^2", "512"],      // right-associative: 2^(3^2), not (2^3)^2 = 64
    ["2^-1", "0.5"],       // exponent goes through unary

    // ── Functions and constants ───────────────────────────────────────────────
    ["sqrt(16)", "4"],
    ["round(2.7)", "3"],
    ["log(1000)", "3"],    // log is base 10
    ["ln(e)", "1"],
    ["pi", "3.14159265359"],
    ["2*pi", "6.28318530718"],

    // ── Thousands separators ──────────────────────────────────────────────────
    // Stripped before tokenising. Doing it inside the tokeniser split "1,234" into
    // two adjacent numbers, which then failed to parse — a real bug this catches.
    ["1,234 + 1", "1235"],
    ["1,234,567 * 2", "2469134"],

    // ── Unit conversion ───────────────────────────────────────────────────────
    ["10 km to mi", "6.21371192237 mi"],
    ["2 h to min", "120 min"],
    ["2*3 km to m", "6000 m"],     // the left side may itself be arithmetic
    ["1 gb to mb", "1000 mb"],
    ["1 gib to mib", "1024 mib"],  // decimal and binary are NOT the same
    ["100 c to f", "212°F"],
    ["32 f to c", "0°C"],
    ["0 c to k", "273.15°K"],

    // ── Must decline ──────────────────────────────────────────────────────────
    ["firefox", null],        // an app name is not a sum
    ["Files", null],          // …even one that is a valid JS identifier
    ["steam", null],
    ["firefox 2", null],      // partial parses must not yield the number
    ["2 3", null],
    ["5", null],              // a bare number is not a calculation worth showing
    ["1.2.3", null],          // a version string
    ["10 km to kg", null],    // mismatched dimensions is a typo, not a question
    ["alert(1)", null],       // not a function we expose
    ["2+", null],
    ["(2+3", null],
    ["", null],

    // ── Edge ──────────────────────────────────────────────────────────────────
    ["1/0", "∞"],
    // Locale-ambiguous: "1,5" is 1.5 in much of the world and 15 elsewhere.
    // Declining beats guessing.
    ["1,5", null],
];

let pass = 0;
const failures = [];

for (const [input, want] of cases) {
    const r = evaluate(input);
    const got = r === null ? null : r.display;
    const ok = want === null ? got === null : got === want;
    if (ok) pass++;
    else failures.push(`  ${JSON.stringify(input)}  want ${want}  got ${got}`);
}

console.log(`${pass}/${cases.length} passed`);
if (failures.length > 0) {
    console.log("\nFAILED:");
    console.log(failures.join("\n"));
    process.exit(1);
}
