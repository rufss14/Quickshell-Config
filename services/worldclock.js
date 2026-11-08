.pragma library

// ── worldclock.js ─────────────────────────────────────────────────────────────
// The arithmetic behind the clock panel's world clocks: what time it is in a zone given its UTC
// offset, whether that is today, tomorrow or yesterday HERE, how far ahead it is, and finding a
// zone from a few typed letters. Tested by `bun scripts/test-worldclock.js`.
//
// QML's JavaScript has no time zones — a Date is the machine's and nothing else — so the offsets
// come from the system (services/WorldClock.qml asks `date`), and this turns an offset into a
// wall-clock reading with plain UTC arithmetic.
// ─────────────────────────────────────────────────────────────────────────────

// An IANA name as `timedatectl` lists them: "Europe/London", "America/Argentina/Buenos_Aires",
// "UTC". Checked before one is stored or handed to `date` as an argument.
function validZone(z) {
    return typeof z === "string" && z.length <= 60 && /^[A-Za-z][A-Za-z0-9_+\-]*(\/[A-Za-z0-9_+\-]+){0,2}$/.test(z)
}

// `date +%z` → minutes east of UTC: "+0530" → 330, "-0300" → -180. NaN for anything else.
function parseOffset(s) {
    const m = /^([+-])(\d{2})(\d{2})$/.exec(String(s || "").trim())
    if (!m) return NaN
    const mins = parseInt(m[2], 10) * 60 + parseInt(m[3], 10)
    return m[1] === "-" ? -mins : mins
}

// "America/Argentina/Buenos_Aires" → "Buenos Aires"; "UTC" → "UTC".
function cityName(zone) {
    const parts = String(zone).split("/")
    return parts[parts.length - 1].replace(/_/g, " ")
}
// …and where it is: "America · Argentina". "" for a bare name.
function regionName(zone) {
    const parts = String(zone).split("/")
    return parts.slice(0, -1).join(" · ").replace(/_/g, " ")
}

function _dayNumber(wallMs) {
    const d = new Date(wallMs)
    return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) / 86400000
}

// The wall clock in a zone at `nowMs`, and which day that is relative to the viewer's own.
// → { h, m, dayShift: -1 | 0 | 1 (or beyond, never in practice) }
function zoneTime(nowMs, offMin, localOffMin) {
    const wall = nowMs + offMin * 60000
    const d = new Date(wall)
    return { h: d.getUTCHours(), m: d.getUTCMinutes(),
             dayShift: Math.round(_dayNumber(wall) - _dayNumber(nowMs + localOffMin * 60000)) }
}

function dayWord(shift) { return shift === 0 ? "Today" : shift > 0 ? "Tomorrow" : "Yesterday" }

// How far ahead of (or behind) the viewer: "same time", "+8 h", "−3 h", "+5:30 h".
function diffLabel(offMin, localOffMin) {
    const diff = offMin - localOffMin
    if (diff === 0) return "same time"
    const a = Math.abs(diff), h = Math.floor(a / 60), m = a % 60
    return (diff > 0 ? "+" : "−") + h + (m ? ":" + (m < 10 ? "0" + m : m) : "") + " h"
}

// Day or night at that wall-clock hour — a plain 06:00–18:00, not an astronomical answer, which
// is all an icon beside a clock needs.
function isDay(h) { return h >= 6 && h < 18 }

// Zones matching what was typed, best first, at most `max`. A city that is exactly the query,
// then one that starts with it, then one with a word that does, then any that contains it
// ("york" finds New York; "new y" does too). Underscores and slashes count as spaces.
function search(zones, query, max) {
    const q = String(query || "").toLowerCase().trim().replace(/[_\/]+/g, " ")
    if (q === "") return []
    const scored = []
    ;(zones || []).forEach(function (z) {
        const city = cityName(z).toLowerCase()
        const full = String(z).toLowerCase().replace(/[_\/]+/g, " ")
        let score = -1
        if (city === q) score = 0
        else if (city.indexOf(q) === 0) score = 1
        else if (city.split(" ").some(function (w) { return w.indexOf(q) === 0 })) score = 2
        else if (full.indexOf(q) >= 0) score = 3
        if (score >= 0) scored.push({ z: z, score: score })
    })
    scored.sort(function (a, b) { return a.score - b.score || (a.z < b.z ? -1 : a.z > b.z ? 1 : 0) })
    return scored.slice(0, max > 0 ? max : 6).map(function (s) { return s.z })
}

// ── The planner ribbon ────────────────────────────────────────────────────────
// A 24-hour window on the VIEWER's timeline, one ribbon per zone, so what is daylight (or office
// hours) in each lines up vertically with what is in the others — the classic meeting planner.
//
// The window starts six hours before the current hour, so "now" sits a quarter of the way in with
// the evening still ahead; it moves only when the hour does.
function windowStart(nowMs) { return Math.floor(nowMs / 3600000) * 3600000 - 6 * 3600000 }
var WINDOW_MS = 24 * 3600000

// The stretches of the window that fall between zone-local hours `fromH` and `toH` (06–18 is its
// daylight, 09–17 its office hours), as fractions of the window: [{ a, b }]. Zone-local midnight
// comes from the offset alone, so each stretch lands where it really is on the viewer's line.
function bands(winStartMs, offMin, fromH, toH) {
    const winEnd = winStartMs + WINDOW_MS
    // Zone-local midnight of the day containing the window's start, as an absolute instant.
    const localMid = Math.floor((winStartMs + offMin * 60000) / 86400000) * 86400000 - offMin * 60000
    const out = []
    for (let k = 0; k <= 2; k++) {
        const a = Math.max(winStartMs, localMid + k * 86400000 + fromH * 3600000)
        const b = Math.min(winEnd,     localMid + k * 86400000 + toH   * 3600000)
        if (b > a) out.push({ a: (a - winStartMs) / WINDOW_MS, b: (b - winStartMs) / WINDOW_MS })
    }
    return out
}

// A dragged-to fraction of the window → an instant, on the quarter hour (a meeting is not at 03:07).
function pointAt(winStartMs, frac) {
    const f = Math.max(0, Math.min(1, frac))
    return Math.round((winStartMs + f * WINDOW_MS) / 900000) * 900000
}
