.pragma library

// ── mixermemory.js ────────────────────────────────────────────────────────────
// The logic of the audio mixer's per-app memory, as pure functions (bun scripts/test-mixermemory.js):
// "Spotify opens at 40% and plays through the headset" — one small record per APP the user pinned, keyed by the
// app's lower-cased id (Audio.appIdFor). cleanMemory is what comes off disk. (Quiet / Gaming / Call presets lived
// here for an afternoon, 2026-11-07, and were removed at the user's request.)
//
// Nothing here touches PipeWire; services/MixerMemory.qml reads the live state in and writes the record out.
// ─────────────────────────────────────────────────────────────────────────────

var MAX_APPS = 40
var CEILING = 1.30          // volumeprofiles.js CEILING — the loudest anything goes

function clampLevel(v) {
    var n = Number(v)
    if (!isFinite(n)) return 1
    return Math.max(0, Math.min(CEILING, n))
}

// An app's key: its id, trimmed and lower-cased. "" when there is nothing usable (it becomes a JSON key).
function keyOf(appId) {
    var k = String(appId === undefined || appId === null ? "" : appId).trim().toLowerCase()
    return k.length > 0 && k.length <= 80 ? k : ""
}

function _rec(r) {
    return {
        level: Math.round(clampLevel(r.level) * 100) / 100,
        muted: r.muted === true,
        sink: typeof r.sink === "string" ? r.sink.slice(0, 160) : "",
        name: typeof r.name === "string" ? r.name.slice(0, 60) : "",
        at: r.at > 0 ? Math.round(r.at) : 0
    }
}

// Whatever came off disk → a well-formed { key: record } map, newest 40 kept.
function cleanMemory(raw) {
    var apps = raw && typeof raw === "object" && raw.apps && typeof raw.apps === "object" ? raw.apps : {}
    var rows = []
    for (var k in apps) {
        var key = keyOf(k)
        var r = apps[k]
        if (key === "" || key !== k || !r || typeof r !== "object" || !isFinite(Number(r.level))) continue
        rows.push([key, _rec(r)])
    }
    rows.sort(function (a, b) { return b[1].at - a[1].at })
    var out = {}
    for (var i = 0; i < rows.length && i < MAX_APPS; i++) out[rows[i][0]] = rows[i][1]
    return out
}

// A new map with `key` set to `patch` laid over what was there. The oldest falls off past MAX_APPS.
function remember(map, key, patch, now) {
    var k = keyOf(key)
    if (k === "") return map
    var out = {}
    for (var m in map) out[m] = map[m]
    var base = map[k] || { level: 1, muted: false, sink: "", name: "", at: 0 }
    var next = {}
    for (var p in base) next[p] = base[p]
    for (var q in patch) next[q] = patch[q]
    next.at = now
    out[k] = _rec(next)
    return cleanMemory({ apps: out })
}

function forget(map, key) {
    var k = keyOf(key)
    if (!(k in map)) return map
    var out = {}
    for (var m in map) if (m !== k) out[m] = map[m]
    return out
}
