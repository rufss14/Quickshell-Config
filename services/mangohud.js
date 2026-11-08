.pragma library

// ── mangohud.js ───────────────────────────────────────────────────────────────
// Reading and setting `fps_limit` in MangoHud.conf's text, for the HUD's FPS widget.
//
// The file is partly hand-tuned and partly generated (scripts/generate-mangohud-config
// owns marked regions), so this changes ONE line and nothing else: the first active
// `fps_limit=` line is rewritten, or one is appended when there is none. Comments,
// ordering and the generated regions are left alone. 0 means "no limit" to MangoHud.
//
// Tested (`bun scripts/test-hud.js`).
// ─────────────────────────────────────────────────────────────────────────────

var MAX_FPS = 1000

var _LINE = /^\s*fps_limit\s*=\s*([^#\r\n]*)/

// The first number of the active fps_limit (MangoHud allows a list, "60,30"), or null.
function readLimit(text) {
    var lines = String(text === undefined || text === null ? "" : text).split("\n")
    for (var i = 0; i < lines.length; i++) {
        var m = _LINE.exec(lines[i])
        if (!m) continue
        var n = parseInt(m[1], 10)
        return isFinite(n) && n >= 0 ? n : null
    }
    return null
}

// A whole integer 0..1000, or null when it isn't one.
function parseLimit(s) {
    var t = String(s === undefined || s === null ? "" : s).trim()
    if (!/^\d{1,4}$/.test(t)) return null
    var n = parseInt(t, 10)
    return n <= MAX_FPS ? n : null
}

// The text with fps_limit set. A limit that isn't valid returns the text unchanged.
function setLimit(text, fps) {
    var n = parseLimit(fps)
    var src = String(text === undefined || text === null ? "" : text)
    if (n === null) return src
    var lines = src.split("\n")
    for (var i = 0; i < lines.length; i++) {
        if (_LINE.test(lines[i])) {
            lines[i] = "fps_limit=" + n
            return lines.join("\n")
        }
    }
    var body = src.replace(/\n+$/, "")
    return (body === "" ? "" : body + "\n") + "fps_limit=" + n + "\n"
}
