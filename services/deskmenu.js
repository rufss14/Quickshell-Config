.pragma library

// ── deskmenu.js ───────────────────────────────────────────────────────────────
// The desktop menu (modules/desktop/DeskMenu) and the lists behind its settings page and the hot
// corner's (sections, switches). What can be tested lives here; what each row DOES is the menu's, which calls the service
// that owns the job.
//
//     bun scripts/test-deskmenu.js
// ─────────────────────────────────────────────────────────────────────────────

// The rows the menu can show under its buttons: how they read. Order = how Settings lists them.
var PLACES = {
    terminal:  { label: "Terminal",         detail: "Open a new terminal here",        symbol: "terminal" },
    launcher:  { label: "Search",           detail: "Apps, files, calculations",       symbol: "search" },
    wallpaper: { label: "Wallpapers",       detail: "Browse and set a picture",        symbol: "wallpaper" },
    colours:   { label: "Colours",          detail: "The palette and its schemes",     symbol: "palette" },
    widgets:   { label: "Edit widgets",     detail: "Move and resize desktop widgets", symbol: "widgets" },
    displays:  { label: "Displays",         detail: "Arrangement, scale, refresh",     symbol: "monitor" },
    bar:       { label: "Bar & sidebar",    detail: "What is on them, and how",        symbol: "dashboard" },
    overview:  { label: "Overview",         detail: "Every window at a glance",        symbol: "grid_view" },
    clipboard: { label: "Clipboard",        detail: "What you copied lately",          symbol: "content_paste" },
    notifications: { label: "Notifications", detail: "What came in",                   symbol: "notifications" },
    monitor:   { label: "Task manager",     detail: "What is using the machine",       symbol: "speed" },
    keys:      { label: "Keybinds",         detail: "Every shortcut at a glance",      symbol: "keyboard" },
    settings:  { label: "Settings",         detail: "Everything else",                 symbol: "settings" },
    power:     { label: "Power",            detail: "Shut down, restart, log out",     symbol: "power_settings_new" }
}
var PLACE_ORDER = ["terminal", "launcher", "wallpaper", "colours", "widgets", "displays", "bar", "overview",
                   "clipboard", "notifications", "monitor", "keys", "settings", "power"]

// The tools row: one-tap captures. What each does is the menu's (it calls Snip, Lens, ColorPicker, Clips);
// this is how they read. Order = how Settings lists them.
var TOOLS = {
    region: { label: "Screenshot",  detail: "Save a region of the screen",     symbol: "crop" },
    copy:   { label: "Copy region", detail: "Copy a region to the clipboard",  symbol: "content_copy" },
    colour: { label: "Colour",      detail: "Copy any pixel's colour",         symbol: "colorize" },
    text:   { label: "Read text",   detail: "Copy text from the screen",       symbol: "text_fields" },
    record: { label: "Record",      detail: "Start or stop a screen recording", symbol: "fiber_manual_record" },
    clip:   { label: "Clip it",     detail: "Keep what just happened",         symbol: "movie" }
}
var TOOL_ORDER = ["region", "copy", "colour", "text", "record", "clip"]

// The hot corner's sections (Config.hotCornerParts: the ones shown, in the order shown).
var PARTS = {
    sliders: { label: "Volume & brightness", symbol: "tune" },
    toggles: { label: "Switches",            symbol: "dashboard" },
    media:   { label: "Music",               symbol: "music_note" },
    apps:    { label: "Pinned apps",         symbol: "apps" },
    capture: { label: "Capture",             symbol: "photo_camera" }
}
var PART_ORDER = ["sliders", "toggles", "media", "apps", "capture"]

// The ids of a saved list that still mean something, in the saved order, once each. A list written by a
// newer shell (or edited by hand) never makes a blank row.
function known(list, table) {
    var out = []
    if (!Array.isArray(list)) return out
    for (var i = 0; i < list.length; i++)
        if (table[list[i]] !== undefined && out.indexOf(list[i]) < 0) out.push(list[i])
    return out
}

// `id` one place earlier (delta -1) or later (+1) among the ids in `list`; the list is returned
// unchanged when it can't move.
function move(list, id, delta) {
    var i = list.indexOf(id), j = i + delta
    if (i < 0 || j < 0 || j >= list.length) return list.slice()
    var out = list.slice()
    out.splice(i, 1)
    out.splice(j, 0, id)
    return out
}

// `id` added at the end (if there is room, `max`) or taken out.
function flip(list, id, max) {
    var i = list.indexOf(id)
    var out = list.slice()
    if (i >= 0) out.splice(i, 1)
    else if (out.length < max) out.push(id)
    return out
}

// Where a menu of w × h opens for a pointer at (px, py) on a screen of sw × sh: its corner at the pointer,
// flipped to the other side of it where it would run off, and kept `margin` inside the screen either way.
// `flipX` / `flipY` say it opened leftward / upward, so the animation grows from the pointer's corner.
// A pointer of -1 (opened by key) means the middle.
function place(px, py, w, h, sw, sh, margin) {
    if (px < 0 || py < 0) return { x: Math.round((sw - w) / 2), y: Math.round((sh - h) / 2), flipX: false, flipY: false }
    var flipX = px + w + margin > sw
    var flipY = py + h + margin > sh
    var x = flipX ? px - w : px
    var y = flipY ? py - h : py
    x = Math.max(margin, Math.min(sw - w - margin, x))
    y = Math.max(margin, Math.min(sh - h - margin, y))
    return { x: Math.round(x), y: Math.round(y), flipX: flipX, flipY: flipY }
}

// The pictures for the strip: the one on the desktop first, then the newest others (`mtimes`: path →
// epoch seconds), `n` in all.
function pictures(list, currentName, mtimes, n) {
    if (!Array.isArray(list) || n <= 0) return []
    var cur = null, rest = []
    for (var i = 0; i < list.length; i++) {
        if (cur === null && list[i].split("/").pop() === currentName) cur = list[i]
        else rest.push(list[i])
    }
    rest.sort(function (a, b) { return ((mtimes && mtimes[b]) || 0) - ((mtimes && mtimes[a]) || 0) })
    var out = cur === null ? [] : [cur]
    return out.concat(rest).slice(0, n)
}
