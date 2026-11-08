// ── test-shellupdate.js ───────────────────────────────────────────────────────
// Regression tests for services/shellupdate.js — which release is newer, and
// which GitHub responses count as a release at all.
//
//     bun scripts/test-shellupdate.js          (or: node scripts/test-shellupdate.js)
//
// Safe to run: pure functions, no network.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "shellupdate.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { parse, newer, release } = new Function(src + "\nreturn { parse, newer, release };")();

let pass = 0, fail = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) pass++;
    else { fail++; console.log(`  FAIL  ${name}\n          got  ${g}\n          want ${w}`); }
}

// ── parse ──
check("plain",        parse("0.3"),    [0, 3]);
check("v-prefixed",   parse("v1.2.10"), [1, 2, 10]);
check("rc rejected",  parse("v0.4-rc1"), null);
check("empty",        parse(""),       null);
check("undefined",    parse(undefined), null);
check("word",         parse("main"),   null);

// ── newer ──
check("0.4 > 0.3",       newer("v0.4", "0.3"),    true);
check("0.10 > 0.9",      newer("v0.10", "0.9"),   true);   // numeric, not string order
check("equal",           newer("v0.3", "0.3"),    false);
check("0.3.0 == 0.3",    newer("0.3.0", "0.3"),   false);
check("0.3.1 > 0.3",     newer("0.3.1", "0.3"),   true);
check("older",           newer("v0.2", "0.3"),    false);
check("bad candidate",   newer("v0.4-rc1", "0.3"), false);
check("bad current",     newer("v0.4", ""),       false);

// ── release ──
const assets = [{ name: "quicktest.tar.xz" }, { name: "SHA256SUMS" }, { name: "SHA256SUMS.sig" }];
const good = { tag_name: "v0.4", body: "Fixes\r\n- a\r\n", html_url: "https://x/r/v0.4",
               published_at: "2026-10-06T12:00:00Z", assets };
check("good", release(JSON.stringify(good)),
      { tag: "v0.4", version: "0.4", notes: "Fixes\n- a", url: "https://x/r/v0.4", date: "2026-10-06" });
check("not json",      release("<html>"), null);
check("rate limited",  release(JSON.stringify({ message: "API rate limit exceeded" })), null);
check("draft",         release(JSON.stringify({ ...good, draft: true })), null);
check("prerelease",    release(JSON.stringify({ ...good, prerelease: true })), null);
check("bad tag",       release(JSON.stringify({ ...good, tag_name: "nightly" })), null);
check("unsigned (v0.3 shape)",
      release(JSON.stringify({ ...good, assets: [{ name: "quicktest.tar.xz" }, { name: "quicktest.zip" }] })), null);
check("null body",     release(JSON.stringify({ ...good, body: null })).notes, "");

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
