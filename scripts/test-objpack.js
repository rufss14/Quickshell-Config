// ── test-objpack.js ───────────────────────────────────────────────────────────
// Tests for services/objpack.js, the decoder for the Spicy Lyrics wire format.
//
//     bun scripts/test-objpack.js          (or: node scripts/test-objpack.js)
//
// Safe to run: pure functions, no network.
//
// Fixtures are hand-built opcode streams with placeholder strings. The decoder only ever
// moves primitives between two shapes, so nothing real is needed — and a packed stream is
// far easier to reason about when every value in it is obviously synthetic.
//
// The malformed cases are the point. This decodes a byte stream fetched from a third
// party, so it is treated as hostile input: a crafted stream must fail cleanly and return
// null, never throw out of a service singleton, blow the JS stack, or install a key that
// corrupts the prototype chain of everything downstream.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "objpack.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

const { unpack } = new Function(src + "\nreturn { unpack };")();

let pass = 0, fail = 0;
function check(name, cond, detail) {
    if (cond) pass++;
    else { fail++; console.log(`  FAIL  ${name}${detail ? "  — " + detail : ""}`); }
}
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ── Primitives ────────────────────────────────────────────────────────────────
console.log("primitives");
check("string", unpack([["alpha"], [0]]) === "alpha");
check("number", unpack([[42], [0]]) === 42);
check("boolean", unpack([[true], [0]]) === true);
check("null", unpack([[null], [0]]) === null);
check("reuses one value from the table", eq(unpack([["x"], [-2, 3, 0, 0, 0]]), ["x", "x", "x"]));

// ── Containers ────────────────────────────────────────────────────────────────
console.log("containers");
check("empty array (-4)", eq(unpack([[], [-4]]), []));
check("empty object (-6)", eq(unpack([[], [-6]]), {}));
check("single-element array (-5)", eq(unpack([["only"], [-5, 0]]), ["only"]));
check("array (-2)", eq(unpack([["a", "b"], [-2, 2, 0, 1]]), ["a", "b"]));
check("object (-1)", eq(unpack([["k", "v"], [-1, 1, 0, 1]]), { k: "v" }));

// Nested: { outer: [ 1, 2 ] }
check("nested structures",
      eq(unpack([["outer", 1, 2], [-1, 1, 0, -2, 2, 1, 2]]), { outer: [1, 2] }));

// ── Schema arrays ─────────────────────────────────────────────────────────────
// The compact form for uniform records, and the reason a lyrics payload packs so small:
// every line repeats the same field names, so they are stored once.
console.log("schema arrays");
const schema = unpack([
    ["t", "d", 1, 2, 3, 4],
    [-3, 2, 2, 0, 1, 2, 3, 4, 5]
]);
check("decodes rows", eq(schema, [{ t: 1, d: 2 }, { t: 3, d: 4 }]));
check("row count is right", Array.isArray(schema) && schema.length === 2);
check("keys shared across rows",
      eq(Object.keys(schema[0]), Object.keys(schema[1])));

// ── Malformed input returns null, never throws ────────────────────────────────
console.log("malformed input");
const bad = [
    ["not an array", "nope"],
    ["wrong shell length", [[], [], []]],
    ["single element", [[]]],
    ["values not an array", ["x", []]],
    ["stream not an array", [[], "x"]],
    ["null payload", null],
    ["undefined payload", undefined],
    ["number payload", 7],
    ["empty stream", [[], []]],
    ["pointer out of range", [["a"], [5]]],
    ["negative pointer beyond opcodes", [["a"], [-99]]],
    ["unknown opcode", [["a"], [-7]]],
    ["stream ends mid-object", [["k"], [-1, 1, 0]]],
    ["stream ends mid-array", [["a"], [-2, 3, 0]]],
    ["non-integer opcode", [["a"], [1.5]]],
    ["object with non-string key", [[7, "v"], [-1, 1, 0, 1]]],
    ["negative count", [["a"], [-2, -1]]],
    ["trailing data", [["a", "b"], [0, 1]]],
    ["values contains an object", [[{}], [0]]],
    ["values contains an array", [[[]], [0]]],
    ["non-finite number in values", [[Infinity], [0]]],
];
let allNull = true;
for (const [name, payload] of bad) {
    let got, threw = false;
    try { got = unpack(payload); } catch (e) { threw = true; }
    if (threw) { allNull = false; console.log(`    THREW on: ${name}`); }
    else if (got !== null) { allNull = false; console.log(`    not null: ${name}`); }
}
check("every malformed payload returns null without throwing", allNull);

// A reason is reported, so a failure can be logged without parsing twice.
const out = {};
unpack([["a"], [-7]], out);
check("failure reports a reason", typeof out.reason === "string" && out.reason.length > 0);

// ── Hostile input ─────────────────────────────────────────────────────────────
// This is network data from a third party. These are the cases that matter.
console.log("hostile input");

// Prototype pollution: a key of __proto__ must be refused outright.
const poison = unpack([["__proto__", "owned"], [-1, 1, 0, 1]]);
check("__proto__ key is refused", poison === null);
check("prototype was not touched", ({}).owned === undefined);
check("constructor key is refused",
      unpack([["constructor", "x"], [-1, 1, 0, 1]]) === null);

// Deep nesting must hit the depth cap rather than the JS stack.
const deepStream = [];
for (let i = 0; i < 5000; i++) deepStream.push(-5);
deepStream.push(0);
let deepThrew = false, deepResult;
try { deepResult = unpack([["x"], deepStream]); } catch (e) { deepThrew = true; }
check("deep nesting does not throw", !deepThrew);
check("deep nesting returns null", deepResult === null);

// A huge declared count must not allocate before the stream is checked.
check("absurd array count is refused", unpack([["a"], [-2, 999999999, 0]]) === null);
check("absurd schema counts are refused",
      unpack([["a", "b"], [-3, 999999, 999999, 0, 1]]) === null);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
