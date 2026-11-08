.pragma library

// ── snip.js ───────────────────────────────────────────────────────────────────
// The snip tool's geometry, as pure functions: what a drag selects, which window a
// click means, and the crop that turns a logical-pixel selection into the screenshot's
// own pixels.
//
// ── Three coordinate spaces, and where each ends ──────────────────────────────
//   logical, screen-local   what the overlay's pointer reports (0,0 = the screen's corner)
//   logical, global         the compositor's layout (what slurp prints, what Lens and the
//                           clip recorder take): the screen's own x/y added
//   image pixels            the frozen grim capture: logical × the screen's scale factor
// A selection is made in the first, handed to Lens/Clips in the second and cropped from
// the file in the third. Mixing them is the bug this file exists to make testable.
//
// The crop is an ARGV (["magick", src, "-crop", …]) and never a shell string, so no path
// can inject anything.
//
// Tested (`bun scripts/test-snip.js`).
// ─────────────────────────────────────────────────────────────────────────────

var MIN_DRAG = 4        // logical px of movement before a press becomes a drag

function rectFromPoints(a, b) {
    var x = Math.min(a.x, b.x), y = Math.min(a.y, b.y)
    return { x: x, y: y, w: Math.abs(a.x - b.x), h: Math.abs(a.y - b.y) }
}

// Inside the screen (0,0,W,H); null if nothing of it is.
function clampRect(r, W, H) {
    var x0 = Math.max(0, r.x), y0 = Math.max(0, r.y)
    var x1 = Math.min(W, r.x + r.w), y1 = Math.min(H, r.y + r.h)
    return (x1 - x0 < 1 || y1 - y0 < 1) ? null : { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }
}

function movedEnough(a, b) {
    return Math.abs(a.x - b.x) >= MIN_DRAG || Math.abs(a.y - b.y) >= MIN_DRAG
}

// Which window a click means: the SMALLEST of those under the point. Hyprland doesn't say
// what is stacked above what, and the smallest is the right guess for the usual case — a
// floating window or a tile over a bigger one behind it. `wins`: [{ x, y, w, h, … }] in
// the same space as the point.
function windowAt(wins, px, py) {
    var best = null, bestArea = Infinity
    for (var i = 0; i < wins.length; i++) {
        var w = wins[i]
        if (px < w.x || py < w.y || px >= w.x + w.w || py >= w.y + w.h) continue
        var a = w.w * w.h
        if (a < bestArea) { best = w; bestArea = a }
    }
    return best
}

// Logical → the capture's pixels. At least 1×1, whole numbers.
function toPixels(r, scale) {
    var s = scale > 0 ? scale : 1
    var x = Math.round(r.x * s), y = Math.round(r.y * s)
    return { x: x, y: y,
             w: Math.max(1, Math.round((r.x + r.w) * s) - x),
             h: Math.max(1, Math.round((r.y + r.h) * s) - y) }
}

function geom(r) {
    return Math.round(r.w) + "x" + Math.round(r.h) + "+" + Math.round(r.x) + "+" + Math.round(r.y)
}

function cropArgs(src, px, dst) {
    return ["magick", src, "-crop", geom(px), "+repage", dst]
}

// A selection in the compositor's global layout (for Lens and the recorder).
function toGlobal(r, screenX, screenY) {
    return { x: r.x + screenX, y: r.y + screenY, w: r.w, h: r.h }
}

// A file-name-safe output name (DP-1, eDP-1, HDMI-A-1); anything else becomes "_".
function safeName(name) {
    return String(name || "").replace(/[^A-Za-z0-9._-]/g, "_")
}

// ── An adjustable selection ───────────────────────────────────────────────────
// After a drag the selection stays up with eight handles, so it can be moved and resized
// before anything is done with it. All of it is arithmetic on a rectangle {x, y, w, h}
// inside a screen of W × H logical pixels.

var HANDLES = ["nw", "n", "ne", "e", "se", "s", "sw", "w"]
var MIN_SIZE = 8

function fullRect(W, H) { return { x: 0, y: 0, w: W, h: H } }

// The eight handle centres.
function handlePoints(r) {
    var cx = r.x + r.w / 2, cy = r.y + r.h / 2, x1 = r.x + r.w, y1 = r.y + r.h
    return { nw: { x: r.x, y: r.y }, n: { x: cx, y: r.y }, ne: { x: x1, y: r.y },
             e: { x: x1, y: cy }, se: { x: x1, y: y1 }, s: { x: cx, y: y1 },
             sw: { x: r.x, y: y1 }, w: { x: r.x, y: cy } }
}

// What a press at (px, py) grabs: a handle's name, "move" (inside the box), or "" (outside).
// `size` is the handle's grab radius. A box too small to leave room between its handles is
// all "move" except its corners, which otherwise could never be grabbed apart.
function hitHandle(r, px, py, size) {
    var pts = handlePoints(r)
    var best = "", bestD = Infinity
    for (var i = 0; i < HANDLES.length; i++) {
        var h = HANDLES[i], p = pts[h]
        var d = Math.max(Math.abs(px - p.x), Math.abs(py - p.y))
        // Corners win over edges when both are in reach.
        if (d <= size && d < bestD - (h.length === 2 ? 0.5 : 0)) { best = h; bestD = d }
    }
    if (best !== "") return best
    if (px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h) return "move"
    return ""
}

// Slide the whole box by (dx, dy), kept inside the screen without squashing it.
function moveRect(r, dx, dy, W, H) {
    var x = Math.max(0, Math.min(W - r.w, r.x + dx))
    var y = Math.max(0, Math.min(H - r.h, r.y + dy))
    return { x: x, y: y, w: r.w, h: r.h }
}

// Drag `handle` of the ORIGINAL rect `r` by (dx, dy). Edges move independently, may cross
// (dragging the left edge past the right flips the box), stay on screen, and never leave less
// than MIN_SIZE.
function resizeRect(r, handle, dx, dy, W, H) {
    var l = r.x, t = r.y, rt = r.x + r.w, b = r.y + r.h
    if (handle.indexOf("w") >= 0) l += dx
    if (handle.indexOf("e") >= 0) rt += dx
    if (handle.indexOf("n") >= 0) t += dy
    if (handle.indexOf("s") >= 0) b += dy
    l = Math.max(0, Math.min(W, l)); rt = Math.max(0, Math.min(W, rt))
    t = Math.max(0, Math.min(H, t)); b = Math.max(0, Math.min(H, b))
    var x0 = Math.min(l, rt), x1 = Math.max(l, rt), y0 = Math.min(t, b), y1 = Math.max(t, b)
    if (x1 - x0 < MIN_SIZE) { if (x0 + MIN_SIZE <= W) x1 = x0 + MIN_SIZE; else x0 = x1 - MIN_SIZE }
    if (y1 - y0 < MIN_SIZE) { if (y0 + MIN_SIZE <= H) y1 = y0 + MIN_SIZE; else y0 = y1 - MIN_SIZE }
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }
}

// The pointer cursor for a hit, as a Qt.CursorShape NAME (the view maps it).
function cursorFor(hit) {
    switch (hit) {
    case "nw": case "se": return "sizeFDiag"
    case "ne": case "sw": return "sizeBDiag"
    case "n": case "s":   return "sizeVer"
    case "e": case "w":   return "sizeHor"
    case "move":          return "sizeAll"
    default:              return "cross"
    }
}

// ── A locked aspect ratio ─────────────────────────────────────────────────────
// `ratio` is width / height (16/9, 1, 9/16); 0 or less means free, and none of these is
// called then. Every function returns a NEW rect and keeps it inside the W × H screen: when
// the ratio and the screen disagree the box shrinks (never stretches off-screen, never goes
// out of ratio).

// A box grown from a fixed corner `a` toward the pointer `p`: the larger of the two
// directions wins, so the box always reaches at least as far as the pointer does. Used for
// dragging a fresh selection and for a corner handle (whose anchor is the opposite corner).
function ratioFromAnchor(a, p, ratio, W, H) {
    var sx = p.x >= a.x ? 1 : -1, sy = p.y >= a.y ? 1 : -1
    var w = Math.abs(p.x - a.x), h = Math.abs(p.y - a.y)
    if (w < h * ratio) w = h * ratio; else h = w / ratio
    var maxW = sx > 0 ? W - a.x : a.x, maxH = sy > 0 ? H - a.y : a.y
    var k = Math.min(1, w > 0 ? maxW / w : 1, h > 0 ? maxH / h : 1)
    w *= k; h *= k
    return { x: sx > 0 ? a.x : a.x - w, y: sy > 0 ? a.y : a.y - h, w: w, h: h }
}

// Drag `handle` of the ORIGINAL rect `r` by (dx, dy), keeping the ratio. A corner holds the
// opposite corner still; an edge holds the opposite edge still and grows the other side about
// its middle.
function resizeRatio(r, handle, dx, dy, ratio, W, H) {
    if (handle.length === 2) {
        var east = handle.indexOf("e") >= 0, south = handle.indexOf("s") >= 0
        var a = { x: east ? r.x : r.x + r.w, y: south ? r.y : r.y + r.h }
        var p = { x: (east ? r.x + r.w : r.x) + dx, y: (south ? r.y + r.h : r.y) + dy }
        return ratioFromAnchor(a, p, ratio, W, H)
    }
    var cx = r.x + r.w / 2, cy = r.y + r.h / 2, w, h
    if (handle === "n" || handle === "s") {
        h = Math.max(MIN_SIZE, handle === "s" ? r.h + dy : r.h - dy)
        var maxH = Math.min(handle === "s" ? H - r.y : r.y + r.h, W / ratio, 2 * Math.min(cx, W - cx) / ratio)
        h = Math.min(h, maxH); w = h * ratio
        return { x: cx - w / 2, y: handle === "s" ? r.y : r.y + r.h - h, w: w, h: h }
    }
    w = Math.max(MIN_SIZE, handle === "e" ? r.w + dx : r.w - dx)
    var maxW = Math.min(handle === "e" ? W - r.x : r.x + r.w, H * ratio, 2 * Math.min(cy, H - cy) * ratio)
    w = Math.min(w, maxW); h = w / ratio
    return { x: handle === "e" ? r.x : r.x + r.w - w, y: cy - h / 2, w: w, h: h }
}

// The biggest box of `ratio` that fits INSIDE `r`, about its middle — what choosing a ratio
// does to a selection that is already up.
function fitRatio(r, ratio) {
    var w = r.w, h = r.h
    if (w / h > ratio) w = h * ratio; else h = w / ratio
    return { x: r.x + (r.w - w) / 2, y: r.y + (r.h - h) / 2, w: w, h: h }
}

// A size typed in the capture's own pixels, as a logical box: the top-left stays put and the
// box is pushed back on screen (and shrunk if it is bigger than the screen).
function sizeRect(r, pxW, pxH, scale, W, H) {
    var s = scale > 0 ? scale : 1
    var w = Math.min(W, Math.max(1, pxW / s)), h = Math.min(H, Math.max(1, pxH / s))
    return { x: Math.max(0, Math.min(W - w, r.x)), y: Math.max(0, Math.min(H - h, r.y)), w: w, h: h }
}

// A ratio as the label the menu shows: "16:9", or "" for free.
function ratioLabel(ratio) {
    var known = [[1, "1:1"], [4 / 3, "4:3"], [3 / 2, "3:2"], [16 / 9, "16:9"], [9 / 16, "9:16"]]
    for (var i = 0; i < known.length; i++) if (Math.abs(known[i][0] - ratio) < 1e-6) return known[i][1]
    return ratio > 0 ? ratio.toFixed(2) + ":1" : ""
}

// ── A live pin ────────────────────────────────────────────────────────────────
// A pin that keeps updating shows its SOURCE live: a window when the selection is exactly one,
// otherwise a region of the screen. A region of the screen includes whatever is drawn over it —
// the pin itself — so a live pin must not sit on its own source. These two keep it off it.

// The window whose rectangle IS this selection (within `tol` px on every side), or null.
// `wins`: [{ x, y, w, h, … }] and `r` in the same space; the smallest match wins.
function matchWindow(wins, r, tol) {
    var best = null, bestArea = Infinity
    for (var i = 0; i < wins.length; i++) {
        var w = wins[i]
        if (Math.abs(w.x - r.x) > tol || Math.abs(w.y - r.y) > tol
            || Math.abs(w.w - r.w) > tol || Math.abs(w.h - r.h) > tol) continue
        if (w.w * w.h < bestArea) { best = w; bestArea = w.w * w.h }
    }
    return best
}

// Where a live pin of source `r` starts, on a W × H screen: at most 45% of the screen each way
// (a big source is shown smaller), BESIDE the source — right, left, below, above, the first that
// fits whole — so it does not cover what it shows. Nothing fits (a near-fullscreen source): the
// bottom-right corner, which overlaps, and the card says so.
function livePlace(r, W, H, gap) {
    var k = Math.min(1, 0.45 * W / r.w, 0.45 * H / r.h)
    var w = r.w * k, h = r.h * k
    var spots = [
        { x: r.x + r.w + gap, y: r.y },
        { x: r.x - gap - w,   y: r.y },
        { x: r.x,             y: r.y + r.h + gap },
        { x: r.x,             y: r.y - gap - h }
    ]
    for (var i = 0; i < spots.length; i++) {
        var s = spots[i]
        // Slide along the edge it sits on, never across onto the source.
        var x = i < 2 ? s.x : Math.max(0, Math.min(W - w, s.x))
        var y = i < 2 ? Math.max(0, Math.min(H - h, s.y)) : s.y
        if (x >= 0 && y >= 0 && x + w <= W && y + h <= H) return { x: x, y: y, w: w, h: h }
    }
    return { x: W - w - gap, y: H - h - gap, w: w, h: h }
}

// Whether two rectangles share any area.
function overlaps(a, b) {
    return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}
