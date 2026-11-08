// ── test-notifyrules.js ───────────────────────────────────────────────────────
// Regression tests for services/notifyrules.js: which repeated notifications collapse
// into one history entry, and when a battery reminder earns a toast.
//
//     bun scripts/test-notifyrules.js          (or: node scripts/test-notifyrules.js)
//
// Safe to run: pure functions, touches nothing. Loads the real file by stripping the
// `.pragma library` line.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "notifyrules.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const N = new Function(src + `
    return { deviceName, batteryKey, collapseKey, batteryLevel, shouldToast };`)();

let pass = 0;
const failures = [];
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    failures.push(`  ${name}\n      want ${w}\n      got  ${g}`);
}

// ── Same mouse, wired or wireless ─────────────────────────────────────────────
check("device: wired suffix dropped", N.deviceName("Razer Viper Ultimate (Wired)"), "Razer Viper Ultimate");
check("device: wireless suffix dropped", N.deviceName("Razer Viper Ultimate (Wireless)"), "Razer Viper Ultimate");
check("device: no suffix", N.deviceName("Razer Basilisk"), "Razer Basilisk");
check("device: undefined", N.deviceName(undefined), "");
check("key: wired and wireless agree",
      N.batteryKey("OpenRazer", "Razer Viper Ultimate (Wired)"),
      N.batteryKey("OpenRazer", "Razer Viper Ultimate (Wireless)"));
check("key: another app's battery message is not ours", N.batteryKey("upower", "Battery low"), "");

// ── What collapses ────────────────────────────────────────────────────────────
check("collapse: shell status", N.collapseKey("Quickshell", "Lyrics connected"), "Quickshell\nLyrics connected");
check("collapse: different summaries stay apart",
      N.collapseKey("Quickshell", "A") === N.collapseKey("Quickshell", "B"), false);
check("collapse: chat app never", N.collapseKey("discord", "Lani"), "");
check("collapse: Clips never (each clip is an event)", N.collapseKey("Clips", "Clip saved"), "");
check("collapse: battery by device", N.collapseKey("OpenRazer", "Razer Viper Ultimate (Wired)"),
      "OpenRazer\nRazer Viper Ultimate");

// ── Reading the level ─────────────────────────────────────────────────────────
check("level: plain", N.batteryLevel("Battery is 29%"), 29);
check("level: low wording", N.batteryLevel("Battery is low (8%). Please charge your device"), 8);
check("level: full", N.batteryLevel("Battery is fully charged (100%)"), 100);
check("level: none", N.batteryLevel("Something else"), -1);
check("level: empty", N.batteryLevel(""), -1);
check("level: undefined", N.batteryLevel(undefined), -1);
check("level: clamped", N.batteryLevel("999%"), 100);

// ── When a reminder is news ───────────────────────────────────────────────────
check("toast: first ever", N.shouldToast(undefined, 33), true);
check("toast: same level again", N.shouldToast(33, 33), false);
check("toast: one point down", N.shouldToast(33, 32), false);
check("toast: four points down", N.shouldToast(33, 29), false);
check("toast: five points down", N.shouldToast(33, 28), true);
check("toast: wobble up one", N.shouldToast(29, 30), false);
check("toast: crosses into critical", N.shouldToast(12, 10), true);
check("toast: already critical, one down", N.shouldToast(10, 9), false);
check("toast: charged and draining again", N.shouldToast(8, 33), true);
check("toast: unreadable level never swallowed", N.shouldToast(33, -1), true);
check("toast: unreadable last", N.shouldToast(-1, 33), true);

if (failures.length) {
    console.log(`FAILED ${failures.length} of ${pass + failures.length}`);
    console.log(failures.join("\n"));
    process.exit(1);
}
console.log(`notifyrules: ${pass} checks passed`);
