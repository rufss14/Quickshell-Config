.pragma library

// ── islands.js ────────────────────────────────────────────────────────────────
// The islands (modules/island/IslandDock): three hang from the bar (left, middle, right) and three stand on
// the screen's bottom edge (bottomLeft, bottomCenter, bottomRight: the sidebar's panels open there). Which page
// is on which island's rail, in what order, which panels open alone in the bar's plain column instead, and
// how a page is named and drawn. Pure, so it can be tested.
//
//     bun scripts/test-islands.js
//
// Two maps decide it, both edited on Settings › Desktop › Island (the board):
//   Config.islandRails     { left: [ids], center: [ids], right: [ids], bottomLeft: [ids], …, off: [ids] }: each rail in order, and
//                          the pages taken off every rail. {} = never edited: the rails come from the older
//                          Config.panelPlacement + Config.islandPages, so an upgraded shell keeps its islands.
//                          A page in none of the lists (one a later build adds) stands at its default.
//   Config.panelPlacement  { key: side }: the plain COLUMN a panel opens in (every panel while the islands
//                          are off; a panel that opens alone while they are on). Overrides only.
// layoutOf() is the one reading of the two; every caller asks it.
// ─────────────────────────────────────────────────────────────────────────────

// The bar's plain columns, which are also the top row's islands.
var COLUMNS = ["left", "center", "right"]
// The bottom row: islands standing on the screen's bottom edge (the frame's strip, or a sidebar there).
var BOTTOM = ["bottomLeft", "bottomCenter", "bottomRight"]
// Every island, top row first.
var SIDES = COLUMNS.concat(BOTTOM)

// How the board names an island. A new island is a side here, in SIDES and in RAILS.
var SIDE_META = {
    left:         { label: "Left",          icon: "first_page" },
    center:       { label: "Middle",        icon: "pip" },
    right:        { label: "Right",         icon: "last_page" },
    bottomLeft:   { label: "Bottom left",   icon: "first_page" },
    bottomCenter: { label: "Bottom middle", icon: "pip" },
    bottomRight:  { label: "Bottom right",  icon: "last_page" }
}
function sideMeta(side) { return SIDE_META[side] || { label: String(side || ""), icon: "square" } }

// "top" | "bottom": the row an island is in.
function rowOf(id) { return BOTTOM.indexOf(id) >= 0 ? "bottom" : "top" }
// "left" | "center" | "right": where along its edge an island stands.
function hOf(id) {
    if (id === "bottomLeft") return "left"
    if (id === "bottomCenter") return "center"
    if (id === "bottomRight") return "right"
    return id
}

// Grouped by what a page is about, not by where its button sits:
//   left    look and sound
//   center  time and you
//   right   the system
// and along the bottom, the sidebar's (2026-11-15, the user's pick):
//   bottomLeft    your day: Desk (to-do, clipboard, idle rules, a timer glance), the timer, your files, your workout, your drawing tablet
//   bottomCenter  clips, the Discord call (voice), screenshots (captures), the AI assistant
//   bottomRight   screen time, Claude, batteries and power
// The order is the rail's.
var ISLANDS = {
    left:         ["wallpaper", "colorScheme", "equalizer", "window", "layout"],
    center:       ["clock", "notifications", "agenda"],
    right:        ["wifi", "bluetooth", "brightness", "gaming", "network", "displays", "update"],
    bottomLeft:   ["desk", "timer", "files", "workout", "tablet"],
    bottomCenter: ["clips", "voice", "captures", "assistant"],
    bottomRight:  ["screentime", "claude", "power"]
}
// The column a bottom page's panel opens in while the islands are off (or once it is sent to open alone):
// the sidebar's modules placed on the bar always opened on the right.
var BOTTOM_COLUMN = "right"

// Panels that open alone by default, and the column they open in: the bar's plain dock on that side
// (modules/bar/BarPanelDock), as every panel does while the islands are switched off. All but the first
// two can be put on a rail on the board (since 2026-11-14 the sidebar's panels too, shown at the island's
// width until they are rebuilt for one).
//   launcher          owns the middle column: the keyboard (LOCKED below)
//   update            the middle column's while the islands are off or it is taken off every rail; on a rail
//                     (since 2026-11-15) it is a page, and takes the keyboard only while its prompt asks
//   media             Now Playing; the island's Media page (OWN) is the player on a rail
//   the rest          small sidebar panels that another page already holds (ALIAS below)
var OFF_RAIL = {
    launcher: "center", media: "left",
    stats: "right", clipboard: "right", inactivity: "right", tasks: "right"
}

// A panel whose job a page already does: its button opens that page while the page is on a rail and the
// panel itself is not (the user, 2026-11-15: "don't copy already built pages like stats"; small panels are
// "worth mixing in a dashboard"). Off every rail, the page gives the button back to the panel.
var ALIAS = { stats: "system", tasks: "desk", clipboard: "desk", inactivity: "desk" }

// `icon` is a Material Symbols name the bundled font already carries; `shape` is the M3E shape
// (components/shapes.js) the rail's indicator becomes on that page. `body` is the page's size on an
// island when it is built for one (the middle island's own size); a panel without it is still the
// bar panel it was, shown at the island's width and its own height.
var META = {
    wallpaper:     { label: "Wallpaper",      icon: "wallpaper",      shape: "cookie9",  body: { w: 780, h: 412 } },
    colorScheme:   { label: "Colour scheme",  icon: "palette",        shape: "clover",   body: { w: 780, h: 436 } },
    equalizer:     { label: "Equalizer",      icon: "volume_up",      shape: "cookie6", body: { w: 780, h: 436 } },
    media:         { label: "Now Playing",    icon: "music_note",     shape: "sunny"    },
    window:        { label: "Focused window", icon: "desktop_mac",    shape: "squircle", body: { w: 780, h: 384 } },
    layout:        { label: "Window layout",  icon: "vertical_split", shape: "hexagon", body: { w: 780, h: 384 } },
    launcher:      { label: "Launcher",       icon: "apps",           shape: "circle"   },
    update:        { label: "Updates",        icon: "update",         shape: "cookie9", body: { w: 780, h: 412 } },
    clock:         { label: "Clock",          icon: "calendar_month", shape: "cookie12" },
    notifications: { label: "Notifications",  icon: "notifications",  shape: "burst", body: { w: 780, h: 384 } },
    timer:         { label: "Timer",          icon: "timer",          shape: "sunny", body: { w: 780, h: 412 } },
    tasks:         { label: "To-do",          icon: "checklist",      shape: "squircle" },
    screentime:    { label: "Screen time",    icon: "hourglass_top",  shape: "pentagon", body: { w: 780, h: 412 } },
    claude:        { label: "Claude",         icon: "terminal",       shape: "cookie6", body: { w: 780, h: 412 } },
    wifi:          { label: "Wi-Fi",          icon: "wifi",           shape: "cookie9", body: { w: 780, h: 384 } },
    bluetooth:     { label: "Bluetooth",      icon: "bluetooth",      shape: "hexagon",  body: { w: 780, h: 384 } },
    brightness:    { label: "Brightness",     icon: "brightness_6",   shape: "sunny", body: { w: 780, h: 384 } },
    gaming:        { label: "Gaming",         icon: "sports_esports", shape: "burst", body: { w: 780, h: 412 } },
    stats:         { label: "Stats",          icon: "speed",          shape: "clover"   },
    clipboard:     { label: "Clipboard",      icon: "content_paste",  shape: "squircle" },
    clips:         { label: "Clips",          icon: "videocam",       shape: "cookie6", body: { w: 780, h: 412 } },
    inactivity:    { label: "Idle",           icon: "pause_circle",   shape: "pentagon" },
    voice:         { label: "Voice",          icon: "headphones",     shape: "clover", body: { w: 780, h: 412 } }
}

// Pages built only for an island that are not the middle's own four (no bar panel either, so off every rail
// they are hidden). Desk is the bottom-left's dashboard: the small sidebar panels mixed into one page.
var PAGE_META = {
    desk:     { label: "Desk",     icon: "checklist",   shape: "cookie12", body: { w: 780, h: 412 } },
    captures: { label: "Captures", icon: "content_cut", shape: "squircle", body: { w: 780, h: 412 } },
    network:  { label: "Network",  icon: "speed",       shape: "burst",    body: { w: 780, h: 412 } },
    power:    { label: "Power",    icon: "battery_full", shape: "clover",  body: { w: 780, h: 412 } },
    files:    { label: "Files",    icon: "folder",       shape: "cookie6", body: { w: 780, h: 412 } },
    workout:  { label: "Workout",  icon: "dumbbell", shape: "burst", body: { w: 780, h: 412 } },
    tablet:   { label: "Tablet",   icon: "tablet",   shape: "squircle", body: { w: 780, h: 412 } },
    agenda:   { label: "Agenda",   icon: "event",        shape: "sunny",   body: { w: 780, h: 412 } },
    displays: { label: "Displays", icon: "monitor",      shape: "squircle", body: { w: 780, h: 412 } },
    assistant: { label: "Assistant", icon: "auto_awesome", shape: "cookie12", body: { w: 780, h: 412 } }
}

// A key with no line above still draws: unfinished, not invisible.
function meta(key) {
    return META[key] || { label: String(key || ""), icon: "square", shape: "circle" }
}

// The island's own pages: built for an island, with no bar panel of their own (except Media, whose bar
// panel is Now Playing: the `media` line in META). Mirrors services/island.js TABS (the test keeps them
// equal); kept here too so this file stays importable on its own.
var OWN_META = {
    today:   { label: "Dashboard",   icon: "dashboard",   shape: "cookie9" },
    media:   { label: "Media",       icon: "queue_music", shape: "clover"  },
    system:  { label: "Performance", icon: "speed",       shape: "burst"   },
    weather: { label: "Weather",     icon: "cloud",       shape: "sunny"   }
}
var OWN = ["today", "media", "system", "weather"]

// A page as a rail (and the board) draws it: the island's own first, then the panel's.
function pageMeta(key) { return OWN_META[key] || PAGE_META[key] || meta(key) }

// What owns the middle column outright: always alone there, never on a rail. (System update was here too
// until 2026-11-15; it is a page now.)
var LOCKED = { launcher: true }

// The rails before anyone arranges them.
var RAILS = {
    left:         ISLANDS.left.slice(),
    center:       OWN.concat(ISLANDS.center),
    right:        ISLANDS.right.slice(),
    bottomLeft:   ISLANDS.bottomLeft.slice(),
    bottomCenter: ISLANDS.bottomCenter.slice(),
    bottomRight:  ISLANDS.bottomRight.slice()
}

// An island id.
function _isSide(v) { return SIDES.indexOf(v) >= 0 }
// A plain column (also the top row).
function _isCol(v) { return v === "left" || v === "center" || v === "right" }

function offRail(key) { return OFF_RAIL[key] !== undefined }

// The plain column a panel opens in before anyone moves it; an unknown key opens on the left.
function defaultSide(key) {
    if (offRail(key)) return OFF_RAIL[key]
    for (var i = 0; i < COLUMNS.length; i++)
        if (ISLANDS[COLUMNS[i]].indexOf(key) >= 0) return COLUMNS[i]
    for (var b = 0; b < BOTTOM.length; b++)
        if (ISLANDS[BOTTOM[b]].indexOf(key) >= 0) return BOTTOM_COLUMN
    return "left"
}

// …and after: `placement` is Config.panelPlacement ({ key: side }, overrides only). A value that is
// not a side is ignored, and the middle's own two cannot be moved.
function sideOf(key, placement) {
    if (key === "launcher" || key === "update") return "center"
    var v = placement ? placement[key] : undefined
    return _isCol(v) ? v : defaultSide(key)
}

// Before the board, the top rail a page stands on: where Config.panelPlacement put it, else the island it is
// listed on. Not always its column: System update's column is always the middle one (sideOf), its rail the right.
function _railCol(key, placement) {
    var v = placement ? placement[key] : undefined
    if (key !== "update" && _isCol(v)) return v
    for (var i = 0; i < COLUMNS.length; i++) if (ISLANDS[COLUMNS[i]].indexOf(key) >= 0) return COLUMNS[i]
    return sideOf(key, placement)
}

// The top island whose rail a panel is on before the board, "" for one that opens alone or a bottom page.
function railSide(key, placement) {
    if (offRail(key) || !META[key]) return ""
    for (var b = 0; b < BOTTOM.length; b++) if (ISLANDS[BOTTOM[b]].indexOf(key) >= 0) return ""
    return _railCol(key, placement)
}

// Every panel that can be placed, rail pages first in island order, then the ones that open alone
// (the Settings rows, and Config's defaults).
function placeable() {
    var out = []
    for (var i = 0; i < SIDES.length; i++) out = out.concat(ISLANDS[SIDES[i]].filter(function (k) { return META[k] !== undefined }))
    for (var k in OFF_RAIL) if (k !== "launcher" && k !== "update") out.push(k)
    return out
}

// { key: side } for every placeable panel: what Config answers when nothing is overridden.
function defaults() {
    var out = {}, keys = placeable()
    for (var i = 0; i < keys.length; i++) out[keys[i]] = defaultSide(keys[i])
    return out
}

// The pages on an island's rail before the board: its own that stayed, then the ones moved in, each run in
// island order, so a moved page lands at the end rather than between two that were neighbours. Placement only
// ever moved the top row's panels between columns; the bottom row is its defaults.
function pagesOf(side, placement) {
    if (!_isSide(side)) return []
    if (rowOf(side) === "bottom") return ISLANDS[side].slice()
    var own = [], moved = []
    for (var i = 0; i < COLUMNS.length; i++) {
        var list = ISLANDS[COLUMNS[i]]
        for (var j = 0; j < list.length; j++) {
            if (_railCol(list[j], placement) !== side) continue
            if (COLUMNS[i] === side) own.push(list[j]); else moved.push(list[j])
        }
    }
    return own.concat(moved)
}

// The page `delta` steps from `current` among `pages`, stopping at either end (a wheel or a key).
// A `current` that is not on the rail stays where it is.
function step(pages, current, delta) {
    var list = Array.isArray(pages) ? pages : []
    var i = list.indexOf(current)
    if (i < 0) return current
    return list[Math.max(0, Math.min(list.length - 1, i + (delta | 0)))]
}


// ── The layout ───────────────────────────────────────────────────────────────

// Can sit on a rail: an own page or a panel, never the middle column's two.
function railable(key) {
    return (OWN_META[key] !== undefined || PAGE_META[key] !== undefined || META[key] !== undefined) && !LOCKED[key]
}
// Has a bar panel, so off the rails it opens alone in a column; an own page without one is hidden.
function hasColumn(key) { return META[key] !== undefined }

// The rail a page stands on before anyone arranges them, "" for none.
function railDefault(key) {
    for (var i = 0; i < SIDES.length; i++)
        if (RAILS[SIDES[i]].indexOf(key) >= 0) return SIDES[i]
    return ""
}

// Every page the board knows, in a stable order: rails' defaults, then the panels that open alone.
function allPages() {
    var out = []
    for (var i = 0; i < SIDES.length; i++) out = out.concat(RAILS[SIDES[i]])
    var rest = placeable().concat(["launcher", "update"])
    for (var j = 0; j < rest.length; j++) if (out.indexOf(rest[j]) < 0) out.push(rest[j])
    return out
}

function _list(v) { return Array.isArray(v) ? v : [] }
function _saved(rails) {
    if (!rails || typeof rails !== "object" || Array.isArray(rails)) return false
    for (var i = 0; i < SIDES.length; i++) if (Array.isArray(rails[SIDES[i]])) return true
    return false
}

// Where every page is: { rails: { side: [ids] }, alone: { side: [ids] }, hidden: [ids] }. Each known page
// is in exactly one place; unknown ids, repeats and junk are dropped (a hand-edited config, an imported
// preset). `rails` is Config.islandRails, `placement` Config.panelPlacement, `shown` Config.islandPages (read
// only while `rails` was never saved).
function layoutOf(rails, placement, shown) {
    var out = { rails: {}, alone: {}, hidden: [] }, seen = {}
    for (var i = 0; i < SIDES.length; i++) out.rails[SIDES[i]] = []
    for (var c = 0; c < COLUMNS.length; c++) out.alone[COLUMNS[c]] = []
    function put(side, key) { if (railable(key) && !seen[key]) { seen[key] = true; out.rails[side].push(key) } }

    if (_saved(rails)) {
        for (var s = 0; s < SIDES.length; s++) {
            var list = _list(rails[SIDES[s]])
            for (var j = 0; j < list.length; j++) put(SIDES[s], list[j])
        }
        // Saved before the bottom row existed (no bottom list at all): its pages were in `off` only because
        // they opened alone then, so they come to their bottom island now. One the user had put on a top
        // rail is already placed above.
        var preBottom = true
        for (var pb = 0; pb < BOTTOM.length; pb++) if (Array.isArray(rails[BOTTOM[pb]])) preBottom = false
        var off = {}, offList = _list(rails.off)
        for (var o = 0; o < offList.length; o++)
            if (!(preBottom && rowOf(railDefault(offList[o])) === "bottom" && railDefault(offList[o]) !== "")) off[offList[o]] = true
        // A page the saved lists never mention (a later build's) stands at its default.
        var all = allPages()
        for (var a = 0; a < all.length; a++) {
            var d = railDefault(all[a])
            if (d !== "" && !off[all[a]]) put(d, all[a])
        }
    } else {
        // Before the board: the middle's own pages as Config.islandPages kept them (nothing valid = all four),
        // then the panels as Config.panelPlacement moved them.
        var own = []
        var src = _list(shown)
        for (var k = 0; k < src.length; k++) if (OWN.indexOf(src[k]) >= 0 && own.indexOf(src[k]) < 0) own.push(src[k])
        if (own.length === 0) own = OWN.slice()
        for (var m = 0; m < own.length; m++) put("center", own[m])
        for (var p = 0; p < SIDES.length; p++) {
            var panels = pagesOf(SIDES[p], placement)
            for (var q = 0; q < panels.length; q++) put(SIDES[p], panels[q])
        }
    }

    var every = allPages()
    for (var e = 0; e < every.length; e++) {
        var key = every[e]
        if (seen[key]) continue
        if (hasColumn(key)) out.alone[sideOf(key, placement)].push(key)
        else out.hidden.push(key)
    }
    return out
}

// The island whose rail holds a page in a layout, "" for none.
function railOf(key, layout) {
    if (!layout || !layout.rails) return ""
    for (var i = 0; i < SIDES.length; i++)
        if (_list(layout.rails[SIDES[i]]).indexOf(key) >= 0) return SIDES[i]
    return ""
}

// The page a panel's button opens on an island: the panel itself while it is on a rail, else the page that does
// its job (ALIAS) while that one is, else "" (it opens alone in its column).
function pageFor(key, layout) {
    if (railOf(key, layout) !== "") return key
    var a = ALIAS[key]
    return a !== undefined && railOf(a, layout) !== "" ? a : ""
}

// A full saved form of a layout (what Config.islandRails keeps once the board has been used): every rail,
// and every known page that is on none of them under `off`.
function snapshot(layout) {
    var out = { off: [] }
    for (var i = 0; i < SIDES.length; i++) out[SIDES[i]] = _list(layout && layout.rails ? layout.rails[SIDES[i]] : []).slice()
    var all = allPages()
    for (var j = 0; j < all.length; j++)
        if (!LOCKED[all[j]] && railOf(all[j], layout) === "") out.off.push(all[j])
    return out
}

// The rails as they ship: what Reset puts back.
function defaultRails() { return snapshot(layoutOf({ left: RAILS.left, center: RAILS.center, right: RAILS.right }, {}, [])) }

// Moves a page and returns what to store: { rails: the new Config.islandRails, column: a side to write into
// Config.panelPlacement for it, or "" }. `zone` is "rail" (at `index` on `side`'s rail; past the end = last),
// "alone" (opens alone in `side`'s column) or "hidden" (taken off; a page with a bar panel then opens alone in
// the column it already had). null for a move that cannot be made (a locked or unknown page, a bad side).
function move(layout, key, zone, side, index) {
    if (LOCKED[key] || !railable(key)) return null
    if (zone === "rail" && !_isSide(side)) return null
    if (zone === "alone" && !_isCol(side)) return null
    var snap = snapshot(layout)
    for (var i = 0; i < SIDES.length; i++) {
        var at = snap[SIDES[i]].indexOf(key)
        if (at >= 0) snap[SIDES[i]].splice(at, 1)
    }
    var offAt = snap.off.indexOf(key)
    if (offAt >= 0) snap.off.splice(offAt, 1)

    if (zone === "rail") {
        var n = Math.max(0, Math.min(snap[side].length, isFinite(index) ? Math.floor(index) : snap[side].length))
        snap[side].splice(n, 0, key)
        return { rails: snap, column: "" }
    }
    if (zone !== "alone" && zone !== "hidden") return null
    snap.off.push(key)
    return { rails: snap, column: zone === "alone" && hasColumn(key) ? side : "" }
}

// ── Per-island options ───────────────────────────────────────────────────────
// Config.islandOverrides is { side: { name: value } }; a name an island does not override is the shared
// setting. Each option's range is the one Settings offers, so a hand-edited value can never reach the dock raw.
var OPTIONS = {
    openBy:  { kind: "pick", values: ["hover", "click"], fallback: "hover" },
    delay:   { kind: "num",  min: 0,   max: 600,  fallback: 180 },
    linger:  { kind: "num",  min: 150, max: 1500, fallback: 450 },
    handle:  { kind: "num",  min: 24,  max: 320,  fallback: 56 },
    scale:   { kind: "num",  min: 0.8, max: 1.25, fallback: 1 },
    effects: { kind: "bool", fallback: true }
}

function _valid(spec, v) {
    if (spec.kind === "pick") return spec.values.indexOf(v) >= 0 ? v : undefined
    if (spec.kind === "bool") return typeof v === "boolean" ? v : undefined
    var n = Number(v)
    return v !== null && v !== "" && typeof v !== "boolean" && isFinite(n) ? Math.max(spec.min, Math.min(spec.max, n)) : undefined
}

// Whether an island overrides an option (with a value that is valid).
function overrides(side, name, map) {
    var spec = OPTIONS[name]
    var own = map && typeof map === "object" && map[side] && typeof map[side] === "object" ? map[side] : null
    return !!spec && !!own && own.hasOwnProperty(name) && _valid(spec, own[name]) !== undefined
}

// An option for one island: its own value when it overrides it, else the shared one (`globals[name]`), each
// kept to the option's range.
function optionOf(side, name, globals, map) {
    var spec = OPTIONS[name]
    if (!spec) return undefined
    if (overrides(side, name, map)) return _valid(spec, map[side][name])
    var g = _valid(spec, globals ? globals[name] : undefined)
    return g === undefined ? spec.fallback : g
}

// The overrides map with one option set for one island, or cleared (`value` undefined, or invalid).
function withOverride(map, side, name, value) {
    var out = {}
    var src = map && typeof map === "object" && !Array.isArray(map) ? map : {}
    for (var s in src) if (_isSide(s) && src[s] && typeof src[s] === "object") out[s] = Object.assign({}, src[s])
    if (!_isSide(side) || !OPTIONS[name]) return out
    var v = value === undefined ? undefined : _valid(OPTIONS[name], value)
    if (!out[side]) out[side] = {}
    if (v === undefined) delete out[side][name]
    else out[side][name] = v
    if (Object.keys(out[side]).length === 0) delete out[side]
    return out
}

// How many options an island overrides.
function overrideCount(side, map) {
    var n = 0
    for (var name in OPTIONS) if (overrides(side, name, map)) n++
    return n
}
