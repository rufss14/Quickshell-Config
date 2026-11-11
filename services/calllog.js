.pragma library

// ── calllog.js ────────────────────────────────────────────────────────────────
// Call log (services/CallLog): how long you have been in a Discord voice call with each person, for the
// scoreboard on the voice panel.
//
//     bun scripts/test-calllog.js
//
// The book is { "<user id>": { name, avatar, seconds, calls, last, hidden } }. Pure: the service hands in
// times and who is in the call. What Discord sends is untrusted — a display name is anything a stranger typed,
// an avatar is a URL — so everything is validated at the door (`person`, `clean`) and nothing is ever
// interpreted: names are drawn as plain text, an avatar only if it is Discord's own CDN over https.
//
// Not stored: window titles, channel or server names, what anyone said, when each call was — only who, for
// how long, how many calls, and when last.
// ─────────────────────────────────────────────────────────────────────────────

var ID_OK = /^\d{5,25}$/
var AVATAR_OK = /^https:\/\/cdn\.discordapp\.com\/[A-Za-z0-9\/_.\-]{1,200}(\?size=\d{1,4})?$/
var MAX_PEOPLE = 2000
var MAX_NAME = 64

// A display name as it is stored: control characters out, trimmed, cut. "" when nothing is left.
function cleanName(n) {
    var s = String(n == null ? "" : n).replace(/[\u0000-\u001f\u007f-\u009f​-‏‪-‮⁦-⁩]/g, "").trim()
    return s.length > MAX_NAME ? s.slice(0, MAX_NAME) : s
}

function cleanAvatar(u) {
    var s = String(u || "")
    return AVATAR_OK.test(s) ? s : ""
}

// Who in a call counts: a well-formed id, not you, not a bot. Returns { id, name, avatar } or null.
function person(p) {
    if (!p || p.isSelf || p.bot) return null
    var id = String(p.id || "")
    if (!ID_OK.test(id)) return null
    return { id: id, name: cleanName(p.name), avatar: cleanAvatar(p.avatar) }
}

// The people of a call, as `person` keeps them.
function people(list) {
    var out = []
    for (var i = 0; i < (list || []).length; i++) {
        var p = person(list[i])
        if (p) out.push(p)
    }
    return out
}

function _rec(book, p) {
    var r = Object.assign({ name: "", avatar: "", seconds: 0, calls: 0, last: 0, hidden: false }, book[p.id] || {})
    // The latest name and picture win; an empty one never erases a known one.
    if (p.name !== "") r.name = p.name
    if (p.avatar !== "") r.avatar = p.avatar
    return r
}

// Someone came into your call: one more call together. Returns a NEW book.
function arrive(book, p, now) {
    var q = person(p)
    if (!q) return book
    var out = Object.assign({}, book || {})
    var r = _rec(out, q)
    r.calls += 1
    r.last = now
    out[q.id] = r
    return out
}

// Credit everyone in `list` with the time from `from` to `to`. A span longer than `maxSpan` ms is clipped to its
// LAST `maxSpan` (a suspend, a stalled clock: you weren't in a call for the gap), as screentime.credit does.
// Returns a NEW book.
function credit(book, list, from, to, maxSpan) {
    if (!(to > from)) return book
    var start = maxSpan > 0 ? Math.max(from, to - maxSpan) : from
    var secs = (to - start) / 1000
    var ppl = people(list)
    if (ppl.length === 0) return book
    var out = Object.assign({}, book || {})
    for (var i = 0; i < ppl.length; i++) {
        var r = _rec(out, ppl[i])
        r.seconds += secs
        r.last = to
        out[ppl[i].id] = r
    }
    return out
}

// The file is hand-editable: only well-formed people with finite, non-negative numbers come through.
// More than MAX_PEOPLE keeps the ones with the most time.
function clean(raw) {
    var out = {}
    var src = raw && typeof raw === "object" && !Array.isArray(raw) && raw.people && typeof raw.people === "object" ? raw.people : null
    if (!src) return out
    var ids = Object.keys(src).filter(function (id) { return ID_OK.test(id) && src[id] && typeof src[id] === "object" })
    ids.sort(function (a, b) { return (Number(src[b].seconds) || 0) - (Number(src[a].seconds) || 0) })
    for (var i = 0; i < Math.min(ids.length, MAX_PEOPLE); i++) {
        var r = src[ids[i]]
        var secs = Number(r.seconds), calls = Number(r.calls), last = Number(r.last)
        out[ids[i]] = {
            name: cleanName(r.name),
            avatar: cleanAvatar(r.avatar),
            seconds: isFinite(secs) && secs > 0 ? Math.round(secs) : 0,
            calls: isFinite(calls) && calls > 0 ? Math.floor(calls) : 0,
            last: isFinite(last) && last > 0 ? Math.floor(last) : 0,
            hidden: r.hidden === true
        }
    }
    return out
}

// The board: people with time together, most first; ties go to the more recent, then the lower id (stable).
// Hidden ones only when asked. [{ id, name, avatar, seconds, calls, last, hidden }]
function ranking(book, withHidden) {
    var rows = []
    for (var id in (book || {})) {
        var r = book[id]
        if (r.hidden && !withHidden) continue
        if (!(r.seconds > 0) && !(r.calls > 0)) continue
        rows.push({ id: id, name: r.name, avatar: r.avatar, seconds: r.seconds, calls: r.calls, last: r.last, hidden: r.hidden })
    }
    rows.sort(function (a, b) {
        return b.seconds !== a.seconds ? b.seconds - a.seconds
             : b.last !== a.last ? b.last - a.last
             : (a.id < b.id ? -1 : 1)
    })
    return rows
}

// Out of the board, but still recorded (so they don't come back the next call). Returns a NEW book.
function hide(book, id, hidden) {
    if (!book || !book[id]) return book
    var out = Object.assign({}, book)
    out[id] = Object.assign({}, book[id], { hidden: hidden !== false })
    return out
}

// Gone from the record altogether. Returns a NEW book.
function forget(book, id) {
    if (!book || !book[id]) return book
    var out = Object.assign({}, book)
    delete out[id]
    return out
}

// Whole seconds as "3 h 12 m", "45 m", "under a minute", "" for nothing — same shape as the Screen time panel's.
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

// "Today", "Yesterday", "3 days ago", "2 weeks ago", "5 months ago" — when you were last together. "" for never.
function ago(last, now) {
    if (!(last > 0)) return ""
    var d = new Date(now), l = new Date(last)
    var days = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(l.getFullYear(), l.getMonth(), l.getDate())) / 86400000)
    if (days <= 0) return "Today"
    if (days === 1) return "Yesterday"
    if (days < 14) return days + " days ago"
    if (days < 60) return Math.floor(days / 7) + " weeks ago"
    return Math.floor(days / 30) + " months ago"
}
