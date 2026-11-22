.pragma library

// ── tablet.js ─────────────────────────────────────────────────────────────────
// The rules behind services/Tablet.qml: the saved document, a profile, the area
// maths, the Lua handed to `hyprctl eval`, and the express-key bindings. Pure, so
// `bun scripts/test-tablet.js` can pin it; the service holds state and talks to the
// compositor.
//
// ── What a profile is ─────────────────────────────────────────────────────────
// One tablet's settings, by name: which output it maps to ("" is the whole desktop),
// which part of the tablet is used (`area`, millimetres in the tablet's own axes),
// whether that area keeps the screen's shape, a quarter-turn, absolute or relative
// input, and the pressure range. A tablet keeps several, one is active.
//
// ── Why the Lua is a string builder with a whitelist ──────────────────────────
// `hyprctl eval` runs what it is given as Lua inside the compositor, and a profile
// comes from a user-editable JSON file. Nothing reaches the string except numbers
// this file clamps and a monitor name matched against a fixed alphabet. (Same rule as
// cursoreffects.js.)
//
// ── Vectors ───────────────────────────────────────────────────────────────────
// A position or size goes in as `{ a, b }`. The `{ x = a, y = b }` form the Lua stub lists for these is
// refused by `hl.config` ("vec2 type requires exactly 2 elements", measured on 0.57.2 through `hyprctl eval`).
//
// ── Pressure ──────────────────────────────────────────────────────────────────
// Hyprland's `pressure_range_min/max` are unset at -1. A profile at 0..1 is the
// tablet's own range, so it sends -1 (unset) and a change back to the default really
// does undo the earlier one.
//
// Tested: `bun scripts/test-tablet.js`.
// ─────────────────────────────────────────────────────────────────────────────

var ROTATIONS = [0, 90, 180, 270]
var BINDING_KINDS = ["none", "chord", "command", "profile"]
// A pad's keys are the BTN_0..BTN_9 range plus BTN_A..BTN_THUMBR (linux/input-event-codes.h); a pen
// reports BTN_TOOL_* and BTN_TOUCH from 0x140 up, so the ranges never meet. tablet-helper.py holds
// the same two ranges.
var PAD_RANGES = [[0x100, 0x110], [0x130, 0x13f]]
var MIN_AREA_MM = 5
var MIN_PRESSURE_SPAN = 0.05
var NAME_MAX = 24
var KEY_MAX = 16

function _num(v, lo, hi, dflt) {
    var n = Number(v)
    if (v === null || v === "" || !isFinite(n)) return dflt
    return Math.max(lo, Math.min(hi, n))
}

function _round(n, places) {
    var f = Math.pow(10, places || 0)
    return Math.round(n * f) / f
}

function _plain(o) { return o !== null && typeof o === "object" && !Array.isArray(o) }

// ── Names and the device list ─────────────────────────────────────────────────

// Hyprland's own spelling of a device name (hyprctl devices): lower case, spaces and newlines to a dash.
// It keys a tablet's saved profiles.
function hyprName(kernelName) {
    return String(kernelName || "").replace(/[ \n]/g, "-").toLowerCase()
}

var _NODE = /^\/dev\/input\/event[0-9]{1,5}$/

// What `tablet-helper.py --probe` printed, read as untrusted: a device needs a pen node and sane sizes.
function parseProbe(text) {
    var doc
    try { doc = typeof text === "string" ? JSON.parse(text) : text } catch (e) { return { ok: false, tablets: [], reason: "unreadable" } }
    if (!_plain(doc)) return { ok: false, tablets: [], reason: "unreadable" }
    var out = []
    var list = Array.isArray(doc.tablets) ? doc.tablets : []
    for (var i = 0; i < list.length; i++) {
        var t = list[i]
        if (!_plain(t) || typeof t.pen !== "string" || !_NODE.test(t.pen)) continue
        var w = _num(t.widthMm, 0, 2000, 0), h = _num(t.heightMm, 0, 2000, 0)
        if (w <= 0 || h <= 0) continue
        out.push({
            name: String(t.name || "Tablet").slice(0, 80),
            hypr: typeof t.hypr === "string" && t.hypr !== "" ? t.hypr : hyprName(t.name),
            model: String(t.model || "").slice(0, 80),
            pen: t.pen,
            pad: typeof t.pad === "string" && _NODE.test(t.pad) ? t.pad : "",
            widthMm: w,
            heightMm: h,
            keys: Math.round(_num(t.keys, 0, KEY_MAX, 0)),
            access: t.access === true
        })
    }
    return { ok: doc.udev !== false, tablets: out, reason: doc.udev === false ? "udevadm" : "" }
}

// ── Pad keys from a sysfs capabilities/key bitmap ─────────────────────────────

// "800 f 0 0 0 0": 64-bit words, the highest first. Returns the set key codes inside the pad ranges.
function padKeyCodes(caps) {
    var words = String(caps || "").trim().split(/\s+/).filter(function (s) { return /^[0-9a-fA-F]+$/.test(s) })
    var codes = []
    for (var r = 0; r < PAD_RANGES.length; r++) {
        for (var c = PAD_RANGES[r][0]; c < PAD_RANGES[r][1]; c++) {
            var wi = words.length - 1 - Math.floor(c / 64)
            if (wi < 0) continue
            // 64-bit words do not fit a double, so take the nibble that holds the bit.
            var hex = words[wi]
            var nib = c % 64 >> 2
            var ch = hex.charAt(hex.length - 1 - nib)
            if (ch === "") continue
            if ((parseInt(ch, 16) >> (c % 4)) & 1) codes.push(c)
        }
    }
    return codes
}

// ── Area ──────────────────────────────────────────────────────────────────────

function fullArea(dev) { return { x: 0, y: 0, w: dev.widthMm, h: dev.heightMm } }

// Inside the tablet, at least MIN_AREA_MM each way. Millimetres to a tenth.
function clampArea(a, dev) {
    var o = _plain(a) ? a : {}
    var w = _round(_num(o.w, MIN_AREA_MM, dev.widthMm, dev.widthMm), 1)
    var h = _round(_num(o.h, MIN_AREA_MM, dev.heightMm, dev.heightMm), 1)
    var x = _round(_num(o.x, 0, dev.widthMm - w, 0), 1)
    var y = _round(_num(o.y, 0, dev.heightMm - h, 0), 1)
    return { x: x, y: y, w: w, h: h }
}

function areaIsFull(a, dev) {
    return a.x <= 0.5 && a.y <= 0.5 && a.w >= dev.widthMm - 0.5 && a.h >= dev.heightMm - 0.5
}

// The shape (width over height) the area must have to fill a screen, in the tablet's own axes: a
// quarter-turn swaps which tablet axis runs along the screen's width.
function areaRatio(screenW, screenH, rotation) {
    var w = Number(screenW), h = Number(screenH)
    if (!(w > 0) || !(h > 0)) return 0
    return (rotation === 90 || rotation === 270) ? h / w : w / h
}

// The size, in pixels, of what a profile maps the tablet onto: the named output, or (empty name) the box
// around every output. {0, 0} when that output is not there. `screens`: [{ name, x, y, width, height }].
function targetSize(screens, output) {
    var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
    var list = Array.isArray(screens) ? screens : []
    for (var i = 0; i < list.length; i++) {
        var s = list[i]
        if (!_plain(s) || (output !== "" && s.name !== output)) continue
        var w = Number(s.width), h = Number(s.height), x = Number(s.x) || 0, y = Number(s.y) || 0
        if (!(w > 0) || !(h > 0)) continue
        x0 = Math.min(x0, x); y0 = Math.min(y0, y)
        x1 = Math.max(x1, x + w); y1 = Math.max(y1, y + h)
    }
    return isFinite(x0) ? { w: x1 - x0, h: y1 - y0 } : { w: 0, h: 0 }
}

// The largest area of `ratio` (width over height) that fits the tablet, around the middle of `from`
// where it can be.
function fitRatio(from, dev, ratio) {
    if (!(ratio > 0)) return clampArea(from, dev)
    var w = dev.widthMm, h = w / ratio
    if (h > dev.heightMm) { h = dev.heightMm; w = h * ratio }
    var cx = from.x + from.w / 2, cy = from.y + from.h / 2
    return clampArea({ x: cx - w / 2, y: cy - h / 2, w: w, h: h }, dev)
}

// Resize to a width and keep the shape: the height follows, then the whole thing is pulled back inside.
function resizeKeeping(from, dev, width, ratio) {
    if (!(ratio > 0)) return clampArea({ x: from.x, y: from.y, w: width, h: from.h }, dev)
    var w = Math.min(width, dev.widthMm, dev.heightMm * ratio)
    return clampArea({ x: from.x, y: from.y, w: w, h: w / ratio }, dev)
}

// ── Profiles ──────────────────────────────────────────────────────────────────

function _name(v, dflt) {
    var s = String(v === undefined || v === null ? "" : v).replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, NAME_MAX)
    return s !== "" ? s : dflt
}

// A monitor name Hyprland takes for `output`: letters, digits and . _ : + - space. No quote, no backslash.
function cleanOutput(v) {
    var s = typeof v === "string" ? v : ""
    return /^[A-Za-z0-9][A-Za-z0-9 ._:+-]{0,63}$/.test(s) ? s : ""
}

function defaultProfile(dev, name) {
    return {
        name: _name(name, "Default"),
        output: "",
        area: fullArea(dev),
        lockRatio: true,
        rotation: 0,
        relative: false,
        pressure: { min: 0, max: 1 }
    }
}

function normaliseProfile(p, dev) {
    var o = _plain(p) ? p : {}
    var pr = _plain(o.pressure) ? o.pressure : {}
    var lo = _num(pr.min, 0, 1 - MIN_PRESSURE_SPAN, 0)
    var hi = _num(pr.max, lo + MIN_PRESSURE_SPAN, 1, 1)
    return {
        name: _name(o.name, "Profile"),
        output: cleanOutput(o.output),
        area: clampArea(o.area, dev),
        lockRatio: o.lockRatio !== false,
        rotation: ROTATIONS.indexOf(o.rotation) >= 0 ? o.rotation : 0,
        relative: o.relative === true,
        pressure: { min: _round(lo, 2), max: _round(hi, 2) }
    }
}

function _lua(n) { return String(_round(Number(n), 2)) }

// The one `hl.config` call that makes the compositor behave as `profile` says. `profile` is normalised
// here, whatever it was.
function lua(profile, dev) {
    var p = normaliseProfile(profile, dev)
    var full = areaIsFull(p.area, dev)
    var stock = p.pressure.min <= 0 && p.pressure.max >= 1
    return "hl.config({ input = { "
        + "tablet = { "
        + "output = \"" + p.output + "\", "
        + "relative_input = " + (p.relative ? "true" : "false") + ", "
        + "transform = " + (p.rotation / 90) + ", "
        + "active_area_position = { " + _lua(full ? 0 : p.area.x) + ", " + _lua(full ? 0 : p.area.y) + " }, "
        + "active_area_size = { " + _lua(full ? 0 : p.area.w) + ", " + _lua(full ? 0 : p.area.h) + " } "
        + "}, "
        + "tablettool = { "
        + "pressure_range_min = " + (stock ? "-1" : _lua(p.pressure.min)) + ", "
        + "pressure_range_max = " + (stock ? "-1" : _lua(p.pressure.max)) + " "
        + "} } })"
}

// ── Express keys ──────────────────────────────────────────────────────────────
// A key runs one of: a chord (wtype), a command (an argv, no shell: services/Tablet.qml reads it with
// inactivity.js parseCommand, so what runs is what the field says), or a profile switch.

var _MODS = { ctrl: "ctrl", control: "ctrl", shift: "shift", alt: "alt", super: "logo", logo: "logo", win: "logo", meta: "logo" }
var _KEYSYM = /^[A-Za-z0-9_]{1,32}$/

// "ctrl+shift+z" as the argv `wtype` takes, or null when it is not a chord. No shell is involved.
function chordArgv(chord) {
    var parts = String(chord || "").split("+").map(function (s) { return s.trim() })
    if (parts.length < 1 || parts.length > 5) return null
    var key = parts.pop()
    if (!_KEYSYM.test(key)) return null
    var mods = []
    for (var i = 0; i < parts.length; i++) {
        var m = _MODS[parts[i].toLowerCase()]
        if (!m) return null
        if (mods.indexOf(m) < 0) mods.push(m)
    }
    var argv = ["wtype"]
    for (var a = 0; a < mods.length; a++) argv.push("-M", mods[a])
    argv.push("-k", key)
    for (var b = mods.length - 1; b >= 0; b--) argv.push("-m", mods[b])
    return argv
}

function normaliseBinding(b) {
    var o = _plain(b) ? b : {}
    var kind = BINDING_KINDS.indexOf(o.kind) >= 0 ? o.kind : "none"
    var value = String(o.value === undefined || o.value === null ? "" : o.value).slice(0, 200)
    if (kind === "chord" && !chordArgv(value)) kind = "none"
    if (kind === "command" && value.trim() === "") kind = "none"
    if (kind === "profile" && value !== "next" && value !== "prev" && _name(value, "") === "") kind = "none"
    return kind === "none" ? { kind: "none", value: "" } : { kind: kind, value: value }
}

// ── The saved document ────────────────────────────────────────────────────────
// { version: 1, devices: { "<hyprland name>": { active: "<profile name>", profiles: [..], keys: [..] } } }

function emptyState() { return { version: 1, devices: {} } }

function _uniqueName(names, base) {
    if (names.indexOf(base) < 0) return base
    for (var n = 2; n < 1000; n++) {
        var s = (base.slice(0, NAME_MAX - String(n).length - 1) + " " + n)
        if (names.indexOf(s) < 0) return s
    }
    return base
}

function _normaliseDevice(raw, dev) {
    var o = _plain(raw) ? raw : {}
    var seen = []
    var profiles = []
    var list = Array.isArray(o.profiles) ? o.profiles.slice(0, 12) : []
    for (var i = 0; i < list.length; i++) {
        var p = normaliseProfile(list[i], dev)
        p.name = _uniqueName(seen, p.name)
        seen.push(p.name)
        profiles.push(p)
    }
    if (profiles.length === 0) profiles.push(defaultProfile(dev))
    var active = typeof o.active === "string" && seen.indexOf(o.active) >= 0 ? o.active : profiles[0].name
    var keys = []
    var kraw = Array.isArray(o.keys) ? o.keys : []
    for (var k = 0; k < KEY_MAX; k++) keys.push(normaliseBinding(kraw[k]))
    return { active: active, profiles: profiles, keys: keys }
}

// Untrusted disk data in, a state out. A device that is not plugged in keeps its entry as it was
// written (its dimensions are unknown, so it cannot be clamped), and is cleaned when it appears.
function normalise(doc) {
    var out = emptyState()
    if (!_plain(doc) || !_plain(doc.devices)) return out
    var names = Object.keys(doc.devices).slice(0, 16)
    for (var i = 0; i < names.length; i++)
        if (_plain(doc.devices[names[i]])) out.devices[names[i]] = doc.devices[names[i]]
    return out
}

// This tablet's entry, cleaned against its real size. Always has one profile and the active one exists.
function deviceState(state, name, dev) {
    var raw = state && _plain(state.devices) ? state.devices[name] : null
    return _normaliseDevice(raw, dev)
}

function _with(state, name, dev, next) {
    var out = { version: 1, devices: {} }
    var src = state && _plain(state.devices) ? state.devices : {}
    for (var k in src) out.devices[k] = src[k]
    out.devices[name] = next
    return out
}

function activeProfile(state, name, dev) {
    var d = deviceState(state, name, dev)
    for (var i = 0; i < d.profiles.length; i++) if (d.profiles[i].name === d.active) return d.profiles[i]
    return d.profiles[0]
}

// Merge `patch` into the active profile; the result is cleaned like any other.
function setProfile(state, name, dev, patch) {
    var d = deviceState(state, name, dev)
    var profiles = d.profiles.map(function (p) {
        if (p.name !== d.active) return p
        var merged = {}
        for (var k in p) merged[k] = p[k]
        for (var j in patch) merged[j] = patch[j]
        merged.name = p.name
        return normaliseProfile(merged, dev)
    })
    return _with(state, name, dev, { active: d.active, profiles: profiles, keys: d.keys })
}

function selectProfile(state, name, dev, profileName) {
    var d = deviceState(state, name, dev)
    var has = d.profiles.some(function (p) { return p.name === profileName })
    return has ? _with(state, name, dev, { active: profileName, profiles: d.profiles, keys: d.keys }) : state
}

// "next" / "prev" around the list.
function cycleProfile(state, name, dev, dir) {
    var d = deviceState(state, name, dev)
    var at = 0
    for (var i = 0; i < d.profiles.length; i++) if (d.profiles[i].name === d.active) at = i
    var n = d.profiles.length
    var to = (at + (dir === "prev" ? n - 1 : 1)) % n
    return selectProfile(state, name, dev, d.profiles[to].name)
}

// A copy of the active profile (or a fresh default), made active.
function addProfile(state, name, dev, base, fresh) {
    var d = deviceState(state, name, dev)
    if (d.profiles.length >= 12) return state
    var seed = fresh ? defaultProfile(dev) : activeProfile(state, name, dev)
    var p = normaliseProfile(seed, dev)
    p.name = _uniqueName(d.profiles.map(function (x) { return x.name }), _name(base, fresh ? "Profile" : p.name + " copy"))
    return _with(state, name, dev, { active: p.name, profiles: d.profiles.concat([p]), keys: d.keys })
}

function renameProfile(state, name, dev, from, to) {
    var d = deviceState(state, name, dev)
    var names = d.profiles.map(function (x) { return x.name }).filter(function (n) { return n !== from })
    var next = _uniqueName(names, _name(to, from))
    var profiles = d.profiles.map(function (p) {
        if (p.name !== from) return p
        var c = normaliseProfile(p, dev)
        c.name = next
        return c
    })
    return _with(state, name, dev, { active: d.active === from ? next : d.active, profiles: profiles, keys: d.keys })
}

// The last profile cannot go.
function removeProfile(state, name, dev, profileName) {
    var d = deviceState(state, name, dev)
    if (d.profiles.length <= 1) return state
    var profiles = d.profiles.filter(function (p) { return p.name !== profileName })
    if (profiles.length === d.profiles.length) return state
    var active = d.active === profileName ? profiles[0].name : d.active
    return _with(state, name, dev, { active: active, profiles: profiles, keys: d.keys })
}

function setKey(state, name, dev, index, binding) {
    var d = deviceState(state, name, dev)
    var i = Math.round(Number(index))
    if (!(i >= 0 && i < KEY_MAX)) return state
    var keys = d.keys.slice()
    keys[i] = normaliseBinding(binding)
    return _with(state, name, dev, { active: d.active, profiles: d.profiles, keys: keys })
}
