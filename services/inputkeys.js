.pragma library

// ── inputkeys.js ──────────────────────────────────────────────────────────────
// The HUD's input overlay: which keys and mouse buttons it draws, where, the Lua hook that
// tells the shell when they go down and up, and the parser for what comes back. Pure, so
// it can be tested (`bun scripts/test-inputkeys.js`, which also RUNS the Lua under lua5.4
// against a stub `hl`).
//
// ── How a press reaches the shell ─────────────────────────────────────────────
// Wayland shows a client only its own input, so the compositor has to say — the SfxKeys
// route (sfxkeys.js has the measured payload): a runtime `hl.on("input.keyboard.key")`
// posts a CUSTOM EVENT per key, heard on the event socket the shell already reads.
// Hyprland's Lua has no mouse event, so each mouse button is a pair of binds — press,
// and `release = true` — both `non_consuming` (the click still reaches the game) and
// `ignore_mods` (a Shift+click still lights). Those are STATIC, in hypr/binds.lua: see
// "NEVER hl.bind from here" below. The wheel isn't shown (a wheel bind would sit on
// every scroll in every app; not added until tried).
//
// ── What it sends — only what is drawn ────────────────────────────────────────
// The event socket is readable by every process this user runs, and unlike SfxKeys this
// hook has to say WHICH key. So it only names the keys in KEYS. Any other key's PRESS goes
// out as a bare "k" — no identity, no release, the same cadence SfxKeys already sends —
// so keys-per-second counts every key, not only the drawn ones. And it only exists while
// the overlay is on screen, and never while the screen is locked (services/InputKeys).
// While it is up, those keys' presses are on the socket — typing in a chat window with
// the overlay pinned puts W/A/S/D/… there. docs/hud.md says so.
//
// ── Keycodes: Hyprland's are evdev + 8 ────────────────────────────────────────
// KEYS lists evdev codes (linux/input-event-codes.h — W is 17); the hook looks them up at
// code + XKB_OFFSET. MEASURED 2026-10-19 by recording the event socket while every drawn
// key was pressed: with the table looked up at plain evdev, all 72 presses went out as
// ANON — not one matched — so the key event does NOT carry evdev codes, despite what
// sfxkeys.js assumed (it only tells space/enter/backspace apart and was never checked).
// +8 is xkb's keycode numbering — CONFIRMED the same day: with it, Q W E A S D F arrived
// named and counted (`inputkeys status`). None of the drawn keys' evdev and +8 codes overlap, so
// the two readings can't be confused for each other.
//
// Codes are PHYSICAL positions: on AZERTY the key drawn "W" is the one printed Z. That is
// the key a game's movement binding usually means too, so the labels stay the QWERTY ones.
// ─────────────────────────────────────────────────────────────────────────────

var PREFIX = "qs-input:"
// What Hyprland's key event adds to an evdev code (see the header).
var XKB_OFFSET = 8
// A press of a key that isn't drawn: counted, never named.
var ANON = PREFIX + "k"

// ── Every key the overlay can draw: id, label, EVDEV codes ────────────────────
// (both copies of a modifier light one cap). The layouts below only place these; the hook names exactly the keys
// of the layout on screen, and no others.
var DEF = {}
function _d(id, label, codes) { DEF[id] = { id: id, label: label, codes: codes } }
_d("esc", "Esc", [1])
;[["f1", 59], ["f2", 60], ["f3", 61], ["f4", 62], ["f5", 63], ["f6", 64], ["f7", 65], ["f8", 66], ["f9", 67], ["f10", 68],
  ["f11", 87], ["f12", 88]].forEach(function (k) { _d(k[0], k[0].toUpperCase(), [k[1]]) })
_d("prtsc", "Prt", [99]); _d("scrlk", "Scr", [70]); _d("pause", "Pse", [119])
_d("grave", "`", [41])
;[["1", 2], ["2", 3], ["3", 4], ["4", 5], ["5", 6], ["6", 7], ["7", 8], ["8", 9], ["9", 10], ["0", 11]]
    .forEach(function (k) { _d("n" + k[0], k[0], [k[1]]) })
_d("minus", "-", [12]); _d("equal", "=", [13]); _d("back", "Back", [14])
_d("tab", "Tab", [15])
;[["q", 16], ["w", 17], ["e", 18], ["r", 19], ["t", 20], ["y", 21], ["u", 22], ["i", 23], ["o", 24], ["p", 25]]
    .forEach(function (k) { _d(k[0], k[0].toUpperCase(), [k[1]]) })
_d("lbrace", "[", [26]); _d("rbrace", "]", [27]); _d("bslash", "\\", [43])
_d("caps", "Caps", [58])
;[["a", 30], ["s", 31], ["d", 32], ["f", 33], ["g", 34], ["h", 35], ["j", 36], ["k", 37], ["l", 38]]
    .forEach(function (k) { _d(k[0], k[0].toUpperCase(), [k[1]]) })
_d("semi", ";", [39]); _d("apos", "'", [40]); _d("enter", "Enter", [28])
_d("shift", "Shift", [42, 54])
;[["z", 44], ["x", 45], ["c", 46], ["v", 47], ["b", 48], ["n", 49], ["m", 50]]
    .forEach(function (k) { _d(k[0], k[0].toUpperCase(), [k[1]]) })
_d("comma", ",", [51]); _d("dot", ".", [52]); _d("slash", "/", [53])
_d("ctrl", "Ctrl", [29, 97]); _d("super", "Super", [125, 126]); _d("alt", "Alt", [56, 100]); _d("space", "Space", [57])
_d("menu", "Menu", [127])
_d("ins", "Ins", [110]); _d("home", "Home", [102]); _d("pgup", "PgUp", [104])
_d("del", "Del", [111]); _d("end", "End", [107]); _d("pgdn", "PgDn", [109])
_d("up", "\u2191", [103]); _d("left", "\u2190", [105]); _d("down", "\u2193", [108]); _d("right", "\u2192", [106])
_d("numlock", "Num", [69]); _d("kpdiv", "/", [98]); _d("kpmul", "*", [55]); _d("kpminus", "-", [74])
_d("kp7", "7", [71]); _d("kp8", "8", [72]); _d("kp9", "9", [73]); _d("kpplus", "+", [78])
_d("kp4", "4", [75]); _d("kp5", "5", [76]); _d("kp6", "6", [77])
_d("kp1", "1", [79]); _d("kp2", "2", [80]); _d("kp3", "3", [81]); _d("kpenter", "Enter", [96])
_d("kp0", "0", [82]); _d("kpdot", ".", [83])

// ── Layouts ───────────────────────────────────────────────────────────────────
// A layout is rows of keys, in key units (1 = one letter key), staggered like a real board: an item is "id" (one unit),
// ["id", w] or ["id", w, h] (a tall key: the row under it leaves a blank), a bare number (a gap), and a bare number as a
// row is a vertical gap. `_build` turns it into { keys: [{ id, label, codes, x, y, w, h }], cols, rows }.
function _build(rows) {
    var keys = [], y = 0, cols = 0
    rows.forEach(function (row) {
        if (typeof row === "number") { y += row; return }
        var x = 0
        row.forEach(function (it) {
            if (typeof it === "number") { x += it; return }
            var id = typeof it === "string" ? it : it[0]
            var w = typeof it === "string" ? 1 : it[1]
            var h = typeof it === "string" || it[2] === undefined ? 1 : it[2]
            keys.push({ id: id, label: DEF[id].label, codes: DEF[id].codes, x: x, y: y, w: w, h: h })
            x += w
        })
        cols = Math.max(cols, x)
        y += 1
    })
    return { keys: keys, cols: cols, rows: y }
}

var _FN = ["esc", 1, "f1", "f2", "f3", "f4", 0.5, "f5", "f6", "f7", "f8", 0.5, "f9", "f10", "f11", "f12"]
var _R1 = ["grave", "n1", "n2", "n3", "n4", "n5", "n6", "n7", "n8", "n9", "n0", "minus", "equal", ["back", 2]]
var _R2 = [["tab", 1.5], "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "lbrace", "rbrace", ["bslash", 1.5]]
var _R3 = [["caps", 1.75], "a", "s", "d", "f", "g", "h", "j", "k", "l", "semi", "apos", ["enter", 2.25]]
var _R4 = [["shift", 2.25], "z", "x", "c", "v", "b", "n", "m", "comma", "dot", "slash", ["shift", 2.75]]
var _R5 = [["ctrl", 1.25], ["super", 1.25], ["alt", 1.25], ["space", 6.25], ["alt", 1.25], ["super", 1.25], ["menu", 1.25], ["ctrl", 1.25]]

// What a layout names on the event socket (see the header): `few` is the keys a game binds, `some` adds the keys round
// them, `all` is every key you type — the card says so before you pick one.
var LAYOUTS = {
    wasd: { name: "WASD", blurb: "Movement keys, Shift, Ctrl and Space", exposes: "few", rows: [
        [["tab", 1.5], "q", "w", "e", "r"],
        [["shift", 1.75], "a", "s", "d", "f"],
        [["ctrl", 1.5], ["space", 4.25]] ] },
    gaming: { name: "Games", blurb: "Numbers, WASD and the keys around them", exposes: "some", rows: [
        ["esc", "n1", "n2", "n3", "n4", "n5"],
        [["tab", 1.5], "q", "w", "e", "r", "t"],
        [["caps", 1.75], "a", "s", "d", "f", "g"],
        [["shift", 2.25], "z", "x", "c", "v"],
        [["ctrl", 1.25], ["alt", 1.25], ["space", 4.25]] ] },
    compact: { name: "60%", blurb: "The main block of a keyboard", exposes: "all", rows: [_R1, _R2, _R3, _R4, _R5] },
    tkl: { name: "TKL", blurb: "Main block, function keys, arrows and navigation", exposes: "all", rows: [
        _FN.concat([0.25, "prtsc", "scrlk", "pause"]), 0.5,
        _R1.concat([0.25, "ins", "home", "pgup"]),
        _R2.concat([0.25, "del", "end", "pgdn"]),
        _R3,
        _R4.concat([0.25, 1, "up", 1]),
        _R5.concat([0.25, "left", "down", "right"]) ] },
    full: { name: "Full", blurb: "Every key, with the number pad", exposes: "all", rows: [
        _FN.concat([0.25, "prtsc", "scrlk", "pause"]), 0.5,
        _R1.concat([0.25, "ins", "home", "pgup", 0.25, "numlock", "kpdiv", "kpmul", "kpminus"]),
        _R2.concat([0.25, "del", "end", "pgdn", 0.25, "kp7", "kp8", "kp9", ["kpplus", 1, 2]]),
        _R3.concat([0.25, 3, 0.25, "kp4", "kp5", "kp6"]),
        _R4.concat([0.25, 1, "up", 1, 0.25, "kp1", "kp2", "kp3", ["kpenter", 1, 2]]),
        _R5.concat([0.25, "left", "down", "right", 0.25, ["kp0", 2], "kpdot"]) ] }
}
var LAYOUT_IDS = ["wasd", "gaming", "compact", "tkl", "full"]
var DEFAULT_LAYOUT = "wasd"
function isLayout(id) { return LAYOUT_IDS.indexOf(id) >= 0 }
var _built = {}
// A layout by id (an unknown one is the default): { keys, cols, rows, name, blurb, exposes }.
function layoutOf(id) {
    var k = isLayout(id) ? id : DEFAULT_LAYOUT
    if (!_built[k]) {
        var b = _build(LAYOUTS[k].rows)
        b.id = k; b.name = LAYOUTS[k].name; b.blurb = LAYOUTS[k].blurb; b.exposes = LAYOUTS[k].exposes
        _built[k] = b
    }
    return _built[k]
}

// The original three-row board, kept under its old names (tests, and anything that drew only that).
var KEYS = layoutOf("wasd").keys
var COLS = layoutOf("wasd").cols
var ROWS = layoutOf("wasd").rows

// Linux input button codes (BTN_LEFT…BTN_EXTRA), as Hyprland's `mouse:N` names them. The
// binds for them are hypr/binds.lua's static block, which must name the same ids
// (scripts/test-inputkeys.js runs it).
var BUTTONS = [
    { id: "lmb", button: 272 },
    { id: "rmb", button: 273 },
    { id: "mmb", button: 274 },
    { id: "m4",  button: 275 },
    { id: "m5",  button: 276 }
]

var KEY_IDS = Object.keys(DEF)
var BUTTON_IDS = BUTTONS.map(function (b) { return b.id })
var IDS = KEY_IDS.concat(BUTTON_IDS)

// The hook's lookup table for ONE layout: its keys only, by keycode (+ XKB_OFFSET).
function _luaKeys(keys) {
    var pairs = [], seen = {}
    keys.forEach(function (k) {
        k.codes.forEach(function (c) {
            if (seen[c]) return
            seen[c] = true
            pairs.push("[" + (c + XKB_OFFSET) + "]=\"" + k.id + "\"")
        })
    })
    return "{ " + pairs.join(", ") + " }"
}

// ── NEVER `hl.bind` from here ─────────────────────────────────────────────────
// The first build made the mouse buttons runtime binds, from this `hyprctl eval`. On
// Hyprland 0.56.2 that SEGFAULTS THE COMPOSITOR: the first install works, and a re-install
// (every shell reload, hot ones included) dies in `CLuaKeybind::push` handing the new bind
// back to Lua (crash reports 2026-10-19, twice). A segfault is past any pcall. So the
// mouse binds are STATIC, in hypr/binds.lua (the "HUD input overlay" block), registered
// once at config load like every other bind there, and silent unless `_G.qs_input_on`
// — the one thing this snippet sets for them.
//
// An install from that first build left `_G.qs_input_subs`: [1] its key subscription,
// the rest runtime keybinds. Only [1] is removed (an event subscription's remove is the
// SfxKeys path, safe on every reload); the keybinds are not touched — not even dropped
// through a method — and go away on the next Hyprland config reload.
var _CLEAR = [
'_G.qs_input_on = false',
'if _G.qs_input_subs then pcall(function() _G.qs_input_subs[1]:remove() end); _G.qs_input_subs = nil end',
'if _G.qs_input_sub then pcall(function() _G.qs_input_sub:remove() end); _G.qs_input_sub = nil end'
].join("\n")

// Installs (replacing any earlier copy of ours, so a shell reload never doubles events).
// Everything is pcall'd: it runs INSIDE the compositor, on the input path, and an error
// there must cost an overlay frame and nothing else.
// Installs for ONE layout (replacing any earlier copy of ours, so a shell reload or a layout change never doubles events).
function installLua(layoutId) {
return [
_CLEAR,
'local KEYS = ' + _luaKeys(layoutOf(layoutId).keys),
'local function say(s) pcall(function() hl.dispatch(hl.dsp.event(s)) end) end',
'-- (timeMs, keycode, state) as bare numbers on 0.56.2 — placed by magnitude, as sfxkeys.js does.',
'local function numeric(args)',
'  if args.n < 2 then return nil end',
'  for i = 1, args.n do if type(args[i]) ~= "number" then return nil end end',
'  if args.n >= 3 and args[3] <= 1 and args[2] < 1000 then return args[2], args[3] end',
'  local small = {}',
'  for i = 1, args.n do if args[i] < 1000 then small[#small + 1] = args[i] end end',
'  if #small == 2 then',
'    if small[2] <= 1 and small[1] > 1 then return small[1], small[2] end',
'    if small[1] <= 1 and small[2] > 1 then return small[2], small[1] end',
'  end',
'  return nil',
'end',
'_G.qs_input_sub = hl.on("input.keyboard.key", function(...)',
'  local args = table.pack(...)',
'  pcall(function()',
'    local code, state = numeric(args)',
'    if not code then return end',
'    local id = KEYS[code]',
'    if id then say("' + PREFIX + '" .. (state >= 1 and "d" or "u") .. id)',
'    elseif state >= 1 then say("' + ANON + '") end',
'  end)',
'end)',
'-- The static mouse binds in hypr/binds.lua speak only while this is set.',
'_G.qs_input_on = true'
].join("\n")
}
var INSTALL_LUA = installLua(DEFAULT_LAYOUT)

var REMOVE_LUA = _CLEAR

// One custom event's data → { id, down } for ours, { anon: true } for an undrawn key's
// press, `null` for anything else. Anyone can post a custom event, so only a known id
// with a known state gets through.
function parse(data) {
    if (data === ANON) return { anon: true }
    if (typeof data !== "string" || data.indexOf(PREFIX) !== 0) return null
    var s = data.charAt(PREFIX.length)
    var id = data.slice(PREFIX.length + 1)
    if ((s !== "d" && s !== "u") || IDS.indexOf(id) < 0) return null
    return { id: id, down: s === "d" }
}

// What a press counts toward: "left" / "right" clicks per second, "keys" per second, or
// "" (a release, the middle and side buttons).
function counts(ev) {
    if (!ev || (!ev.anon && !ev.down)) return ""
    if (ev.anon) return "keys"
    if (ev.id === "lmb") return "left"
    if (ev.id === "rmb") return "right"
    if (BUTTON_IDS.indexOf(ev.id) >= 0) return ""
    return "keys"
}

// A rate is presses in the last WINDOW_MS — what a CPS counter means by "per second".
var WINDOW_MS = 1000
// The press times still inside the window at `now`, oldest first (times arrive in order).
function prune(times, now) {
    var i = 0
    while (i < times.length && times[i] <= now - WINDOW_MS) i++
    return i === 0 ? times : times.slice(i)
}

// The held set after one event — a new object, so a binding on it notices.
function apply(held, ev) {
    var out = {}
    for (var k in held) if (held[k]) out[k] = true
    if (ev.down) out[ev.id] = true
    else delete out[ev.id]
    return out
}
