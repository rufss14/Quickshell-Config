.pragma library

// ── quickadd.js ───────────────────────────────────────────────────────────────
// "dentist tomorrow 9am" → an item with a title and a moment. The clock panel's quick-add reads
// what you type with this while you type it, shows what it understood, and on Enter makes an
// event (or a reminder at that time). English only, and deliberately a small grammar: it
// finds the words that are unmistakably a date or a time, takes them OUT of the title, and
// leaves everything else alone and in order — so a phrase it does not understand is just a title.
// Tested by `bun scripts/test-quickadd.js`.
//
// What it knows (case-insensitive; the order of the words does not matter):
//   day     today · tonight (20:00 unless a time is given) · tomorrow / tmrw · monday … sunday (mon…sun;
//           "next fri" and "this fri" mean the coming one, and today's name means next week's)
//           · in 3 days / 2 weeks · 12 oct / oct 12 / 12th of october · 12/10 (day first) · 2026-10-12
//   time    9am · 9:30pm · 21:00 · at 9 (1–6 reads as the afternoon) · noon · midnight
//   length  9am-10:30am · 9:00-10:00 · from 9 to 10 · at 9-10 · for 2h · for 90 min · all day
//   in      in 20 min · in 2 hours   (a moment from now, no day word needed)
//   repeat  daily · weekly · monthly · yearly · every day / week / month / year / monday …
//
// A bare number is never a time ("table for 2", "room 101", "meeting 9-10"): a time needs am/pm,
// a colon, or "at"; a bare range needs "from" or "at" in front.
//
// A time alone means today if it is still ahead, tomorrow if not. A day alone is an all-day item.
// A repeat alone ("water plants weekly") is an all-day item starting today.
//
// → { ok, summary, hasDate, hasTime, allDay, start, end, repeat, relative } — `start` / `end` in epoch ms
//   (end = start + 1 h when no length was given), `repeat` "" | DAILY | WEEKLY | MONTHLY | YEARLY.
//   `start` is null when nothing date-like was found. `ok` is false when no title is left.
// ─────────────────────────────────────────────────────────────────────────────

const DAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
const MONTHS = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]

function _dayIndex(w) { return w.length >= 3 ? DAYS.indexOf(w.toLowerCase().slice(0, 3)) : -1 }
// A month by its full name or any prefix of at least three letters ("oct", "sept").
function _monthIndex(w) {
    w = w.toLowerCase()
    if (w.length < 3) return -1
    for (let i = 0; i < 12; i++) if (MONTHS[i].indexOf(w) === 0) return i
    return -1
}

// Removes the first match of `re` for which `ok(match)` holds (default: any), leaving the other
// words where they were. → [match | null, rest]
function _take(s, re, ok) {
    const m = re.exec(s)
    if (!m || (ok && !ok(m))) return [null, s]
    return [m, s.slice(0, m.index) + " " + s.slice(m.index + m[0].length)]
}

// "9", "9:30", "21:00" + optional am/pm → { h, m } or null.
function _clock(h, m, ap) {
    h = parseInt(h, 10); m = m === undefined || m === "" ? 0 : parseInt(m, 10)
    if (!isFinite(h) || !isFinite(m) || m > 59) return null
    if (ap) {
        ap = ap.toLowerCase().replace(/\./g, "")
        if (h < 1 || h > 12) return null
        if (ap === "pm" && h < 12) h += 12
        if (ap === "am" && h === 12) h = 0
    } else if (h > 23) return null
    return { h: h, m: m }
}

// A day-and-month with an optional year. A date already behind us this year means NEXT year's;
// 31 February (anything that rolls into another month) is not a date → null.
function _dateFrom(now, month, dom, yearStr) {
    if (!(dom >= 1 && dom <= 31) || !(month >= 0 && month <= 11)) return null
    const y = yearStr ? parseInt(yearStr, 10) : now.getFullYear()
    let d = new Date(y, month, dom)
    if (d.getMonth() !== month) return null
    if (!yearStr && d.getTime() < new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime())
        d = new Date(y + 1, month, dom)
    return d
}

function parse(text, nowMs) {
    const now = new Date(nowMs)
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    const plusDays = function (n) { return new Date(today.getFullYear(), today.getMonth(), today.getDate() + n) }
    let s = " " + String(text === undefined || text === null ? "" : text) + " "
    let m
    let day = null, time = null, endTime = null, durMin = 0, allDay = false, repeat = "", weekday = -1, rel = null

    // ── repeat ────────────────────────────────────────────────────────────────
    ;[m, s] = _take(s, /\b(daily|weekly|monthly|yearly|annually)\b/i)
    if (m) repeat = { daily: "DAILY", weekly: "WEEKLY", monthly: "MONTHLY", yearly: "YEARLY", annually: "YEARLY" }[m[1].toLowerCase()]
    if (!repeat) {
        ;[m, s] = _take(s, /\bevery\s+(day|week|month|year|mon(?:day)?|tue(?:s|sday)?|wed(?:nesday)?|thu(?:rs|rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)\b/i)
        if (m) {
            const w = m[1].toLowerCase()
            if (w === "day") repeat = "DAILY"
            else if (w === "week") repeat = "WEEKLY"
            else if (w === "month") repeat = "MONTHLY"
            else if (w === "year") repeat = "YEARLY"
            else { repeat = "WEEKLY"; weekday = _dayIndex(w) }
        }
    }

    // ── all day, and a length ─────────────────────────────────────────────────
    ;[m, s] = _take(s, /\ball[\s-]day\b/i)
    if (m) allDay = true
    ;[m, s] = _take(s, /\bfor\s+(\d+(?:\.\d+)?)\s*(h|hr|hrs|hours?|m|mins?|minutes?)\b/i)
    if (m) durMin = Math.round(parseFloat(m[1]) * (/^h/i.test(m[2]) ? 60 : 1))

    // ── in N units ────────────────────────────────────────────────────────────
    ;[m, s] = _take(s, /\bin\s+(\d+)\s*(m|mins?|minutes?|h|hrs?|hours?|d|days?|w|wks?|weeks?)\b/i)
    if (m) {
        const n = parseInt(m[1], 10), u = m[2].toLowerCase()
        if (/^m/.test(u)) rel = new Date(nowMs + n * 60000)
        else if (/^h/.test(u)) rel = new Date(nowMs + n * 3600000)
        else day = plusDays(/^d/.test(u) ? n : n * 7)
    }

    // ── a time range ──────────────────────────────────────────────────────────
    // A suffix on one end is the other's too ("9-10pm" is 9pm–10pm); "11-1pm" can only mean 11am.
    ;[m, s] = _take(s, /\b(from\s+|at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\s*(?:-|–|—|to|until|till)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?(?![\d:])/i,
        function (r) { return !!(r[1] || r[3] || r[4] || r[6] || r[7]) })
    if (m) {
        const ap1 = m[4] || m[7] || "", ap2 = m[7] || m[4] || ""
        let a = _clock(m[2], m[3], ap1)
        const b = _clock(m[5], m[6], ap2)
        if (a && b && !m[4] && m[7] && /^p/i.test(m[7]) && (a.h * 60 + a.m) > (b.h * 60 + b.m)) a = _clock(m[2], m[3], "am")
        if (a && b) { time = a; endTime = b }
    }

    // ── a single time ─────────────────────────────────────────────────────────
    if (!time) {
        ;[m, s] = _take(s, /\b(noon|midday|midnight)\b/i)
        if (m) time = /midnight/i.test(m[1]) ? { h: 0, m: 0 } : { h: 12, m: 0 }
    }
    if (!time) {
        ;[m, s] = _take(s, /\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)(?![a-z])/i,
            function (r) { return _clock(r[1], r[2], r[3]) !== null })
        if (m) time = _clock(m[1], m[2], m[3])
    }
    if (!time) {
        ;[m, s] = _take(s, /\b(?:at\s+)?([01]?\d|2[0-3]):([0-5]\d)\b/i)
        if (m) time = _clock(m[1], m[2], "")
    }
    if (!time) {
        ;[m, s] = _take(s, /\bat\s+(\d{1,2})\b(?![\/:\d])/i, function (r) { return _clock(r[1], "", "") !== null })
        if (m) {
            const t = _clock(m[1], "", "")
            time = { h: t.h >= 1 && t.h <= 6 ? t.h + 12 : t.h, m: 0 }
        }
    }

    // ── a day ─────────────────────────────────────────────────────────────────
    if (!day) {
        ;[m, s] = _take(s, /\b(\d{4})-(\d{1,2})-(\d{1,2})\b/, function (r) {
            return _dateFrom(now, parseInt(r[2], 10) - 1, parseInt(r[3], 10), r[1]) !== null })
        if (m) day = _dateFrom(now, parseInt(m[2], 10) - 1, parseInt(m[3], 10), m[1])
    }
    if (!day) {
        ;[m, s] = _take(s, /\b(today|tonight|tomorrow|tmrw|tmr)\b/i)
        if (m) {
            const w = m[1].toLowerCase()
            day = plusDays(w === "today" || w === "tonight" ? 0 : 1)
            if (w === "tonight" && !time) time = { h: 20, m: 0 }
        }
    }
    if (!day) {
        const re = /\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?([a-z]{3,9})\.?(?:\s+(\d{4}))?\b/i
        ;[m, s] = _take(s, re, function (r) { return _monthIndex(r[2]) >= 0 && _dateFrom(now, _monthIndex(r[2]), parseInt(r[1], 10), r[3]) !== null })
        if (m) day = _dateFrom(now, _monthIndex(m[2]), parseInt(m[1], 10), m[3])
    }
    if (!day) {
        const re = /\b([a-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?\b/i
        ;[m, s] = _take(s, re, function (r) { return _monthIndex(r[1]) >= 0 && _dateFrom(now, _monthIndex(r[1]), parseInt(r[2], 10), r[3]) !== null })
        if (m) day = _dateFrom(now, _monthIndex(m[1]), parseInt(m[2], 10), m[3])
    }
    if (!day) {
        const re = /\b(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b/
        const year = function (r) { return r[3] ? String(r[3].length <= 2 ? 2000 + parseInt(r[3], 10) : r[3]) : undefined }
        ;[m, s] = _take(s, re, function (r) { return _dateFrom(now, parseInt(r[2], 10) - 1, parseInt(r[1], 10), year(r)) !== null })
        if (m) day = _dateFrom(now, parseInt(m[2], 10) - 1, parseInt(m[1], 10), year(m))
    }
    if (!day) {
        ;[m, s] = _take(s, /\b(?:(?:next|this|on)\s+)?(mon(?:day)?|tue(?:s|sday)?|wed(?:nesday)?|thu(?:rs|rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)\b/i)
        if (m) {
            const wd = _dayIndex(m[1])
            const ahead = (wd - now.getDay() + 7) % 7
            day = plusDays(ahead === 0 ? 7 : ahead)
        }
    }

    // ── the title: what is left, tidied ───────────────────────────────────────
    // Connectives stranded by what was taken out ("lunch with Sam on" + "friday"), and punctuation.
    let summary = s.replace(/\s+/g, " ").trim()
    for (let i = 0; i < 3; i++)
        summary = summary.replace(/^(?:on|at|from|by|in|for)\s+/i, "").replace(/\s+(?:on|at|from|by|in|for|until|till|to)$/i, "")
                         .replace(/^[,;:\-–—]+\s*|\s*[,;:\-–—]+$/g, "").trim()

    // ── the moment ────────────────────────────────────────────────────────────
    const dated = !!day || !!rel || repeat !== "" || !!time || allDay
    let start = null, end = null
    if (rel) {
        start = rel.getTime()
    } else if (dated) {
        let d = day
        if (!d && weekday >= 0) {
            // "every monday 7am", said on a Monday after 7: the next one.
            let ahead = (weekday - now.getDay() + 7) % 7
            if (ahead === 0 && time && new Date(today.getFullYear(), today.getMonth(), today.getDate(), time.h, time.m).getTime() <= nowMs) ahead = 7
            d = plusDays(ahead)
        }
        if (!d) {
            d = today
            // A time alone: today if it is still ahead, else tomorrow.
            if (time && !allDay && new Date(d.getFullYear(), d.getMonth(), d.getDate(), time.h, time.m).getTime() <= nowMs)
                d = plusDays(1)
        }
        if (allDay || !time) {
            allDay = true
            start = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
            end = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1).getTime()
        } else {
            start = new Date(d.getFullYear(), d.getMonth(), d.getDate(), time.h, time.m).getTime()
        }
    }
    if (start !== null && !allDay) {
        if (endTime) {
            const d = new Date(start)
            end = new Date(d.getFullYear(), d.getMonth(), d.getDate(), endTime.h, endTime.m).getTime()
            if (end <= start) end += 86400000          // "22:00-01:00"
        } else {
            end = start + (durMin > 0 ? durMin : 60) * 60000
        }
    }

    return { ok: summary !== "", summary: summary, hasDate: start !== null, hasTime: !!time || !!rel, allDay: allDay,
             start: start, end: end, repeat: repeat, relative: !!rel }
}

// How it reads back to the user: "Tomorrow, 09:00–10:00", "Tue 13 Oct (all day)", "in 20 min · 19:05".
function describe(r, nowMs) {
    if (!r || r.start === null) return ""
    const p = function (x) { return x < 10 ? "0" + x : "" + x }
    const hm = function (ms) { const d = new Date(ms); return p(d.getHours()) + ":" + p(d.getMinutes()) }
    const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    const mons = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    const d = new Date(r.start), now = new Date(nowMs)
    let out
    if (r.relative) {
        out = "in " + Math.max(1, Math.round((r.start - nowMs) / 60000)) + " min · " + hm(r.start)
    } else {
        const diff = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
                               - new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()) / 86400000)
        const word = diff === 0 ? "Today" : diff === 1 ? "Tomorrow" : days[d.getDay()] + " " + d.getDate() + " " + mons[d.getMonth()]
        out = r.allDay ? word + " (all day)" : word + ", " + hm(r.start) + (r.end > r.start ? "–" + hm(r.end) : "")
    }
    const rep = { DAILY: "every day", WEEKLY: "every week", MONTHLY: "every month", YEARLY: "every year" }[r.repeat]
    return rep ? out + " · " + rep : out
}
