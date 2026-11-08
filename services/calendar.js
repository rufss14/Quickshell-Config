.pragma library

// ── calendar.js ───────────────────────────────────────────────────────────────
// The date arithmetic the Calendar tile needs and Qt's Date does not give: ISO week
// numbers, how far through the year it is, and "in 5 days". Pure functions, tested by
// scripts/test-calendar.js.
//
// Everything works on whole LOCAL days. Differences go through Date.UTC of the
// y/m/d parts, never through subtracting two local Dates: across a daylight-saving
// change that is 23 or 25 hours, and dividing by 86400000 then rounds a day wrong.

function _utc(d) { return Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) }

// Whole days from a to b (b later = positive).
function daysBetween(a, b) { return Math.round((_utc(b) - _utc(a)) / 86400000) }

function isLeap(y) { return (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0 }
function daysInYear(y) { return isLeap(y) ? 366 : 365 }

// 1-based: 1 January is day 1.
function dayOfYear(d) { return daysBetween(new Date(d.getFullYear(), 0, 1), d) + 1 }

// ISO 8601 week: weeks start Monday, and week 1 is the one holding the year's first
// Thursday — so the first days of January can be week 52/53, and the last days of
// December can be week 1.
function isoWeek(d) {
    const day = (d.getDay() + 6) % 7                       // Monday = 0
    const thursday = new Date(d.getFullYear(), d.getMonth(), d.getDate() - day + 3)
    return Math.floor((dayOfYear(thursday) - 1) / 7) + 1
}

// "Today", "Tomorrow", "in 5 days", "3 days ago".
function relative(n) {
    if (n === 0)  return "Today"
    if (n === 1)  return "Tomorrow"
    if (n === -1) return "Yesterday"
    return n > 0 ? "in " + n + " days" : -n + " days ago"
}

// The date a countdown points at, or null if `dateStr` isn't "YYYY-MM-DD". Parsed field
// by field, never with `new Date(str)`: a bare "2026-12-25" is UTC midnight by the ES
// spec, so east of Greenwich it silently becomes the day before. A `recurring` date
// (birthday, anniversary) ignores its year and runs to the NEXT occurrence, today
// included.
function nextDate(dateStr, recurring, now) {
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateStr || "")
    if (!m) return null
    const mon = Number(m[2]) - 1, dom = Number(m[3])
    let d
    if (recurring) {
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        d = new Date(now.getFullYear(), mon, dom)
        if (d.getTime() < today.getTime()) d = new Date(now.getFullYear() + 1, mon, dom)
    } else {
        d = new Date(Number(m[1]), mon, dom)
    }
    return isNaN(d.getTime()) ? null : d
}
