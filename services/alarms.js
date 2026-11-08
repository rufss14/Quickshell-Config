.pragma library

// ── alarms.js ─────────────────────────────────────────────────────────────────
// When an alarm goes off next, and how its repeat reads. Used by services/Timers.qml and the clock
// panel's Clocks page; tested by `bun scripts/test-alarms.js`.
//
// An alarm repeats on a set of weekdays held as a bitmask, bit 0 = Sunday … bit 6 = Saturday (the
// order Date.getDay() uses), so a day is `(mask >> date.getDay()) & 1`. 0 means no repeat: it
// goes off at the next h:m and is spent. Built from the LOCAL Date constructor, so "07:30"
// stays 07:30 across a daylight-saving change.
// ─────────────────────────────────────────────────────────────────────────────

var WEEKDAYS = 62        // Mon–Fri
var WEEKENDS = 65        // Sat, Sun
var EVERY_DAY = 127

// The first moment strictly after `nowMs` that is h:m on a day the mask allows.
function nextOccurrence(h, m, mask, nowMs) {
    const now = new Date(nowMs)
    for (let k = 0; k <= 7; k++) {
        const c = new Date(now.getFullYear(), now.getMonth(), now.getDate() + k, h, m, 0, 0)
        if (c.getTime() > nowMs && (!mask || ((mask >> c.getDay()) & 1))) return c.getTime()
    }
    return NaN      // a mask with no valid day bit (garbage): nothing to schedule
}

// The presets a single chip steps through.
var PRESETS = [0, WEEKDAYS, EVERY_DAY, WEEKENDS]
function nextPreset(mask) {
    const i = PRESETS.indexOf(mask)
    return PRESETS[(i + 1) % PRESETS.length]
}

// "Once", "Every day", "Weekdays", "Weekends", else "Mon Wed Fri" (Monday first).
function repeatLabel(mask) {
    if (!mask) return "Once"
    if (mask === EVERY_DAY) return "Every day"
    if (mask === WEEKDAYS) return "Weekdays"
    if (mask === WEEKENDS) return "Weekends"
    const names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    return [1, 2, 3, 4, 5, 6, 0].filter(function (d) { return (mask >> d) & 1 }).map(function (d) { return names[d] }).join(" ")
}

// A stored alarm's `days`: 0 unless it is a whole number 1..127.
function cleanMask(v) {
    return Number.isInteger(v) && v > 0 && v <= 127 ? v : 0
}
