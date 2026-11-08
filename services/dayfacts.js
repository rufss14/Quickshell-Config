.pragma library

// ── dayfacts.js ───────────────────────────────────────────────────────────────
// Small facts about a day for the Calendar page: its ISO week, its place in the
// year, and the moon. Pure arithmetic, no network. Tested by
// `bun scripts/test-dayfacts.js`.
// ─────────────────────────────────────────────────────────────────────────────

const _DAY = 86400000

// ISO 8601 week: weeks start on Monday, and week 1 is the one holding the year's
// first Thursday — so 1 January can belong to the previous year's week 53.
function isoWeek(ms) {
    const d = new Date(ms)
    const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
    const dow = t.getUTCDay() || 7
    t.setUTCDate(t.getUTCDate() + 4 - dow)
    const yearStart = Date.UTC(t.getUTCFullYear(), 0, 1)
    return Math.ceil(((t.getTime() - yearStart) / _DAY + 1) / 7)
}

function dayOfYear(ms) {
    const d = new Date(ms)
    return Math.round((Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) - Date.UTC(d.getFullYear(), 0, 1)) / _DAY) + 1
}

function daysInYear(y) {
    return (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0 ? 366 : 365
}

function daysLeft(ms) {
    return daysInYear(new Date(ms).getFullYear()) - dayOfYear(ms)
}

// ── The moon ──────────────────────────────────────────────────────────────────
// The mean synodic month from a known new moon (6 Jan 2000, 18:14 UTC). The real
// month wobbles around the mean by up to about half a day, so a phase NAME is right
// to within a day of the change — plenty for "waxing crescent", not for astronomy.
const _SYNODIC = 29.530588853
const _NEW_MOON = Date.UTC(2000, 0, 6, 18, 14)

// → { phase: 0..1 (0 new, 0.5 full), illumination: 0..1, name, waxing }
function moon(ms) {
    let p = ((ms - _NEW_MOON) / _DAY / _SYNODIC) % 1
    if (p < 0) p += 1
    const name = p < 0.0339 || p >= 0.9661 ? "New moon"
               : p < 0.216                 ? "Waxing crescent"
               : p < 0.284                 ? "First quarter"
               : p < 0.466                 ? "Waxing gibbous"
               : p < 0.534                 ? "Full moon"
               : p < 0.716                 ? "Waning gibbous"
               : p < 0.784                 ? "Last quarter"
               :                             "Waning crescent"
    return { phase: p, illumination: (1 - Math.cos(2 * Math.PI * p)) / 2, name: name, waxing: p < 0.5 }
}
