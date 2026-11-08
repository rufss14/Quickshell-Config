.pragma library

// ── reminders.js ──────────────────────────────────────────────────────────────
// The logic behind the Calendar page's reminders: what a valid reminder is, the
// quick times ("in an hour", "this evening", "tomorrow morning"), which ones are due
// to notify, the order they're listed in, and the words for when. Used by
// services/Reminders.qml; tested by `bun scripts/test-reminders.js`.
//
// A reminder: { id, text, due, done, doneAt, notified, created }
//   due      — epoch ms, or 0 for "no time" (a plain to-do)
//   notified — it has already fired for this `due`; snoozing clears it
// Times are epoch ms and local wall-clock, like everything else in the calendar.
// ─────────────────────────────────────────────────────────────────────────────

const MAX_TEXT  = 200
const MAX_ITEMS = 500
const _HOUR = 3600 * 1000
const _DAY  = 24 * _HOUR

// ── Input ─────────────────────────────────────────────────────────────────────
// A text field is a trust boundary: nothing reaches the file these haven't accepted.

// → { ok, error, item }. `due` is ms or 0; `id` is supplied by the caller so this
// stays a pure function.
function create(text, due, nowMs, id) {
    const t = String(text === undefined || text === null ? "" : text).replace(/\s+/g, " ").trim()
    if (t === "") return { ok: false, error: "Write what to remember", item: null }
    if (t.length > MAX_TEXT) return { ok: false, error: "That's too long for a reminder", item: null }
    const d = Number(due) || 0
    if (d < 0 || !isFinite(d)) return { ok: false, error: "That time isn't valid", item: null }
    return { ok: true, error: "", item: {
        id: String(id), text: t, due: Math.round(d), done: false, doneAt: 0, notified: false, created: nowMs
    } }
}

// The quick times. → ms, or 0 for an unknown name.
//   hour     — an hour from now, rounded up to the next five minutes
//   evening  — 20:00 today, or tomorrow once it's past 19:30
//   tomorrow — 09:00 tomorrow
function presetDue(name, nowMs) {
    const n = new Date(nowMs)
    if (name === "hour") {
        const five = 5 * 60 * 1000
        return Math.ceil((nowMs + _HOUR) / five) * five
    }
    if (name === "evening") {
        const tonight = new Date(n.getFullYear(), n.getMonth(), n.getDate(), 20, 0).getTime()
        const cutoff  = new Date(n.getFullYear(), n.getMonth(), n.getDate(), 19, 30).getTime()
        return nowMs < cutoff ? tonight : new Date(n.getFullYear(), n.getMonth(), n.getDate() + 1, 20, 0).getTime()
    }
    if (name === "tomorrow")
        return new Date(n.getFullYear(), n.getMonth(), n.getDate() + 1, 9, 0).getTime()
    return 0
}

// A typed time on a day. A time already past on TODAY means the next one — "remind
// me at 8" at ten in the evening is tomorrow morning, not a reminder that fires at
// once for a moment gone. Any other day is taken as asked.
function dueAt(dayMs, h, m, nowMs) {
    const d = new Date(dayMs)
    let due = new Date(d.getFullYear(), d.getMonth(), d.getDate(), h, m).getTime()
    const today = new Date(new Date(nowMs).getFullYear(), new Date(nowMs).getMonth(), new Date(nowMs).getDate()).getTime()
    const isToday = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime() === today
    if (isToday && due <= nowMs) due = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1, h, m).getTime()
    return due
}

// ── State ─────────────────────────────────────────────────────────────────────

// The ones to notify now: open, timed, due, not yet fired.
function dueToFire(list, nowMs) {
    return (list || []).filter(function (r) { return !r.done && r.due > 0 && r.due <= nowMs && !r.notified })
}

// Done ones are kept for a day so a mis-tick can be undone, then dropped.
function prune(list, nowMs) {
    return (list || []).filter(function (r) { return !r.done || (nowMs - (r.doneAt || 0)) < _DAY })
}

function snooze(r, minutes, nowMs) {
    return Object.assign({}, r, { due: nowMs + Math.max(1, minutes) * 60 * 1000, notified: false, done: false, doneAt: 0 })
}

// Listing order: overdue first, then by time, then untimed in the order added, and
// done ones last, most recently ticked first.
function sorted(list, nowMs) {
    const rank = function (r) {
        if (r.done) return 3
        if (r.due > 0 && r.due <= nowMs) return 0
        return r.due > 0 ? 1 : 2
    }
    return (list || []).slice().sort(function (a, b) {
        const ra = rank(a), rb = rank(b)
        if (ra !== rb) return ra - rb
        if (ra === 3) return (b.doneAt || 0) - (a.doneAt || 0)
        if (ra === 2) return (a.created || 0) - (b.created || 0)
        return a.due - b.due
    })
}

// A file that came back from disk: keep only well-formed items, coerce the rest, cap
// the count. Nothing here throws on garbage.
function normalize(raw) {
    if (!Array.isArray(raw)) return []
    const out = []
    for (let i = 0; i < raw.length && out.length < MAX_ITEMS; i++) {
        const r = raw[i]
        if (!r || typeof r !== "object") continue
        const text = String(r.text === undefined || r.text === null ? "" : r.text).trim().slice(0, MAX_TEXT)
        if (typeof r.id !== "string" || r.id === "" || text === "") continue
        const num = function (v) { const n = Number(v); return isFinite(n) && n > 0 ? Math.round(n) : 0 }
        out.push({ id: r.id, text: text, due: num(r.due), done: r.done === true,
                   doneAt: num(r.doneAt), notified: r.notified === true, created: num(r.created) })
    }
    return out
}

// ── Words ─────────────────────────────────────────────────────────────────────
const _WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const _MONTHS   = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function _hm(ms) {
    const d = new Date(ms)
    const p = function (x) { return (x < 10 ? "0" : "") + x }
    return p(d.getHours()) + ":" + p(d.getMinutes())
}

// "", "Overdue · 14:00", "in 25 min", "Today 20:00", "Tomorrow 09:00", "Mon 09:00",
// "12 Oct 09:00".
function dueLabel(due, nowMs) {
    if (!(due > 0)) return ""
    const n = new Date(nowMs), d = new Date(due)
    const dayOf = function (x) { return new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime() }
    const days = Math.round((dayOf(d) - dayOf(n)) / _DAY)
    if (due <= nowMs) return "Overdue · " + (days === 0 ? _hm(due) : (days === -1 ? "yesterday " : d.getDate() + " " + _MONTHS[d.getMonth()] + " ") + _hm(due))
    const mins = Math.ceil((due - nowMs) / 60000)
    if (mins < 60) return "in " + mins + " min"
    if (days === 0) return "Today " + _hm(due)
    if (days === 1) return "Tomorrow " + _hm(due)
    if (days < 7)   return _WEEKDAYS[d.getDay()] + " " + _hm(due)
    return d.getDate() + " " + _MONTHS[d.getMonth()] + " " + _hm(due)
}
