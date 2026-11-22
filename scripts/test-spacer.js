// ── test-spacer.js ────────────────────────────────────────────────────────────
// Regression tests for services/spacer.js, the spacer module's length.
//
//     bun scripts/test-spacer.js          (or: node scripts/test-spacer.js)
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "spacer.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { length } = new Function(src + "\n return { length };")();

let pass = 0;
const failures = [];
function check(name, got, want) {
    if (got === want) { pass++; return; }
    failures.push(`  ${name}\n      want ${want}\n      got  ${got}`);
}

check("fixed: the size", length(24, 0, false, 0), 24);
check("grow: size plus the module", length(24, 100, false, 0), 124);
check("grow: the module alone", length(0, 100, false, 0), 100);
check("fill: what is left of the size", length(300, 100, true, 0), 200);
check("fill: never below nothing", length(100, 300, true, 0), 0);
check("fill: with no module it is the size", length(80, 0, true, 0), 80);
check("a floor while arranging lifts a small one", length(0, 0, false, 28), 28);
check("a floor leaves a long one alone", length(200, 0, false, 28), 200);
check("a floor lifts a spacer filled to nothing", length(100, 300, true, 28), 28);
check("garbage size is nothing", length(NaN, 0, false, 0), 0);
check("negative size is nothing", length(-5, 0, false, 0), 0);
check("negative follow is nothing", length(10, -50, false, 0), 10);
check("undefined arguments are nothing", length(undefined, undefined, undefined, undefined), 0);

if (failures.length) {
    console.log(`${pass} passed, ${failures.length} FAILED\n` + failures.join("\n"));
    process.exit(1);
}
console.log(`${pass}/${pass} passed`);
