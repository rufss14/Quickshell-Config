.pragma library

// ── notifyrules.js ────────────────────────────────────────────────────────────
// What the notification centre does with notifications that REPEAT, kept apart from
// the D-Bus server so `bun scripts/test-notifyrules.js` can exercise it. Two kinds:
//
//  • Shell status ("Lyrics connected", "Colours applied"): the shell reporting a state.
//    One history entry per (app, summary); the newest wins.
//  • Battery reminders (OpenRazer's notifier repeats "Battery is 29%" every 10 minutes
//    while under its threshold): one history entry per DEVICE, and a toast only when
//    the level has moved enough to be news (see shouldToast).

var STATUS_APPS  = ["Quickshell"];
var BATTERY_APPS = ["OpenRazer"];

// A toast is worth it when the level fell this many points since the last one…
var DROP = 5;
// …or crossed into the "charge it now" zone…
var CRITICAL = 10;
// …or came back up this far (charged, now draining again: a new cycle).
var RISE = 10;

// OpenRazer names one mouse "Razer Viper Ultimate (Wired)" or "(Wireless)" depending on
// how it is connected right now; it is the same battery.
function deviceName(summary) {
    return String(summary || "").replace(/\s*\([^)]*\)\s*$/, "");
}

// The device a battery reminder is about, or "" when this isn't one.
function batteryKey(appName, summary) {
    return BATTERY_APPS.indexOf(appName) >= 0 ? appName + "\n" + deviceName(summary) : "";
}

// Records with the same non-empty key are the same thing; "" = never collapsed.
function collapseKey(appName, summary) {
    var b = batteryKey(appName, summary);
    if (b !== "") return b;
    return STATUS_APPS.indexOf(appName) >= 0 ? appName + "\n" + summary : "";
}

// "Battery is 29%" / "Battery is low (8%). Please charge…" → 29 / 8. -1 when no number.
function batteryLevel(body) {
    var m = /(\d{1,3})\s*%/.exec(String(body || ""));
    return m ? Math.min(100, parseInt(m[1], 10)) : -1;
}

// `last` is the level at the previous toast for this device (undefined = none yet).
// An unreadable level always toasts: better one repeat than a swallowed warning.
function shouldToast(last, level) {
    if (level < 0 || last === undefined || last < 0) return true;
    if (level - last >= RISE) return true;
    if (last - level >= DROP) return true;
    return level <= CRITICAL && last > CRITICAL;
}
