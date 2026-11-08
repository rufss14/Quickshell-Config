// ── test-polkit.js ────────────────────────────────────────────────────────────
// Tests for services/polkit.js, the cleaning of text a polkit request supplies.
//
//     bun scripts/test-polkit.js      (or: node scripts/test-polkit.js)
//
// Safe to run: pure functions, no I/O. Loads the real .js by stripping its
// `.pragma library` line, like test-kelvin.js, so it can't test a drifted copy.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "polkit.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

const { message, prompt, actionId } =
    new Function(src + "\nreturn { message, prompt, actionId };")();

let pass = 0, fail = 0;
const failures = [];
function check(name, ok, detail) {
    if (ok) { pass++; return }
    fail++;
    failures.push(`  ${name}${detail ? "\n      " + detail : ""}`);
}
const eq = (name, got, want) => check(name, got === want, `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);

// ── message ──────────────────────────────────────────────────────────────────
eq("trailing full stop goes", message("Authentication is required to run X."), "Authentication is required to run X");
eq("only one full stop goes", message("Wait..."), "Wait..");
eq("plain text untouched", message("Authentication is required"), "Authentication is required");
eq("null is empty", message(null), "");
eq("undefined is empty", message(undefined), "");

// A newline run can't hide the real action below the fold, and controls vanish.
eq("newlines flatten", message("Run this\n\n\n\n\nharmless thing"), "Run this harmless thing");
eq("escape and nul dropped", message("a\u001b[2Jb\u0000c"), "a [2Jb c");
eq("tabs flatten", message("a\t\tb"), "a b");

// Capped, and the cap is visible rather than silent.
{
    const long = message("x".repeat(1000));
    check("long message is capped", long.length <= 240, "length " + long.length);
    check("capped message ends with an ellipsis", long.endsWith("…"));
}

// Markup is NOT interpreted here — it stays text, for the view's PlainText to show as-is.
eq("markup is left as text", message("<b>sudo</b>"), "<b>sudo</b>");

// ── prompt ───────────────────────────────────────────────────────────────────
eq("colon and space go", prompt("Password: ", true), "Password");
eq("no colon is fine", prompt("Password", true), "Password");
eq("empty hidden prompt", prompt("", true), "Password");
eq("empty visible prompt", prompt("", false), "Input");
eq("only a colon is empty", prompt(":", true), "Password");
eq("whitespace is empty", prompt("   ", false), "Input");
eq("undefined hidden", prompt(undefined, true), "Password");
eq("a real prompt is kept", prompt("Enter your PIN:", true), "Enter your PIN");
check("long prompt is capped", prompt("p".repeat(500), true).length <= 60);

// ── actionId ─────────────────────────────────────────────────────────────────
eq("a real id is kept", actionId("org.freedesktop.policykit.exec"), "org.freedesktop.policykit.exec");
eq("odd characters dropped", actionId("org.x/..;rm -rf"), "org.x..rm-rf");
eq("null is empty", actionId(null), "");
check("long id is capped", actionId("a".repeat(500)).length <= 80);

// ─────────────────────────────────────────────────────────────────────────────
if (fail) {
    console.log(`FAIL  ${fail} failed, ${pass} passed`);
    console.log(failures.join("\n"));
    process.exit(1);
}
console.log(`ok  ${pass} checks`);
