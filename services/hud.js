.pragma library

// ── hud.js ────────────────────────────────────────────────────────────────────
// The HUD's rules, as pure functions: which widgets exist, what a saved layout may
// say, where a widget may sit, and what is shown and clickable in which mode.
//
// ── What the HUD is ───────────────────────────────────────────────────────────
// Small widgets (performance, clips, voice, input) that live as cards in the overview,
// above and below the workspaces (modules/hud/HudCard), and — when PINNED — are also drawn
// on screen (modules/hud/HudLayer), unlike the desktop widgets, which sit under windows.
// WHERE a pinned one shows is its own `where`: "games" (over a fullscreen window on the
// focused monitor) or "always" (a plain overlay, over everything, on the overlay's HOME
// monitor — `home`, the one it was last arranged on, so it doesn't hop screens as focus
// follows the mouse). A pinned one is click-through unless said otherwise.
// Placing one is the overview island's job (HudInspector), on a map of the screen.
// (2026-10-20: there used to be a SUPER+G edit overlay with its own add/remove; gone.)
//
// ── Positions are fractions of the screen, by the centre ──────────────────────
// A layout saved on one monitor must not put a widget off the edge of another, and a
// widget meant to be dead centre must stay so. So a widget stores the centre of
// itself as (cx, cy) in 0..1 and `clampCentre` keeps the whole rectangle on screen.
//
// ── The disk is a trust boundary ──────────────────────────────────────────────
// hud.json is a file anyone can edit: `normalise` rebuilds the layout from it — only
// known widgets, only the right types, fractions clamped, option values checked against
// the choices that exist — so a bad file gives a default layout, not a broken binding.
//
// Tested (`bun scripts/test-hud.js`).
// ─────────────────────────────────────────────────────────────────────────────

// How see-through the input overlay's plate and keys may be (lit keys stay solid).
// Where a pinned widget is drawn (see the header).
var WHERE = ["games", "always"]
var OPACITY_MIN = 0.1, OPACITY_MAX = 1, OPACITY_STEP = 0.1
function clampOpacity(v, fallback) {
    var n = Number(v)
    return isFinite(n) ? Math.round(Math.max(OPACITY_MIN, Math.min(OPACITY_MAX, n)) * 100) / 100 : fallback
}
// How far a resizable widget (the input overlay) may be scaled, by its corner grip.
var SCALE_MIN = 0.5, SCALE_MAX = 2
function clampScale(v, fallback) {
    var n = Number(v)
    return isFinite(n) && n > 0 ? Math.round(Math.max(SCALE_MIN, Math.min(SCALE_MAX, n)) * 100) / 100 : fallback
}

// The input overlay's keyboard presets (services/inputkeys.js LAYOUT_IDS — scripts/test-hud.js keeps the two equal).
var INPUT_LAYOUTS = ["wasd", "gaming", "osu4k", "compact", "tkl", "full"]

// Marks text for translation where it is written (scripts/translations.py finds it); the
// view translates it where it is drawn with Translation.tr(modelData.label).
function N_(s) { return s }

// `blurb` is the library card's one line: what the widget is FOR over a game.
// `blurb` is the card's one line: what the widget is FOR over a game.
var CATALOG = [
    { id: "stats",     label: N_("Performance"), symbol: "memory",
      blurb: N_("How hard your computer is working"),
      defaults: { cx: 0.9, cy: 0.12 }, opts: { opacity: 0.9 } },
    { id: "clips",     label: N_("Replay clips"), symbol: "videocam",
      blurb: N_("Save the last minutes of what you were playing"),
      defaults: { cx: 0.9, cy: 0.86 }, opts: { opacity: 0.9 } },
    { id: "voice",     label: N_("Voice chat"),  symbol: "headphones",
      blurb: N_("Who is talking in your call"),
      defaults: { cx: 0.1, cy: 0.2 }, opts: { opacity: 0.9 } },
    { id: "input",     label: N_("Key display"), symbol: "keyboard",
      blurb: N_("Shows the keys and clicks you press, for streams"),
      defaults: { cx: 0.16, cy: 0.80 }, opts: { scale: 1, opacity: 0.85, layout: "wasd", mouse: true, stats: true } }
]

// The nine places the inspector's map offers with one click (a fraction pair, before
// clampCentre pulls the widget's whole rectangle on screen).
var ANCHORS = {
    tl: [0.06, 0.08], t: [0.5, 0.08], tr: [0.94, 0.08],
    l:  [0.06, 0.5],  c: [0.5, 0.5],  r:  [0.94, 0.5],
    bl: [0.06, 0.92], b: [0.5, 0.92], br: [0.94, 0.92]
}

// ── The Performance card's one-line verdict ──────────────────────────────────
// What the three rings add up to, in words a person who has never read a temperature can act on, worst first:
// `m` is { cpu, gpu, ram } as 0..1 loads, { cpuTemp, gpuTemp } in °C (-1 = no sensor) and `swap` in GB. `level` is 0 fine,
// 1 worth a look, 2 act (the card colours its status line by it); `text` is for Translation.tr (N_-marked).
function perfVerdict(m) {
    var cpuT = m.cpuTemp === undefined ? -1 : m.cpuTemp
    var gpuT = m.gpuTemp === undefined ? -1 : m.gpuTemp
    if (cpuT >= 90 || gpuT >= 88) return { level: 2, key: "hot", text: N_("Running hot") }
    if (m.ram >= 0.92) return { level: 2, key: "memory", text: N_("Memory almost full") }
    if (cpuT >= 80 || gpuT >= 80) return { level: 1, key: "warm", text: N_("Getting warm") }
    if (m.cpu >= 0.85) return { level: 1, key: "cpu", text: N_("Processor is busy") }
    if (m.gpu >= 0.9) return { level: 1, key: "gpu", text: N_("Graphics are busy") }
    if (m.ram >= 0.8) return { level: 1, key: "ram", text: N_("Memory is filling up") }
    return { level: 0, key: "ok", text: N_("Running smoothly") }
}

function ids() { return CATALOG.map(function (c) { return c.id }) }
function info(id) { return CATALOG.filter(function (c) { return c.id === id })[0] || null }

function _frac(v, fallback) {
    var n = Number(v)
    return isFinite(n) ? Math.max(0, Math.min(1, n)) : fallback
}

function _entry(c, src) {
    src = src && typeof src === "object" ? src : {}
    var o = src.opts && typeof src.opts === "object" ? src.opts : {}
    var opts = {}
    if (c.opts.scale !== undefined) opts.scale = clampScale(o.scale, c.opts.scale)
    if (c.opts.opacity !== undefined) opts.opacity = clampOpacity(o.opacity, c.opts.opacity)
    // The input overlay's own: which keyboard, whether the mouse and the click / key rates are drawn.
    if (c.opts.layout !== undefined) opts.layout = INPUT_LAYOUTS.indexOf(o.layout) >= 0 ? o.layout : c.opts.layout
    if (c.opts.mouse !== undefined) opts.mouse = o.mouse === undefined ? c.opts.mouse : o.mouse !== false
    if (c.opts.stats !== undefined) opts.stats = o.stats === undefined ? c.opts.stats : o.stats !== false
    return {
        // A file from before 2026-10-20 also had `shown` (added in the edit overlay); a widget
        // pinned there but not shown was never drawn, so it stays unpinned.
        pinned: src.pinned === true && src.shown !== false,
        // Click-through unless said otherwise: a pinned widget must not swallow the game's
        // clicks by default.
        clickthrough: src.clickthrough !== false,
        where: WHERE.indexOf(src.where) >= 0 ? src.where : "games",
        cx: _frac(src.cx, c.defaults.cx),
        cy: _frac(src.cy, c.defaults.cy),
        opts: opts
    }
}

// A monitor name as Hyprland spells one ("DP-2", "HDMI-A-1"), or "" — never anything a
// binding could choke on.
function _home(v) {
    return typeof v === "string" && /^[A-Za-z0-9._-]{1,64}$/.test(v) ? v : ""
}

// A whole layout: { home, widgets: { id: entry } } with every catalogue id present.
function normalise(doc) {
    var src = doc && doc.widgets && typeof doc.widgets === "object" ? doc.widgets : {}
    var out = {}
    CATALOG.forEach(function (c) { out[c.id] = _entry(c, src[c.id]) })
    return { home: _home(doc && doc.home), widgets: out }
}

function set(layout, id, patch) {
    var c = info(id)
    if (!c || !layout.widgets[id]) return layout
    var w = {}
    for (var k in layout.widgets) w[k] = layout.widgets[k]
    var merged = {}
    for (var f in layout.widgets[id]) merged[f] = layout.widgets[id][f]
    for (var p in patch) merged[p] = patch[p]
    if (patch.opts) {
        merged.opts = {}
        for (var q in layout.widgets[id].opts) merged.opts[q] = layout.widgets[id].opts[q]
        for (var r in patch.opts) merged.opts[r] = patch.opts[r]
    }
    // Re-run it through the same gate the disk goes through.
    w[id] = _entry(c, merged)
    return { home: layout.home || "", widgets: w }
}

function setHome(layout, name) {
    var h = _home(name)
    if (h === "" || h === layout.home) return layout
    return { home: h, widgets: layout.widgets }
}

// Keeps the whole rectangle (w×h) inside the screen (W×H), by its centre fractions.
// A widget bigger than the screen centres.
function clampCentre(cx, cy, w, h, W, H) {
    function one(c, size, total) {
        if (total <= 0 || size >= total) return 0.5
        var lo = (size / 2) / total, hi = 1 - lo
        return Math.max(lo, Math.min(hi, _frac(c, 0.5)))
    }
    return { cx: one(cx, w, W), cy: one(cy, h, H) }
}

// Drawn on THIS monitor? `ctx` is { game, home }: a fullscreen window covers it and it is
// the focused one; it is the overlay's home. Without `ctx`: is it pinned at all.
function visible(entry, ctx) {
    if (!entry || entry.pinned !== true) return false
    if (!ctx) return true
    return entry.where === "always" ? ctx.home === true : ctx.game === true
}

// Takes the mouse there? Drawn and not click-through.
function interactive(entry, ctx) { return visible(entry, ctx) && !entry.clickthrough }

function anyPinned(layout, ctx) {
    return ids().some(function (id) { return visible(layout.widgets[id], ctx) })
}

// ── Snapping, on the real screen (arranging) ─────────────────────────────────
// Where a dragged w×h widget lands on a W×H screen, by its centre fractions: onto the centre
// lines (snapCentre), else with an EDGE on the screen's `margin` (px in from each side), when
// within `px` of either; then kept wholly on screen. `guides` says which line each axis
// snapped to — "centre", "start", "end" or "" — for the guide lines the arrange view draws.
function snapPlace(cx, cy, w, h, W, H, margin, px) {
    var p = px === undefined ? SNAP_PX : px
    function axis(c, size, total) {
        var n = Number(c)
        if (!isFinite(n) || !(total > 0)) return { c: 0.5, g: "" }
        if (snapCentre(n, total, p) === 0.5) return { c: 0.5, g: "centre" }
        var lo = margin + size / 2, hi = total - margin - size / 2, at = n * total
        if (Math.abs(at - lo) <= p) return { c: lo / total, g: "start" }
        if (Math.abs(at - hi) <= p) return { c: hi / total, g: "end" }
        return { c: n, g: "" }
    }
    var x = axis(cx, w, W), y = axis(cy, h, H)
    var k = clampCentre(x.c, y.c, w, h, W, H)
    return { cx: k.cx, cy: k.cy, guides: { x: x.g, y: y.g } }
}

// The monitor "always" widgets live on: the saved home while it's connected, else the
// focused one (a laptop undocked from the monitor it was arranged on).
function homeScreen(home, connected, focused) {
    return home !== "" && (connected || []).indexOf(home) >= 0 ? home : (focused || "")
}

// ── Snapping to the screen's centre lines ─────────────────────────────────────
// A widget's centre fraction pulled onto 0.5 when it lands within `px` screen pixels of
// it (a widget a pixel off centre reads as a mistake). `total` is the
// screen's size on that axis; returns the fraction unchanged otherwise.
var SNAP_PX = 12
function snapCentre(c, total, px) {
    var n = Number(c)
    if (!isFinite(n) || !(total > 0)) return c
    return Math.abs(n - 0.5) * total <= (px === undefined ? SNAP_PX : px) + 1e-6 ? 0.5 : n
}
