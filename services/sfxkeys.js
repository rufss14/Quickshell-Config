.pragma library

// ── sfxkeys.js ────────────────────────────────────────────────────────────────
// The "typing sounds everywhere" hook: the Lua the shell hands Hyprland, and the parser
// for what comes back. Pure, so it can be tested (`bun scripts/test-sfxkeys.js`, which
// also RUNS the Lua under lua5.4 against a stub `hl`).
//
// ── How a key reaches the shell ───────────────────────────────────────────────
// Wayland shows a client only the keys that go to it, so the compositor has to say. The
// install snippet subscribes to Hyprland's `input.keyboard.key` and, per key, posts a
// CUSTOM EVENT with `hl.dsp.event(...)`. Hyprland pushes it on the event socket the shell
// already listens to (Quickshell.Hyprland's rawEvent: name "custom", data = our string).
// No file, no subprocess, no `io` — and nothing polls.
//
// ── What it sends, and what it must never send ────────────────────────────────
// ONE LETTER of state ("d" down, "u" up, "?" unknown) and ONE of CLASS: k a key, s space,
// e enter, b backspace. Never the key, the keycode or the text: the event socket is
// readable by every process this user runs, so anything put on it is public to them. A
// class is all the sounds need. A key that isn't typing (a modifier, an arrow, escape,
// a function key) is class "" and not sent at all.
//
// ── What is NOT known, and how that is handled ────────────────────────────────
// The stub names the event but not its payload. MEASURED on the installed Hyprland 0.56.2
// (`qs ipc … call sfxkeys status` → shape "number|number|number"): the callback gets THREE
// BARE NUMBERS, not a table. IKeyboard::SKeyEvent (the headers) is { timeMs, keycode,
// updateMods, state }, so they are most likely (time, keycode, state) with state 0 released
// / 1 pressed. `numeric()` places them by magnitude — a time is huge, a state is 0 or 1, a
// keycode is the other small one — so it does not depend on the order being right. Table
// payloads are still handled (a future Hyprland may send one). The first SHAPE_REPORTS
// events also post the payload's SHAPE, numbers bucketed (0, 1, small, big — never
// exact), so a wrong guess is read off the machine and fixed, not guessed again.
//   · state unplaceable    → every event sounds (a press and its release: two clicks)
//   · keycode base         → evdev (space 57), which is what SKeyEvent carries; Hyprland adds
//                            the +8 for xkb itself, later
// ─────────────────────────────────────────────────────────────────────────────

var PREFIX = "qs-sfx-key:"
var SHAPE_PREFIX = "qs-sfx-shape:"
var SHAPE_REPORTS = 6

// Installs (replacing any earlier subscription of ours, so a shell reload never doubles
// the events). Everything in the callback is pcall'd: this runs INSIDE the compositor,
// on the input path, and an error there must cost a key click and nothing else.
var INSTALL_LUA = [
'if _G.qs_sfx_sub then pcall(function() _G.qs_sfx_sub:remove() end); _G.qs_sfx_sub = nil end',
'local reported = 0',
'local function lc(v) if type(v) == "string" then return v:lower() end end',
'-- keys that are not typing: modifiers, locks, navigation, escape, tab, function keys',
'local SILENT_NAMES = { shift_l=1, shift_r=1, control_l=1, control_r=1, alt_l=1, alt_r=1, super_l=1, super_r=1,',
'  meta_l=1, meta_r=1, hyper_l=1, hyper_r=1, caps_lock=1, num_lock=1, scroll_lock=1, iso_level3_shift=1,',
'  escape=1, tab=1, left=1, right=1, up=1, down=1, home=1, ["end"]=1, prior=1, next=1, page_up=1, page_down=1,',
'  insert=1, menu=1, print=1, pause=1, delete=1,',
'  shift=1, control=1, ctrl=1, alt=1, super=1, meta=1, esc=1 }',
'local SILENT_CODES = { [1]=1, [15]=1, [29]=1, [42]=1, [54]=1, [56]=1, [58]=1, [97]=1, [100]=1, [125]=1, [126]=1,',
'  [103]=1, [105]=1, [106]=1, [108]=1, [102]=1, [107]=1, [104]=1, [109]=1, [110]=1, [111]=1,',
'  [69]=1, [70]=1, [87]=1, [88]=1, [119]=1, [127]=1 }',
'for c = 59, 68 do SILENT_CODES[c] = 1 end',
'local function classOfCode(code)',
'  code = code - 8  -- Hyprland hands xkb codes (evdev + 8); the tables below are evdev',
'  if code == 57 then return "s" end',
'  if code == 28 or code == 96 then return "e" end',
'  if code == 14 then return "b" end',
'  if SILENT_CODES[code] then return "" end',
'  return "k"',
'end',
'-- Hyprland hands the callback bare numbers: (timeMs, keycode, state) in IKeyboard::SKeyEvent order,',
'-- state 0 released / 1 pressed. Told apart by MAGNITUDE rather than trusted by position: a time is',
'-- huge, a state is 0 or 1, a keycode is the other small one. Anything it cannot place is nil.',
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
'local function classOf(ev)',
'  local name',
'  if type(ev) == "table" then name = lc(ev.key) or lc(ev.keysym) or lc(ev.name) or lc(ev.display_key) end',
'  if name then',
'    if name == "space" then return "s" end',
'    if name == "return" or name == "enter" or name == "kp_enter" then return "e" end',
'    if name == "backspace" then return "b" end',
'    if SILENT_NAMES[name] or name:match("^f%d+$") then return "" end',
'    return "k"',
'  end',
'  local code',
'  if type(ev) == "table" then code = ev.keycode or ev.code elseif type(ev) == "number" then code = ev end',
'  if type(code) == "number" then return classOfCode(code) end',
'  return "k"',
'end',
'local function stateOf(ev)',
'  if type(ev) ~= "table" then return "?" end',
'  local s = ev.state',
'  if s == nil then s = ev.pressed end',
'  if s == true or s == 1 or s == "pressed" or s == "press" or s == "down" then return "d" end',
'  if s == false or s == 0 or s == "released" or s == "release" or s == "up" then return "u" end',
'  if ev.released == true then return "u" end',
'  return "?"',
'end',
'local HIDDEN = { key=1, keycode=1, code=1, text=1, keysym=1, name=1, display_key=1, utf8=1 }',
'local function shape(...)',
'  local out = {}',
'  for i = 1, select("#", ...) do',
'    local v = select(i, ...)',
'    if type(v) == "table" then',
'      local f = {}',
'      for k, x in pairs(v) do',
'        local t = type(x)',
'        f[#f + 1] = tostring(k) .. ":" .. ((HIDDEN[tostring(k)] or t == "table" or t == "function") and t or (t .. "=" .. tostring(x)))',
'      end',
'      table.sort(f)',
'      out[#out + 1] = "{" .. table.concat(f, ",") .. "}"',
'    elseif type(v) == "number" then',
'      -- bucketed, never exact: a keycode would name the key. 0/1 is a state; big is a time.',
'      out[#out + 1] = "number:" .. ((v == 0 or v == 1) and tostring(v) or v >= 1000 and "big" or v >= 2 and "small" or "neg")',
'    else',
'      out[#out + 1] = type(v)',
'    end',
'  end',
'  return table.concat(out, "|")',
'end',
'local function say(s) pcall(function() hl.dispatch(hl.dsp.event(s)) end) end',
'_G.qs_sfx_sub = hl.on("input.keyboard.key", function(...)',
'  local args = table.pack(...)',
'  pcall(function()',
'    local ev = args[1]',
'    local ncode, nstate = numeric(args)',
'    if reported < ' + SHAPE_REPORTS + ' then reported = reported + 1; say("' + SHAPE_PREFIX + '" .. shape(table.unpack(args, 1, args.n))) end',
'    local c = ncode and classOfCode(ncode) or classOf(ev)',
'    if c == "" then return end',
'    local st = nstate and (nstate >= 1 and "d" or "u") or stateOf(ev)',
'    say("' + PREFIX + '" .. st .. c)',
'  end)',
'end)'
].join("\n")

var REMOVE_LUA =
    'if _G.qs_sfx_sub then pcall(function() _G.qs_sfx_sub:remove() end); _G.qs_sfx_sub = nil end'

// What the shell receives for one custom event's data. `null` for anything that isn't
// ours; { shape } for a shape report; { down, cls } for a key, where `down` is true,
// false, or null when Hyprland's payload didn't say. cls is "key" | "space" | "enter" |
// "back" — sfx.js cue ids.
var CLASSES = { k: "key", s: "space", e: "enter", b: "back" }

function parse(data) {
    if (typeof data !== "string") return null
    if (data.indexOf(SHAPE_PREFIX) === 0)
        return { shape: data.slice(SHAPE_PREFIX.length).slice(0, 400) }
    if (data.indexOf(PREFIX) !== 0) return null
    var body = data.slice(PREFIX.length)
    if (body.length !== 2) return null
    var cls = CLASSES[body.charAt(1)]
    if (!cls) return null
    var s = body.charAt(0)
    if (s !== "d" && s !== "u" && s !== "?") return null
    return { down: s === "d" ? true : s === "u" ? false : null, cls: cls }
}

// Whether an event should sound: a release never does when Hyprland says so; an unknown
// state does (see the header — better two clicks than none, until the shape is read).
function sounds(ev) {
    return !!ev && ev.cls !== undefined && ev.down !== false
}
