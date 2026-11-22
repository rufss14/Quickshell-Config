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

// ── The island's Weather page ─────────────────────────────────────────────────
// Where the sun is between sunrise and sunset, for the arc on the sun plate. Local ISO times from
// the forecast's daily block (the same reading goldenHour makes). `frac` is 0..1 along the day and
// sits at an end while it is night; `leftS` is the daylight still to come, 0 outside it.
// → { state: "before" | "day" | "after", frac, lengthS, leftS } or null without both times.
function sunArc(sunriseIso, sunsetIso, nowMs) {
    if (!sunriseIso || !sunsetIso) return null
    const rise = new Date(sunriseIso).getTime(), set = new Date(sunsetIso).getTime()
    if (!isFinite(rise) || !isFinite(set) || set <= rise) return null
    const state = nowMs < rise ? "before" : nowMs >= set ? "after" : "day"
    return { state: state,
             frac: state === "before" ? 0 : state === "after" ? 1 : (nowMs - rise) / (set - rise),
             lengthS: (set - rise) / 1000,
             leftS: state === "day" ? (set - nowMs) / 1000 : 0 }
}

// The hours the page draws for one forecast day: today is the next 24 from the current hour
// (`hoursStart`, an index into `hours`), any other day is that day's own hours. `hours` is
// Weather.hours' shape.
function dayHours(hours, hoursStart, date, todayDate) {
    const hs = hours || []
    if (date === todayDate) {
        const s = Math.max(0, hoursStart | 0)
        return hs.slice(s, s + 24)
    }
    return hs.filter(function (h) { return h.date === date })
}

// The bars of a day's rain chance, one per hour, 0..1. `pick` marks the one hour that is the
// noon-ish one for a day with nothing scrubbed.
function chanceBars(hours) {
    return (hours || []).map(function (h) {
        return { v: Math.max(0, Math.min(1, (h.precip || 0) / 100)), snow: false }
    })
}

// The hour a day is judged by when nothing is scrubbed: the one at 12:00, else the middle one.
function middayOf(hours) {
    const hs = hours || []
    if (hs.length === 0) return null
    const noon = hs.find(function (h) { return h.hour === 12 })
    return noon || hs[Math.floor(hs.length / 2)]
}

// The colour role for an air quality figure: green through the fair band, amber to moderate, red beyond.
function aqiRole(eaqi) {
    return !isFinite(eaqi) || eaqi < 0 ? "fgDim" : eaqi <= 40 ? "success" : eaqi <= 60 ? "warning" : "danger"
}

// ── Blending several forecast models ──────────────────────────────────────────
// One model's idea of "now" can sit a degree or two off (and call a thunderstorm on a grey, dry
// afternoon). Asking Open-Meteo for several at once and keeping the MIDDLE of them is steadier than
// its single best guess: a model that is far out on its own is outvoted. The API then names every
// series with the model after it (`temperature_2m_gfs_seamless`), and a multi-model request has no
// blended `current`, so blend() rebuilds the response as ONE model's would have been (plain names,
// a `current`), and Weather._parse reads it as before. A response of one model passes through.
var MODELS = ["ecmwf_ifs025", "gfs_seamless", "icon_seamless", "ukmo_seamless", "meteofrance_seamless"];

function _num(v) { return typeof v === "number" && isFinite(v) }

function median(list) {
    var v = list.filter(_num).sort(function (a, b) { return a - b })
    if (v.length === 0) return null
    var m = v.length >> 1
    return v.length % 2 ? v[m] : (v[m - 1] + v[m]) / 2
}
function _mean(list) {
    var v = list.filter(_num)
    return v.length ? v.reduce(function (a, b) { return a + b }, 0) / v.length : null
}
// Directions average round the circle (350 and 10 are 0, not 180).
function _meanDir(list) {
    var v = list.filter(_num)
    if (v.length === 0) return null
    var s = 0, c = 0
    v.forEach(function (d) { s += Math.sin(d * Math.PI / 180); c += Math.cos(d * Math.PI / 180) })
    return Math.round((Math.atan2(s, c) * 180 / Math.PI + 360) % 360)
}
function _mode(list) {
    var count = {}
    list.forEach(function (c) { count[c] = (count[c] || 0) + 1 })
    return list.slice().sort(function (a, b) { return count[b] - count[a] || a - b })[0]
}

// The sky from the models' codes: a storm needs most of them to say so, fog likewise; rain needs some
// to fall (`precip` is the models' mean for the span, over `wetMm`) and then the commonest rain code
// wins; otherwise a dry sky is named by how much cloud there is (`cloud`, 0..100), or, with no cloud
// figure (a day), by the commonest dry code.
function blendCode(codes, precip, cloud, wetMm) {
    var cs = (codes || []).filter(_num)
    if (cs.length === 0) return 0
    var storm = cs.filter(function (c) { return c >= 95 })
    if (storm.length * 2 > cs.length) return _mode(storm)
    var fog = cs.filter(function (c) { return c === 45 || c === 48 })
    if (fog.length * 2 > cs.length) return _mode(fog)
    if (!_num(precip)) return _mode(cs)
    var wet = cs.filter(function (c) { return c >= 51 && c < 95 })
    if (precip >= wetMm && wet.length) return _mode(wet)
    if (_num(cloud)) return cloud < 20 ? 0 : cloud < 45 ? 1 : cloud < 75 ? 2 : 3
    var dry = cs.filter(function (c) { return c <= 3 })
    return dry.length ? _mode(dry) : 3
}

// The model a series name ends in, or "".
function _modelOf(key) {
    for (var i = 0; i < MODELS.length; i++)
        if (key.length > MODELS[i].length + 1 && key.slice(-(MODELS[i].length + 1)) === "_" + MODELS[i]) return MODELS[i]
    return ""
}

var _SUMS = { precipitation: 1, snowfall: 1, rain: 1, showers: 1, cloud_cover: 1, precipitation_sum: 1 }

// One block (hourly / daily / minutely_15) from per-model series to plain ones; null when the block names no model.
// `wetMm` is the amount, per step, at which the sky is called wet.
function _blendBlock(block, wetMm) {
    if (!block || !block.time) return null
    var groups = {}, any = false
    Object.keys(block).forEach(function (k) {
        if (k === "time") return
        var m = _modelOf(k)
        if (m === "") return
        any = true
        var base = k.slice(0, -(m.length + 1))
        ;(groups[base] = groups[base] || []).push(block[k])
    })
    if (!any) return null
    var out = { time: block.time }
    Object.keys(groups).forEach(function (base) {
        var series = groups[base]
        out[base] = block.time.map(function (_, i) {
            var pool = series.map(function (s) { return s ? s[i] : null })
            var first = pool.filter(function (v) { return v !== null && v !== undefined })[0]
            if (typeof first === "string") return first
            if (base.indexOf("wind_direction") === 0) return _meanDir(pool)
            if (_SUMS[base]) return _mean(pool)
            if (base === "is_day") { var m = median(pool); return m === null ? null : Math.round(m) }
            return median(pool)
        })
    })
    if (groups.weather_code)
        out.weather_code = block.time.map(function (_, i) {
            var codes = groups.weather_code.map(function (s) { return s ? s[i] : null })
            var p = out.precipitation ? out.precipitation[i] : out.precipitation_sum ? out.precipitation_sum[i] : null
            return blendCode(codes, p, out.cloud_cover ? out.cloud_cover[i] : null, wetMm)
        })
    return out
}

function _localIso(ms) {
    var d = new Date(ms)
    return d.getFullYear() + "-" + _pad(d.getMonth() + 1) + "-" + _pad(d.getDate()) + "T" + _pad(d.getHours()) + ":" + _pad(d.getMinutes())
}

// The response a single model would have given, from a multi-model one. `current` is the blended hours
// either side of `nowMs`, read at the minute (a straight line between them); the sky and the day/night
// flag are the nearer hour's, the rain the quarter hour's.
function blend(d, nowMs) {
    if (!d || !d.hourly) return d
    // Under half a millimetre an hour is drizzle the models disagree on, and a grey sky is the better word.
    var h = _blendBlock(d.hourly, 0.5)
    if (!h) return d
    var out = {}
    Object.keys(d).forEach(function (k) { out[k] = d[k] })
    out.hourly = h
    var dy = _blendBlock(d.daily, 1)
    if (dy) out.daily = dy
    var mq = _blendBlock(d.minutely_15, 0)
    if (mq) out.minutely_15 = mq

    var i = 0
    for (var j = 0; j < h.time.length; j++) if (new Date(h.time[j]).getTime() <= nowMs) i = j
    var t0 = new Date(h.time[i]).getTime()
    var f = i + 1 < h.time.length ? Math.max(0, Math.min(1, (nowMs - t0) / 3600000)) : 0
    function at(k) {
        var a = h[k] ? h[k][i] : null, b = h[k] && i + 1 < h.time.length ? h[k][i + 1] : null
        return !_num(a) ? (_num(b) ? b : null) : !_num(b) ? a : a + (b - a) * f
    }
    var near = f < 0.5 ? i : Math.min(i + 1, h.time.length - 1)
    var rain = h.precipitation ? h.precipitation[i] : null
    if (mq && mq.precipitation) {
        var slot = -1
        for (var s = 0; s < mq.time.length; s++) if (new Date(mq.time[s]).getTime() <= nowMs) slot = s
        if (slot >= 0 && _num(mq.precipitation[slot])) rain = mq.precipitation[slot]
    }
    out.current = {
        time: _localIso(nowMs),
        temperature_2m: at("temperature_2m"),
        apparent_temperature: at("apparent_temperature"),
        relative_humidity_2m: _num(at("relative_humidity_2m")) ? Math.round(at("relative_humidity_2m")) : null,
        wind_speed_10m: at("wind_speed_10m"),
        wind_gusts_10m: at("wind_gusts_10m"),
        uv_index: at("uv_index"),
        wind_direction_10m: h.wind_direction_10m ? h.wind_direction_10m[near] : null,
        weather_code: h.weather_code ? h.weather_code[near] : 0,
        is_day: h.is_day ? h.is_day[near] : 1,
        precipitation: rain
    }
    return out
}

// ── Places to switch between ──────────────────────────────────────────────────
// The saved cities are [{ name, lat, lon, countryCode }]. Two entries are the same place within a hundredth
// of a degree (about a kilometre), whatever they are called.
function sameCity(a, b) {
    return !!a && !!b && Math.abs(a.lat - b.lat) < 0.01 && Math.abs(a.lon - b.lon) < 0.01
}
function _validCity(c) {
    return !!c && typeof c.name === "string" && c.name !== "" && _num(c.lat) && _num(c.lon) && !(c.lat === 0 && c.lon === 0)
}
// The list the page offers: what was saved, in its order (so a chip never jumps when you switch), with the
// place you are on added at the end when it is not in it. `here` is that place, or null.
function cityList(saved, here) {
    var out = []
    ;(Array.isArray(saved) ? saved : []).forEach(function (c) {
        if (_validCity(c) && !out.some(function (o) { return sameCity(o, c) })) out.push(c)
    })
    if (_validCity(here) && !out.some(function (o) { return sameCity(o, here) })) out.push(here)
    return out
}
// `city` added (the oldest goes when there are more than `max`); one already there keeps its place.
function withCity(list, city, max) {
    var out = cityList(list, null)
    if (!_validCity(city)) return out
    if (!out.some(function (o) { return sameCity(o, city) })) out.push(city)
    var cap = max > 0 ? max : 8
    return out.length > cap ? out.slice(out.length - cap) : out
}
function withoutCity(list, city) {
    return cityList(list, null).filter(function (o) { return !sameCity(o, city) })
}
