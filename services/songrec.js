.pragma library

// ── songrec.js ────────────────────────────────────────────────────────────────
// Reading what `songrec listen --json` prints, and making links from it.
//
// ── Why it scans instead of parsing a line ────────────────────────────────────
// songrec streams one Shazam response per attempt, and a miss and a hit look alike
// (a response with `"matches": []` vs one with a `track`). Whether it prints each on one
// line or pretty-printed over many is not something its README pins down, and it also
// writes other chatter beside the JSON. So this does not assume lines: it walks the
// text, tracks braces and strings, and parses each top-level `{…}` it finds — a
// half-written object at the end of the buffer is simply not there yet, and is picked
// up when the rest arrives.
//
// ── Why the links are checked ─────────────────────────────────────────────────
// The track's url comes off the network and is handed to the browser. Only https goes
// through; anything else (javascript:, file:, a custom scheme) is dropped, and the
// service falls back to a search link it builds itself.
//
// Tested (`bun scripts/test-songrec.js`).
// ─────────────────────────────────────────────────────────────────────────────

// Every complete top-level JSON object in `text`, in order. Anything that isn't valid
// JSON (log chatter in braces) is skipped.
function objects(text) {
    var out = [], depth = 0, start = -1, inStr = false, esc = false
    var s = String(text === undefined || text === null ? "" : text)
    for (var i = 0; i < s.length; i++) {
        var c = s[i]
        if (inStr) {
            if (esc) esc = false
            else if (c === "\\") esc = true
            else if (c === "\"") inStr = false
            continue
        }
        if (c === "\"") { if (depth > 0) inStr = true; continue }
        if (c === "{") { if (depth === 0) start = i; depth++ }
        else if (c === "}" && depth > 0) {
            depth--
            if (depth === 0) {
                try { out.push(JSON.parse(s.slice(start, i + 1))) } catch (e) { }
                start = -1
            }
        }
    }
    return out
}

function _str(v) { return typeof v === "string" ? v.trim() : "" }

// https only. Returns "" for anything else.
function safeUrl(u) {
    var s = _str(u)
    return /^https:\/\/[^\s]+$/i.test(s) ? s : ""
}

// The first response in `text` that actually names a track, or null.
// { title, artist, url, art }
function pick(text) {
    var all = objects(text)
    for (var i = 0; i < all.length; i++) {
        var t = all[i] && all[i].track
        if (!t || typeof t !== "object") continue
        var title = _str(t.title)
        if (title === "") continue
        return {
            title:  title,
            artist: _str(t.subtitle),
            url:    safeUrl(t.url),
            art:    safeUrl(t.images && t.images.coverart)
        }
    }
    return null
}

// A YouTube search for the track — what the "open" action falls back to, and an
// alternative to Shazam's page.
function searchUrl(track) {
    var q = [track.title, track.artist].filter(function (p) { return p }).join(" ")
    return "https://www.youtube.com/results?search_query=" + encodeURIComponent(q)
}
