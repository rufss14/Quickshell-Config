.pragma library

// ── island.js ─────────────────────────────────────────────────────────────────
// The island (modules/island/IslandDock: the handle and the card under the bar): what the card shows, and the
// small rules behind it. Pure, so they can be tested.
//
//     bun scripts/test-island.js
// ─────────────────────────────────────────────────────────────────────────────

// The pages of the card, in the order Settings lists them. The ids are what `Config.islandTab` / `islandPages` keep; the
// labels are what the rail says; `shape` is the M3E shape the rail's indicator becomes on that page.
var TABS = [
    { value: "today",   label: "Dashboard",   icon: "dashboard",   shape: "cookie9" },
    { value: "media",   label: "Media",       icon: "queue_music", shape: "clover"  },
    { value: "system",  label: "Performance", icon: "speed",       shape: "burst"   },
    { value: "weather", label: "Weather",     icon: "cloud",       shape: "sunny"   }
]
var TAB_IDS = TABS.map(function (t) { return t.value })

function tabMeta(value) {
    for (var i = 0; i < TABS.length; i++) if (TABS[i].value === value) return TABS[i]
    return TABS[0]
}

// The pages a saved list asks for, in its order: unknown ids and repeats dropped (a config written by hand, or by a
// build with other pages). Nothing left means every page: the card is never empty.
function pagesOf(list) {
    var src = Array.isArray(list) ? list : [], out = []
    for (var i = 0; i < src.length; i++)
        if (TAB_IDS.indexOf(src[i]) >= 0 && out.indexOf(src[i]) < 0) out.push(src[i])
    return out.length > 0 ? out : TAB_IDS.slice()
}

// A saved page that is still shown, else the first shown one: the card never lands on a page it has no room for.
// `pages` is the saved list (pagesOf runs on it); left out, every page.
function tabOf(value, pages) {
    var list = pagesOf(pages === undefined ? TAB_IDS : pages)
    return list.indexOf(value) >= 0 ? value : list[0]
}

// The page `delta` steps from `current` among the shown ones, stopping at either end (a wheel or a key).
function stepTab(pages, current, delta) {
    var list = pagesOf(pages)
    var i = Math.max(0, list.indexOf(current))
    return list[Math.max(0, Math.min(list.length - 1, i + (delta | 0)))]
}

// What the handle shows at rest, most pressing first: a recording (always: a click on it stops it), then, with the
// live handle on, a running timer, then a song that is playing. "" is the plain line.
function subject(s) {
    s = s || {}
    if (s.recording) return "record"
    if (!s.live) return ""
    if (s.timer) return "timer"
    if (s.playing) return "song"
    return ""
}

// The page that matches what the handle shows, when it is on the island's rail (`pages`, as it stands: an empty
// rail has none); "" for none.
function pageFor(subj, pages) {
    var want = subj === "song" ? "media" : ""
    return want !== "" && Array.isArray(pages) && pages.indexOf(want) >= 0 ? want : ""
}

// The wall clock's digits and its AM/PM marker. Built by hand: Qt's "h" is the 24-hour hour unless the SAME format
// also carries "AP", so formatting the digits and the marker apart drew "23:06 PM".
function clockText(hours, minutes, twelve, am, pm) {
    var h = ((hours | 0) % 24 + 24) % 24, m = ((minutes | 0) % 60 + 60) % 60
    var mm = (m < 10 ? "0" : "") + m
    if (!twelve) return { time: (h < 10 ? "0" : "") + h + ":" + mm, marker: "" }
    return { time: (h % 12 === 0 ? 12 : h % 12) + ":" + mm, marker: h < 12 ? (am || "AM") : (pm || "PM") }
}

// The card's size setting, kept to the range Settings offers (a hand-edited config can say anything).
function scaleOf(v) {
    var n = Number(v)
    return isFinite(n) && n > 0 ? Math.max(0.8, Math.min(1.25, n)) : 1
}

// Seconds as a clock: 65 -> "1:05", 3723 -> "1:02:03".
function elapsed(sec) {
    var s = Math.max(0, Math.floor(Number(sec) || 0))
    var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60
    var mm = h > 0 && m < 10 ? "0" + m : "" + m
    return (h > 0 ? h + ":" : "") + mm + ":" + (r < 10 ? "0" + r : r)
}

// Where the handle and the card sit: the left edge of a `w` wide thing in a window `winW` wide for an alignment.
function alignedX(align, w, winW, margin) {
    if (align === "left") return margin
    if (align === "right") return Math.max(margin, winW - w - margin)
    return Math.round((winW - w) / 2)
}

// The same, kept clear of a sidebar's face at either side (`clearL` / `clearR`: how far in from the edge it
// stands, 0 for none): never nearer an edge than `margin`, nor nearer a face than its clearance.
function placeX(align, w, winW, margin, clearL, clearR) {
    var lo = Math.max(margin, clearL || 0)
    var hi = Math.max(lo, winW - Math.max(margin, clearR || 0) - w)
    var x = align === "left" ? lo : align === "right" ? hi : Math.round((winW - w) / 2)
    return Math.max(lo, Math.min(hi, x))
}

// The month grid of the Today tab: always six weeks (42 cells) so the card never changes height between
// months. `firstDow` is the locale's first weekday (Qt's value: 0 or 7 is Sunday, 1 Monday), `month` is
// 0-based, `today` is { y, m, d } or null. Each cell is { y, m, d, off, today, weekend }; `off` is -1 / 0 / 1
// for the month before / this / after.
function monthCells(year, month, firstDow, today) {
    var fd = ((firstDow | 0) % 7 + 7) % 7
    var lead = (new Date(year, month, 1).getDay() - fd + 7) % 7
    var out = []
    for (var i = 0; i < 42; i++) {
        var dt = new Date(year, month, 1 - lead + i)
        var off = (dt.getFullYear() * 12 + dt.getMonth()) - (year * 12 + month)
        var dow = dt.getDay()
        out.push({
            y: dt.getFullYear(), m: dt.getMonth(), d: dt.getDate(), off: off,
            today: !!today && today.y === dt.getFullYear() && today.m === dt.getMonth() && today.d === dt.getDate(),
            weekend: dow === 0 || dow === 6
        })
    }
    return out
}

// Weekday numbers (Date.getDay: 0 is Sunday) in the order a row of the grid shows them.
function weekdays(firstDow) {
    var fd = ((firstDow | 0) % 7 + 7) % 7
    var out = []
    for (var i = 0; i < 7; i++) out.push((fd + i) % 7)
    return out
}

// What is left of a day for the Today tab's agenda: all-day entries first, then timed ones that have not
// ended yet, soonest first, at most `max`. `occ` are Calendar occurrences ({ start, end, allDay, summary }, ms).
// Each item is { summary, allDay, start, end, live } — `live` while `nowMs` is inside it.
function agenda(occ, nowMs, max) {
    var list = (occ || []).filter(function (o) {
        return o && (o.allDay || o.end > nowMs || o.start >= nowMs)
    }).map(function (o) {
        return { summary: o.summary || "", allDay: !!o.allDay, start: o.start, end: Math.max(o.end || 0, o.start),
                 live: !o.allDay && o.start <= nowMs && nowMs < Math.max(o.end || 0, o.start + 1) }
    })
    list.sort(function (a, b) { return (b.allDay ? 1 : 0) - (a.allDay ? 1 : 0) || a.start - b.start })
    return list.slice(0, Math.max(0, max | 0))
}

// A trace of unbounded values (bytes a second) as 0..1 for a sparkline: against its own peak in the window,
// but never against less than `floor`, so a quiet line stays flat instead of drawing noise as a mountain.
// `last` keeps only the newest that many (a chart that fills in seconds, not in the history's whole minute).
function scaled(values, floor, last) {
    var src = Array.isArray(values) ? values : []
    if (last > 0) src = src.slice(-last)
    var list = src.map(function (v) { return Math.max(0, Number(v) || 0) })
    var peak = Math.max(floor > 0 ? floor : 1, Math.max.apply(null, list.concat([0])))
    return list.map(function (v) { return Math.min(1, v / peak) })
}

// The card's body size per tab { w, h }, and the size to draw while one tab hands over to another: the larger
// of the two in each direction, so the card grows at once and shrinks only after the new page is in. One width
// for every tab: the card only changes height between them. The rail stands beside the body, outside these. Numbers, not Tokens: they are the room the pages are
// composed in (the pieces inside are Tokens).
var BODY = {
    today:   { w: 780, h: 384 },
    media:   { w: 780, h: 320 },
    system:  { w: 780, h: 332 },
    weather: { w: 780, h: 412 }
}
function bodyFor(shown, wanted) {
    var a = BODY[tabOf(shown)], b = BODY[tabOf(wanted)]
    return { w: Math.max(a.w, b.w), h: Math.max(a.h, b.h) }
}

// A forecast day's labels: "Today", then the weekday, and the short date. `iso` is "YYYY-MM-DD"; `todayIso` the same
// for today. Parsed by field, never with new Date(str) (a bare ISO date is UTC midnight and slips a day east of it).
function forecastDay(iso, todayIso, dayNames, monthNames) {
    var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso || "")
    if (!m) return { name: "", date: "", today: false }
    var d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
    return { name: iso === todayIso ? "Today" : dayNames[d.getDay()],
             date: monthNames[d.getMonth()] + " " + d.getDate(), today: iso === todayIso }
}

// The time out of a local ISO timestamp ("2026-11-12T07:18") as hours and minutes, or null.
function isoTime(iso) {
    var m = /T(\d{2}):(\d{2})/.exec(iso || "")
    return m ? { h: Number(m[1]), m: Number(m[2]) } : null
}

// A short series scaled to fill its own range, for a curve that shows the shape rather than the level: values 0..1 with
// `pad` of headroom top and bottom, plus the low and the high. Flat input is a flat line in the middle. { norm, lo, hi }.
function spanOf(values, pad) {
    var list = (Array.isArray(values) ? values : []).map(function (v) { return Number(v) || 0 })
    if (list.length === 0) return { norm: [], lo: 0, hi: 0 }
    var lo = Math.min.apply(null, list), hi = Math.max.apply(null, list)
    var p = Math.max(0, Math.min(0.4, pad || 0))
    var norm = list.map(function (v) { return hi === lo ? 0.5 : p + (1 - 2 * p) * (v - lo) / (hi - lo) })
    return { norm: norm, lo: lo, hi: hi }
}

// A greeting for the hour: morning from 5, afternoon from 12, evening from 18, night from 22.
function greeting(hour) {
    var h = hour | 0
    if (h >= 22 || h < 5) return "Good night"
    if (h < 12) return "Good morning"
    if (h < 18) return "Good afternoon"
    return "Good evening"
}

// What the weather looks like, for the drifting layer behind it: WMO code and day/night → "clear", "cloud", "fog",
// "rain", "snow" or "storm" (Weather.symbol's own groups).
function weatherKind(code, isDay) {
    var c = Number(code)
    if (c === 0 || c === 1) return "clear"
    if (c === 2 || c === 3) return "cloud"
    if (c === 45 || c === 48) return "fog"
    if (c >= 95) return "storm"
    if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82)) return "rain"
    if (c === 71 || c === 73 || c === 75 || c === 77 || c === 85 || c === 86) return "snow"
    return "cloud"
}

// The M3E shape that stands for a kind of weather, for the badge that holds its symbol (the shape morphs when the
// weather changes): a sunburst for clear, a cookie for cloud, a squircle for fog, a clover for rain, a hexagon for snow,
// a burst for a storm.
function weatherShape(kind) {
    switch (kind) {
        case "clear": return "sunny"
        case "fog":   return "squircle"
        case "rain":  return "clover"
        case "snow":  return "hexagon"
        case "storm": return "burst"
        default:      return "cookie9"
    }
}

// Whether a locale time format is a 12-hour one: it carries an AM/PM marker ("h:mm AP", "hh:mm:ss a").
function isTwelveHour(format) {
    return /(^|[^A-Za-z'])(ap|a)([^A-Za-z']|$)/i.test(String(format || ""))
}

// A day's low-to-high as a bar along the week's own range: where the bar starts and ends, 0..1. `lo` / `hi` are the
// week's lowest low and highest high. A flat week is a full bar; a day outside the range is clamped.
function rangeBar(min, max, lo, hi) {
    var span = hi - lo
    if (!(span > 0)) return { from: 0, to: 1 }
    var a = Math.max(0, Math.min(1, (min - lo) / span))
    var b = Math.max(a, Math.min(1, (max - lo) / span))
    return { from: a, to: b }
}

// The settings page a Dashboard switch's right-click opens (toggles.js ids); one with none has no page.
var SWITCH_PAGES = {
    wifi:       "NetworkPage.qml",
    bluetooth:  "BluetoothPage.qml",
    nightlight: "NightLightPage.qml",
    mute:       "SoundPage.qml",
    micMute:    "SoundPage.qml",
    theme:      "AppearancePage.qml"
}
function switchPage(id) { return SWITCH_PAGES.hasOwnProperty(id) ? SWITCH_PAGES[id] : "" }

// How loaded a reading is, for its ring's tone: "calm" below 75%, "busy" to 90%, "hot" from there.
function loadTone(v) {
    var n = Number(v) || 0
    return n >= 0.9 ? "hot" : n >= 0.75 ? "busy" : "calm"
}
