.pragma library

// ── timers.js ─────────────────────────────────────────────────────────────────
// The pure parts of services/Timers.qml: the focus (Pomodoro) cycle, and what a list of stopwatch laps
// says. Tested by `bun scripts/test-timers.js`.
//
// ── The focus cycle ───────────────────────────────────────────────────────────
// A focus session, then a short break; after every `every`-th focus session the break is the long one;
// then focus again, for as long as it is left running. It rides the countdown (Timers keeps one set of
// timer fields): the phase decides the length, and finishing one starts the next.
// ─────────────────────────────────────────────────────────────────────────────

var POMO_DEFAULTS = { focus: 25, short: 5, long: 15, every: 4 }

function _clamp(v, lo, hi, dflt) {
    var n = Math.round(Number(v))
    return isFinite(n) ? Math.max(lo, Math.min(hi, n)) : dflt
}

// A stored or hand-typed config, every field in range (minutes; `every` in sessions).
function pomoClean(c) {
    var o = c || {}
    return {
        focus: _clamp(o.focus, 1, 120, POMO_DEFAULTS.focus),
        short: _clamp(o.short, 1, 60, POMO_DEFAULTS.short),
        long:  _clamp(o.long, 1, 90, POMO_DEFAULTS.long),
        every: _clamp(o.every, 2, 8, POMO_DEFAULTS.every)
    }
}

// What comes after the phase that just ended. `cycle` = focus sessions COMPLETED before this one ended.
// → { phase, cycle, seconds, label } for the NEXT phase; `cycle` counts the focus session that just
// finished (so the long break comes after the `every`-th).
function pomoNext(phase, cycle, cfg) {
    var c = pomoClean(cfg)
    var done = Math.max(0, Math.floor(Number(cycle) || 0))
    if (phase === "focus") {
        done += 1
        if (done % c.every === 0) return { phase: "long", cycle: done, seconds: c.long * 60, label: "Long break" }
        return { phase: "short", cycle: done, seconds: c.short * 60, label: "Short break" }
    }
    return { phase: "focus", cycle: done, seconds: c.focus * 60, label: "Focus" }
}

// The first phase of a fresh cycle.
function pomoStart(cfg) {
    return { phase: "focus", cycle: 0, seconds: pomoClean(cfg).focus * 60, label: "Focus" }
}

// Which focus session of the round you are in (1..every) — for "Session 2 of 4" and the dots.
function pomoSession(phase, cycle, every) {
    var n = Math.max(2, Math.floor(Number(every) || 4))
    var done = Math.max(0, Math.floor(Number(cycle) || 0))
    var inRound = done % n
    // During a focus session it is the next one; after it (a break), the one just done.
    return phase === "focus" ? inRound + 1 : (inRound === 0 ? n : inRound)
}

// What to say when a phase has ended and the next begins.
function pomoNotice(next) {
    return next.phase === "focus" ? { title: "Back to focus", body: "Break over — " + Math.round(next.seconds / 60) + " minutes." }
         : { title: next.label, body: "Focus session done — " + Math.round(next.seconds / 60) + " minutes off." }
}

// ── Stopwatch laps ────────────────────────────────────────────────────────────
// `laps` are the elapsed times at each press, NEWEST FIRST (Timers.laps). The split of a lap is its time
// less the one before it (the next entry; the oldest is its own split).
function lapSplits(laps) {
    var l = Array.isArray(laps) ? laps : []
    return l.map(function (t, i) { return i + 1 < l.length ? t - l[i + 1] : t })
}

// The index (in the same newest-first order) of the fastest and slowest split — only meaningful with
// two or more laps and a real difference, else -1 for both.
function lapExtremes(laps) {
    var s = lapSplits(laps)
    if (s.length < 2) return { best: -1, worst: -1 }
    var best = 0, worst = 0
    for (var i = 1; i < s.length; i++) {
        if (s[i] < s[best]) best = i
        if (s[i] > s[worst]) worst = i
    }
    return s[best] === s[worst] ? { best: -1, worst: -1 } : { best: best, worst: worst }
}

// The laps as text for the clipboard, oldest first: "Lap 1  00:12.34  +00:12.34". `fmt` formats ms.
function lapsText(laps, fmt) {
    var l = Array.isArray(laps) ? laps : []
    var s = lapSplits(l)
    var out = []
    for (var i = l.length - 1; i >= 0; i--)
        out.push("Lap " + (l.length - i) + "  " + fmt(l[i]) + "  +" + fmt(s[i]))
    return out.join("\n")
}

// ── Extending a countdown ─────────────────────────────────────────────────────
// +N seconds on a running or paused one: the end moves and the span (what the ring is a fraction of)
// grows with it, so the ring never reads more than full.
function extend(spanSecs, remainSecs, addSecs) {
    var add = Math.max(0, Math.floor(Number(addSecs) || 0))
    return { span: Math.max(0, Math.floor(Number(spanSecs) || 0)) + add,
             remain: Math.max(0, Math.floor(Number(remainSecs) || 0)) + add }
}

// "Ends 14:32" — when a countdown with `remainSecs` left finishes, from `nowMs`, local time. A countdown
// that ends tomorrow says so.
function endsAt(nowMs, remainSecs) {
    var end = new Date(Number(nowMs) + Math.max(0, Number(remainSecs) || 0) * 1000)
    var now = new Date(Number(nowMs))
    var p = function (v) { return (v < 10 ? "0" : "") + v }
    var t = p(end.getHours()) + ":" + p(end.getMinutes())
    return end.getDate() === now.getDate() && end.getMonth() === now.getMonth() ? "Ends " + t : "Ends tomorrow " + t
}
