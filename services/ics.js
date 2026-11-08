.pragma library

// ── ics.js ────────────────────────────────────────────────────────────────────
// Reads an iCalendar (RFC 5545) feed into plain event objects, and expands
// recurring ones into the occurrences that fall inside a window. Used by
// services/Calendar.qml; tested by `bun scripts/test-ics.js`.
//
// ── Why hand-rolled ───────────────────────────────────────────────────────────
// The only input is a calendar feed URL (a Google/Outlook/school timetable export),
// and nothing that parses ICS is installed by default — no khal, no python
// icalendar. The subset real exports use is small: VEVENT, DTSTART/DTEND/DURATION,
// RRULE, EXDATE, RECURRENCE-ID, STATUS. Everything else is ignored, never an error.
//
// ── What it does NOT do: time zones ───────────────────────────────────────────
// Qt's JS engine has no Intl, so there is no tz database to convert with. A
// `DTSTART;TZID=Europe/Paris:…` is read as LOCAL wall time — correct whenever the
// calendar's zone is the machine's, which for a personal timetable it almost always
// is. `…Z` (UTC) times are converted properly.
//
// ── Bounded, because the feed is someone else's file ──────────────────────────
// A `FREQ=DAILY` with no end, dated 1900, is valid ICS. Expansion skips ahead to the
// window where it can, caps iterations per event, and caps the total. Malformed
// lines are skipped; parse() never throws on garbage.
// ─────────────────────────────────────────────────────────────────────────────

const _MAX_EVENTS      = 20000
const _MAX_ITERATIONS  = 20000   // candidate dates examined per event
const _MAX_OCCURRENCES = 20000   // total, across all events
const _DAY_MS = 86400000

const _WEEKDAYS = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 }

// ── Lexing ────────────────────────────────────────────────────────────────────
// Lines longer than 75 octets are folded: CRLF followed by one space or tab.
function _unfold(text) {
    return String(text).replace(/\r\n|\r/g, "\n").replace(/\n[ \t]/g, "").split("\n")
}

// "NAME;P=V;Q=\"a:b\":value" → { name, params, value }. The first colon OUTSIDE a
// quoted parameter separates the head from the value — the value itself may hold
// more colons (URLs, times in descriptions).
function _splitLine(line) {
    let i = 0, quoted = false
    for (; i < line.length; i++) {
        const c = line[i]
        if (c === '"') quoted = !quoted
        else if (c === ":" && !quoted) break
    }
    if (i >= line.length) return null
    const parts = line.slice(0, i).split(";")
    const params = {}
    for (let k = 1; k < parts.length; k++) {
        const eq = parts[k].indexOf("=")
        if (eq > 0)
            params[parts[k].slice(0, eq).toUpperCase()] = parts[k].slice(eq + 1).replace(/^"|"$/g, "")
    }
    return { name: parts[0].toUpperCase(), params: params, value: line.slice(i + 1) }
}

function _unescape(s) {
    return String(s).replace(/\\([\\;,nN])/g, function (m, c) {
        return (c === "n" || c === "N") ? "\n" : c
    })
}

// ── Values ────────────────────────────────────────────────────────────────────
// → { ms, allDay } or null. See the header on TZID.
function parseDate(value) {
    const v = String(value).trim()
    let m = /^(\d{4})(\d{2})(\d{2})$/.exec(v)
    if (m) {
        if (+m[2] < 1 || +m[2] > 12 || +m[3] < 1 || +m[3] > 31) return null
        return { ms: new Date(+m[1], +m[2] - 1, +m[3]).getTime(), allDay: true }
    }
    m = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$/.exec(v)
    if (!m) return null
    const y = +m[1], mo = +m[2] - 1, d = +m[3], h = +m[4], mi = +m[5], s = +m[6]
    if (mo > 11 || d < 1 || d > 31 || h > 23 || mi > 59 || s > 60) return null
    const ms = m[7] ? Date.UTC(y, mo, d, h, mi, s) : new Date(y, mo, d, h, mi, s).getTime()
    return isNaN(ms) ? null : { ms: ms, allDay: false }
}

// "PT1H30M", "P1D", "-P1W" → milliseconds, or null.
function parseDuration(value) {
    const v = String(value).trim()
    const m = /^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$/.exec(v)
    if (!m || /^[+-]?PT?$/.test(v)) return null
    const secs = (+(m[2] || 0)) * 604800 + (+(m[3] || 0)) * 86400
               + (+(m[4] || 0)) * 3600 + (+(m[5] || 0)) * 60 + (+(m[6] || 0))
    return (m[1] === "-" ? -1 : 1) * secs * 1000
}

// Calendar-day arithmetic in local time, so an all-day or recurring event keeps its
// wall-clock time across a DST change instead of drifting by an hour.
function _addDays(ms, n) {
    const d = new Date(ms)
    return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n,
                    d.getHours(), d.getMinutes(), d.getSeconds()).getTime()
}

function parseRRule(value) {
    const r = { freq: "", interval: 1, count: 0, until: null, byday: [], bymonthday: [] }
    const parts = String(value).split(";")
    for (let i = 0; i < parts.length; i++) {
        const eq = parts[i].indexOf("=")
        if (eq < 0) continue
        const k = parts[i].slice(0, eq).trim().toUpperCase()
        const v = parts[i].slice(eq + 1).trim()
        if (k === "FREQ") r.freq = v.toUpperCase()
        else if (k === "INTERVAL") r.interval = Math.max(1, parseInt(v, 10) || 1)
        else if (k === "COUNT") r.count = Math.max(0, parseInt(v, 10) || 0)
        else if (k === "UNTIL") {
            const d = parseDate(v)
            // A date-only UNTIL includes that whole day.
            r.until = d ? (d.allDay ? _addDays(d.ms, 1) - 1 : d.ms) : null
        } else if (k === "BYDAY") {
            r.byday = v.split(",").map(function (x) {
                const mm = /^([+-]?\d{1,2})?(SU|MO|TU|WE|TH|FR|SA)$/i.exec(x.trim())
                return mm ? { n: mm[1] ? parseInt(mm[1], 10) : 0, wd: _WEEKDAYS[mm[2].toUpperCase()] } : null
            }).filter(function (x) { return x !== null })
        } else if (k === "BYMONTHDAY") {
            r.bymonthday = v.split(",").map(function (x) { return parseInt(x, 10) })
                            .filter(function (x) { return x >= -31 && x <= 31 && x !== 0 })
        }
    }
    return ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].indexOf(r.freq) >= 0 ? r : null
}

// ── Parsing ───────────────────────────────────────────────────────────────────
// → [{ uid, summary, location, description, start, end, allDay, rrule, exdates,
//      recurrenceId, cancelled }], times in epoch ms.
function parse(text) {
    const lines = _unfold(text === undefined || text === null ? "" : text)
    const events = []
    let cur = null, depth = 0   // depth: components nested inside the VEVENT (VALARM)
    for (let i = 0; i < lines.length; i++) {
        if (lines[i] === "") continue
        const p = _splitLine(lines[i])
        if (!p) continue
        if (p.name === "BEGIN") {
            if (cur) depth++
            else if (p.value.trim().toUpperCase() === "VEVENT") { cur = { props: {}, exdates: [] }; depth = 0 }
            continue
        }
        if (p.name === "END") {
            if (!cur) continue
            if (depth > 0) { depth--; continue }
            const e = _finish(cur)
            if (e) events.push(e)
            cur = null
            if (events.length >= _MAX_EVENTS) break
            continue
        }
        if (!cur || depth > 0) continue
        if (p.name === "EXDATE") {
            const xs = p.value.split(",")
            for (let k = 0; k < xs.length; k++) {
                const d = parseDate(xs[k])
                if (d) cur.exdates.push(d.ms)
            }
        } else if (!(p.name in cur.props)) {
            cur.props[p.name] = p
        }
    }
    return events
}

function _finish(c) {
    const P = c.props
    if (!P.DTSTART) return null
    const s = parseDate(P.DTSTART.value)
    if (!s) return null

    let end = null
    if (P.DTEND) {
        const e = parseDate(P.DTEND.value)
        if (e) end = e.ms
    } else if (P.DURATION) {
        const d = parseDuration(P.DURATION.value)
        if (d !== null) end = s.ms + d
    }
    // Missing or backwards: an all-day event lasts its day, a timed one is an instant.
    if (end === null || end < s.ms) end = s.allDay ? _addDays(s.ms, 1) : s.ms

    const rid = P["RECURRENCE-ID"] ? parseDate(P["RECURRENCE-ID"].value) : null
    return {
        uid:          P.UID ? P.UID.value.trim() : "",
        summary:      P.SUMMARY ? _unescape(P.SUMMARY.value).trim() : "",
        location:     P.LOCATION ? _unescape(P.LOCATION.value).trim() : "",
        description:  P.DESCRIPTION ? _unescape(P.DESCRIPTION.value).trim() : "",
        start:        s.ms,
        end:          end,
        allDay:       s.allDay,
        rrule:        P.RRULE ? parseRRule(P.RRULE.value) : null,
        exdates:      c.exdates,
        recurrenceId: rid ? rid.ms : null,
        cancelled:    !!P.STATUS && P.STATUS.value.trim().toUpperCase() === "CANCELLED"
    }
}

// ── Recurrence ────────────────────────────────────────────────────────────────
// Calls emit(ms) for each occurrence start, in order, from DTSTART until COUNT,
// UNTIL, or `toMs`. Without COUNT the whole periods before `fromMs` are skipped
// arithmetically; with COUNT they can't be, because every earlier one counts.
function _eachStart(ev, fromMs, toMs, emit) {
    const r = ev.rrule
    if (!r) { emit(ev.start); return }

    const d0 = new Date(ev.start)
    const y0 = d0.getFullYear(), m0 = d0.getMonth(), day0 = d0.getDate()
    const H = d0.getHours(), Mi = d0.getMinutes(), S = d0.getSeconds()
    function at(y, m, d) { return new Date(y, m, d, H, Mi, S).getTime() }

    let n = 0, iter = 0
    // false = stop generating.
    function take(ms) {
        if (++iter > _MAX_ITERATIONS) return false
        if (ms < ev.start) return true
        if (r.until !== null && ms > r.until) return false
        if (ms > toMs) return false
        n++
        emit(ms)
        return !(r.count && n >= r.count)
    }
    function unsorted(xs) { return xs.filter(function (x, i) { return xs.indexOf(x) === i }).sort(function (a, b) { return a - b }) }

    const skipping = !r.count && fromMs > ev.start
    const daysBehind = skipping ? Math.floor((fromMs - ev.start) / _DAY_MS) - 7 : 0

    if (r.freq === "DAILY") {
        const wds = r.byday.filter(function (b) { return b.n === 0 }).map(function (b) { return b.wd })
        let k = daysBehind > 0 ? Math.floor(daysBehind / r.interval) * r.interval : 0
        for (;; k += r.interval) {
            const ms = at(y0, m0, day0 + k)
            if (wds.length && wds.indexOf(new Date(ms).getDay()) < 0) {
                if (++iter > _MAX_ITERATIONS || ms > toMs) return
                continue
            }
            if (!take(ms)) return
        }
    }

    if (r.freq === "WEEKLY") {
        // Weeks start on Monday (WKST's default).
        const weekStart = day0 - (d0.getDay() + 6) % 7
        const offs = unsorted(r.byday.length
            ? r.byday.map(function (b) { return (b.wd + 6) % 7 })
            : [(d0.getDay() + 6) % 7])
        const step = 7 * r.interval
        let w = daysBehind > 0 ? Math.floor(daysBehind / step) * step : 0
        for (;; w += step)
            for (let i = 0; i < offs.length; i++)
                if (!take(at(y0, m0, weekStart + w + offs[i]))) return
    }

    if (r.freq === "MONTHLY") {
        const monthsBehind = skipping
            ? (new Date(fromMs).getFullYear() - y0) * 12 + new Date(fromMs).getMonth() - m0 - 1 : 0
        let k = monthsBehind > 0 ? Math.floor(monthsBehind / r.interval) * r.interval : 0
        for (;; k += r.interval) {
            const first = new Date(y0, m0 + k, 1)
            const Y = first.getFullYear(), M = first.getMonth()
            const dim = new Date(Y, M + 1, 0).getDate()
            let days = []
            if (r.bymonthday.length) {
                days = r.bymonthday.map(function (x) { return x > 0 ? x : dim + 1 + x })
            } else if (r.byday.length) {
                const firstWd = first.getDay()
                r.byday.forEach(function (b) {
                    const firstHit = 1 + (b.wd - firstWd + 7) % 7
                    const hits = []
                    for (let d = firstHit; d <= dim; d += 7) hits.push(d)
                    if (b.n === 0) days = days.concat(hits)
                    else if (b.n > 0 && b.n <= hits.length) days.push(hits[b.n - 1])
                    else if (b.n < 0 && -b.n <= hits.length) days.push(hits[hits.length + b.n])
                })
            } else {
                days = [day0]
            }
            days = unsorted(days.filter(function (d) { return d >= 1 && d <= dim }))
            if (days.length === 0) {
                // Day 31 in a 30-day month: RFC 5545 skips it rather than clamping.
                if (++iter > _MAX_ITERATIONS || first.getTime() > toMs) return
                continue
            }
            for (let i = 0; i < days.length; i++)
                if (!take(at(Y, M, days[i]))) return
        }
    }

    if (r.freq === "YEARLY") {
        const yearsBehind = skipping ? new Date(fromMs).getFullYear() - y0 - 1 : 0
        let k = yearsBehind > 0 ? Math.floor(yearsBehind / r.interval) * r.interval : 0
        for (;; k += r.interval) {
            const ms = at(y0 + k, m0, day0)
            // 29 February in a non-leap year doesn't exist, and is skipped.
            if (new Date(ms).getMonth() !== m0) {
                if (++iter > _MAX_ITERATIONS || ms > toMs) return
                continue
            }
            if (!take(ms)) return
        }
    }
}

// → [{ summary, location, description, start, end, allDay }] overlapping
// [fromMs, toMs), sorted by start.
function expand(events, fromMs, toMs) {
    // An instance with RECURRENCE-ID replaces the series occurrence it names. Keyed
    // by source as well as UID: the same event subscribed through two feeds is two
    // series, and one feed's moved instance must not delete the other's.
    const seriesKey = function (e) { return (e.source || "") + " " + e.uid }
    const moved = {}
    for (let i = 0; i < events.length; i++) {
        const e = events[i]
        if (e.recurrenceId !== null && e.uid !== "") {
            if (!moved[seriesKey(e)]) moved[seriesKey(e)] = {}
            moved[seriesKey(e)][e.recurrenceId] = true
        }
    }

    const out = []
    for (let i = 0; i < events.length && out.length < _MAX_OCCURRENCES; i++) {
        const e = events[i]
        const dur = e.end - e.start
        const days = Math.round(dur / _DAY_MS)
        const skip = {}
        e.exdates.forEach(function (x) { skip[x] = true })
        const replaced = (e.rrule && e.recurrenceId === null && moved[seriesKey(e)]) || null

        _eachStart(e, fromMs, toMs, function (ms) {
            if (e.cancelled || skip[ms] || (replaced && replaced[ms])) return
            if (out.length >= _MAX_OCCURRENCES) return
            const end = e.allDay ? _addDays(ms, days) : ms + dur
            const overlaps = ms < toMs && (end > fromMs || (end === ms && ms >= fromMs))
            if (!overlaps) return
            // `uid` and `source` let the panel colour an occurrence by its feed and
            // open a local one for editing.
            out.push({ summary: e.summary, location: e.location, description: e.description,
                       start: ms, end: end, allDay: e.allDay,
                       uid: e.uid, source: e.source || "", recurring: !!e.rrule })
        })
    }
    out.sort(function (a, b) { return a.start - b.start || a.end - b.end })
    return out
}

// ── Queries the panel asks ────────────────────────────────────────────────────
function dayKey(ms) {
    const d = new Date(ms)
    const p = function (x) { return x < 10 ? "0" + x : "" + x }
    return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate())
}

function _touchesDay(o, dayStart, dayEnd) {
    return o.start < dayEnd && (o.end > dayStart || (o.end === o.start && o.start >= dayStart))
}

// Occurrences touching local day (y, m 0-based, d).
function onDay(occ, y, m, d) {
    const a = new Date(y, m, d).getTime(), b = new Date(y, m, d + 1).getTime()
    return occ.filter(function (o) { return _touchesDay(o, a, b) })
}

// Calls fn(dayKey) for every local day an occurrence covers. A multi-day event
// marks each day (capped, so a year-long event can't stall the loop).
function _eachDay(o, fn) {
    const s = new Date(o.start)
    for (let k = 0; k < 366; k++) {
        const a = new Date(s.getFullYear(), s.getMonth(), s.getDate() + k).getTime()
        if (k > 0 && a >= o.end) break
        fn(dayKey(a))
    }
}

// { "YYYY-MM-DD": count }.
function dayCounts(occ) {
    const out = {}
    for (let i = 0; i < occ.length; i++)
        _eachDay(occ[i], function (key) { out[key] = (out[key] || 0) + 1 })
    return out
}

// { "YYYY-MM-DD": [source, …] } — the distinct sources with something that day, in
// first-seen order, at most `limit` — the month grid's coloured dots.
function daySources(occ, limit) {
    const cap = limit > 0 ? limit : 3
    const out = {}
    for (let i = 0; i < occ.length; i++) {
        const src = occ[i].source || ""
        _eachDay(occ[i], function (key) {
            const list = out[key] || (out[key] = [])
            if (list.length < cap && list.indexOf(src) < 0) list.push(src)
        })
    }
    return out
}

// The first day, today or later, with something still to come — the events row's
// "Tuesday, 19 May (Tomorrow)". → { day: dayStartMs, items } or null.
function nextDay(occ, nowMs) {
    for (let i = 0; i < occ.length; i++) {
        const o = occ[i]
        if (o.end <= nowMs && !(o.end === o.start && o.start >= nowMs)) continue
        const s = new Date(Math.max(o.start, nowMs))
        const y = s.getFullYear(), m = s.getMonth(), d = s.getDate()
        return {
            day: new Date(y, m, d).getTime(),
            items: onDay(occ, y, m, d).filter(function (x) { return x.end > nowMs || x.start >= nowMs })
        }
    }
    return null
}

// The next TIMED thing — running now, or starting within `horizonMs` — for the clock panel's
// "next up" line. All-day entries are not "up next": they have no moment to count down to.
// → { summary, start, end, live, minutes, when } or null. `when` is the words for it:
// "now · until 11:00", "in 25 min", "at 15:30", "tomorrow 09:00", "Fri 09:00".
// `occ` is expand()'s output (sorted by start); a long event already under way is found
// before one that merely starts sooner, which is the right order — it is the live one.
function nextUp(occ, nowMs, horizonMs) {
    const p = function (x) { return x < 10 ? "0" + x : "" + x }
    const hm = function (ms) { const d = new Date(ms); return p(d.getHours()) + ":" + p(d.getMinutes()) }
    const dayStart = function (ms) { const d = new Date(ms); return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime() }
    const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    for (let i = 0; i < (occ || []).length; i++) {
        const o = occ[i]
        if (o.allDay || o.end <= nowMs) continue
        if (o.start >= nowMs + horizonMs) return null     // sorted: nothing later can be sooner
        const live = o.start <= nowMs
        const minutes = live ? 0 : Math.ceil((o.start - nowMs) / 60000)
        // Whole local days apart, by calendar date: 23 hours ahead can still be "tomorrow".
        const days = Math.round((dayStart(o.start) - dayStart(nowMs)) / 86400000)
        const when = live ? "now" + (o.end > o.start ? " · until " + hm(o.end) : "")
                   : minutes < 60 ? "in " + minutes + " min"
                   : days === 0 ? "at " + hm(o.start)
                   : days === 1 ? "tomorrow " + hm(o.start)
                   : WEEKDAYS[new Date(o.start).getDay()] + " " + hm(o.start)
        return { summary: o.summary || "", start: o.start, end: o.end, live: live, minutes: minutes, when: when }
    }
    return null
}

// ══ Subscribed calendars ══════════════════════════════════════════════════════
// A feed is a URL the user pastes (Google's "secret address in iCal format", Outlook's "published
// calendar", any .ics). It becomes a curl ARGUMENT — never shell text — and curl follows
// redirects, so the only thing to check here is that it is a web address and nothing else (no
// file:, no ftp:, no option smuggled in as a "URL" starting with a dash).
// → { ok, url } | { ok: false, error }. `webcal://` is just https under another name.
function feedUrl(raw) {
    const t = String(raw === undefined || raw === null ? "" : raw).trim()
    if (t === "") return { ok: false, error: "Paste the calendar's address" }
    if (t.length > 2000) return { ok: false, error: "That address is too long" }
    if (/\s/.test(t)) return { ok: false, error: "The address has a space in it" }
    const url = t.replace(/^webcals?:\/\//i, "https://")
    if (!/^https?:\/\/[^\/?#]+/i.test(url)) return { ok: false, error: "It has to be a web address (https://…)" }
    return { ok: true, url: url }
}

// ══ Writing ═══════════════════════════════════════════════════════════════════
// The local calendar is stored as a real .ics file, so it can be imported anywhere
// else as-is. Only what parse() models is written: an event created here has no
// alarms or attendees to lose.

function _escape(s) {
    return String(s === undefined || s === null ? "" : s)
        .replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,")
        .replace(/\r\n|\r|\n/g, "\\n")
}

function _utf8Len(ch) {
    const c = ch.codePointAt(0)
    return c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4
}

// RFC 5545 §3.1: a line over 75 OCTETS folds — CRLF plus one space. Counted in
// UTF-8 bytes and walked by code point, so a multi-byte character (an accent, an
// emoji) is never cut in half across the fold.
function _fold(line) {
    const out = []
    let cur = "", len = 0
    for (const ch of line) {
        const n = _utf8Len(ch)
        if (len + n > 75) {
            out.push(cur)
            cur = " "
            len = 1
        }
        cur += ch
        len += n
    }
    out.push(cur)
    return out.join("\r\n")
}

// Local wall time, or a bare date for all-day — the same model parse() reads.
function formatDate(ms, allDay) {
    const d = new Date(ms)
    const p = function (x) { return (x < 10 ? "0" : "") + x }
    const day = d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate())
    return allDay ? day : day + "T" + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds())
}

function _formatUtc(ms) {
    return new Date(ms).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "")
}

// The rule object parseRRule() returns → its RRULE value, or "" for none.
function rruleString(r) {
    if (!r || ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].indexOf(r.freq) < 0) return ""
    const days = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
    let s = "FREQ=" + r.freq
    if (r.interval > 1) s += ";INTERVAL=" + Math.floor(r.interval)
    if (r.count > 0) s += ";COUNT=" + Math.floor(r.count)
    else if (isFinite(r.until) && r.until !== null) s += ";UNTIL=" + formatDate(r.until, false)
    if (r.byday && r.byday.length)
        s += ";BYDAY=" + r.byday.map(function (b) { return (b.n ? b.n : "") + days[b.wd] }).join(",")
    return s
}

// events: [{ uid, summary, location, description, start, end, allDay, rrule, exdates }]
function serialize(events, stampMs) {
    const lines = ["BEGIN:VCALENDAR", "VERSION:2.0",
                   "PRODID:-//quickshell-quicktest//calendar//EN", "CALSCALE:GREGORIAN"]
    ;(events || []).forEach(function (e) {
        const allDay = !!e.allDay
        lines.push("BEGIN:VEVENT")
        // A UID is opaque, but a line break inside one would end the property early.
        lines.push("UID:" + String(e.uid).replace(/[\r\n]/g, ""))
        lines.push("DTSTAMP:" + _formatUtc(stampMs))
        lines.push((allDay ? "DTSTART;VALUE=DATE:" : "DTSTART:") + formatDate(e.start, allDay))
        lines.push((allDay ? "DTEND;VALUE=DATE:"   : "DTEND:")   + formatDate(e.end, allDay))
        lines.push("SUMMARY:" + _escape(e.summary))
        if (e.location)    lines.push("LOCATION:" + _escape(e.location))
        if (e.description) lines.push("DESCRIPTION:" + _escape(e.description))
        const rr = rruleString(e.rrule)
        if (rr) lines.push("RRULE:" + rr)
        ;(e.exdates || []).forEach(function (x) {
            lines.push((allDay ? "EXDATE;VALUE=DATE:" : "EXDATE:") + formatDate(x, allDay))
        })
        lines.push("END:VEVENT")
    })
    lines.push("END:VCALENDAR")
    return lines.map(_fold).join("\r\n") + "\r\n"
}

// ══ Input from the event editor ═══════════════════════════════════════════════
// The editor is a text field, so this is a trust boundary: nothing reaches the
// file that these haven't accepted.

// "8", "08", "830", "0830", "8:30", "8.30", "8h30", "20h" → { h, m } or null.
function parseTime(s) {
    const v = String(s === undefined || s === null ? "" : s).trim().toLowerCase()
    let h, mi
    let m = /^(\d{1,2})(?:[:.h](\d{2})?)?$/.exec(v)
    if (m) {
        h = +m[1]
        mi = m[2] ? +m[2] : 0
    } else {
        m = /^(\d{1,2})(\d{2})$/.exec(v)
        if (!m) return null
        h = +m[1]
        mi = +m[2]
    }
    return h > 23 || mi > 59 ? null : { h: h, m: mi }
}

const MAX_TEXT = 500

// A draft from the editor → { ok, error, event }. The draft's day is local
// midnight ms; times are "HH:MM"-ish strings. All-day events end the next day
// (DTEND is exclusive). A repeat is "", "DAILY", "WEEKLY", "MONTHLY" or "YEARLY".
function validateEvent(d) {
    const fail = function (msg) { return { ok: false, error: msg, event: null } }
    if (!d) return fail("Nothing to save")
    const summary = String(d.summary || "").trim()
    if (summary === "") return fail("Give it a title")
    if (summary.length > MAX_TEXT) return fail("The title is too long")
    const location = String(d.location || "").trim()
    if (location.length > MAX_TEXT) return fail("The location is too long")
    if (!isFinite(d.day)) return fail("Pick a day")

    const base = new Date(d.day)
    const y = base.getFullYear(), mo = base.getMonth(), da = base.getDate()
    let start, end
    if (d.allDay) {
        start = new Date(y, mo, da).getTime()
        end = new Date(y, mo, da + 1).getTime()
    } else {
        const s = parseTime(d.startTime), e = parseTime(d.endTime)
        if (!s) return fail("Start time isn't a time")
        if (!e) return fail("End time isn't a time")
        start = new Date(y, mo, da, s.h, s.m).getTime()
        end = new Date(y, mo, da, e.h, e.m).getTime()
        // 22:00 → 01:00 is an evening that runs past midnight, not a mistake.
        if (end <= start) end = new Date(y, mo, da + 1, e.h, e.m).getTime()
    }

    const freq = String(d.repeat || "")
    if (freq !== "" && ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"].indexOf(freq) < 0)
        return fail("Unknown repeat")

    return { ok: true, error: "", event: {
        uid: d.uid || "", summary: summary, location: location,
        description: String(d.description || "").trim().slice(0, MAX_TEXT),
        start: start, end: end, allDay: !!d.allDay,
        rrule: freq === "" ? null
             : { freq: freq, interval: 1, count: 0, until: null, byday: [], bymonthday: [] },
        exdates: [], recurrenceId: null, cancelled: false, source: "local"
    } }
}

// A fresh UID. The randomness is passed in, so this stays a pure function.
function newUid(nowMs, random) {
    return nowMs.toString(36) + "-" + String(random).replace(/[^a-z0-9]/gi, "") + "@quickshell-quicktest"
}
