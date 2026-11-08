.pragma library

// ── holidays.js ───────────────────────────────────────────────────────────────
// Nager.Date's PublicHolidays response → the calendar's special dates, keyed by
// local day. Used by services/Calendar.qml; tested by `bun scripts/test-holidays.js`.
//
// ── Three kinds, from two fields ──────────────────────────────────────────────
// Measured against the live API (PT, DE): every entry has `types` and `global`.
//   · national   — a "Public" holiday for the whole country (`global: true`)
//   · regional   — "Public", but only somewhere (`global: false`, `counties` set):
//                  Portugal's Azores and Madeira days
//   · observance — any entry without "Public": "Optional" (Portugal's Carnival),
//                  "Bank", "School", "Authorities", "Observance"
// The kind decides how loudly the grid marks a day; a regional holiday is still
// marked, because a user in that region does have the day off.
//
// The response is someone else's JSON, so entries without a usable date or name
// are skipped, and names are capped.
// ─────────────────────────────────────────────────────────────────────────────

const _RANK = { national: 0, regional: 1, observance: 2 }

// "Y-M-D", unpadded — the same key the month grid builds from (y, m + 1, d).
function key(y, m1, d) { return y + "-" + m1 + "-" + d }

// → { "Y-M-D": [{ name, english, kind }] }, strongest kind first within a day.
function classify(list) {
    const out = {}
    ;(Array.isArray(list) ? list : []).forEach(function (h) {
        if (!h || typeof h.date !== "string") return
        const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(h.date)
        if (!m) return
        const local = String(h.localName || "").trim()
        const english = String(h.name || "").trim()
        const name = (local || english).slice(0, 120)
        if (name === "") return
        const types = Array.isArray(h.types) ? h.types : []
        const kind = types.indexOf("Public") < 0 ? "observance"
                   : h.global === false          ? "regional"
                   :                               "national"
        const k = key(+m[1], +m[2], +m[3])
        if (!out[k]) out[k] = []
        out[k].push({ name: name, english: english !== name ? english.slice(0, 120) : "", kind: kind })
    })
    for (const k in out) out[k].sort(function (a, b) { return _RANK[a.kind] - _RANK[b.kind] })
    return out
}

// The first day from `fromMs` (inclusive) with a special date, within `maxDays`.
// → { day: local-midnight ms, entries } or null.
function next(map, fromMs, maxDays) {
    if (!map) return null
    const s = new Date(fromMs)
    const limit = maxDays > 0 ? maxDays : 400
    for (let i = 0; i <= limit; i++) {
        const d = new Date(s.getFullYear(), s.getMonth(), s.getDate() + i)
        const entries = map[key(d.getFullYear(), d.getMonth() + 1, d.getDate())]
        if (entries && entries.length) return { day: d.getTime(), entries: entries }
    }
    return null
}

function kindLabel(kind) {
    return kind === "national" ? "Public holiday"
         : kind === "regional" ? "Regional holiday"
         : kind === "observance" ? "Observance" : ""
}
