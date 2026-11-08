.pragma library

// ── snap.js ───────────────────────────────────────────────────────────────────
// Snap zones (services/Snap): drag a FLOATING window to an edge or corner of the screen
// and it fills that half, quarter or the whole area — Windows 11's snap, for the windows
// Hyprland doesn't tile.
//
//     bun scripts/test-snap.js
//
// All in global layout pixels. `area` is a monitor's USABLE rectangle — minus what the
// bar and the sidebar reserve — so the top band sits just under the bar, never on it:
// a drop on the bar is the workspace pill's.
// ─────────────────────────────────────────────────────────────────────────────

// How close to an edge counts, and how far along an edge a corner reaches (a share of
// that side, capped).
var BAND = 24
var CORNER_FRAC = 0.18
var CORNER_MAX = 240

// The usable rectangle of a monitor: { x, y, w, h } from its origin, its logical size
// and Hyprland's reserved [left, top, right, bottom].
function usable(mon, reserved) {
    var r = reserved || [0, 0, 0, 0]
    return { x: mon.x + r[0], y: mon.y + r[1], w: mon.w - r[0] - r[2], h: mon.h - r[1] - r[3] }
}

// Which zone the pointer (px, py) is in: "max" (the top band), "left", "right",
// "tl" "tr" "bl" "br" (the corners), or "". Past the left, right and bottom edges of
// the area counts (that's the sidebar or the screen's edge); ABOVE the top doesn't
// (that's the bar).
function zoneAt(px, py, area) {
    if (!area || !(area.w > 0) || !(area.h > 0)) return ""
    var left = px <= area.x + BAND
    var right = px >= area.x + area.w - BAND
    var top = py >= area.y && py <= area.y + BAND
    var bottom = py >= area.y + area.h - BAND
    if (py < area.y) return ""
    var cw = Math.min(CORNER_MAX, area.w * CORNER_FRAC)
    var ch = Math.min(CORNER_MAX, area.h * CORNER_FRAC)
    var nearL = px <= area.x + cw, nearR = px >= area.x + area.w - cw
    var nearT = py <= area.y + ch, nearB = py >= area.y + area.h - ch
    if ((top && nearL) || (left && nearT)) return "tl"
    if ((top && nearR) || (right && nearT)) return "tr"
    if ((bottom && nearL) || (left && nearB)) return "bl"
    if ((bottom && nearR) || (right && nearB)) return "br"
    if (top) return "max"
    if (left) return "left"
    if (right) return "right"
    return ""
}

// Where a window in `zone` goes: { x, y, w, h }, whole pixels, with Hyprland's own gaps
// (gaps_out at the area's edges, gaps_in between two halves) so a snapped window lines
// up with tiled ones. null for no zone.
function rectFor(zone, area, gapsOut, gapsIn) {
    if (!zone || !area) return null
    var go = Math.max(0, gapsOut || 0), gi = Math.max(0, gapsIn || 0)
    var x0 = area.x + go, y0 = area.y + go
    var W = area.w - go * 2, H = area.h - go * 2
    var halfW = (W - gi) / 2, halfH = (H - gi) / 2
    var r
    switch (zone) {
    case "max":   r = { x: x0, y: y0, w: W, h: H }; break
    case "left":  r = { x: x0, y: y0, w: halfW, h: H }; break
    case "right": r = { x: x0 + halfW + gi, y: y0, w: halfW, h: H }; break
    case "tl":    r = { x: x0, y: y0, w: halfW, h: halfH }; break
    case "tr":    r = { x: x0 + halfW + gi, y: y0, w: halfW, h: halfH }; break
    case "bl":    r = { x: x0, y: y0 + halfH + gi, w: halfW, h: halfH }; break
    case "br":    r = { x: x0 + halfW + gi, y: y0 + halfH + gi, w: halfW, h: halfH }; break
    default:      return null
    }
    return { x: Math.round(r.x), y: Math.round(r.y), w: Math.max(1, Math.round(r.w)), h: Math.max(1, Math.round(r.h)) }
}

// The grid the desktop widgets snap to (Config.widgetGrid), for a window: where its
// top-left corner lands, or null if it is already there. `origin` is the monitor's
// top-left — the widget layer covers the whole monitor, so its dots start there — and
// `area` is the usable rectangle the window must stay inside (under the bar, beside the
// sidebar). The corner is pulled to the nearest grid point INSIDE the area; a window too
// big to have one is only clamped, since a grid point it can't reach is no use.
function gridPoint(win, origin, area, grid) {
    if (!win || !origin || !area) return null
    var g = Math.max(1, Math.round(grid || 0))
    function axis(pos, o, lo, hi) {
        var top = Math.max(lo, hi)              // a window bigger than the area: pin to lo
        var gLo = o + Math.ceil((lo - o) / g) * g
        var gHi = o + Math.floor((top - o) / g) * g
        var v = o + Math.round((pos - o) / g) * g
        if (gHi < gLo) return Math.min(Math.max(pos, lo), top)
        return Math.min(Math.max(v, gLo), gHi)
    }
    var x = axis(win.x, origin.x, area.x, area.x + area.w - win.w)
    var y = axis(win.y, origin.y, area.y, area.y + area.h - win.h)
    return x === win.x && y === win.y ? null : { x: x, y: y }
}

// The Lua Hyprland runs to put the window there: resize, then move (a move first would
// briefly hang a too-big window off the edge). The address is checked here — it goes
// into compositor Lua — and the numbers are integers we computed.
function dispatches(address, rect) {
    var a = String(address || "").toLowerCase()
    if (!/^(0x)?[0-9a-f]{1,16}$/.test(a) || !rect) return []
    if (a.indexOf("0x") !== 0) a = "0x" + a
    var w = 'window = "address:' + a + '"'
    if (rect.w === undefined) return ["hl.dsp.window.move({ x = " + rect.x + ", y = " + rect.y + ", " + w + " })"]
    return [
        "hl.dsp.window.resize({ x = " + rect.w + ", y = " + rect.h + ", " + w + " })",
        "hl.dsp.window.move({ x = " + rect.x + ", y = " + rect.y + ", " + w + " })"
    ]
}


// The overlay's label for a zone.
function label(zone) {
    switch (zone) {
    case "max": return "Fill the screen"
    case "left": return "Left half"
    case "right": return "Right half"
    case "tl": return "Top-left quarter"
    case "tr": return "Top-right quarter"
    case "bl": return "Bottom-left quarter"
    case "br": return "Bottom-right quarter"
    default: return ""
    }
}
