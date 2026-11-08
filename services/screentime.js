.pragma library

// ── screentime.js ─────────────────────────────────────────────────────────────
// Screen time (services/ScreenTime): seconds per app per day, from the focused window.
//
//     bun scripts/test-screentime.js
//
// The data is { "YYYY-MM-DD": { "<app id>": seconds } } — local days, app ids and whole
// seconds, nothing else (never a window title). Pure: the service hands in times.
// ─────────────────────────────────────────────────────────────────────────────

var DAY_MS = 86400000
var APP_OK = /^[a-z0-9][a-z0-9._+-]{0,127}$/
var KEEP_MIN = 7
var KEEP_MAX = 365

// The local calendar day of a time, as "YYYY-MM-DD".
function dayKey(ms) {
    var d = new Date(ms)
    var m = d.getMonth() + 1, day = d.getDate()
    return d.getFullYear() + "-" + (m < 10 ? "0" : "") + m + "-" + (day < 10 ? "0" : "") + day
}

// The local midnight that starts the day after `ms`.
function nextMidnight(ms) {
    var d = new Date(ms)
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1).getTime()
}

// An app id as it is stored: lowercased, and only a sane id (a window's class is
// whatever the app says it is).
function appKey(id) {
    var s = String(id || "").trim().toLowerCase()
    return APP_OK.test(s) ? s : ""
}

// Credit `app` with the time from `from` to `to`, split at local midnights. A span longer
// than `maxSpan` ms is clipped to its LAST `maxSpan` (a suspend, a stalled clock — the
// machine wasn't being used for the gap). Returns a NEW days object.
function credit(days, app, from, to, maxSpan) {
    var key = appKey(app)
    if (key === "" || !(to > from)) return days
    var start = maxSpan > 0 ? Math.max(from, to - maxSpan) : from
    var out = Object.assign({}, days || {})
    var t = start
    while (t < to) {
        var end = Math.min(to, nextMidnight(t))
        var dk = dayKey(t)
        var day = Object.assign({}, out[dk] || {})
        day[key] = (day[key] || 0) + (end - t) / 1000
        out[dk] = day
        t = end
    }
    return out
}

// The file is hand-editable: only well-formed days and apps with a finite, non-negative
// number come through, rounded to whole seconds.
function clean(raw) {
    var out = {}
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out
    var days = raw.days && typeof raw.days === "object" ? raw.days : raw
    for (var dk in days) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(dk)) continue
        var d = days[dk]
        if (!d || typeof d !== "object" || Array.isArray(d)) continue
        var day = {}
        for (var a in d) {
            var k = appKey(a)
            var v = Number(d[a])
            if (k !== "" && isFinite(v) && v > 0) day[k] = Math.round(v)
        }
        if (Object.keys(day).length > 0) out[dk] = day
    }
    return out
}

// Days older than `keep` days before `now` dropped.
function prune(days, keep, now) {
    var k = Math.max(KEEP_MIN, Math.min(KEEP_MAX, Math.round(keep) || 30))
    var oldest = dayKey(now - (k - 1) * DAY_MS)
    var out = {}
    for (var dk in days) if (dk >= oldest) out[dk] = days[dk]
    return out
}

function total(day) {
    var s = 0
    for (var a in (day || {})) s += day[a]
    return s
}

// A day's apps, longest first: [{ app, seconds }], at most `n`.
function top(day, n) {
    var rows = []
    for (var a in (day || {})) rows.push({ app: a, seconds: day[a] })
    rows.sort(function (x, y) { return y.seconds !== x.seconds ? y.seconds - x.seconds : (x.app < y.app ? -1 : 1) })
    return n > 0 ? rows.slice(0, n) : rows
}

// The last `n` days ending today, oldest first: [{ key, label, seconds, today }].
var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
function lastDays(days, now, n) {
    var out = []
    var count = Math.max(1, n || 7)
    for (var i = count - 1; i >= 0; i--) {
        // Noon, so a DST change can't land the step on the wrong day.
        var d = new Date(now)
        var at = new Date(d.getFullYear(), d.getMonth(), d.getDate() - i, 12).getTime()
        var k = dayKey(at)
        out.push({ key: k, label: WEEKDAYS[new Date(at).getDay()], seconds: total(days && days[k]), today: i === 0 })
    }
    return out
}

// "3 h 12 m", "45 m", "under a minute", "" for nothing.
function duration(seconds) {
    var s = Math.max(0, Math.floor(seconds || 0))
    if (s === 0) return ""
    if (s < 60) return "under a minute"
    var m = Math.floor(s / 60)
    if (m < 60) return m + " m"
    var h = Math.floor(m / 60)
    var r = m % 60
    return r === 0 ? h + " h" : h + " h " + r + " m"
}

// The cell's hover readout: "3h", "45m", "0m".
function short(seconds) {
    var m = Math.floor(Math.max(0, seconds || 0) / 60)
    if (m < 60) return m + "m"
    var h = m / 60
    return (h < 10 ? Math.round(h * 10) / 10 : Math.round(h)) + "h"
}

// ── Steam games ───────────────────────────────────────────────────────────────
// A game run under Steam has a window class that says nothing: `steam_app_1245620`. Its
// name is in the library's appmanifest file, one `"name"` line each. `steamNames` reads the
// grep output of those (`path/appmanifest_<id>.acf:<tab>"name"<tab><tab>"Elden Ring"`) into
// { "<id>": "Elden Ring" }.
function steamNames(text) {
    var out = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        var m = /appmanifest_(\d+)\.acf:\s*"name"\s*"([^"]*)"/.exec(lines[i])
        if (m && m[2] !== "") out[m[1]] = m[2]
    }
    return out
}

// The id in a `steam_app_<id>` class, or "" for anything else.
function steamId(app) {
    var m = /^steam_app_(\d+)$/.exec(String(app || ""))
    return m ? m[1] : ""
}

// What an app is CALLED in a list: a Steam game by its title once known ("Steam game
// 1245620" until then), Proton's own helper window for what it is, anything else as given
// (the caller resolves ordinary apps through their desktop entry).
function gameName(app, names) {
    var id = steamId(app)
    if (id !== "") return (names && names[id]) || "Steam game " + id
    if (app === "steam_proton") return "Game (Proton)"
    return ""
}
