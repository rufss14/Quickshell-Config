.pragma library

// ── weather.js ────────────────────────────────────────────────────────────────
// The weather logic that isn't fetching: the rain nowcast and the plain-words bands
// (UV, air quality, wind direction, daylight, pollen). Used by services/Weather.qml,
// services/AirQuality.qml and the clock panel; tested by `bun scripts/test-weather.js`.
//
// Pure functions, no QML — the same reason palette.js and calc.js are .js files.
// ─────────────────────────────────────────────────────────────────────────────

const _SLOT_MS = 15 * 60 * 1000

// ── Rain nowcast ──────────────────────────────────────────────────────────────
// From Open-Meteo's 15-minute precipitation. Where no nowcast model covers the
// location, Open-Meteo interpolates these from the hourly forecast — still the best
// answer available, just coarser, so the wording stays approximate ("~20 min").
//
// A slot counts as wet at 0.1 mm — the smallest amount the API reports, and the
// usual "measurable precipitation" line. Intensity uses the standard rain-rate
// bands, converted from mm per 15 minutes to mm per hour.

function _wet(s) { return (s.mm || 0) >= 0.1 }

function intensity(mmPer15) {
    const perHour = mmPer15 * 4
    return perHour < 2.5 ? "Light" : perHour < 7.6 ? "Moderate" : "Heavy"
}

// slots: [{ t: epoch ms, mm, snowCm }] in time order.
// → { state: "dry" | "incoming" | "wet", kind: "rain" | "snow", minutes, text } or null
//   `minutes` is until it starts (incoming) / stops (wet); -1 when it doesn't.
function nowcast(slots, nowMs) {
    const future = (slots || []).filter(function (s) {
        return s && isFinite(s.t) && s.t + _SLOT_MS > nowMs
    })
    if (future.length === 0) return null

    const horizonMin = Math.round((future[future.length - 1].t + _SLOT_MS - nowMs) / 60000)
    const span = horizonMin >= 90 ? Math.round(horizonMin / 60) + " h" : horizonMin + " min"
    // Rounded to five minutes: the data is quarter-hourly, "~17 min" claims precision
    // it doesn't have. Under five real minutes is "soon" — decided on the RAW value,
    // or three minutes would round up and read as "~5 min".
    function minsUntil(t) {
        const raw = (t - nowMs) / 60000
        return raw < 5 ? 0 : Math.round(raw / 5) * 5
    }
    function describe(run) {
        const peak = Math.max.apply(null, run.map(function (s) { return s.mm || 0 }))
        const kind = run.some(function (s) { return (s.snowCm || 0) > 0 }) ? "snow" : "rain"
        return { kind: kind, words: intensity(peak) + " " + kind }
    }

    function name(kind) { return kind === "snow" ? "Snow" : "Rain" }

    if (_wet(future[0])) {
        const stop = future.findIndex(function (s) { return !_wet(s) })
        const run = stop < 0 ? future : future.slice(0, stop)
        const d = describe(run)
        if (stop < 0)
            return { state: "wet", kind: d.kind, minutes: -1, text: d.words + " for the next " + span,
                     short: name(d.kind) + " for " + span }
        const m = minsUntil(future[stop].t)
        return { state: "wet", kind: d.kind, minutes: m,
                 text: d.words + (m < 5 ? " stopping soon" : " stopping in ~" + m + " min"),
                 short: name(d.kind) + (m < 5 ? " ending soon" : " ends ~" + m + " min") }
    }

    const start = future.findIndex(_wet)
    if (start < 0)
        return { state: "dry", kind: "rain", minutes: -1, text: "No rain for the next " + span,
                 short: "Dry for " + span }

    let end = future.slice(start).findIndex(function (s) { return !_wet(s) })
    end = end < 0 ? future.length : start + end
    const d = describe(future.slice(start, end))
    const m = minsUntil(future[start].t)
    return { state: "incoming", kind: d.kind, minutes: m,
             text: d.words + (m < 5 ? " starting soon" : " starting in ~" + m + " min"),
             short: name(d.kind) + (m < 5 ? " soon" : " in ~" + m + " min") }
}

// The nowcast as bars, one per slot still to come: 0 for a dry slot, else up to 1 by how hard it
// rains (the square root of the amount, so the 0.1 mm that counts as wet is already a visible 0.23
// and a downpour does not flatten everything else; 1.9 mm per 15 min is the "heavy" line intensity() draws).
// → [{ v, snow }], at most `n`. Same filter as nowcast(): slots already over are dropped.
function bars(slots, nowMs, n) {
    return (slots || []).filter(function (s) {
        return s && isFinite(s.t) && s.t + _SLOT_MS > nowMs
    }).slice(0, n > 0 ? n : 12).map(function (s) {
        const mm = s.mm || 0
        return { v: _wet(s) ? Math.min(1, Math.sqrt(mm / 1.9)) : 0, snow: (s.snowCm || 0) > 0 }
    })
}

// ── Words ─────────────────────────────────────────────────────────────────────
function compass(deg) {
    if (!isFinite(deg)) return ""
    const names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    return names[((Math.round(((deg % 360) + 360) % 360 / 45)) % 8)]
}

// WHO UV index categories.
function uvLevel(uv) {
    if (!isFinite(uv)) return ""
    return uv < 3 ? "Low" : uv < 6 ? "Moderate" : uv < 8 ? "High" : uv < 11 ? "Very high" : "Extreme"
}

// European Air Quality Index bands, as Open-Meteo documents them.
function aqiLevel(eaqi) {
    if (!isFinite(eaqi) || eaqi < 0) return ""
    return eaqi <= 20 ? "Good" : eaqi <= 40 ? "Fair" : eaqi <= 60 ? "Moderate"
         : eaqi <= 80 ? "Poor" : eaqi <= 100 ? "Very poor" : "Extremely poor"
}

// 0..1 through those bands, for a meter — capped at 100, where "Very poor" ends.
function aqiRatio(eaqi) {
    return isFinite(eaqi) ? Math.max(0, Math.min(1, eaqi / 100)) : 0
}

// 46181.4 s → "12h 49m".
function duration(seconds) {
    if (!isFinite(seconds) || seconds < 0) return ""
    const mins = Math.round(seconds / 60)
    return Math.floor(mins / 60) + "h " + (mins % 60 < 10 ? "0" : "") + (mins % 60) + "m"
}

// Pollen from the air-quality response: the species actually present, most first.
// Values are null outside Europe (no model), which is "not covered", not "none".
// → { covered, items: [{ name, grains }] }
function pollen(current) {
    const species = [["alder_pollen", "Alder"], ["birch_pollen", "Birch"], ["grass_pollen", "Grass"],
                     ["mugwort_pollen", "Mugwort"], ["olive_pollen", "Olive"], ["ragweed_pollen", "Ragweed"]]
    let covered = false
    const items = []
    species.forEach(function (s) {
        const v = current ? current[s[0]] : null
        if (v === null || v === undefined || !isFinite(v)) return
        covered = true
        if (v > 0) items.push({ name: s[1], grains: v })
    })
    items.sort(function (a, b) { return b.grains - a.grains })
    return { covered: covered, items: items }
}

// ── The planner ───────────────────────────────────────────────────────────────
// "Dry until 17:00", "Rain 14:00–16:00", "Golden hour 17:58–18:58": what the hourly forecast
// means for the day, in words. An hour is WET at a 50 % chance of rain or 0.3 mm — the chance
// alone says "maybe", and a trace in the amount alone is not worth a coat.
//
// Hours are Weather.hours' shape — { date: "YYYY-MM-DD", hour, precip (%), precipMm } in order —
// and "now" is passed as the date and hour the place is in, so nothing here goes through a Date
// in the machine's zone (the forecast's own times are the place's).

function isWet(h) { return !!h && ((h.precip || 0) >= 50 || (h.precipMm || 0) >= 0.3) }

function _pad(n) { return n < 10 ? "0" + n : "" + n }
function _hh(n) { return _pad(n) + ":00" }

// "2026-10-12" → the next day's string, by calendar arithmetic (not 24 h of milliseconds).
function _nextDate(ds) {
    const p = ds.split("-")
    const d = new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10) + 1)
    return d.getFullYear() + "-" + _pad(d.getMonth() + 1) + "-" + _pad(d.getDate())
}

// "17:00", "tomorrow 03:00", "Thu 09:00" — the hour `h` seen from the day `nowDate`.
function _when(h, nowDate) {
    if (h.date === nowDate) return _hh(h.hour)
    if (h.date === _nextDate(nowDate)) return "tomorrow " + _hh(h.hour)
    const p = h.date.split("-")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][new Date(parseInt(p[0], 10), parseInt(p[1], 10) - 1, parseInt(p[2], 10)).getDay()]
         + " " + _hh(h.hour)
}

// From the current hour: how long the weather you are in lasts.
// → { state: "dry" | "wet", until: hour object | null, text } or null if `now` isn't in the data.
function dryWindow(hours, nowDate, nowHour) {
    const hs = hours || []
    const i0 = hs.findIndex(function (h) { return h.date === nowDate && h.hour === nowHour })
    if (i0 < 0) return null
    const wet = isWet(hs[i0])
    let until = null
    for (let j = i0 + 1; j < hs.length; j++) if (isWet(hs[j]) !== wet) { until = hs[j]; break }
    if (wet) return { state: "wet", until: until, text: until ? "Rain until " + _when(until, nowDate) : "Rain through the forecast" }
    return { state: "dry", until: until, text: until ? "Dry until " + _when(until, nowDate) : "No rain in the forecast" }
}

// One day's wet stretches: "Dry all day", "Rain 14:00–17:00", "Rain 08:00–10:00 · 15:00–17:00" (the
// first two). The end is the END of the last wet hour, so 14 and 15 wet reads 14:00–16:00.
// `dayHours` are one day's hours in order.
function rainSpans(dayHours) {
    const runs = []
    let cur = null
    ;(dayHours || []).forEach(function (h) {
        if (isWet(h)) { if (cur) cur.end = h.hour + 1; else { cur = { start: h.hour, end: h.hour + 1 }; runs.push(cur) } }
        else cur = null
    })
    if (runs.length === 0) return { runs: [], text: "Dry all day" }
    const shown = runs.slice(0, 2).map(function (r) { return _hh(r.start) + "–" + _hh(r.end) })
    return { runs: runs, text: "Rain " + shown.join(" · ") + (runs.length > 2 ? " …" : "") }
}

// The hour before sunset, when the light is low and warm. Local ISO times from the forecast's daily
// block. → { start, end: "HH:MM", live, over } against `nowMs`, or null without a sunset.
// (The morning one is the hour after sunrise; the panel shows the evening's, which is the one
// people plan around.)
function goldenHour(sunriseIso, sunsetIso, nowMs) {
    if (!sunsetIso || !isFinite(new Date(sunsetIso).getTime())) return null
    const set = new Date(sunsetIso).getTime(), start = set - 3600000
    return { start: _hm(start), end: _hm(set), live: nowMs >= start && nowMs < set, over: nowMs >= set }
}
function _hm(ms) { const d = new Date(ms); return _pad(d.getHours()) + ":" + _pad(d.getMinutes()) }
