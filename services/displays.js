.pragma library

// ── displays.js ───────────────────────────────────────────────────────────────
// The logic half of Settings › Displays (services/Displays.qml): monitors as Hyprland
// reports them, the modes each one offers, where a dragged screen lands, and the spec
// handed to scripts/hypr-monitors.py --write-spec. Tested by scripts/test-displays.js.
//
// Units: Hyprland positions monitors in LOGICAL pixels — a 2560-wide panel at scale 2
// occupies 1280 of the layout, and a quarter-turn swaps width and height. Everything
// geometric here works in those units (`logical()`).
// ─────────────────────────────────────────────────────────────────────────────

// `hyprctl monitors -j` (or `monitors all -j`) → [{ name, desc, width, height, refresh,
// x, y, scale, transform, vrr, disabled, modes: [{ width, height, refresh, label }] }].
// Anything malformed is dropped rather than half-trusted.
function parseMonitors(text) {
    var raw
    try { raw = JSON.parse(String(text || "")) } catch (e) { return [] }
    if (!Array.isArray(raw)) return []
    var out = []
    raw.forEach(function (m) {
        if (!m || typeof m.name !== "string" || !validName(m.name)) return
        var modes = (m.availableModes || []).map(parseMode).filter(function (x) { return x !== null })
        out.push({
            name: m.name,
            desc: String(m.description || m.model || ""),
            width: m.width | 0, height: m.height | 0,
            refresh: Number(m.refreshRate) || 60,
            x: m.x | 0, y: m.y | 0,
            scale: Number(m.scale) || 1,
            transform: (m.transform | 0) & 7,
            vrr: m.vrr === true,
            disabled: m.disabled === true,
            modes: dedupeModes(modes)
        })
    })
    return out
}

function validName(n) { return /^[A-Za-z0-9._-]{1,64}$/.test(n) }

// "2560x1440@143.97Hz" → { width, height, refresh, label: "2560 × 1440 · 144 Hz" }.
function parseMode(s) {
    var m = /^(\d{2,5})x(\d{2,5})@(\d+(?:\.\d+)?)Hz$/.exec(String(s || ""))
    if (!m) return null
    var w = parseInt(m[1], 10), h = parseInt(m[2], 10), r = parseFloat(m[3])
    return { width: w, height: h, refresh: r, label: w + " × " + h + " · " + Math.round(r) + " Hz" }
}

// Monitors list many near-identical refresh rates (59.94 and 60.00); keep the highest of
// each rounded rate per resolution, biggest resolution first, then fastest.
function dedupeModes(modes) {
    var best = {}
    modes.forEach(function (m) {
        var k = m.width + "x" + m.height + "@" + Math.round(m.refresh)
        if (!best[k] || best[k].refresh < m.refresh) best[k] = m
    })
    return Object.keys(best).map(function (k) { return best[k] }).sort(function (a, b) {
        return (b.width * b.height - a.width * a.height) || (b.refresh - a.refresh)
    })
}

// The rectangle a monitor occupies in the layout, in logical pixels.
function logical(m) {
    var s = m.scale > 0 ? m.scale : 1
    var w = Math.round(m.width / s), h = Math.round(m.height / s)
    return (m.transform & 1) ? { w: h, h: w } : { w: w, h: h }
}

function _overlaps(a, b) {
    return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}

// Where `name` lands when dropped near (x, y): flush against one side of another enabled
// monitor (the nearest such spot), never overlapping one. Along that side it aligns to
// the neighbour's start edge, end edge or centre — in that order of preference — when the
// drop is within `snap` px of it, otherwise it stays where it was dropped. Logical px.
function snapPosition(monitors, name, x, y, snap) {
    snap = snap > 0 ? snap : 48
    var me = monitors.filter(function (m) { return m.name === name })[0]
    if (!me) return { x: x | 0, y: y | 0 }
    var sz = logical(me)
    var others = monitors.filter(function (m) { return m.name !== name && !m.disabled })
        .map(function (m) { var l = logical(m); return { x: m.x, y: m.y, w: l.w, h: l.h } })
    if (others.length === 0) return { x: 0, y: 0 }
    function align(free, options) {
        for (var i = 0; i < options.length; i++)
            if (Math.abs(options[i] - free) <= snap) return options[i]
        return free
    }
    var cands = []
    others.forEach(function (o) {
        var ys = [o.y, o.y + o.h - sz.h, o.y + Math.round((o.h - sz.h) / 2)]
        var xs = [o.x, o.x + o.w - sz.w, o.x + Math.round((o.w - sz.w) / 2)]
        cands.push({ x: o.x + o.w, y: align(y, ys) })     // right of it
        cands.push({ x: o.x - sz.w, y: align(y, ys) })    // left of it
        cands.push({ x: align(x, xs), y: o.y + o.h })     // below it
        cands.push({ x: align(x, xs), y: o.y - sz.h })    // above it
    })
    var best = null, bestD = Infinity
    cands.forEach(function (c) {
        var r = { x: c.x, y: c.y, w: sz.w, h: sz.h }
        if (others.some(function (o) { return _overlaps(r, o) })) return
        // Touching along an edge that shares some length, not corner to corner.
        var shares = others.some(function (o) {
            var vert = (r.x === o.x + o.w || r.x + r.w === o.x) && r.y < o.y + o.h && o.y < r.y + r.h
            var horz = (r.y === o.y + o.h || r.y + r.h === o.y) && r.x < o.x + o.w && o.x < r.x + r.w
            return vert || horz
        })
        if (!shares) return
        var d = Math.hypot(c.x - x, c.y - y)
        if (d < bestD) { best = c; bestD = d }
    })
    return best ? { x: Math.round(best.x), y: Math.round(best.y) } : { x: x | 0, y: y | 0 }
}

// Shift the whole layout so its top-left is (0, 0) — Hyprland is happy with negatives,
// but a written config that starts at 0x0 is the one people can read.
function normalise(monitors) {
    var on = monitors.filter(function (m) { return !m.disabled })
    if (on.length === 0) return monitors
    var minX = Math.min.apply(null, on.map(function (m) { return m.x }))
    var minY = Math.min.apply(null, on.map(function (m) { return m.y }))
    return monitors.map(function (m) { return Object.assign({}, m, { x: m.x - minX, y: m.y - minY }) })
}

// The spec hypr-monitors.py --write-spec reads: only the fields it writes.
function spec(monitors) {
    return normalise(monitors).map(function (m) {
        return m.disabled ? { name: m.name, disabled: true }
            : { name: m.name, width: m.width, height: m.height, refresh: m.refresh,
                x: m.x, y: m.y, scale: m.scale, transform: m.transform, vrr: m.vrr }
    })
}

// Does the edited layout differ from what's live? (Ignores fields the page can't change.)
function changed(live, edited) {
    return JSON.stringify(spec(live)) !== JSON.stringify(spec(edited))
}

// A refused layout: every monitor disabled leaves nothing to show the revert prompt on.
function problem(monitors) {
    if (monitors.length > 0 && monitors.every(function (m) { return m.disabled }))
        return "At least one screen has to stay on"
    return ""
}
