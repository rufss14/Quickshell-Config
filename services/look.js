.pragma library

// ── look.js ───────────────────────────────────────────────────────────────────
// A look bundle: how the shell LOOKS, as one small .json file you can send someone.
// Pure functions over plain data, so `bun scripts/test-look.js` can pin them; the
// singleton that talks to files and Config is services/Look.qml.
//
//   {
//     "format": "quicktest-look", "version": 1, "shell": "0.4.1",
//     "name": "Night market",
//     "wallpaper": "market.jpg",            // a NAME, for the reader — never a path, never the image
//     "style":  { fontScale: 1.05, ... },   // the whitelist below, nothing else
//     "bar":    { ...Config._snapshot() },  // bar, frame, sidebar, modules — what a bar preset holds
//     "scheme": { "mode": "dark", "palette": { special: {...}, colors: {...} } }
//   }
//
// ── Why a whitelist, not "everything persisted" ───────────────────────────────
// A shell preset (Config._dumpPrefs) holds every setting, including a lock-screen avatar
// path, the weather town, an AI model, clip folders. A look is for sending to a stranger:
// it carries appearance only, and every value is checked against the table below on the
// way OUT (so an export is always valid) and on the way IN (so a hand-edited or hostile
// file can't reach a property with the wrong type or a absurd size).
//
// ── What is deliberately NOT in a look ────────────────────────────────────────
// Motion (motionEnabled, motionScale, motionReduced): the user's own comfort setting, not
// a style — an imported look must never turn their animations back on. Paths, accounts,
// locations, keybinds, behaviour switches. Wallpapers: the file names the picture it was
// made with and nothing more (no licensing, no size).
//
// Invalid values are DROPPED (the user's own value stays), not clamped: "applied" then
// means exactly what the file said. `skipped` counts them so the UI can say so.
// ─────────────────────────────────────────────────────────────────────────────

var FORMAT = "quicktest-look"
var VERSION = 1
// A real look is a few KB (the bar layout is the bulk). Anything near this is not one.
var MAX_BYTES = 100000
var MAX_OBJ_BYTES = 40000

// ── Value specs ───────────────────────────────────────────────────────────────
function _bool()            { return { t: "bool" } }
function _num(lo, hi)       { return { t: "num", lo: lo, hi: hi } }
function _int(lo, hi)       { return { t: "int", lo: lo, hi: hi } }
function _str(max, re)      { return { t: "str", max: max, re: re || null } }
function _one(values)       { return { t: "enum", values: values } }
var ID = /^[A-Za-z0-9_-]*$/

// Appearance only. Ranges are Config's own (the *Min/*Max beside each property, or the
// range the settings page's slider offers).
var STYLE = {
    fontFamily:      _str(80),            fontMonoFamily:  _str(80),         fontBlockFamily: _str(80),
    fontScale:       _num(0.8, 1.3),      densityScale:    _num(0.75, 1.5),  radiusScale:     _num(0.5, 1.5),
    cornerStyle:     _one(["default", "ii"]),
    iconShape:       _one(["default", "squircle", "cookie", "clover", "circle"]),
    surfaceOpacity:  _num(0.5, 1),        shadowScale:     _num(0, 1.5),
    accentRole:      _str(32, ID),        themeMode:       _one(["dark", "light"]),
    colorizeIcons:   _bool(),
    panelCookies:    _bool(),             barCookies:      _bool(),
    barCookiesFrom:  _one(["panels", "everywhere"]),
    dockStyle:       _one(["frame", "ii"]),
    dockIconSize:    _int(24, 56),        dockInnerPill:   _bool(),          dockMagnify:     _bool(),
    dockMagnifyScale: _num(1.2, 2.2),
    // The generated wallpaper (no image involved: a look can carry it whole).
    wallMaterial:         _bool(),
    wallMaterialRole:     _str(32, ID),   wallMaterialRole2:    _str(32, ID),
    wallMaterialContrast: _num(0.5, 1.5), wallMaterialSoftness: _num(0.4, 1.8),
    wallMaterialSize:     _num(0.7, 1.4), wallMaterialSeed:     _int(0, 2147483647),
    wallMaterialStack:    _str(32, ID),   wallMaterialCentre:   _str(32, ID),
    wallMaterialSide:     _str(32, ID),   wallMaterialCorner:   _str(32, ID),
    wallMaterialBackdrop: _num(0, 1),     wallMaterialMirror:   _bool(),
    wallMaterialDrift:    _bool(),        wallMaterialDriftSpeed: _num(0.2, 3),
    wallMaterialSpin:     _num(0, 1),
    wallFx:          _bool(),             wallFxIntensity: _num(0, 1),
    cavaBgStyle:     _one(["bars", "wave", "dots"]),
    cavaBgOpacity:   _num(0, 1),          cavaBgGlow:      _bool(),
    cavaBgPeaks:     _bool(),             cavaBgRingCover: _bool(),
    widgetOpacity:   _num(0.2, 1),        widgetRoundness: _int(0, 64),      widgetGlass:     _bool()
}

// What Config._snapshot() writes (a bar preset), minus the motion keys. Sizes are
// sanity-bounded here; the semantic cleaning (layouts, hero, style) is done by Config's own
// loaders (Layout.reconcile, Surfaces.cleanStyle) when the snapshot is applied.
var BAR = {
    barShape:        _bool(),   barThickness:    _num(0, 1000), barRoundness:    _num(0, 1000),
    barInset:        _num(0, 1000), barBorderWidth: _num(0, 100), barOpacity:     _num(0, 1),
    barCentreAnchor: _bool(),   barFontScale:    _num(0.8, 1.4), barIconScale:    _num(0.8, 1.4),
    barInnerPill:    _bool(),   screenFrame:     _bool(),
    barLayout:       _str(40, ID),
    frameThickness:  _num(0, 1000), frameRoundness: _num(0, 1000), frameBorderWidth: _num(0, 100),
    barHoverGrow:    _bool(),
    barHero:         _str(40, ID), sidebarHero: _str(40, ID),
    sidebarIslands:  _bool(),   barMusicReact:   _bool()
}
// Structured parts: plain JSON objects/arrays, size-bounded.
var BAR_OBJECTS = ["layout", "moduleSettings", "groupSettings", "panelPlacement", "panelZoom",
                   "sidebarLayout", "sidebarStyle"]

function styleKeys() { return Object.keys(STYLE) }

// ── Validation ────────────────────────────────────────────────────────────────
function _isObj(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }

// Undefined = invalid. A control character in a string is invalid (it would reach a font
// name or a role id).
function _value(spec, v) {
    switch (spec.t) {
    case "bool": return typeof v === "boolean" ? v : undefined
    case "num":
        return (typeof v === "number" && isFinite(v) && v >= spec.lo && v <= spec.hi) ? v : undefined
    case "int":
        return (typeof v === "number" && Math.floor(v) === v && v >= spec.lo && v <= spec.hi) ? v : undefined
    case "enum": return spec.values.indexOf(v) >= 0 ? v : undefined
    case "str":
        if (typeof v !== "string" || v.length > spec.max) return undefined
        if (/[\u0000-\u001f\u007f]/.test(v)) return undefined
        if (spec.re && !spec.re.test(v)) return undefined
        return v
    }
    return undefined
}

function _clean(table, src, out, bump) {
    if (!_isObj(src)) return
    Object.keys(src).forEach(function (k) {
        if (!Object.prototype.hasOwnProperty.call(table, k)) return       // unknown: ignored, not an error
        var v = _value(table[k], src[k])
        if (v === undefined) bump(); else out[k] = v
    })
}

var _BAD_KEYS = { "__proto__": 1, "constructor": 1, "prototype": 1 }

// A JSON value with no hostile keys, bounded depth and size. null = refuse.
function _plain(v, depth) {
    if (depth > 8) return null
    if (v === null || typeof v === "boolean" || typeof v === "string") return v
    if (typeof v === "number") return isFinite(v) ? v : null
    if (Array.isArray(v)) {
        var a = []
        for (var i = 0; i < v.length; i++) {
            var x = _plain(v[i], depth + 1)
            if (x === null && v[i] !== null) return null
            a.push(x)
        }
        return a
    }
    if (_isObj(v)) {
        var o = {}
        var keys = Object.keys(v)
        for (var j = 0; j < keys.length; j++) {
            if (_BAD_KEYS[keys[j]]) return null
            var y = _plain(v[keys[j]], depth + 1)
            if (y === null && v[keys[j]] !== null) return null
            o[keys[j]] = y
        }
        return o
    }
    return null
}

function cleanStyle(src) {
    var out = {}, skipped = 0
    _clean(STYLE, src, out, function () { skipped++ })
    return { value: out, skipped: skipped }
}

function cleanBar(src) {
    var out = {}, skipped = 0
    if (!_isObj(src)) return { value: null, skipped: 0 }
    _clean(BAR, src, out, function () { skipped++ })
    BAR_OBJECTS.forEach(function (k) {
        if (!(k in src)) return
        var p = _plain(src[k], 0)
        if (p === null || !(_isObj(p) || Array.isArray(p)) || JSON.stringify(p).length > MAX_OBJ_BYTES) skipped++
        else out[k] = p
    })
    return { value: Object.keys(out).length ? out : null, skipped: skipped }
}

// The 18 colours a palette is: special.{background,foreground,cursor} and colors.color0..15,
// each #rrggbb. All or nothing — half a palette would leave the shell part-recoloured.
var HEX = /^#[0-9a-fA-F]{6}$/
function cleanPalette(p) {
    if (!_isObj(p) || !_isObj(p.special) || !_isObj(p.colors)) return null
    var out = { special: {}, colors: {} }
    var sp = ["background", "foreground", "cursor"]
    for (var i = 0; i < sp.length; i++) {
        var s = p.special[sp[i]]
        if (typeof s !== "string" || !HEX.test(s)) return null
        out.special[sp[i]] = s.toLowerCase()
    }
    for (var n = 0; n < 16; n++) {
        var c = p.colors["color" + n]
        if (typeof c !== "string" || !HEX.test(c)) return null
        out.colors["color" + n] = c.toLowerCase()
    }
    return out
}

function cleanScheme(s) {
    if (!_isObj(s) || (s.mode !== "dark" && s.mode !== "light")) return null
    var pal = cleanPalette(s.palette)
    return pal ? { mode: s.mode, palette: pal } : null
}

// A display name: no control characters, one line, 48 at most. "" if nothing is left.
function cleanName(n) {
    if (typeof n !== "string") return ""
    return n.replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim().slice(0, 48)
}

// Same set ColorScheme.sanitiseName allows, so the saved scheme's name round-trips.
function schemeName(n) {
    var s = String(n || "").trim().replace(/[^a-zA-Z0-9 _.-]/g, "").trim()
    return s === "" ? "Look" : s
}

function fileName(n) {
    var s = schemeName(n).replace(/\s+/g, "-").replace(/^[.-]+/, "")
    return (s === "" ? "look" : s) + ".look.json"
}

// A picture's NAME as shown to the reader. Never a path: anything with a slash keeps only
// its last part.
function cleanWallpaper(w) {
    if (typeof w !== "string") return ""
    var base = w.split("/").pop()
    return /[\u0000-\u001f\u007f]/.test(base) ? "" : base.slice(0, 80)
}

// `name`, or "name 2", "name 3"… so an import never overwrites a scheme already in the library.
function uniqueName(name, taken) {
    var base = schemeName(name)
    var has = function (n) { return taken.indexOf(n) >= 0 }
    if (!has(base)) return base
    for (var i = 2; i < 1000; i++) if (!has(base + " " + i)) return base + " " + i
    return base + " " + Date.now()
}

// ── Build ─────────────────────────────────────────────────────────────────────
// `input`: { name, shell, wallpaper, values (every Config property, by name), bar (the
// _snapshot()), mode, palette }. Everything passes through the same cleaners as an import,
// so what is written is what would be accepted.
function build(input) {
    var style = cleanStyle(input.values || {}).value
    var bar = cleanBar(input.bar || {}).value
    var scheme = cleanScheme({ mode: input.mode, palette: input.palette })
    if (!scheme) delete style.themeMode            // a mode without its colours would half-apply
    var doc = { format: FORMAT, version: VERSION, shell: String(input.shell || ""),
                name: cleanName(input.name) || "My look" }
    var wp = cleanWallpaper(input.wallpaper)
    if (wp) doc.wallpaper = wp
    doc.style = style
    if (bar) doc.bar = bar
    if (scheme) doc.scheme = scheme
    return doc
}

function serialize(doc) { return JSON.stringify(doc, null, 2) + "\n" }

// ── Parse ─────────────────────────────────────────────────────────────────────
// → { ok, error, look: { name, wallpaper, style, bar, scheme }, skipped }
function parse(text) {
    var fail = function (m) { return { ok: false, error: m, look: null, skipped: 0 } }
    if (typeof text !== "string" || text.trim() === "") return fail("The file is empty")
    if (text.length > MAX_BYTES) return fail("Too big to be a look")
    var doc
    try { doc = JSON.parse(text) } catch (e) { return fail("Not a look file (not valid JSON)") }
    if (!_isObj(doc) || doc.format !== FORMAT) return fail("Not a Quicktest look file")
    if (typeof doc.version !== "number" || Math.floor(doc.version) !== doc.version || doc.version < 1)
        return fail("Not a Quicktest look file")
    if (doc.version > VERSION) return fail("Made by a newer shell: update, then import it")

    var st = cleanStyle(doc.style)
    var bar = cleanBar(doc.bar)
    var scheme = cleanScheme(doc.scheme)
    var skipped = st.skipped + bar.skipped + (doc.scheme !== undefined && !scheme ? 1 : 0)
    // A mode without the colours that go with it would flip the shell's mode and leave the old palette.
    if (!scheme && "themeMode" in st.value) { delete st.value.themeMode; skipped++ }

    var look = { name: cleanName(doc.name) || "Imported look", wallpaper: cleanWallpaper(doc.wallpaper),
                 style: st.value, bar: bar.value, scheme: scheme }
    if (Object.keys(look.style).length === 0 && !look.bar && !look.scheme)
        return fail("Nothing in this file can be applied")
    return { ok: true, error: "", look: look, skipped: skipped }
}

// The lines the confirm card shows: what applying this look will change.
function summary(look) {
    var out = []
    if (look.bar) out.push("Bar, frame and sidebar")
    var n = Object.keys(look.style).length
    if (n > 0) out.push(n + (n === 1 ? " style setting" : " style settings"))
    if (look.scheme) out.push("Colour scheme, " + look.scheme.mode + " (saved to your library)")
    if (look.wallpaper) out.push("Made with the wallpaper “" + look.wallpaper + "” (not included)")
    return out
}
