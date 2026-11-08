.pragma library

// ── tasks.js ──────────────────────────────────────────────────────────────────
// The to-do list's rules, as pure functions over a plain state:
//
//     { items: [{ id, text, done, at, doneAt }], seq }
//
// `seq` is the last id handed out, so an id is never reused after a delete (a row
// that animates out while a new one animates in must not share a key).
//
// ── Why it's here and not in the service ──────────────────────────────────────
// Every operation returns a NEW state and never touches its argument — the JsonStore
// only saves on assignment, and an in-place mutation is silently never written. Keeping
// them pure makes that a property of the file rather than a habit of the caller, and
// lets `bun scripts/test-tasks.js` pin it.
//
// ── The disk is a trust boundary ──────────────────────────────────────────────
// tasks.json is a file a person (or a sync tool) can edit, so `normalise()` rebuilds
// the state from whatever was read: wrong types dropped, text cleaned and capped, ids
// made unique, `seq` pushed past the highest id. A half-broken file yields a smaller
// list, never a crash in a binding.
// ─────────────────────────────────────────────────────────────────────────────

var MAX_TEXT  = 200
var MAX_ITEMS = 500

function empty() { return { items: [], seq: 0 } }

// One line, no control characters, capped. "" = nothing worth keeping.
function clean(text) {
    var s = String(text === undefined || text === null ? "" : text)
        .replace(/[\u0000-\u001f\u007f-\u009f]+/g, " ").replace(/ {2,}/g, " ").trim()
    return s.length > MAX_TEXT ? s.slice(0, MAX_TEXT - 1).trimEnd() + "…" : s
}

function normalise(doc) {
    var src = doc && Array.isArray(doc.items) ? doc.items : []
    var seen = {}, items = [], top = 0
    for (var i = 0; i < src.length && items.length < MAX_ITEMS; i++) {
        var it = src[i]
        if (!it || typeof it !== "object") continue
        var text = clean(it.text)
        if (text === "") continue
        var id = Math.floor(Number(it.id))
        if (!isFinite(id) || id <= 0 || seen[id]) continue
        seen[id] = true
        top = Math.max(top, id)
        var at = Number(it.at)
        var doneAt = Number(it.doneAt)
        items.push({
            id: id, text: text, done: it.done === true,
            at: isFinite(at) ? at : 0,
            doneAt: it.done === true && isFinite(doneAt) ? doneAt : 0
        })
    }
    var seq = Math.floor(Number(doc && doc.seq))
    return { items: items, seq: Math.max(top, isFinite(seq) ? seq : 0) }
}

function add(state, text, now) {
    var t = clean(text)
    if (t === "" || state.items.length >= MAX_ITEMS) return state
    var id = state.seq + 1
    return { items: state.items.concat([{ id: id, text: t, done: false, at: now, doneAt: 0 }]), seq: id }
}

function _map(state, id, fn) {
    var hit = false
    var items = state.items.map(function (it) {
        if (it.id !== id) return it
        hit = true
        return fn(it)
    })
    return hit ? { items: items, seq: state.seq } : state
}

function toggle(state, id, now) {
    return _map(state, id, function (it) {
        return { id: it.id, text: it.text, done: !it.done, at: it.at, doneAt: it.done ? 0 : now }
    })
}

function rename(state, id, text) {
    var t = clean(text)
    if (t === "") return state
    return _map(state, id, function (it) {
        return { id: it.id, text: t, done: it.done, at: it.at, doneAt: it.doneAt }
    })
}

function remove(state, id) {
    var items = state.items.filter(function (it) { return it.id !== id })
    return items.length === state.items.length ? state : { items: items, seq: state.seq }
}

function clearDone(state) {
    var items = state.items.filter(function (it) { return !it.done })
    return items.length === state.items.length ? state : { items: items, seq: state.seq }
}

// What the panel lists: open ones in the order they were added, then the finished, most
// recently finished first — so ticking something off sends it to the top of the done pile.
function view(state) {
    var open = state.items.filter(function (it) { return !it.done })
    var done = state.items.filter(function (it) { return it.done })
        .sort(function (a, b) { return b.doneAt - a.doneAt })
    return open.concat(done)
}

function openCount(state) {
    return state.items.filter(function (it) { return !it.done }).length
}
