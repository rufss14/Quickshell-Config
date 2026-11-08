// ── test-unityentry.js ────────────────────────────────────────────────────────
// Regression tests for services/unityentry.js — the LauncherEntry reader behind
// the dock's app-reported badges and progress bars.
//
//     bun scripts/test-unityentry.js          (or: node scripts/test-unityentry.js)
//
// Safe to run: pure functions over dbus-monitor output captured from a real
// `gdbus emit` of the signal (the fixture below is that capture, verbatim).
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "unityentry.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { createParser, apply, appIdOf } =
    new Function(src + "\nreturn { createParser, apply, appIdOf };")();

let pass = 0, fail = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) pass++;
    else { fail++; console.log(`  FAIL  ${name}\n          got  ${g}\n          want ${w}`); }
}

function run(text) {
    const p = createParser();
    const out = [];
    for (const line of text.split("\n")) { const u = p.feed(line); if (u) out.push(u); }
    return out;
}

const capture = `signal time=1790406841.136640 sender=org.freedesktop.DBus -> destination=:1.1076 serial=4294967295 path=/org/freedesktop/DBus; interface=org.freedesktop.DBus; member=NameAcquired
   string ":1.1076"
signal time=1790406842.138398 sender=:1.1077 -> destination=(null destination) serial=2 path=/quicktest/test; interface=com.canonical.Unity.LauncherEntry; member=Update
   string "application://quicktest-test.desktop"
   array [
      dict entry(
         string "count"
         variant             int64 7
      )
      dict entry(
         string "count-visible"
         variant             boolean true
      )
      dict entry(
         string "progress"
         variant             double 0.42
      )
      dict entry(
         string "progress-visible"
         variant             boolean true
      )
      dict entry(
         string "urgent"
         variant             boolean false
      )
   ]`;

const ups = run(capture);
check("one update from the capture (NameAcquired ignored)", ups.length, 1);
check("app id from the uri", ups[0].app, "quicktest-test");
check("props parsed", ups[0].props,
      { "count": 7, "count-visible": true, "progress": 0.42, "progress-visible": true, "urgent": false });

// A variant holding its own array must not end the update early.
const nested = `signal time=1 sender=:1.2 -> destination=(null destination) serial=3 path=/x; interface=com.canonical.Unity.LauncherEntry; member=Update
   string "application://firefox.desktop"
   array [
      dict entry(
         string "quicklist"
         variant             array [
            string "a"
         ]
      )
      dict entry(
         string "progress"
         variant             double 0.5
      )
   ]`;
const n = run(nested);
check("nested array: still one update", n.length, 1);
check("nested array: later keys still read", n[0].props, { "progress": 0.5 });

// A header mid-update abandons it.
check("interrupted update is dropped",
      run(`signal time=1 sender=:1.2 -> destination=(null destination) serial=3 path=/x; interface=com.canonical.Unity.LauncherEntry; member=Update
   string "application://a.desktop"
   array [
signal time=2 sender=:1.3 -> destination=(null destination) serial=4 path=/y; interface=org.x; member=Other
   ]`).length, 0);

// apply(): partial updates merge, values clamp.
let st = apply({}, { app: "firefox", props: { "progress": 0.3, "progress-visible": true } });
st = apply(st, { app: "firefox", props: { "progress": 1.7 } });
check("apply: merges, keeps untouched fields", st.firefox.progressVisible, true);
check("apply: progress clamped to 1", st.firefox.progress, 1);
check("apply: other apps untouched", apply(st, { app: "tg", props: { "count": 3 } }).firefox.progress, 1);
check("apply: count floors and can't go negative",
      apply({}, { app: "x", props: { "count": -2 } }).x.count, 0);
check("appIdOf: reverse-DNS kept", appIdOf("application://org.telegram.desktop.desktop"), "org.telegram.desktop");

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
