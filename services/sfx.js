.pragma library

// ── sfx.js ────────────────────────────────────────────────────────────────────
// The sound effects' decisions, pure so they can be tested (`bun scripts/test-sfx.js`):
// which key makes which sound, what a panel changing hands means, how loud, and how
// often. The service (Sfx.qml) owns the player and the files; none of that is here.
//
// The sound NAMES are scripts/gen-sfx.py's. test-gen-sfx.py pins that every name in
// FILES exists there, so adding a cue is a row here plus a sound there.
// ─────────────────────────────────────────────────────────────────────────────

// Every cue: which group's switch gates it, the file(s) it picks from, and a gain
// relative to the master volume (the generator already levels each sound; this is the
// taste knob — typing sits under a swoosh).
var CUES = {
    open:     { group: "panels", files: ["open"],     gain: 0.55 },
    close:    { group: "panels", files: ["close"],    gain: 0.45 },
    key:      { group: "typing", files: ["key1", "key2", "key3", "key4"], gain: 0.8 },
    space:    { group: "typing", files: ["keyspace"], gain: 0.9 },
    enter:    { group: "typing", files: ["keyenter"], gain: 0.9 },
    back:     { group: "typing", files: ["keyback"],  gain: 0.8 },
    on:       { group: "switches", files: ["on"],     gain: 0.8 },
    off:      { group: "switches", files: ["off"],    gain: 0.8 },
    notify:   { group: "notify", files: ["notify"],   gain: 1.0 },
    tick:     { group: "switches", files: ["tick"],   gain: 0.7 },
    timer:    { group: "alerts", files: ["timer"],     gain: 1.0 },
    alarm:    { group: "alerts", files: ["alarm"],     gain: 1.0 },
    shutter:  { group: "capture", files: ["shutter"],  gain: 0.9 },
    clipsaved: { group: "capture", files: ["clipsaved"], gain: 0.9 }
}

// The groups, in the order the settings page lists them. Each has a switch (`prefs`) and
// a level (`levels`) of its own under the master.
var GROUPS = ["panels", "typing", "switches", "notify", "alerts", "capture"]

// The distinct file names, for the player to preload.
function allFiles() {
    var seen = {}, out = []
    for (var id in CUES)
        for (var i = 0; i < CUES[id].files.length; i++) {
            var f = CUES[id].files[i]
            if (!seen[f]) { seen[f] = true; out.push(f) }
        }
    return out
}

// Qt.Key values — numbers, because this file has no Qt. Modifiers and navigation make
// no sound: a key you hold for a shortcut, or arrow through a list with, isn't typing.
var KEY_RETURN = 0x01000004, KEY_ENTER = 0x01000005, KEY_BACKSPACE = 0x01000003
var KEY_DELETE = 0x01000007, KEY_SPACE = 0x20

// What a key press is, as a cue id — or "" for silence. `text` is the key event's own
// text, which is what separates a letter (has text) from Shift, Escape, F-keys and
// arrows (none), so layouts and dead keys need no table here.
function typingCue(key, text, ctrlOrMeta) {
    if (ctrlOrMeta) return ""                       // a shortcut, not typing
    if (key === KEY_RETURN || key === KEY_ENTER) return "enter"
    if (key === KEY_BACKSPACE || key === KEY_DELETE) return "back"
    if (key === KEY_SPACE) return "space"
    if (typeof text === "string" && text.length > 0 && text.charCodeAt(0) >= 0x20
        && text.charCodeAt(0) !== 0x7f) return "key"
    return ""
}

// What a panel slot changing hands means. A slot (left / right / centre / side) holds
// one panel name, "" when empty. Closed → something is an opening; something → closed
// is a closing; one panel replacing another is ONE motion (Accordion plays the old out
// and the new in as a single gesture), so it is a single "open", not a close and an open.
function panelCue(prev, next) {
    prev = prev || ""
    next = next || ""
    if (prev === next) return ""
    if (next !== "") return "open"
    return "close"
}

// Which file a cue plays. A cue with several files never repeats the last one used,
// or a run of letters is the same sample over and over. `pick` is a 0..1 random.
function chooseFile(id, last, pick) {
    var c = CUES[id]
    if (!c) return ""
    var files = c.files
    if (files.length === 1) return files[0]
    var pool = files.filter(function (f) { return f !== last })
    var i = Math.floor((pick < 0 ? 0 : pick >= 1 ? 0.999999 : pick) * pool.length)
    return pool[i]
}

// The loudest the slider can make a cue. Full scale on a normalised sound is far too
// loud for something that fires on every keystroke, so 100% is a fraction of it.
var CEILING = 0.6

function _unit(v) {
    v = Number(v)
    return v > 0 ? Math.min(1, v) : 0
}

// 0..1 for the player. A slider is SQUARED before it scales: loudness is perceived on
// roughly a log scale, so a linear slider spends its whole lower half on "quiet" and its
// top on "louder than it should go". Squared, 50% is a quarter of the amplitude (about
// -12 dB) — a useful, much quieter place to rest. The master and the cue's group level
// are each squared and multiply, so turning either down is audible all the way.
// `levels` = { panels: 0..1, … }; a group with no entry is at full.
function volumeFor(id, master, levels) {
    var c = CUES[id]
    if (!c) return 0
    var m = _unit(master)
    var g = (levels && levels[c.group] !== undefined) ? _unit(levels[c.group]) : 1
    return CEILING * m * m * g * g * c.gain
}

// The shortest gap between two plays of the same cue, ms. A swoosh twice inside a
// frame or two is a stutter, not an event; typing is bounded only by key repeat.
var MIN_GAP = { open: 80, close: 80, key: 20, space: 20, enter: 20, back: 20,
                on: 60, off: 60, notify: 250, tick: 45,
                timer: 500, alarm: 500, shutter: 300, clipsaved: 300 }

function allowed(id, now, lastAt) {
    var gap = MIN_GAP[id] === undefined ? 50 : MIN_GAP[id]
    return lastAt === undefined || now - lastAt >= gap
}

// Whether a cue should sound at all, given the switches. `prefs` = { enabled, panels,
// typing, switches, notify, alerts, capture }. The master switch first; then the cue's own group.
function shouldPlay(id, prefs) {
    var c = CUES[id]
    if (!c || !prefs || !prefs.enabled) return false
    return prefs[c.group] === true
}

// A timer, an alarm and a saved clip announce themselves with a notification too, and
// that notification would chime a beat after the cue that already said so. `announces`
// says which cues are those; for NOTIFY_HOLD_MS after one, the notification chime stays
// quiet.
var NOTIFY_HOLD_MS = 2500

function announces(id) {
    var c = CUES[id]
    return !!c && (c.group === "alerts" || c.group === "capture")
}

function ducked(id, now, lastAnnounceAt) {
    return id === "notify" && lastAnnounceAt !== undefined && now - lastAnnounceAt < NOTIFY_HOLD_MS
}
