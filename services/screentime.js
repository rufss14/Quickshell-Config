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

// ── Hours ─────────────────────────────────────────────────────────────────────
// Alongside the per-app seconds, each day keeps 24 numbers: the seconds counted in each local hour, with no app
// in them (the day strip and the pace read these). { "YYYY-MM-DD": [24 seconds] }. A file from before hours
// existed has none; the strip then fills from the day it is updated.

function nextHour(ms) {
    var d = new Date(ms)
    var n = new Date(d.getFullYear(), d.getMonth(), d.getDate(), d.getHours() + 1).getTime()
    // A DST fall-back can resolve to the same instant: always move on.
    return n > ms ? n : ms + 3600000
}

// Credit the span from `from` to `to` to its local hours, clipped to its last `maxSpan` ms exactly as credit()
// clips, so the two never disagree. Returns a NEW object.
function creditHours(hours, from, to, maxSpan) {
    if (!(to > from)) return hours
    var t = maxSpan > 0 ? Math.max(from, to - maxSpan) : from
    var out = Object.assign({}, hours || {})
    while (t < to) {
        var end = Math.min(to, nextHour(t))
        var dk = dayKey(t)
        var arr = (out[dk] || []).slice()
        while (arr.length < 24) arr.push(0)
        arr[new Date(t).getHours()] += (end - t) / 1000
        out[dk] = arr
        t = end
    }
    return out
}

// The `hours` of a loaded file: well-formed days only, 24 whole non-negative numbers each (an hour holds at most
// 3600 seconds), days with nothing in them dropped.
function cleanHours(raw) {
    var out = {}
    var hs = raw && typeof raw === "object" && !Array.isArray(raw) ? raw.hours : null
    if (!hs || typeof hs !== "object" || Array.isArray(hs)) return out
    for (var dk in hs) {
        if (!/^\d{4}-\d{2}-\d{2}$/.test(dk) || !Array.isArray(hs[dk])) continue
        var arr = [], any = false
        for (var i = 0; i < 24; i++) {
            var v = Number(hs[dk][i])
            v = isFinite(v) && v > 0 ? Math.min(3600, Math.round(v)) : 0
            if (v > 0) any = true
            arr.push(v)
        }
        if (any) out[dk] = arr
    }
    return out
}

// A day's 24 hours, zeros when there are none.
function hoursOf(hours, key) {
    var a = hours && hours[key]
    var out = []
    for (var i = 0; i < 24; i++) out.push(a && a[i] > 0 ? a[i] : 0)
    return out
}

// Today so far against the same moment on the days before (`prevKeys`, only those with hourly numbers):
// { ahead, expected, dir } — seconds ahead (negative: behind) of what an average day had by now, and dir
// -1 / 0 / 1 (within 5% or 5 minutes is level). null while there is nothing to compare with, or the day is so
// young (the average has under 10 minutes by now) that a comparison would be noise.
function paceVs(hours, todayKey, prevKeys, now) {
    var d = new Date(now)
    var h = d.getHours()
    var frac = (d.getMinutes() * 60 + d.getSeconds()) / 3600
    var sum = 0, n = 0
    for (var i = 0; i < prevKeys.length; i++) {
        var a = hours && hours[prevKeys[i]]
        if (!a) continue
        var tot = 0, upto = 0
        for (var j = 0; j < 24; j++) { tot += a[j] || 0; if (j < h) upto += a[j] || 0 }
        if (!(tot > 0)) continue
        sum += upto + (a[h] || 0) * frac
        n++
    }
    if (n === 0) return null
    var expected = sum / n
    if (expected < 600) return null
    var today = 0
    var t = hours && hours[todayKey]
    if (t) for (var k = 0; k < 24; k++) today += t[k] || 0
    var diff = today - expected
    return { ahead: Math.round(diff), expected: Math.round(expected),
             dir: Math.abs(diff) < Math.max(300, expected * 0.05) ? 0 : diff > 0 ? 1 : -1 }
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

// The apps that have the most time across `keys` (day keys), biggest first: [{ app, seconds }], at most `n`.
// A colour in the week chart stands for one of these in every bar.
function topAcross(days, keys, n) {
    var tot = {}
    for (var i = 0; i < keys.length; i++) {
        var day = (days && days[keys[i]]) || {}
        for (var a in day) tot[a] = (tot[a] || 0) + day[a]
    }
    return top(tot, n)
}

// One day cut into its stack, bottom first: [{ rank, seconds, from }]. `rank` is the app's index in
// `apps` ([{ app }], at most 3); whatever is not one of them is one last "other" slice, always rank 3 — the
// views give ranks 0-2 an accent tint each and rank 3 a neutral, so "other" must not borrow a ranked tint.
function segments(day, apps) {
    var d = day || {}
    var all = total(d)
    var out = []
    var from = 0
    for (var i = 0; i < apps.length; i++) {
        var s = d[apps[i].app] || 0
        if (s <= 0) continue
        out.push({ rank: i, seconds: s, from: from })
        from += s
    }
    if (all - from > 0) out.push({ rank: 3, seconds: all - from, from: from })
    return out
}

// Today against what the other days of the week usually are: { pct, dir } with dir -1 / 0 / 1, or
// null when there is nothing to compare with (no earlier day with time on it). Within 5% counts as
// level, so the chip doesn't flicker between "+1%" and "-1%" while a minute is credited.
function versus(week) {
    var today = 0, sum = 0, n = 0
    for (var i = 0; i < week.length; i++) {
        if (week[i].today) today = week[i].seconds
        else if (week[i].seconds > 0) { sum += week[i].seconds; n++ }
    }
    if (n === 0) return null
    var avg = sum / n
    var pct = Math.round((today - avg) / avg * 100)
    return { pct: Math.abs(pct), dir: Math.abs(pct) < 5 ? 0 : pct > 0 ? 1 : -1 }
}

// The heat strip's level for a day, 0..4: 0 nothing, then quarters of the busiest day.
function heat(seconds, peak) {
    if (!(seconds > 0) || !(peak > 0)) return 0
    return Math.max(1, Math.min(4, Math.ceil(seconds / peak * 4)))
}

// Days in a row, counting back from today: `days` is lastDays() output, oldest first. mode "under": a recorded
// day at or under `limit` seconds; "any": any recorded day. A day with nothing recorded ends the run — except
// today, which has simply not started yet and is skipped. Today OVER the limit ends it too (0).
function streak(days, mode, limit) {
    var n = 0
    for (var i = days.length - 1; i >= 0; i--) {
        var s = days[i].seconds
        if (!(s > 0)) { if (i === days.length - 1) continue; break }
        if (mode === "under" && limit > 0 && s > limit) break
        n++
    }
    return n
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
