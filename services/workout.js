.pragma library

// ── workout.js ────────────────────────────────────────────────────────────────
// The workout log's rules, as pure functions over a plain state:
//
//     { unit: "kg" | "lb",
//       restGoal: seconds to rest between sets (the rest bar fills to it),
//       active:  null | Session,           the one being done right now (kept across a reload)
//       history: [Session, …],             finished ones, newest first
//       seq }                              the last id handed out (never reused)
//
//     Session { id, start, end, pausedMs, pausedAt, entries: [Entry] }      times in ms since the epoch
//     Entry   { id, name, kind: "reps" | "time", sets: [{ reps, weight, secs, at, done }] }
//
// It is a checklist: an exercise is added with its sets PLANNED (`done: false`), and a set is ticked off as it
// is done (`done: true`, `at` = when). Only ticked sets count (stats, history, the rest clock), and finishing a
// workout keeps only those: a set you never did is not in the log. A set without a `done` field is done, which
// is what every set was before the checklist.
//
// A "reps" set is reps at a weight (0 = bodyweight); a "time" set is seconds, optionally with a weight
// (a loaded carry, a weighted plank). The weight is a number in whatever unit the log says: the unit is a
// label for how it was typed, so changing it converts nothing.
//
// ── Why it's here and not in the service ──────────────────────────────────────
// Every operation returns a NEW state and never touches its argument — the JsonStore only saves on
// assignment, and an in-place mutation is silently never written (services/tasks.js says the same). Pure
// also means `bun scripts/test-workout.js` can pin the date maths, which is where a log goes wrong.
//
// ── The disk is a trust boundary ──────────────────────────────────────────────
// workouts.json is a file a person (or a sync tool) can edit, so `normalise()` rebuilds the state from
// whatever was read: wrong types dropped, names cleaned and capped, numbers clamped, ids made unique.
// A half-broken file gives a smaller log, never a crash in a binding.
// ─────────────────────────────────────────────────────────────────────────────

var MAX_NAME = 60
var MAX_HISTORY = 2000
var MAX_ENTRIES = 60
var MAX_SETS = 100
var DAY = 86400000

function empty() { return { unit: "kg", restGoal: 90, active: null, history: [], seq: 0 } }

// One line, no control characters, capped. "" = nothing worth keeping.
function clean(text) {
    var s = String(text === undefined || text === null ? "" : text)
        .replace(/[\u0000-\u001f\u007f-\u009f]+/g, " ").replace(/ {2,}/g, " ").trim()
    return s.length > MAX_NAME ? s.slice(0, MAX_NAME - 1).trimEnd() + "…" : s
}

function _num(v, lo, hi, fallback) {
    var n = Number(v)
    if (!isFinite(n)) return fallback
    return Math.min(hi, Math.max(lo, n))
}

function _set(s) {
    if (!s || typeof s !== "object") return null
    return {
        reps:   Math.round(_num(s.reps, 0, 999, 0)),
        weight: Math.round(_num(s.weight, 0, 2000, 0) * 100) / 100,
        secs:   Math.round(_num(s.secs, 0, 86400, 0)),
        at:     _num(s.at, 0, 8.64e15, 0),
        done:   s.done !== false
    }
}

function _session(s, nextId) {
    if (!s || typeof s !== "object") return null
    var start = _num(s.start, 0, 8.64e15, 0)
    if (start <= 0) return null
    var entries = []
    var src = Array.isArray(s.entries) ? s.entries : []
    for (var i = 0; i < src.length && entries.length < MAX_ENTRIES; i++) {
        var e = src[i]
        if (!e || typeof e !== "object") continue
        var name = clean(e.name)
        if (name === "") continue
        var sets = []
        var ss = Array.isArray(e.sets) ? e.sets : []
        for (var j = 0; j < ss.length && sets.length < MAX_SETS; j++) {
            var one = _set(ss[j])
            if (one) sets.push(one)
        }
        if (sets.length === 0) continue
        entries.push({ id: nextId(e.id), name: name, kind: e.kind === "time" ? "time" : "reps", sets: sets })
    }
    return {
        id: nextId(s.id), start: start,
        end: _num(s.end, 0, 8.64e15, 0),
        pausedMs: _num(s.pausedMs, 0, 8.64e15, 0),
        pausedAt: _num(s.pausedAt, 0, 8.64e15, 0),
        entries: entries
    }
}

function normalise(doc) {
    var used = {}, top = 0
    var seqIn = Math.floor(_num(doc && doc.seq, 0, 1e12, 0))
    // An id is kept when it is a positive whole number nobody else has; otherwise a fresh one.
    function nextId(raw) {
        var id = Math.floor(Number(raw))
        if (!isFinite(id) || id <= 0 || used[id]) { id = Math.max(top, seqIn) + 1 }
        used[id] = true
        top = Math.max(top, id)
        return id
    }
    var out = empty()
    out.unit = doc && doc.unit === "lb" ? "lb" : "kg"
    var rg = doc && doc.restGoal !== undefined && doc.restGoal !== null ? doc.restGoal : 90
    out.restGoal = Math.round(_num(rg, 15, 600, 90))
    var src = doc && Array.isArray(doc.history) ? doc.history : []
    for (var i = 0; i < src.length && out.history.length < MAX_HISTORY; i++) {
        var s = _session(src[i], nextId)
        if (s && s.end > 0 && s.entries.length > 0) out.history.push(s)
    }
    out.history.sort(function (a, b) { return b.start - a.start })
    var act = doc && doc.active ? _session(doc.active, nextId) : null
    if (act) { act.end = 0; out.active = act }
    out.seq = Math.max(top, seqIn)
    return out
}

// ── The session being done ────────────────────────────────────────────────────
function startWorkout(state, now) {
    if (state.active) return state
    var id = state.seq + 1
    return Object.assign({}, state, {
        seq: id,
        active: { id: id, start: now, end: 0, pausedMs: 0, pausedAt: 0, entries: [] }
    })
}

function togglePause(state, now) {
    var a = state.active
    if (!a) return state
    var next = a.pausedAt > 0
        ? Object.assign({}, a, { pausedMs: a.pausedMs + Math.max(0, now - a.pausedAt), pausedAt: 0 })
        : Object.assign({}, a, { pausedAt: now })
    return Object.assign({}, state, { active: next })
}

// Time spent working: the clock minus the pauses (a pause still running counts as paused).
function elapsed(session, now) {
    if (!session) return 0
    var stop = session.end > 0 ? session.end : (session.pausedAt > 0 ? session.pausedAt : now)
    return Math.max(0, stop - session.start - session.pausedMs)
}

// Add `count` identical sets of `spec` { name, kind, reps, weight, secs }: onto the exercise of that name
// and kind if the workout has it already, else as a new one. No name, or no work in the set, is a no-op.
function _add(state, spec, count, now, done) {
    var a = state.active
    var name = clean(spec && spec.name)
    if (!a || name === "") return state
    var kind = spec.kind === "time" ? "time" : "reps"
    var one = _set({ reps: spec.reps, weight: spec.weight, secs: spec.secs, at: done ? now : 0, done: done })
    if (kind === "time" ? one.secs <= 0 : one.reps <= 0) return state
    var n = Math.max(1, Math.min(20, Math.floor(Number(count) || 1)))
    var entries = a.entries.slice()
    var at = -1
    for (var i = 0; i < entries.length; i++)
        if (entries[i].kind === kind && entries[i].name.toLowerCase() === name.toLowerCase()) { at = i; break }
    var seq = state.seq
    if (at < 0) {
        if (entries.length >= MAX_ENTRIES) return state
        seq += 1
        entries.push({ id: seq, name: name, kind: kind, sets: [] })
        at = entries.length - 1
    }
    var sets = entries[at].sets.slice()
    for (var k = 0; k < n && sets.length < MAX_SETS; k++) sets.push(Object.assign({}, one))
    entries[at] = Object.assign({}, entries[at], { sets: sets })
    return Object.assign({}, state, { seq: seq, active: Object.assign({}, a, { entries: entries }) })
}

// Sets already done (a quick log) / sets planned to tick off.
function logSets(state, spec, count, now) { return _add(state, spec, count, now, true) }
function planSets(state, spec, count, now) { return _add(state, spec, count, now, false) }

function _editSet(state, entryId, index, change) {
    var a = state.active
    if (!a) return state
    var done = false
    var entries = a.entries.map(function (e) {
        if (e.id !== entryId || index < 0 || index >= e.sets.length) return e
        var next = change(e.sets[index], e)
        if (!next) return e
        done = true
        var sets = e.sets.slice(); sets[index] = next
        return Object.assign({}, e, { sets: sets })
    })
    return done ? Object.assign({}, state, { active: Object.assign({}, a, { entries: entries }) }) : state
}

// Tick a set off (done now), or take the tick back.
function toggleSet(state, entryId, index, now) {
    return _editSet(state, entryId, index, function (s) {
        var on = s.done === false
        return Object.assign({}, s, { done: on, at: on ? now : 0 })
    })
}

// Change a set's numbers: patch { reps, weight, secs }, each clamped as it is on the way in; a rep set keeps
// at least one rep and a time set at least a second, so a set never becomes nothing.
function tweakSet(state, entryId, index, patch) {
    return _editSet(state, entryId, index, function (s, e) {
        var n = _set(Object.assign({}, s, patch))
        if (e.kind === "time") n.secs = Math.max(1, n.secs); else n.reps = Math.max(1, n.reps)
        n.at = s.at; n.done = s.done
        return n.reps === s.reps && n.weight === s.weight && n.secs === s.secs ? null : n
    })
}

// One more set like the last, still to do.
function addSetLike(state, entryId) {
    var a = state.active
    if (!a) return state
    var changed = false
    var entries = a.entries.map(function (e) {
        if (e.id !== entryId || e.sets.length === 0 || e.sets.length >= MAX_SETS) return e
        changed = true
        var last = e.sets[e.sets.length - 1]
        return Object.assign({}, e, { sets: e.sets.concat([Object.assign({}, last, { done: false, at: 0 })]) })
    })
    return changed ? Object.assign({}, state, { active: Object.assign({}, a, { entries: entries }) }) : state
}

function removeSet(state, entryId, index) {
    var a = state.active
    if (!a) return state
    var entries = []
    var changed = false
    for (var i = 0; i < a.entries.length; i++) {
        var e = a.entries[i]
        if (e.id !== entryId || index < 0 || index >= e.sets.length) { entries.push(e); continue }
        changed = true
        var sets = e.sets.slice(); sets.splice(index, 1)
        if (sets.length > 0) entries.push(Object.assign({}, e, { sets: sets }))
    }
    return changed ? Object.assign({}, state, { active: Object.assign({}, a, { entries: entries }) }) : state
}

function removeEntry(state, entryId) {
    var a = state.active
    if (!a) return state
    var entries = a.entries.filter(function (e) { return e.id !== entryId })
    return entries.length === a.entries.length ? state
        : Object.assign({}, state, { active: Object.assign({}, a, { entries: entries }) })
}

// Done: it goes into the history, unless nothing was logged (then it is simply dropped).
function finish(state, now) {
    var a = state.active
    if (!a) return state
    var done = a.pausedAt > 0 ? Object.assign({}, a, { pausedMs: a.pausedMs + Math.max(0, now - a.pausedAt), pausedAt: 0 }) : a
    var kept = []
    for (var i = 0; i < done.entries.length; i++) {
        var sets = done.entries[i].sets.filter(function (s) { return s.done !== false })
        if (sets.length > 0) kept.push(Object.assign({}, done.entries[i], { sets: sets }))
    }
    done = Object.assign({}, done, { entries: kept, end: Math.max(now, done.start + 1) })
    var history = done.entries.length > 0 ? [done].concat(state.history).slice(0, MAX_HISTORY) : state.history
    return Object.assign({}, state, { active: null, history: history })
}

function discard(state) {
    return state.active ? Object.assign({}, state, { active: null }) : state
}

function removeWorkout(state, id) {
    var history = state.history.filter(function (s) { return s.id !== id })
    return history.length === state.history.length ? state : Object.assign({}, state, { history: history })
}

// The rest you aim for between sets, in seconds (15 s to 10 min): the rest bar fills to it.
function setRestGoal(state, secs) {
    var g = Math.round(_num(secs, 15, 600, 90) / 5) * 5
    return g === state.restGoal ? state : Object.assign({}, state, { restGoal: g })
}

function setUnit(state, unit) {
    var u = unit === "lb" ? "lb" : "kg"
    return u === state.unit ? state : Object.assign({}, state, { unit: u })
}

// ── Reading a session ─────────────────────────────────────────────────────────
// sets, reps, volume (reps × weight, for the reps sets), seconds held (time sets), exercises: of the sets DONE.
// `total` is every set, planned or done, and `exercises` the exercises that have any.
function stats(session) {
    var out = { sets: 0, reps: 0, volume: 0, secs: 0, exercises: 0, total: 0 }
    if (!session) return out
    out.exercises = session.entries.length
    for (var i = 0; i < session.entries.length; i++) {
        var e = session.entries[i]
        for (var j = 0; j < e.sets.length; j++) {
            var s = e.sets[j]
            out.total += 1
            if (s.done === false) continue
            out.sets += 1
            if (e.kind === "time") out.secs += s.secs
            else { out.reps += s.reps; out.volume += s.reps * s.weight }
        }
    }
    out.volume = Math.round(out.volume * 100) / 100
    return out
}

// The newest set of an exercise anywhere in the log, for prefilling the composer; the exercises you do
// most often first among equals. `limit` entries, most recently done first.
function recents(state, limit) {
    var by = {}
    var sessions = (state.active ? [state.active] : []).concat(state.history)
    for (var i = 0; i < sessions.length; i++) {
        var es = sessions[i].entries
        for (var j = 0; j < es.length; j++) {
            var e = es[j]
            var key = e.kind + ":" + e.name.toLowerCase()
            var last = e.sets[e.sets.length - 1]
            for (var q = e.sets.length - 1; q >= 0; q--) if (e.sets[q].done !== false) { last = e.sets[q]; break }
            var at = last ? last.at || sessions[i].start : sessions[i].start
            var cur = by[key]
            if (!cur) by[key] = { name: e.name, kind: e.kind, reps: last ? last.reps : 0, weight: last ? last.weight : 0,
                                  secs: last ? last.secs : 0, at: at, uses: 1 }
            else {
                cur.uses += 1
                if (at > cur.at) { cur.at = at; cur.reps = last.reps; cur.weight = last.weight; cur.secs = last.secs }
            }
        }
    }
    var list = Object.keys(by).map(function (k) { return by[k] })
    list.sort(function (a, b) { return b.at - a.at || b.uses - a.uses })
    return list.slice(0, Math.max(0, limit))
}

// ── Typing an exercise ────────────────────────────────────────────────────────
// What the add field understands. Not a grammar, a handful of habits people already type:
//
//     bench 3x8 60kg        3 sets of 8 at 60 kg           pull-ups 4 sets 10 reps
//     squat 5x5 @ 100       "@ 100" is a weight            plank 45s     (a time set)
//     deadlift 100kg        the numbers you did last time fill the rest       plank 3x1:30
//
// `parseQuick` reads the numbers out and leaves the name; `quickSpec` fills what was not typed from the
// last time you did that exercise, then from the steppers' defaults.
var LIBRARY = [
    "Bench press", "Incline bench press", "Overhead press", "Push-ups", "Pull-ups", "Chin-ups", "Dips",
    "Barbell row", "Dumbbell row", "Lat pulldown", "Deadlift", "Romanian deadlift", "Squat", "Front squat",
    "Goblet squat", "Lunges", "Bulgarian split squat", "Leg press", "Leg curl", "Leg extension", "Calf raise",
    "Hip thrust", "Biceps curl", "Hammer curl", "Triceps extension", "Lateral raise", "Face pull",
    "Shoulder press", "Crunches", "Sit-ups", "Leg raise", "Russian twist", "Burpees", "Kettlebell swing"
].map(function (n) { return { name: n, kind: "reps" } }).concat([
    "Plank", "Side plank", "Wall sit", "Dead hang", "L-sit", "Jump rope", "Farmer's carry", "Mountain climbers"
].map(function (n) { return { name: n, kind: "time" } }))

function _lib(name) {
    var k = String(name).toLowerCase()
    for (var i = 0; i < LIBRARY.length; i++) if (LIBRARY[i].name.toLowerCase() === k) return LIBRARY[i]
    return null
}

// { name, kind: "reps" | "time" | null (not said), sets, reps, secs, weight (-1 = not said), tail, any }
// `tail` is the numbers as typed, for completing the name without losing them.
function parseQuick(text, unit) {
    var src = String(text === undefined || text === null ? "" : text)
    var s = src
    var found = []
    var out = { name: "", kind: null, sets: 0, reps: 0, secs: 0, weight: -1, tail: "", any: false }
    function take(re, fn) {
        var m = re.exec(s)
        if (!m) return false
        found.push({ at: m.index, text: m[0].trim() })
        fn(m)
        s = s.slice(0, m.index) + " ".repeat(m[0].length) + s.slice(m.index + m[0].length)
        return true
    }
    function num(v) { return Number(String(v).replace(",", ".")) }
    function secsOf(v, u) { return Math.round(num(v) * (/^m/i.test(u) ? 60 : 1)) }

    // 3x45s, 3 x 1:30, 3x2min
    take(/(\d+)\s*[x×]\s*(\d+(?:[.,]\d+)?)\s*(min|mins|minutes|m|sec|secs|seconds|s)\b/i, function (m) {
        out.sets = Number(m[1]); out.secs = secsOf(m[2], m[3]); out.kind = "time" })
    take(/(\d+)\s*[x×]\s*(\d+):(\d{2})\b/i, function (m) {
        out.sets = Number(m[1]); out.secs = Number(m[2]) * 60 + Number(m[3]); out.kind = "time" })
    // 3x8
    if (!out.sets) take(/(\d+)\s*[x×]\s*(\d+)\b/i, function (m) { out.sets = Number(m[1]); out.reps = Number(m[2]) })
    // @ 60, 60kg, 135 lb
    var w = function (m) {
        var v = num(m[1]), u = (m[2] || "").toLowerCase()
        var from = /^lb/.test(u) ? "lb" : /^kg/.test(u) ? "kg" : (unit === "lb" ? "lb" : "kg")
        var to = unit === "lb" ? "lb" : "kg"
        if (from !== to) v = from === "lb" ? v * 0.45359237 : v * 2.20462262
        out.weight = Math.round(v * 100) / 100
    }
    take(/@\s*(\d+(?:[.,]\d+)?)\s*(kgs?|lbs?)?\b/i, w) || take(/(\d+(?:[.,]\d+)?)\s*(kgs?|lbs?)\b/i, w)
    // 4 sets, 10 reps
    take(/(\d+)\s*sets?\b/i, function (m) { out.sets = Number(m[1]) })
    take(/(\d+)\s*reps?\b/i, function (m) { out.reps = Number(m[1]); out.kind = out.kind || "reps" })
    // 1:30, 2 min, 45 s
    if (!out.secs) {
        take(/(\d+):(\d{2})\b/, function (m) { out.secs = Number(m[1]) * 60 + Number(m[2]); out.kind = "time" }) ||
        take(/(\d+(?:[.,]\d+)?)\s*(min|mins|minutes)\b/i, function (m) { out.secs = secsOf(m[1], "m"); out.kind = "time" }) ||
        take(/(\d+)\s*(sec|secs|seconds|s)\b/i, function (m) { out.secs = Number(m[1]); out.kind = "time" })
    }
    // A number left on its own at the end is reps: "pull-ups 12".
    if (out.kind !== "time") {
        if (!out.reps) take(/(?:^|\s)(\d+)\s*$/, function (m) { out.reps = Number(m[1]); out.kind = "reps" })
        // Reps already said, so a number left over is the weight: "bench 5x3 70".
        else if (out.weight < 0) take(/(?:^|\s)(\d+(?:[.,]\d+)?)\s*$/, w)
    }

    out.name = clean(s.replace(/[@×]/g, " ").replace(/\b(for|of|at|with)\s*$/i, " ").replace(/^\s*(for|of|at|with)\b/i, " ")
                      .replace(/\s[x-]\s*$/i, " "))
    out.sets = Math.max(0, Math.min(20, out.sets))
    out.reps = Math.max(0, Math.min(999, out.reps))
    out.secs = Math.max(0, Math.min(86400, out.secs))
    found.sort(function (a, b) { return a.at - b.at })
    out.tail = found.map(function (f) { return f.text }).join(" ")
    out.any = found.length > 0
    return out
}

// Everything the add field would add for `text`: { name, kind, sets, reps, weight, secs, known, said }.
// `defaults` = { kind, sets, reps, weight, secs } (the steppers); `said` says which numbers were typed.
function quickSpec(state, text, unit, defaults) {
    var p = parseQuick(text, unit)
    var d = defaults || {}
    var key = p.name.toLowerCase()
    var seen = null
    var all = recents(state, 500)
    for (var i = 0; i < all.length; i++) {
        if (all[i].name.toLowerCase() !== key) continue
        if (!seen || (p.kind && all[i].kind === p.kind)) seen = all[i]
        if (p.kind && all[i].kind === p.kind) break
    }
    var lib = _lib(p.name)
    var kind = p.kind || (seen && seen.kind) || (lib && lib.kind) || (d.kind === "time" ? "time" : "reps")
    var last = seen && seen.kind === kind ? seen : null
    return {
        name: seen ? seen.name : lib ? lib.name : p.name,
        kind: kind,
        sets: p.sets || d.sets || 1,
        reps: p.reps || (last ? Math.max(1, last.reps) : 0) || d.reps || 10,
        secs: p.secs || (last ? Math.max(5, last.secs) : 0) || d.secs || 45,
        weight: p.weight >= 0 ? p.weight : last ? last.weight : (d.weight || 0),
        known: !!seen,
        said: { sets: p.sets > 0, reps: p.reps > 0, secs: p.secs > 0, weight: p.weight >= 0 }
    }
}

// Exercises that match what was typed, the ones you have done first, then the built-in list.
// { name, kind, reps, weight, secs, known, uses }, best match first. Nothing typed: what you did most lately.
function suggest(state, query, limit) {
    var q = parseQuick(query, state.unit).name.toLowerCase()
    var pool = recents(state, 500).map(function (r) { r.known = true; return r })
    var have = {}
    pool.forEach(function (r) { have[r.name.toLowerCase()] = true })
    LIBRARY.forEach(function (l) {
        if (!have[l.name.toLowerCase()]) pool.push({ name: l.name, kind: l.kind, reps: 0, weight: 0, secs: 0, uses: 0, at: 0, known: false })
    })
    if (q === "") return pool.filter(function (r) { return r.known }).slice(0, Math.max(0, limit))
    var tokens = q.split(" ").filter(function (t) { return t !== "" })
    var out = []
    pool.forEach(function (r) {
        var low = r.name.toLowerCase()
        var words = low.split(/[\s'-]+/)
        var worst = 0
        for (var i = 0; i < tokens.length; i++) {
            var best = 9
            if (low.indexOf(tokens[i]) === 0) best = 0
            else if (words.some(function (w) { return w.indexOf(tokens[i]) === 0 })) best = 1
            else if (low.indexOf(tokens[i]) >= 0) best = 2
            if (best === 9) return
            worst = Math.max(worst, best)
        }
        out.push({ r: r, score: worst })
    })
    out.sort(function (a, b) {
        return a.score - b.score || (b.r.known ? 1 : 0) - (a.r.known ? 1 : 0) || b.r.uses - a.r.uses
            || (a.r.name < b.r.name ? -1 : 1)
    })
    return out.slice(0, Math.max(0, limit)).map(function (o) { return o.r })
}

// ── Records ───────────────────────────────────────────────────────────────────
// How big a set is, for comparing two of the same exercise: a loaded rep set by weight and reps (a rough
// estimated one-rep max), a bodyweight one by its reps, a time set by its seconds.
function score(kind, s) {
    if (kind === "time") return s.secs
    return s.weight > 0 ? s.weight * (1 + s.reps / 30) : s.reps
}

// The best set of each exercise in the finished history: { "reps:bench press": score }.
function bests(history) {
    var out = {}
    for (var i = 0; i < history.length; i++)
        for (var j = 0; j < history[i].entries.length; j++) {
            var e = history[i].entries[j]
            var key = e.kind + ":" + e.name.toLowerCase()
            for (var k = 0; k < e.sets.length; k++) {
                if (e.sets[k].done === false) continue
                var sc = score(e.kind, e.sets[k])
                if (!(out[key] >= sc)) out[key] = sc
            }
        }
    return out
}

// Is this set a record: better than everything done of that exercise before this workout? Never the first
// time you do one (there is nothing to beat).
function isRecord(best, kind, name, s) {
    var b = best[kind + ":" + String(name).toLowerCase()]
    return b > 0 && score(kind, s) > b * 1.0001
}

// A new workout with the exercises of `session` planned, every set still to do: "do that again".
function startFrom(state, session, now) {
    if (state.active || !session) return state
    var base = startWorkout(state, now)
    var seq = base.seq
    var entries = session.entries.map(function (e) {
        seq += 1
        return { id: seq, name: e.name, kind: e.kind, sets: e.sets.map(function (s) {
            return { reps: s.reps, weight: s.weight, secs: s.secs, at: 0, done: false } }) }
    })
    return Object.assign({}, base, { seq: seq, active: Object.assign({}, base.active, { entries: entries }) })
}

// ── Dates ─────────────────────────────────────────────────────────────────────
function pad(n) { return (n < 10 ? "0" : "") + n }

// The local calendar day of a moment, "2026-11-16": the key a day is looked up by.
function dayKey(ms) {
    var d = new Date(ms)
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

// The local midnight a moment falls after.
function dayStart(ms) {
    var d = new Date(ms)
    return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
}

// { "2026-11-16": [Session, …] } , each day's sessions newest first.
function byDay(history) {
    var out = {}
    for (var i = 0; i < history.length; i++) {
        var k = dayKey(history[i].start)
        if (!out[k]) out[k] = []
        out[k].push(history[i])
    }
    return out
}

// A grid of days, `weeks` columns of seven (Monday first), the last column the week of `now` shifted back
// by `back` weeks. A cell: { key, ts, count, future }. Calendar days are stepped by date, not by 24 hours,
// so a clock change cannot slip a day.
function heat(history, now, weeks, back) {
    var days = byDay(history)
    var today = new Date(now)
    var monday = new Date(today.getFullYear(), today.getMonth(), today.getDate())
    monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7) - Math.max(0, back) * 7)
    var first = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate())
    first.setDate(first.getDate() - (weeks - 1) * 7)
    var todayStart = dayStart(now)
    var cols = []
    for (var w = 0; w < weeks; w++) {
        var col = []
        for (var d = 0; d < 7; d++) {
            var cell = new Date(first.getFullYear(), first.getMonth(), first.getDate() + w * 7 + d)
            var key = dayKey(cell.getTime())
            col.push({ key: key, ts: cell.getTime(), count: days[key] ? days[key].length : 0, future: cell.getTime() > todayStart })
        }
        cols.push(col)
    }
    return cols
}

// { week: workouts in the last seven days (today included), total, streak: consecutive days with one,
//   counting back from today, or from yesterday while today is still open }.
function summary(history, now) {
    var days = byDay(history)
    var t = dayStart(now)
    var week = 0
    for (var i = 0; i < 7; i++) {
        var d = new Date(t); d.setDate(d.getDate() - i)
        var l = days[dayKey(d.getTime())]
        if (l) week += l.length
    }
    var streak = 0
    var cur = new Date(t)
    if (!days[dayKey(cur.getTime())]) cur.setDate(cur.getDate() - 1)
    while (days[dayKey(cur.getTime())]) { streak++; cur.setDate(cur.getDate() - 1) }
    return { week: week, total: history.length, streak: streak }
}

// ── Words ─────────────────────────────────────────────────────────────────────
// 754000 → "12:34", 4521000 → "1:15:21": the running clock.
function clock(ms) {
    var s = Math.max(0, Math.floor(ms / 1000))
    var h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, r = s % 60
    return h > 0 ? h + ":" + pad(m) + ":" + pad(r) : pad(m) + ":" + pad(r)
}

// 2880000 → "48 min", 3900000 → "1 h 05 min": how long a finished one took.
function lasted(ms) {
    var m = Math.max(1, Math.round(ms / 60000))
    return m < 60 ? m + " min" : Math.floor(m / 60) + " h " + pad(m % 60) + " min"
}

// 20 → "20", 22.5 → "22.5", 20.00 → "20": a weight without trailing zeros.
function weightText(n) { return String(Math.round(Number(n) * 100) / 100) }

// One set as a person says it: "12 × 20 kg", "12 reps", "45 s", "1:30 · 10 kg".
function setText(kind, s, unit) {
    if (kind === "time") {
        var t = s.secs >= 60 ? Math.floor(s.secs / 60) + ":" + pad(s.secs % 60) : s.secs + " s"
        return s.weight > 0 ? t + " · " + weightText(s.weight) + " " + unit : t
    }
    return s.weight > 0 ? s.reps + " × " + weightText(s.weight) + " " + unit : s.reps + " reps"
}
