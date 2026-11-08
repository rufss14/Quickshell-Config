.pragma library

// ── materialwall.js ───────────────────────────────────────────────────────────
// The composition behind Settings › Wallpaper › Material Wallpaper
// (components/MaterialWallpaper): a field of big, flat Material shapes in tonal steps of the
// palette, after End-4's default wallpaper. The shapes and where they sit are data here, so a
// screen of any aspect gets the same picture and the QML only has to draw them.
//
//     bun scripts/test-materialwall.js
//
// ── The shapes ────────────────────────────────────────────────────────────────
// Material's own shape set (the "expressive" shapes: soft burst, pentagon, cookies, ghost…) is
// vertex lists with a corner radius on each vertex. FORMS below holds the ones the wallpaper uses,
// in the unit square those lists are published in; `outline()` rounds every corner with a circular
// arc of its radius (shortened where two corners would overlap on a short edge) and fits the result
// to a box. Circles and rounded rectangles are drawn by the QML directly.
//
// ── Sized by the HEIGHT ───────────────────────────────────────────────────────
// Positions are fractions of the screen, but a shape's size is a fraction of its HEIGHT, so a
// circle stays a circle on an ultrawide and only the spacing between shapes stretches.
//
// ── Tone, not colour ──────────────────────────────────────────────────────────
// `tone` is how far the fill is mixed from the palette's base toward a role (0 = the base itself).
// A stack of bursts steps up toward the middle, which is what gives the picture its depth without
// a shadow. The colours are the QML's to choose, so a new palette re-tints all of it.
// ─────────────────────────────────────────────────────────────────────────────

function pt(x, y, r) { return { x: x, y: y, r: r || 0 } }

// `pts` turned about (0.5, 0.5), `reps` times round (so a two-point motif becomes a whole star).
function repeat(pts, reps) {
    const out = []
    for (let i = 0; i < pts.length * reps; i++) {
        const p = pts[i % pts.length]
        const a = Math.floor(i / pts.length) * 2 * Math.PI / reps
        const dx = p.x - 0.5, dy = p.y - 0.5
        out.push(pt(0.5 + dx * Math.cos(a) - dy * Math.sin(a), 0.5 + dx * Math.sin(a) + dy * Math.cos(a), p.r))
    }
    return out
}

// A regular star: `n` points at radius 1 alternating with valleys at `inner`, every corner `r`.
// Turned by `turn` degrees.
function star(n, inner, r, turn) {
    const out = []
    const t = (turn || 0) * Math.PI / 180
    for (let i = 0; i < n * 2; i++) {
        const rad = i % 2 === 0 ? 1 : inner
        const a = Math.PI * i / n + t
        out.push(pt(rad * Math.cos(a), rad * Math.sin(a), r))
    }
    return out
}

// A regular polygon of `n` corners at radius 1, every corner `r`; turned by `turn` degrees.
function ngon(n, r, turn) {
    const out = []
    for (let i = 0; i < n; i++) {
        const a = 2 * Math.PI * i / n + (turn || 0) * Math.PI / 180
        out.push(pt(Math.cos(a), Math.sin(a), r))
    }
    return out
}

// Material's shape set (the vertex lists and radii are theirs, published with the shapes).
const FORMS = {
    softBurst: repeat([pt(0.193, 0.277, 0.053), pt(0.176, 0.055, 0.053)], 10),
    burst:     repeat([pt(0.592, 0.842, 0.006), pt(0.500, 1.006, 0.006)], 12),
    boom:      repeat([pt(0.457, 0.296, 0.007), pt(0.500, -0.051, 0.007)], 15),
    sunny:     star(8, 0.8, 0.15, 45),
    verySunny: repeat([pt(0.500, 1.080, 0.085), pt(0.358, 0.843, 0.085)], 8),
    cookie4:   repeat([pt(1.237, 1.236, 0.258), pt(0.500, 0.918, 0.233)], 4),
    cookie6:   repeat([pt(0.723, 0.884, 0.394), pt(0.500, 1.099, 0.398)], 6),
    cookie7:   star(7, 0.75, 0.5, -90),
    cookie9:   star(9, 0.8, 0.5, 30),
    cookie12:  star(12, 0.8, 0.5, 30),
    clover4:   repeat([pt(1.099, 0.725, 0.476), pt(0.725, 1.099, 0.476), pt(0.500, 0.926, 0)], 4),
    clover8:   repeat([pt(0.758, 1.101, 0.209), pt(0.500, 0.964, 0)], 8),
    flower:    repeat([pt(0.370, 0.187, 0), pt(0.416, 0.049, 0.381), pt(0.479, 0.001, 0.095),
                       pt(0.521, 0.001, 0.095), pt(0.584, 0.049, 0.381), pt(0.630, 0.187, 0)], 8),
    pentagon:  [pt(0.828, 0.970, 0.169), pt(0.172, 0.970, 0.169), pt(-0.030, 0.365, 0.164),
                pt(0.500, -0.009, 0.172), pt(1.030, 0.365, 0.164)],
    gem:       [pt(1.005, 0.792, 0.208), pt(0.500, 1.023, 0.241), pt(-0.005, 0.792, 0.208),
                pt(0.073, 0.258, 0.228), pt(0.500, 0.000, 0.241), pt(0.927, 0.258, 0.228)],
    diamond:   repeat([pt(0.500, 1.096, 0.151), pt(0.040, 0.500, 0.159)], 2),
    triangle:  ngon(3, 0.2, -90),
    square:    [pt(1, 1, 0.3), pt(0, 1, 0.3), pt(0, 0, 0.3), pt(1, 0, 0.3)],
    // Flat top, two feet.
    ghost:     [pt(1.000, 1.140, 0.254), pt(0.575, 0.906, 0.253), pt(0.425, 0.906, 0.253),
                pt(0.000, 1.140, 0.254), pt(0.000, 0.000, 1.0), pt(0.500, 0.000, 1.0), pt(1.000, 0.000, 1.0)]
}

// The forms in the order a picker offers them, with their names.
const FORM_LIST = [
    ["softBurst", "Soft burst"], ["burst", "Burst"], ["boom", "Boom"], ["sunny", "Sunny"],
    ["verySunny", "Very sunny"], ["cookie4", "Cookie 4"], ["cookie6", "Cookie 6"], ["cookie7", "Cookie 7"],
    ["cookie9", "Cookie 9"], ["cookie12", "Cookie 12"], ["clover4", "Clover 4"], ["clover8", "Clover 8"],
    ["flower", "Flower"], ["pentagon", "Pentagon"], ["gem", "Gem"], ["diamond", "Diamond"],
    ["triangle", "Triangle"], ["square", "Square"], ["ghost", "Ghost"]
].map(function (f) { return { id: f[0], label: f[1] } })

// Which form each SLOT of the composition wears unless chosen otherwise: the two stacks, the
// middle, the one on the left edge, the one in the top right corner.
const DEFAULT_FORMS = { stack: "softBurst", centre: "pentagon", side: "cookie9", corner: "ghost" }

// The rounded outline of `verts` ([{x, y, r}], r in the same units as x and y), fitted to a
// `size` box and centred in it (the larger side of the shape touches the box). `softness` scales
// every radius. Closed: the last point repeats the first, so a stroke joins up.
function outline(verts, size, softness, seg) {
    seg = seg || 8
    const k = softness === undefined ? 1 : softness
    const n = verts.length
    const info = verts.map(function (c, i) {
        const p = verts[(i + n - 1) % n], q = verts[(i + 1) % n]
        const lu = Math.hypot(p.x - c.x, p.y - c.y), lv = Math.hypot(q.x - c.x, q.y - c.y)
        const ux = (p.x - c.x) / lu, uy = (p.y - c.y) / lu
        const vx = (q.x - c.x) / lv, vy = (q.y - c.y) / lv
        const cos = ux * vx + uy * vy
        const sin = Math.sqrt(Math.max(0, 1 - cos * cos))
        // How far along each edge the corner's circle touches it.
        const cut = sin > 1e-3 ? c.r * k * (cos + 1) / sin : 0
        return { ux: ux, uy: uy, vx: vx, vy: vy, cos: cos, sin: sin, cut: cut, lu: lu, lv: lv }
    })
    // Two corners share an edge: where their cuts would overrun it, both give way in proportion.
    const side = info.map(function (a, i) {
        const b = info[(i + 1) % n]
        const need = a.cut + b.cut
        return need > a.lv ? a.lv / need : 1
    })
    const pts = []
    for (let i = 0; i < n; i++) {
        const c = verts[i], a = info[i]
        const d = a.cut * Math.min(side[i], side[(i + n - 1) % n])
        if (d < 1e-9) { pts.push({ x: c.x, y: c.y }); continue }
        // The arc: radius d·tan(θ/2) over the turn φ = π − θ, as a cubic whose handles are 4/3·tan(φ/4)·radius long.
        const theta = Math.acos(Math.max(-1, Math.min(1, a.cos)))
        const radius = d * Math.tan(theta / 2)
        const h = 4 / 3 * Math.tan((Math.PI - theta) / 4) * radius
        const A = { x: c.x + a.ux * d, y: c.y + a.uy * d }
        const B = { x: c.x + a.vx * d, y: c.y + a.vy * d }
        const C1 = { x: A.x - a.ux * h, y: A.y - a.uy * h }
        const C2 = { x: B.x - a.vx * h, y: B.y - a.vy * h }
        for (let s = 0; s <= seg; s++) {
            const u = s / seg, w = 1 - u
            pts.push({ x: w * w * w * A.x + 3 * w * w * u * C1.x + 3 * w * u * u * C2.x + u * u * u * B.x,
                       y: w * w * w * A.y + 3 * w * w * u * C1.y + 3 * w * u * u * C2.y + u * u * u * B.y })
        }
    }
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
    for (const p of pts) { x0 = Math.min(x0, p.x); y0 = Math.min(y0, p.y); x1 = Math.max(x1, p.x); y1 = Math.max(y1, p.y) }
    const f = size / Math.max(x1 - x0, y1 - y0)
    const ox = (size - (x1 - x0) * f) / 2, oy = (size - (y1 - y0) * f) / 2
    const out = pts.map(function (p) { return { x: (p.x - x0) * f + ox, y: (p.y - y0) * f + oy } })
    out.push({ x: out[0].x, y: out[0].y })
    return out
}

// Back to front. kind: "circle" | "rect" | "poly".
//   x, y   centre, as a fraction of the screen          size   box height, as a fraction of the screen height
//   rot    turn, degrees                                tone   see above
//   alt    wears the SECOND colour when one is chosen
//   rect:  aspect (box width / height), round (corner radius as a fraction of the shorter side, 0.5 is a pill)
//   poly:  slot (a key of DEFAULT_FORMS: which form is chosen for it)
// Placed from End-4's default wallpaper (measured off the picture).
const SHAPES = [
    { kind: "circle", x: 0.50, y: 0.18, size: 1.05, tone: 0.035 },
    { kind: "circle", x: 0.94, y: 0.46, size: 1.03, tone: 0.05 },
    { kind: "rect",   x: 0.30, y: 1.05, size: 0.92, aspect: 1.0, round: 0.30, rot: 0, tone: 0.045 },
    { kind: "poly",   slot: "corner", x: 0.86, y: 0.06, size: 0.64, rot: 0, tone: 0.07, alt: true },
    { kind: "circle", x: 0.29, y: 0.94, size: 0.47, tone: 0.065 },
    { kind: "poly",   slot: "centre", x: 0.53, y: 0.44, size: 0.57, rot: 0, tone: 0.075 },
    { kind: "poly",   slot: "side", x: -0.02, y: 0.61, size: 0.62, rot: 0, tone: 0.065, alt: true },
    // Two stacks of bursts, biggest and darkest first, one step lighter and smaller each.
    { kind: "poly",   slot: "stack", x: 0.15, y: 0.05, size: 1.15, rot: 0,  tone: 0.10 },
    { kind: "poly",   slot: "stack", x: 0.15, y: 0.05, size: 0.88, rot: 0,  tone: 0.17 },
    { kind: "poly",   slot: "stack", x: 0.15, y: 0.05, size: 0.62, rot: 0,  tone: 0.25 },
    { kind: "poly",   slot: "stack", x: 0.835, y: 0.97, size: 0.95, rot: 18, tone: 0.10, alt: true },
    { kind: "poly",   slot: "stack", x: 0.835, y: 0.97, size: 0.72, rot: 18, tone: 0.17, alt: true },
    { kind: "poly",   slot: "stack", x: 0.835, y: 0.97, size: 0.50, rot: 18, tone: 0.25, alt: true }
]

// A small seeded generator (mulberry32), so a seed is the same arrangement every time.
function rng(seed) {
    let a = seed | 0
    return function () {
        a = (a + 0x6D2B79F5) | 0
        let t = Math.imul(a ^ (a >>> 15), 1 | a)
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

// The picture for a `w` × `h` screen: each shape as a box in pixels (x, y = top left), plus
// the outline for a polygon. `opts` is the style (every field optional, 1 / 0 = as authored):
//   contrast  × every tone, so the steps between shapes are stronger or flatter
//   softness  × every corner radius (a circle has none)
//   size      × every shape, about its own centre
//   seed      0 is the composition as authored; any other number nudges every shape's place and
//             turn by its own seeded amount, so each is a different arrangement of the same shapes
//   forms     { stack, centre, side, corner } → a key of FORMS; a missing or unknown one is the default
function layout(w, h, opts) {
    const o = opts || {}
    const contrast = o.contrast === undefined ? 1 : o.contrast
    const softness = o.softness === undefined ? 1 : o.softness
    const scale    = o.size === undefined ? 1 : o.size
    const forms    = o.forms || {}
    const rand = o.seed ? rng(o.seed) : null
    return SHAPES.map(function (s) {
        // Drawn for every shape, used or not, so a shape's nudge does not depend on the others'.
        const jx = rand ? (rand() - 0.5) * 0.12 : 0
        const jy = rand ? (rand() - 0.5) * 0.12 : 0
        const jr = rand ? (rand() - 0.5) * 60 : 0
        const bh = s.size * scale * h
        const bw = bh * (s.aspect || 1)
        const box = {
            kind: s.kind, tone: clamp(s.tone * contrast, 0, 0.9), rot: (s.rot || 0) + jr, alt: s.alt === true,
            x: (s.x + jx) * w - bw / 2, y: (s.y + jy) * h - bh / 2, w: bw, h: bh,
            round: clamp((s.round || 0) * softness, 0, 0.5),
            outline: []
        }
        if (s.kind === "poly") {
            const f = FORMS[forms[s.slot]] || FORMS[DEFAULT_FORMS[s.slot]]
            box.outline = outline(f, bh, softness)
        }
        return box
    })
}

// ── Motion ────────────────────────────────────────────────────────────────────
// Both are pure functions of a shape's index and the time `t` (seconds, already scaled by the
// speed), so the QML only has to advance a clock — and a change of speed bends the motion instead
// of jumping it.

// How far shape `i` has wandered from where it was put: a slow sway of its own, each axis and the
// turn on a different period (about 50–120 s at speed 1), bigger shapes calmer than small ones.
// x and y are fractions of the screen HEIGHT, like a size; r is degrees.
function wander(i, t) {
    const r = rng(i * 7919 + 17)
    const px = r() * 6.2832, py = r() * 6.2832, pr = r() * 6.2832
    const wx = 0.05 + r() * 0.07, wy = 0.05 + r() * 0.07, wr = 0.04 + r() * 0.06
    const calm = 1 / (0.6 + SHAPES[i].size)
    return { x: Math.sin(t * wx + px) * 0.06 * calm,
             y: Math.sin(t * wy + py) * 0.05 * calm,
             r: Math.sin(t * wr + pr) * 9 * calm }
}

// A steady turn, `rate` degrees a second at t = 1, alternating direction from shape to shape so a
// stack does not all wind the same way. A circle or a rounded square would show nothing, so it
// stays put.
function spin(i, t, rate) {
    return SHAPES[i].kind === "poly" ? (i % 2 === 0 ? 1 : -1) * t * rate : 0
}

// ── The style, and looks ─────────────────────────────────────────────────────
// The whole style as one flat object, so a PRESET is a handful of its fields, "Reset" is the object
// itself, and the panel can ask which preset is the one in force. CONFIG_KEY is where each field
// lives in Config (the panel writes them, the wallpaper reads them).
const STYLE = {
    role: "", role2: "", contrast: 1, softness: 1, size: 1, backdrop: 0, seed: 0,
    stack: "", centre: "", side: "", corner: "",
    mirror: false, drift: false, speed: 1, spin: 0
}

const CONFIG_KEY = {
    role: "wallMaterialRole", role2: "wallMaterialRole2", contrast: "wallMaterialContrast",
    softness: "wallMaterialSoftness", size: "wallMaterialSize", backdrop: "wallMaterialBackdrop",
    seed: "wallMaterialSeed", stack: "wallMaterialStack", centre: "wallMaterialCentre",
    side: "wallMaterialSide", corner: "wallMaterialCorner", mirror: "wallMaterialMirror",
    drift: "wallMaterialDrift", speed: "wallMaterialDriftSpeed", spin: "wallMaterialSpin"
}

// A look is a STYLE with some fields changed; what it leaves out is the default, not "whatever it
// was". Colours are role names, so a look re-tints with the wallpaper like everything else. The
// seed is not part of a look (it is "which arrangement", picked with Shuffle) and a look leaves it.
const PRESETS = [
    { id: "default", label: "Classic", icon: "category", style: {} },
    { id: "calm",    label: "Calm",    icon: "cloud",
      style: { contrast: 0.7, softness: 1.5, size: 1.1, backdrop: 0.04, drift: true, speed: 0.5 } },
    { id: "bold",    label: "Bold",    icon: "bolt",
      style: { contrast: 1.4, softness: 0.55, stack: "burst", centre: "gem", side: "clover8", corner: "boom" } },
    { id: "duo",     label: "Duo",     icon: "opacity",
      style: { role: "focus", role2: "ramp5", contrast: 1.2, backdrop: 0.06 } },
    { id: "sunny",   label: "Sunny",   icon: "wb_sunny",
      style: { role2: "ramp3", stack: "verySunny", centre: "sunny", side: "flower", corner: "cookie12", softness: 1.2 } },
    { id: "drifter", label: "Drifter", icon: "auto_awesome",
      style: { drift: true, spin: 0.3, speed: 0.8, mirror: true } }
]

// A look as a full style (every field), the seed kept as it is.
function lookStyle(id, seed) {
    const p = PRESETS.find(function (x) { return x.id === id })
    const out = Object.assign({}, STYLE, p ? p.style : {})
    out.seed = seed || 0
    return out
}

// Which look `style` is exactly (ignoring the seed), or "" when it is none of them.
function lookOf(style) {
    for (const p of PRESETS) {
        const want = lookStyle(p.id, 0)
        if (Object.keys(STYLE).every(function (k) { return k === "seed" || want[k] === style[k] }))
            return p.id
    }
    return ""
}

// ── Saved presets ─────────────────────────────────────────────────────────────
// A preset the user saved is a full STYLE (seed included: the arrangement is part of what they liked)
// under a name. It lives in the saved config, which can be hand-edited, so it is read through
// `normaliseStyle`: unknown keys dropped, a missing one the default, a number clamped to the range the
// panel offers, a form that does not exist back to the slot's own.
const RANGES = { contrast: [0.5, 1.5], softness: [0.4, 1.8], size: [0.7, 1.4], backdrop: [0, 0.3],
                 speed: [0.2, 3], spin: [0, 1] }
const ROLES = ["", "primary", "focus", "ramp2", "ramp3", "ramp5", "ramp9"]

function normaliseStyle(obj) {
    const o = obj && typeof obj === "object" ? obj : {}
    const out = {}
    for (const k in STYLE) {
        const d = STYLE[k], v = o[k]
        if (RANGES[k]) out[k] = typeof v === "number" && isFinite(v) ? clamp(v, RANGES[k][0], RANGES[k][1]) : d
        else if (typeof d === "boolean") out[k] = typeof v === "boolean" ? v : d
        else if (k === "seed") out[k] = typeof v === "number" && isFinite(v) ? Math.floor(clamp(v, 0, 2147483647)) : d
        else if (k === "role" || k === "role2") out[k] = ROLES.indexOf(v) >= 0 ? v : d
        else out[k] = typeof v === "string" && (v === "" || FORMS[v]) ? v : d   // a form
    }
    // The first colour's "primary" and "" are the same colour; one spelling.
    if (out.role === "primary") out.role = ""
    return out
}

// Do two styles look the same? The seed is the arrangement; `withSeed` false compares the rest only.
function sameStyle(a, b, withSeed) {
    return Object.keys(STYLE).every(function (k) { return (k === "seed" && !withSeed) || a[k] === b[k] })
}

// A preset's name as stored: trimmed, one line, at most 32 characters. "" when nothing is left.
function cleanName(name) {
    return String(name === undefined || name === null ? "" : name).replace(/\s+/g, " ").trim().slice(0, 32)
}

// `name` as a name no preset in `taken` has: "Calm" → "Calm 2" → "Calm 3". The built-in looks' labels count as taken.
function freeName(name, taken) {
    const base = cleanName(name) || "My look"
    const has = function (n) { return taken.some(function (t) { return t.toLowerCase() === n.toLowerCase() }) }
    if (!has(base)) return base
    for (let i = 2; ; i++) {
        const n = (base.slice(0, 28) + " " + i)
        if (!has(n)) return n
    }
}
