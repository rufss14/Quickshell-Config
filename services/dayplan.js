.pragma library

// ── dayplan.js ────────────────────────────────────────────────────────────────
// One day as a strip: where its timed events fall on the 24 hours, which lane each sits in
// when they overlap, where "now" is, and whether you are free or busy right now. Used by the
// clock panel's Calendar page; tested by `bun scripts/test-dayplan.js`.
//
// Pure functions. Positions are FRACTIONS of the day (0..1), measured against that day's real
// length — 23 or 25 hours on a daylight-saving change — so a bar never runs off the strip.
// ─────────────────────────────────────────────────────────────────────────────

function dayBounds(y, m, d) {
    return { start: new Date(y, m, d).getTime(), end: new Date(y, m, d + 1).getTime() }
}

// occ: occurrences touching the day (ics.js onDay). All-day entries have no place on a clock,
// so they are left out. → [{ start, end, lane, summary, uid, source }] sorted by start; `start` and
// `end` are fractions, clipped to the day. A zero-length event gets a hair of width the strip
// can draw. `lanes` caps how many rows overlap into: past that, an event shares the last lane
// (drawn on top) rather than making the strip taller.
function layout(occ, dayStart, dayEnd, lanes) {
    const span = dayEnd - dayStart
    const cap = lanes > 0 ? lanes : 2
    const items = (occ || []).filter(function (o) {
        return o && !o.allDay && o.end >= dayStart && o.start < dayEnd
    }).sort(function (a, b) { return a.start - b.start || a.end - b.end })

    const laneEnd = []      // the time each lane is busy until
    return items.map(function (o) {
        const s = Math.max(o.start, dayStart), e = Math.min(Math.max(o.end, o.start), dayEnd)
        let lane = laneEnd.findIndex(function (t) { return t <= s })
        if (lane < 0) lane = laneEnd.length < cap ? laneEnd.length : cap - 1
        laneEnd[lane] = Math.max(laneEnd[lane] || 0, e)
        return { start: (s - dayStart) / span, end: (e - dayStart) / span, lane: lane,
                 summary: o.summary || "", uid: o.uid || "", source: o.source || "" }
    })
}

// How many lanes layout() used — the strip's height in rows.
function laneCount(items) {
    let n = 1
    for (let i = 0; i < items.length; i++) n = Math.max(n, items[i].lane + 1)
    return n
}

// Where `nowMs` is on the day, 0..1, or -1 when it is not that day.
function nowFraction(nowMs, dayStart, dayEnd) {
    return nowMs >= dayStart && nowMs < dayEnd ? (nowMs - dayStart) / (dayEnd - dayStart) : -1
}

// Free or busy at `nowMs`, from the day's timed occurrences (ms, not fractions).
// → { busy, until } — `until` is when that changes: the end of the run of back-to-back or
// overlapping events you are inside, or the start of the next one; null when nothing more
// is on today's list (free for the rest of it).
function status(occ, nowMs) {
    const items = (occ || []).filter(function (o) { return o && !o.allDay && o.end > o.start })
                             .sort(function (a, b) { return a.start - b.start })
    // Inside something? Follow the chain of events that touch or overlap it.
    let until = -1
    for (let i = 0; i < items.length; i++) {
        const o = items[i]
        if (o.start <= nowMs && o.end > nowMs) { until = Math.max(until, o.end) }
    }
    if (until >= 0) {
        let grew = true
        while (grew) {
            grew = false
            for (let i = 0; i < items.length; i++)
                if (items[i].start <= until && items[i].end > until) { until = items[i].end; grew = true }
        }
        return { busy: true, until: until }
    }
    const next = items.find(function (o) { return o.start > nowMs })
    return { busy: false, until: next ? next.start : null }
}
