.pragma library

// ── claudeusage.js ────────────────────────────────────────────────────────────
// How the Claude panel words the account's rate limit. Pure functions over the helper's
// `rate` message ({ at, five_hour: { pct, resetsAt }, seven_day }), so
// `bun scripts/test-claudeusage.js` can pin it.
//
// ── A window that has reset ───────────────────────────────────────────────────
// The saved percentage is from the last time a session reported, and a window that has
// rolled over since is empty — saying "83%" at 09:00 about a window that ended at 08:00
// is the one thing this must not do. Past its reset time a window reads as reset (0%),
// until a session reports the new one.
//
// ── Times are the wall clock's, 24-hour ("13:40"), like the rest of the shell ─
// A reset more than ~a day away says which weekday ("Tue 14:00"), since "14:00" alone
// would be ambiguous.
// ─────────────────────────────────────────────────────────────────────────────

var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
// How long before the saved figures are called old.
var STALE_MS = 30 * 60 * 1000

function pad(n) { return n < 10 ? "0" + n : "" + n }

// "42m", "2h 14m", "3d 4h" — the two biggest units, nothing under a minute.
function span(ms) {
    var m = Math.max(0, Math.round(ms / 60000))
    if (m < 1) return "under a minute"
    if (m < 60) return m + "m"
    var h = Math.floor(m / 60)
    if (h < 48) return h + "h" + (m % 60 > 0 ? " " + (m % 60) + "m" : "")
    var d = Math.floor(h / 24)
    return d + "d" + (h % 24 > 0 ? " " + (h % 24) + "h" : "")
}

// "13:40" within the day; "Tue 14:00" further out.
function clock(whenMs, nowMs) {
    var d = new Date(whenMs)
    var t = pad(d.getHours()) + ":" + pad(d.getMinutes())
    return whenMs - nowMs > 20 * 3600 * 1000 ? DAYS[d.getDay()] + " " + t : t
}

// One limit window → what to draw. null when there is no such window to draw.
//   { pct, ratio, reset, left, when }
function limit(w, nowMs) {
    if (!w || typeof w.pct !== "number" || typeof w.resetsAt !== "number") return null
    var at = w.resetsAt * 1000
    if (at <= nowMs) return { pct: 0, ratio: 0, reset: true, left: "", when: "" }
    var pct = Math.max(0, Math.min(100, w.pct))
    return { pct: Math.round(pct), ratio: pct / 100, reset: false,
             left: span(at - nowMs), when: clock(at, nowMs) }
}

// "5m ago" — when the figures were last reported; "" while fresh enough not to matter.
function stale(atMs, nowMs) {
    if (!atMs || nowMs - atMs < STALE_MS) return ""
    return span(nowMs - atMs) + " ago"
}
