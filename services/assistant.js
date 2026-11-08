.pragma library

// ── assistant.js ──────────────────────────────────────────────────────────────
// The overview's AI page (services/Assistant.qml) lets a model CHANGE the shell — "make me another
// colour scheme, I don't like this one". The model has no tools (ai-ask.py runs it with none);
// what it can do is end its reply with a fenced block:
//
//     ```action
//     {"do": "scheme", "name": "Harbour Dusk", "background": "#101418", "foreground": "#d6dde4",
//      "colors": ["#101418", "#e0707a", … 16 hex colours, color0…color15]}
//     ```
//     ```action
//     {"do": "set", "key": "radiusScale", "value": 1.3}
//     ```
//
// This file turns that text into things the page can offer — each one a card with an Apply
// button, never applied by itself. A reply is somebody else's output: everything in it is
// checked here against a fixed list (SETTINGS) and a fixed shape (a palette of real hex
// colours), and what doesn't fit becomes an "invalid" card that says why, rather than
// vanishing. Pure functions, no QML — scripts/test-assistant.js runs them.
// ─────────────────────────────────────────────────────────────────────────────

// What a model may set, and how. Every key is a Config property the settings pages already
// expose; ranges are Config's own *Min/*Max. A key that isn't here can't be set at all.
var SETTINGS = {
    themeMode:       { type: "enum", options: ["dark", "light"], label: "Theme",
                       about: "dark or light palette from the wallpaper (re-extracts colours)" },
    radiusScale:     { type: "real", min: 0.5, max: 1.5, label: "Corner roundness",
                       about: "how round every corner is, 1 = default" },
    fontScale:       { type: "real", min: 0.8, max: 1.3, label: "Text size",
                       about: "shell-wide text scale" },
    densityScale:    { type: "real", min: 0.75, max: 1.5, label: "Spacing",
                       about: "shell-wide padding/spacing scale" },
    shadowScale:     { type: "real", min: 0, max: 1.5, label: "Shadows",
                       about: "shadow strength, 0 = none" },
    surfaceOpacity:  { type: "real", min: 0.5, max: 1, label: "Panel opacity",
                       about: "opacity of panels and cards" },
    barOpacity:      { type: "real", min: 0.5, max: 1, label: "Bar opacity",
                       about: "opacity of the bar's pills" },
    iconShape:       { type: "enum", options: ["default", "squircle", "cookie", "clover", "circle"],
                       label: "Icon holder", about: "the shape behind header and section icons" },
    cornerStyle:     { type: "enum", options: ["default", "ii"], label: "Corner style",
                       about: "default ladder, or ii (rounder)" },
    motionEnabled:   { type: "bool", label: "Animations", about: "all animation on/off" },
    motionScale:     { type: "real", min: 0.25, max: 2, label: "Animation speed",
                       about: "duration multiplier, 0.5 = twice as fast" },
    colorizeIcons:   { type: "bool", label: "Tint icons", about: "tint tray icons with the accent" },
    cavaBg:          { type: "bool", label: "Desktop visualiser", about: "audio spectrum behind windows" },
    cavaBgStyle:     { type: "enum", options: ["bars", "wave", "dots"], label: "Visualiser style",
                       about: "how the desktop visualiser draws" },
    nightLight:      { type: "bool", label: "Night light", about: "warm screen tint" },
    nightLightTemp:  { type: "int", min: 2500, max: 6500, label: "Night light warmth",
                       about: "colour temperature in kelvin, lower = warmer" },
    sfxEnabled:      { type: "bool", label: "Sound effects", about: "the shell's UI sounds" },
    sfxVolume:       { type: "real", min: 0, max: 1, label: "Sound volume", about: "UI sound volume" },
    widgetsEnabled:  { type: "bool", label: "Desktop widgets", about: "widgets on the desktop" },
    panelCookies:    { type: "bool", label: "Panel cookies", about: "drifting cookie shapes in panels" },
    barCookies:      { type: "bool", label: "Bar cookies", about: "drifting cookie shapes in the bar" },
    screenFrame:     { type: "bool", label: "Screen frame", about: "the frame around the screen" }
};

var HEX = /^#[0-9a-fA-F]{6}$/;

function _num(v) {
    if (typeof v === "number") return v;
    if (typeof v === "string" && v.trim() !== "" && !isNaN(Number(v))) return Number(v);
    return NaN;
}

function _bool(v) {
    if (v === true || v === false) return v;
    var s = String(v).trim().toLowerCase();
    if (s === "true" || s === "on" || s === "yes" || s === "1") return true;
    if (s === "false" || s === "off" || s === "no" || s === "0") return false;
    return null;
}

function _round(x) { return Math.round(x * 100) / 100; }

// A shown value: booleans as on/off, numbers trimmed.
function show(v) {
    if (v === true) return "on";
    if (v === false) return "off";
    if (typeof v === "number") return String(_round(v));
    return String(v);
}

// One `set` → { do, key, value, label } or { do: "invalid", reason }.
function _set(a) {
    var key = String(a.key || "");
    var spec = Object.prototype.hasOwnProperty.call(SETTINGS, key) ? SETTINGS[key] : null;
    if (!spec) return { do: "invalid", reason: "no setting called “" + key + "”" };
    var v;
    if (spec.type === "bool") {
        v = _bool(a.value);
        if (v === null) return { do: "invalid", reason: spec.label + ": not on/off" };
    } else if (spec.type === "real" || spec.type === "int") {
        v = _num(a.value);
        if (isNaN(v)) return { do: "invalid", reason: spec.label + ": not a number" };
        v = Math.min(spec.max, Math.max(spec.min, v));
        v = spec.type === "int" ? Math.round(v) : _round(v);
    } else {
        v = String(a.value);
        if (spec.options.indexOf(v) < 0) return { do: "invalid", reason: spec.label + ": “" + v + "” isn't one of " + spec.options.join(", ") };
    }
    return { do: "set", key: key, value: v, label: spec.label + " → " + show(v) };
}

// One `scheme` → a pywal-shaped palette ({ special, colors }, what ColorScheme.applyPalette takes).
// Eight colours are accepted too (the bright half then repeats them) — a model often stops there.
function _scheme(a) {
    var cols = Array.isArray(a.colors) ? a.colors.map(function (c) { return String(c).trim(); }) : [];
    if (cols.length === 8) cols = cols.concat(cols);
    if (cols.length !== 16) return { do: "invalid", reason: "a scheme needs 16 colours (got " + cols.length + ")" };
    for (var i = 0; i < 16; i++)
        if (!HEX.test(cols[i])) return { do: "invalid", reason: "colour " + i + " (“" + cols[i] + "”) isn't #rrggbb" };
    var bg = String(a.background || cols[0]).trim();
    var fg = String(a.foreground || cols[7]).trim();
    if (!HEX.test(bg) || !HEX.test(fg)) return { do: "invalid", reason: "background/foreground aren't #rrggbb" };
    var name = String(a.name || "New scheme").replace(/[\u0000-\u001f<>\/\\"`{}\[\].:;|*?$&]/g, "").trim().slice(0, 40) || "New scheme";
    var colors = {};
    for (var k = 0; k < 16; k++) colors["color" + k] = cols[k].toLowerCase();
    return {
        do: "scheme", name: name, label: name,
        palette: { special: { background: bg.toLowerCase(), foreground: fg.toLowerCase(), cursor: fg.toLowerCase() },
                   colors: colors },
        swatch: [bg.toLowerCase(), cols[1], cols[2], cols[3], cols[4], cols[5], cols[6], fg.toLowerCase()].map(function (c) { return c.toLowerCase(); })
    };
}

// ── Beyond settings: the shell's own actions (2026-10-24) ─────────────────────
// The user: "I want it to have access to the shell, but not be able to delete stuff — apply safety
// measures". So it reaches the shell through a FIXED list, never a command line:
//   · `action` — a ShellActions entry (the launcher's own catalogue: night light, Do Not Disturb,
//     game mode, Lens, clips, mute…), only the ids in SHELL; toggles take an optional `on`;
//   · `volume`, `brightness` (0–100), `wallpaper` (a picture from the library by name, or "random"),
//     `preset` (a saved colour scheme by name), `media` (play/pause/next/previous), `workspace`,
//     `launch` (an installed app, found by name), `timer` (minutes).
// Safety, in three layers:
//   1. what isn't on these lists can't be expressed — no shell command, no file, nothing that deletes
//      or closes (clearing notifications, closing windows, removing clips and alarms aren't offered);
//   2. every value is checked and clamped here, and names must match something that exists
//      (`ctx`: the wallpapers and schemes on this machine) — a model can't invent a path;
//   3. `confirm` actions — locking, reloading the shell, the power menu, starting a screen recording,
//      opening Settings — wait on the card for the user's OK; everything else runs at once with Undo
//      where there's something to undo.
// `leaves`: it needs the screen (a panel, a picker, another workspace), so the overview steps aside.
var SHELL = {
    nightlight:    { toggle: true },
    dnd:           { toggle: true },
    gamemode:      { toggle: true },
    awake:         { toggle: true },
    clipping:      { toggle: true },
    wifi:          { toggle: true },
    mute:          { toggle: true },
    micMute:       { toggle: true },
    sidebar:       { toggle: true },
    record:        { toggle: true, confirm: true },
    clip:          {},
    shuffle:       {},
    lens:          { leaves: true },
    lensTranslate: { leaves: true },
    colour:        { leaves: true },
    clipsLibrary:  { leaves: true },
    wallpaper:     { leaves: true },
    scheme:        { leaves: true },
    bluetooth:     { leaves: true },
    notifications: { leaves: true },
    updates:       { leaves: true },
    settings:      { leaves: true, confirm: true },
    lock:          { leaves: true, confirm: true },
    power:         { leaves: true, confirm: true },
    reload:        { confirm: true }
};
var MEDIA = ["play", "pause", "toggle", "next", "previous"];
var DISCORD = ["mute", "unmute", "deafen", "undeafen", "leave", "camera", "screenshare"];
var DISCORD_SETTINGS = ["noise", "echo", "agc", "pushtotalk"];
var DAYNAMES = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];

// "07:30", "7", "19h", "7pm" → { h, m } or null.
function clock(t) {
    var m = /^\s*(\d{1,2})(?:[:h.](\d{2}))?\s*(am|pm)?\s*$/i.exec(String(t == null ? "" : t));
    if (!m) return null;
    var h = Number(m[1]), mi = Number(m[2] || 0);
    if (m[3]) { var pm = m[3].toLowerCase() === "pm"; if (h === 12) h = pm ? 12 : 0; else if (pm) h += 12; }
    if (h > 23 || mi > 59) return null;
    return { h: h, m: mi };
}
function pad2(n) { return (n < 10 ? "0" : "") + n; }

// An alarm's days → the Timers bitmask (bit 0 = Sunday … bit 6 = Saturday; 0 = once).
function daysMask(d) {
    if (d === undefined || d === null || d === "" || d === "once") return 0;
    var s = Array.isArray(d) ? d.join(",") : String(d);
    s = s.toLowerCase();
    if (s === "daily" || s === "every day" || s === "everyday") return 127;
    if (s === "weekdays") return 62;
    if (s === "weekends") return 65;
    var mask = 0;
    var parts = s.split(/[\s,]+/);
    for (var i = 0; i < parts.length; i++) {
        var k = DAYNAMES.indexOf(parts[i].slice(0, 3));
        if (k < 0) return -1;
        mask |= (1 << k);
    }
    return mask;
}

// When a reminder is due (epoch ms) from `in` minutes, or `at` a clock time (today, or tomorrow when
// that's past; `date` "tomorrow" or YYYY-MM-DD moves it). null when neither makes sense.
function dueFrom(a, now) {
    if (a.in !== undefined && a.in !== null && a.in !== "") {
        var mins = _num(a.in);
        if (isNaN(mins) || mins <= 0 || mins > 60 * 24 * 60) return null;
        return now + Math.round(mins * 60000);
    }
    var t = clock(a.at);
    if (!t) return null;
    var d = new Date(now);
    var date = String(a.date || "").toLowerCase();
    var ymd = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
    if (ymd) d = new Date(Number(ymd[1]), Number(ymd[2]) - 1, Number(ymd[3]));
    else if (date === "tomorrow") d.setDate(d.getDate() + 1);
    d.setHours(t.h, t.m, 0, 0);
    if (!ymd && date !== "tomorrow" && d.getTime() <= now) d.setDate(d.getDate() + 1);
    return d.getTime() > now ? d.getTime() : null;
}

function _has(o, k) { return Object.prototype.hasOwnProperty.call(o, k); }
function _clean(s, n) { return String(s == null ? "" : s).replace(/[\u0000-\u001f]/g, "").trim().slice(0, n); }

// A name against a list: exact (any case), else the one that contains it, else none.
function match(list, name) {
    var want = _clean(name, 120).toLowerCase();
    if (!want) return "";
    for (var i = 0; i < list.length; i++) if (String(list[i]).toLowerCase() === want) return list[i];
    for (var j = 0; j < list.length; j++) if (String(list[j]).toLowerCase().indexOf(want) >= 0) return list[j];
    return "";
}

function _action(a, ctx) {
    var id = String(a.id || "");
    if (!_has(SHELL, id)) return { do: "invalid", reason: "no shell action “" + _clean(id, 40) + "”" };
    var meta = SHELL[id];
    var named = (ctx && ctx.names && ctx.names[id]) || id;
    var out = { do: "action", id: id, label: named, confirm: !!meta.confirm, leaves: !!meta.leaves, toggle: !!meta.toggle };
    if (meta.toggle && a.on !== undefined && a.on !== null) {
        var on = _bool(a.on);
        if (on === null) return { do: "invalid", reason: named + ": on must be true or false" };
        out.on = on;
        out.label = named + " → " + (on ? "on" : "off");
    }
    return out;
}

function _level(a, what) {
    var v = _num(a.value);
    if (isNaN(v)) return { do: "invalid", reason: what + ": not a number" };
    // 0–1 is read as a fraction (a model often says 0.4 for 40%).
    if (v > 0 && v <= 1 && String(a.value).indexOf(".") >= 0) v = v * 100;
    v = Math.round(Math.min(100, Math.max(0, v)));
    return { do: what, value: v, label: (what === "volume" ? "Volume" : "Brightness") + " → " + v + "%" };
}

function validate(a, ctx) {
    if (!a || typeof a !== "object" || Array.isArray(a)) return { do: "invalid", reason: "not an action" };
    ctx = ctx || {};
    switch (a.do) {
    case "set": return _set(a);
    case "scheme": return _scheme(a);
    case "action": return _action(a, ctx);
    case "volume": return _level(a, "volume");
    case "brightness": return _level(a, "brightness");
    case "wallpaper": {
        var pick = _clean(a.pick || a.name, 120);
        if (pick.toLowerCase() === "random") return { do: "wallpaper", random: true, label: "A random wallpaper" };
        var w = match(ctx.wallpapers || [], pick);
        if (!w) return { do: "invalid", reason: "no wallpaper called “" + pick + "”" };
        return { do: "wallpaper", name: w, label: "Wallpaper → " + w, leaves: false };
    }
    case "preset": {
        var p = match(ctx.presets || [], a.name);
        if (!p) return { do: "invalid", reason: "no saved scheme called “" + _clean(a.name, 40) + "”" };
        return { do: "preset", name: p, label: p };
    }
    case "media": {
        var c = String(a.command || "").toLowerCase();
        if (MEDIA.indexOf(c) < 0) return { do: "invalid", reason: "media: one of " + MEDIA.join(", ") };
        return { do: "media", command: c, label: "Media → " + c };
    }
    case "workspace": {
        var n = Math.round(_num(a.id !== undefined ? a.id : a.value));
        if (isNaN(n) || n < 1 || n > 20) return { do: "invalid", reason: "workspace: a number from 1 to 20" };
        return { do: "workspace", id: n, label: "Go to workspace " + n, leaves: true };
    }
    case "launch": {
        var app = _clean(a.app || a.name, 60);
        if (!app) return { do: "invalid", reason: "launch: which app?" };
        return { do: "launch", app: app, label: "Open " + app, leaves: true };
    }
    case "scene": {
        var sc = match(ctx.scenes || [], a.pick || a.name);
        if (!sc) return { do: "invalid", reason: "no Wallpaper Engine scene called “" + _clean(a.pick || a.name, 60) + "”" };
        return { do: "scene", name: sc, label: "Scene → " + sc };
    }
    case "play": {
        var what = _clean(a.query || a.name, 120);
        var kind = ["track", "album", "playlist", "artist"].indexOf(String(a.kind || "track")) >= 0 ? String(a.kind || "track") : "track";
        if (!what) return { do: "invalid", reason: "play: what?" };
        return { do: "play", query: what, kind: kind, label: "Play " + what };
    }
    case "open": {
        var url = _clean(a.url, 2000);
        // A web address only — http(s), no spaces. Not a file, not a custom scheme.
        if (!/^https?:\/\/[^\s<>"]+$/i.test(url)) return { do: "invalid", reason: "open: only http(s) web addresses" };
        var host = url.replace(/^https?:\/\//i, "").split(/[\/?#]/)[0];
        return { do: "open", url: url, label: "Open " + host, leaves: true };
    }
    case "search": {
        var sq = _clean(a.query, 200);
        if (!sq) return { do: "invalid", reason: "search: what?" };
        return { do: "search", query: sq, label: "Search “" + sq + "”", leaves: true };
    }
    case "remind": {
        var rt = _clean(a.text, 140);
        if (!rt) return { do: "invalid", reason: "remind: about what?" };
        var now = ctx.nowMs || Date.now();
        var due = dueFrom(a, now);
        if (due === null) return { do: "invalid", reason: "remind: when? (in minutes, or at HH:MM)" };
        var dd = new Date(due);
        var sameDay = new Date(now).toDateString() === dd.toDateString();
        return { do: "remind", text: rt, due: due,
                 label: "Remind: " + rt + " · " + (sameDay ? "" : dd.toDateString().slice(0, 10) + " ") + pad2(dd.getHours()) + ":" + pad2(dd.getMinutes()) };
    }
    case "todo": {
        var tt = _clean(a.text, 140);
        if (!tt) return { do: "invalid", reason: "todo: what?" };
        return { do: "todo", text: tt, label: "To-do: " + tt };
    }
    case "alarm": {
        var at = clock(a.at);
        if (!at) return { do: "invalid", reason: "alarm: at HH:MM" };
        var mask = daysMask(a.days);
        if (mask < 0) return { do: "invalid", reason: "alarm: days like weekdays, weekends, daily or mon,wed" };
        var dayText = mask === 0 ? "once" : mask === 127 ? "daily" : mask === 62 ? "weekdays" : mask === 65 ? "weekends"
                    : DAYNAMES.filter(function (n, i) { return mask & (1 << i); }).join(" ");
        return { do: "alarm", h: at.h, m: at.m, days: mask, label: "Alarm " + pad2(at.h) + ":" + pad2(at.m) + " · " + dayText };
    }
    case "window": {
        var wapp = match(ctx.windowApps || [], a.app);
        if (!wapp) return { do: "invalid", reason: "no open window of “" + _clean(a.app, 40) + "”" };
        var wo = { do: "window", app: wapp };
        var bits = [];
        if (a.workspace !== undefined && a.workspace !== null) {
            var wn = Math.round(_num(a.workspace));
            if (isNaN(wn) || wn < 1 || wn > 20) return { do: "invalid", reason: "window: workspace 1–20" };
            wo.workspace = wn; bits.push("workspace " + wn);
        }
        if (a.float !== undefined && a.float !== null) { var fl = _bool(a.float); if (fl === null) return { do: "invalid", reason: "window: float true/false" }; wo.float = fl; bits.push(fl ? "floating" : "tiled"); }
        if (a.fullscreen !== undefined && a.fullscreen !== null) { var fs = _bool(a.fullscreen); if (fs === null) return { do: "invalid", reason: "window: fullscreen true/false" }; wo.fullscreen = fs; bits.push(fs ? "fullscreen" : "not fullscreen"); }
        if (_bool(a.focus) === true) { wo.focus = true; wo.leaves = true; bits.push("focused"); }
        if (bits.length === 0) return { do: "invalid", reason: "window: move it, float it, fullscreen it or focus it" };
        wo.label = wapp + " → " + bits.join(", ");
        return wo;
    }
    case "output": {
        var dev = match(ctx.outputs || [], a.device);
        if (!dev) return { do: "invalid", reason: "no sound output called “" + _clean(a.device, 40) + "”" };
        return { do: "output", device: dev, label: "Sound → " + dev };
    }
    case "appvolume": {
        // An app can go past 100% — the shell's boost, up to its ceiling (ctx.appCeiling, 130).
        var va = _clean(a.app, 60);
        if (!va) return { do: "invalid", reason: "appvolume: which app?" };
        var av = _num(a.value);
        if (isNaN(av)) return { do: "invalid", reason: "appvolume: not a number" };
        if (av > 0 && av <= 1 && String(a.value).indexOf(".") >= 0) av = av * 100;
        var cap = ctx.appCeiling || 130;
        av = Math.round(Math.min(cap, Math.max(0, av)));
        return { do: "appvolume", app: va, value: av, label: va + " volume → " + av + "%" };
    }
    case "bluetooth": {
        var bd = match(ctx.bluetooth || [], a.device);
        if (!bd) return { do: "invalid", reason: "no paired Bluetooth device called “" + _clean(a.device, 40) + "”" };
        var con = a.connect === undefined || a.connect === null ? true : _bool(a.connect);
        if (con === null) return { do: "invalid", reason: "bluetooth: connect true/false" };
        return { do: "bluetooth", device: bd, connect: con, label: (con ? "Connect " : "Disconnect ") + bd };
    }
    case "clip": {
        var secs = a.seconds === undefined || a.seconds === null ? 0 : Math.round(_num(a.seconds));
        if (isNaN(secs) || secs < 0) return { do: "invalid", reason: "clip: seconds" };
        secs = Math.min(600, secs);
        return { do: "clip", seconds: secs, label: "Save a clip" + (secs ? " · last " + secs + " s" : "") };
    }
    case "screenshot":
        return { do: "screenshot", label: "Screenshot", leaves: true };
    case "look": {
        var list = (Array.isArray(a.workspaces) ? a.workspaces : [a.workspaces]).map(function (x) { return Math.round(_num(x)); })
                   .filter(function (x) { return x >= 1 && x <= 10; });
        if (list.length === 0) return { do: "invalid", reason: "look: which workspaces (1–10)?" };
        var lw = a.wallpaper ? match(ctx.wallpapers || [], a.wallpaper) : "";
        var ls = a.scheme ? match(ctx.presets || [], a.scheme) : "";
        if (a.wallpaper && !lw) return { do: "invalid", reason: "no wallpaper called “" + _clean(a.wallpaper, 60) + "”" };
        if (a.scheme && !ls) return { do: "invalid", reason: "no saved scheme called “" + _clean(a.scheme, 40) + "”" };
        if (!lw && !ls) return { do: "invalid", reason: "look: a wallpaper, a saved scheme, or both" };
        return { do: "look", workspaces: list, wallpaper: lw, scheme: ls,
                 label: "Workspace " + list.join(", ") + " → " + [lw, ls].filter(function (x) { return !!x; }).join(" + ") };
    }
    case "discord": {
        var dc = String(a.command || "").toLowerCase();
        if (DISCORD.indexOf(dc) < 0) return { do: "invalid", reason: "discord: one of " + DISCORD.join(", ") };
        var dl = { mute: "Mute in Discord", unmute: "Unmute in Discord", deafen: "Deafen in Discord", undeafen: "Undeafen in Discord",
                   leave: "Leave the Discord call", camera: "Discord camera", screenshare: "Discord screen share" }[dc];
        return { do: "discord", command: dc, label: dl };
    }
    case "discordvolume": {
        // Your mic (0–100), what you hear (0–200), or one person in the call (0–200, for you).
        var tgt = String(a.target || "").toLowerCase();
        var who = tgt === "input" || tgt === "mic" ? "input" : tgt === "output" || tgt === "speaker" ? "output"
                : match(ctx.discordUsers || [], a.target);
        if (!who) return { do: "invalid", reason: "discordvolume: input, output, or someone in the call" };
        var dv = _num(a.value);
        if (isNaN(dv)) return { do: "invalid", reason: "discordvolume: not a number" };
        dv = Math.round(Math.min(who === "input" ? 100 : 200, Math.max(0, dv)));
        return { do: "discordvolume", target: who, value: dv,
                 label: (who === "input" ? "Discord mic" : who === "output" ? "Discord volume" : who) + " → " + dv + "%" };
    }
    case "discorduser": {
        var du = match(ctx.discordUsers || [], a.user);
        if (!du) return { do: "invalid", reason: "nobody called “" + _clean(a.user, 40) + "” in the call" };
        var dm = a.mute === undefined || a.mute === null ? true : _bool(a.mute);
        if (dm === null) return { do: "invalid", reason: "discorduser: mute true/false" };
        return { do: "discorduser", user: du, mute: dm, label: (dm ? "Mute " : "Unmute ") + du + " for you" };
    }
    case "discordsetting": {
        var ds = String(a.setting || "").toLowerCase();
        if (DISCORD_SETTINGS.indexOf(ds) < 0) return { do: "invalid", reason: "discordsetting: one of " + DISCORD_SETTINGS.join(", ") };
        var don = _bool(a.on);
        if (don === null) return { do: "invalid", reason: "discordsetting: on true/false" };
        var dsl = { noise: "Noise suppression", echo: "Echo cancellation", agc: "Automatic gain", pushtotalk: "Push to talk" }[ds];
        return { do: "discordsetting", setting: ds, on: don, label: dsl + " → " + (don ? "on" : "off") };
    }
    case "findsetting": {
        var fq = _clean(a.query, 80);
        if (!fq) return { do: "invalid", reason: "findsetting: what setting?" };
        return { do: "findsetting", query: fq, label: "Find “" + fq + "” in Settings", leaves: true };
    }
    case "remember": {
        var fact = _clean(a.fact || a.text, 140);
        if (!fact) return { do: "invalid", reason: "remember: what?" };
        return { do: "remember", fact: fact, label: "Remember: " + fact };
    }
    case "forget": {
        var ff = _clean(a.fact || a.text || "", 140);
        if (!ff) return { do: "invalid", reason: "forget: what? (or \"all\")" };
        return { do: "forget", fact: ff, label: ff.toLowerCase() === "all" ? "Forget everything" : "Forget: " + ff };
    }
    case "timer": {
        var m = _num(a.minutes !== undefined ? a.minutes : a.value);
        if (isNaN(m) || m <= 0) return { do: "invalid", reason: "timer: minutes, more than 0" };
        m = Math.min(600, Math.round(m * 10) / 10);
        return { do: "timer", minutes: m, label: "Timer · " + show(m) + " min" };
    }
    }
    return { do: "invalid", reason: "unknown action “" + _clean(a.do, 30) + "”" };
}

// A reply → { text, actions }. `text` is the reply with its action blocks taken out (what the
// bubble shows); `actions` are validated, in order. A block that isn't JSON is an invalid card.
// At most 6 actions: past that it's a model looping, not a request.
function parseReply(reply, ctx) {
    var text = String(reply || "");
    var actions = [];
    var re = /```(?:action|json)?[ \t]*\n([\s\S]*?)```/g;
    var out = text.replace(re, function (whole, body) {
        var trimmed = body.trim();
        var looksLikeAction = /"do"\s*:/.test(trimmed);
        if (!looksLikeAction && whole.indexOf("```action") !== 0) return whole;   // ordinary code, left alone
        var doc;
        try { doc = JSON.parse(trimmed); }
        catch (e) { actions.push({ do: "invalid", reason: "an action that isn't valid JSON" }); return ""; }
        var list = Array.isArray(doc) ? doc : [doc];
        for (var i = 0; i < list.length; i++) actions.push(validate(list[i], ctx));
        return "";
    });
    return { text: out.replace(/\n{3,}/g, "\n\n").trim(), actions: actions.slice(0, 6) };
}

// Worked examples: [what the user says, the one-sentence reply, the actions].
function examples() {
    return [
        ["turn on night light and set volume to 40", "Night light is on and the volume is at 40%.",
         [{ do: "action", id: "nightlight", on: true }, { do: "volume", value: 40 }]],
        ["switch to light mode", "Switched to light mode.", [{ do: "set", key: "themeMode", value: "light" }]],
        ["play blinding lights", "Playing Blinding Lights.", [{ do: "play", query: "Blinding Lights The Weeknd", kind: "track" }]],
        ["open youtube", "Opening YouTube.", [{ do: "open", url: "https://www.youtube.com" }]],
        ["remind me to call mum at 6pm", "I'll remind you to call mum at 18:00.", [{ do: "remind", text: "Call mum", at: "18:00" }]],
        ["wake me up at 7 on weekdays", "Alarm set for 07:00 on weekdays.", [{ do: "alarm", at: "07:00", days: "weekdays" }]],
        ["move kitty to workspace 4 and float it", "Kitty is floating on workspace 4.", [{ do: "window", app: "kitty", workspace: 4, float: true }]],
        ["turn spotify up to 120%", "Spotify is at 120%.", [{ do: "appvolume", app: "spotify", value: 120 }]],
        ["leave the call", "Left the Discord call.", [{ do: "discord", command: "leave" }]],
        ["what's playing?", "(the song and artist from Right now)", []],
        ["delete my screenshots", "I can't delete anything — I can only change settings and run the shell's actions.", []],
        ["what can you do?", "I can change colours, settings, wallpapers and scenes, sound, brightness, music, apps, sites, windows, reminders, alarms and timers.", []]
    ];
}

// The examples as JSON-form turns, for ai-ask.py to put before the conversation (local models).
function exampleTurns() {
    var out = [];
    var ex = examples();
    for (var i = 0; i < ex.length; i++) {
        if (ex[i][1].charAt(0) === "(") continue;       // a placeholder answer only makes sense as text
        out.push({ role: "user", text: ex[i][0] });
        out.push({ role: "model", text: JSON.stringify({ reply: ex[i][1], actions: ex[i][2] }) });
    }
    // The end of the examples, said in the conversation itself: without it a 4B model answered "what did
    // I just ask you?" with an example's question (measured).
    out.push({ role: "user", text: "(Those were examples of the format, not things I asked. The real conversation starts now — forget them.)" });
    out.push({ role: "model", text: JSON.stringify({ reply: "Understood.", actions: [] }) });
    return out;
}

// The context a turn is sent with: what the shell can do, and how it is set right now.
// `current` is { key: value } for SETTINGS; `palette` is the live pywal document (or null).
// `json`: the local model's form (scripts/ai-ask.py constrains its output to {reply, actions} and
// turns that back into blocks); otherwise the reply ends in ```action blocks.
//
// The user (2026-10-24): it "should just flip settings, so it's as fast as possible" — no code, no
// how-to, one short sentence. So the prompt is about doing, and the replies are tiny (fewer tokens is
// the speed a local model has).
function systemPrompt(current, palette, today, json, ctx) {
    ctx = ctx || {};
    var lines = [];
    lines.push("You control Quicktest, a desktop shell (Quickshell on Hyprland). Today is " + today + ".");
    lines.push("Your ONLY job is operating the shell with the actions below: its colours, settings, wallpaper, sound, brightness, media, workspaces, apps, timers and built-in tools. You DO have this access: your actions run the moment you send them (the user can undo; a few ask the user first).");
    lines.push("You can't delete, close or remove anything, run commands or touch files — if asked, say so in one sentence.");
    lines.push("Reply in ONE short sentence saying what you changed. Never write code, scripts, commands, config files or step-by-step instructions. Never explain how the shell works.");
    lines.push("If the request isn't something the actions below can do, say so in one sentence and change nothing. A greeting or question gets a one-sentence answer and no actions.");
    lines.push("");
    if (json) {
        lines.push('Answer as JSON: {"reply": "<one sentence>", "actions": [<action>, …]} — "actions" is [] when nothing should change.');
    } else {
        lines.push("To change something, end your reply with a block like this (one action, or a JSON list of them):");
        lines.push("```action");
        lines.push('{"do": "set", "key": "radiusScale", "value": 1.2}');
        lines.push("```");
    }
    lines.push("");
    lines.push('A colour scheme: {"do": "scheme", "name": "<2-3 words>", "background": "#rrggbb", "foreground": "#rrggbb", "colors": [16 × "#rrggbb", color0…color15]}');
    lines.push("Palette rules (pywal): color0 = background, color7 = foreground, color8 = a dim grey, colors 1-6 = distinct accents (color1 is the main one), colors 9-15 = brighter versions of 1-7. Keep the background and foreground far apart in lightness.");
    lines.push("");
    lines.push('Other actions:');
    lines.push('- {"do": "action", "id": "<id>", "on": true|false} — a shell action; "on" only for toggles (leave it out to flip). Ids:');
    for (var id in SHELL) {
        var name = (ctx.names && ctx.names[id]) || id;
        lines.push("    " + id + " — " + name + (SHELL[id].toggle ? " (toggle" + (ctx.states && ctx.states[id] ? ", now " + ctx.states[id] : "") + ")" : "") + (SHELL[id].confirm ? " [asks the user first]" : ""));
    }
    lines.push('- {"do": "volume", "value": 0-100}' + (ctx.volume !== undefined ? " (now " + ctx.volume + ")" : "") + '   {"do": "brightness", "value": 0-100}');
    lines.push('- {"do": "wallpaper", "pick": "<a name below>" | "random"}' + ((ctx.wallpapers || []).length ? " — wallpapers: " + ctx.wallpapers.slice(0, 40).join(", ") : ""));
    lines.push('- {"do": "preset", "name": "<a saved scheme>"}' + ((ctx.presets || []).length ? " — saved schemes: " + ctx.presets.join(", ") : ""));
    if ((ctx.scenes || []).length) lines.push('- {"do": "scene", "pick": "<a scene below>"} — Wallpaper Engine scenes: ' + ctx.scenes.slice(0, 40).join(", "));
    lines.push('- {"do": "play", "query": "<song / album / artist / playlist>", "kind": "track|album|playlist|artist"} — plays it on Spotify');
    lines.push('- {"do": "media", "command": "play|pause|toggle|next|previous"} — the player that\'s on');
    lines.push('- {"do": "open", "url": "https://…"} — a website   {"do": "search", "query": "…"} — a web search');
    lines.push('- {"do": "workspace", "id": 1-10}   {"do": "launch", "app": "<app name>"}   {"do": "timer", "minutes": <n>}');
    lines.push('- {"do": "remind", "text": "…", "in": <minutes>} or {"do": "remind", "text": "…", "at": "HH:MM", "date": "tomorrow"|"YYYY-MM-DD"}   {"do": "todo", "text": "…"}');
    lines.push('- {"do": "alarm", "at": "HH:MM", "days": "once|daily|weekdays|weekends|mon,wed,fri"}');
    lines.push('- {"do": "window", "app": "<an open window below>", "workspace": n, "float": bool, "fullscreen": bool, "focus": bool} — any of them; "side by side" = move both to one workspace');
    lines.push('- {"do": "output", "device": "<a sound output below>"}   {"do": "appvolume", "app": "<app>", "value": 0-' + (ctx.appCeiling || 130) + '} — ONE app\'s volume; apps (Spotify too) go past 100% up to ' + (ctx.appCeiling || 130) + '%');
    lines.push('- {"do": "bluetooth", "device": "<a paired device below>", "connect": true|false}');
    lines.push('- {"do": "clip", "seconds": n} — save the replay buffer   {"do": "screenshot"} — the snip tool');
    lines.push('- {"do": "look", "workspaces": [n, …], "wallpaper": "<name>", "scheme": "<saved scheme>"} — a workspace\'s own wallpaper and/or colours');
    lines.push('- {"do": "discord", "command": "mute|unmute|deafen|undeafen|leave|camera|screenshare"} — leave = hang up the call');
    lines.push('- {"do": "discordvolume", "target": "input"|"output"|"<someone in the call>", "value": n} — input 0-100, output and people 0-200');
    lines.push('- {"do": "discorduser", "user": "<someone in the call>", "mute": bool} — mute them for you   {"do": "discordsetting", "setting": "noise|echo|agc|pushtotalk", "on": bool}');
    lines.push('- {"do": "findsetting", "query": "…"} — opens that page in Settings');
    lines.push('- {"do": "remember", "fact": "…"} / {"do": "forget", "fact": "…"|"all"} — your notes about the user, kept between chats');
    if ((ctx.outputs || []).length) lines.push("Sound outputs: " + ctx.outputs.join(", ") + ".");
    if ((ctx.bluetooth || []).length) lines.push("Paired Bluetooth devices: " + ctx.bluetooth.join(", ") + ".");
    if ((ctx.windowApps || []).length) lines.push("Open windows (app names to use): " + ctx.windowApps.join(", ") + ".");
    lines.push("");
    lines.push('A setting: {"do": "set", "key": "<key>", "value": <value>}. Keys (range, current value in brackets):');
    for (var k in SETTINGS) {
        var st = SETTINGS[k];
        var range = st.type === "enum" ? st.options.join("|")
                  : st.type === "bool" ? "true|false"
                  : st.min + "–" + st.max;
        lines.push("- " + k + " (" + range + ") [" + (current && k in current ? show(current[k]) : "?") + "]: " + st.about);
    }
    lines.push("");
    lines.push("Rules:");
    lines.push("- Light or dark mode is the themeMode setting, never a new scheme. \"Make it lighter/darker\" means themeMode too.");
    lines.push("- A new colour scheme only when asked for colours/a palette/a look; make it coherent: one hue family, readable contrast.");
    lines.push("- Use the names from the lists exactly (wallpapers, scenes, saved schemes). If nothing matches, say so.");
    lines.push("- \"Play <something>\" is the play action; pause/next/previous are media.");
    lines.push("- Several requests in one message: one action each, all in the same reply.");
    lines.push("- Never claim something happened that you didn't put in an action.");
    lines.push("- A question (what/how/did/is…) gets an answer and NO actions. Answer from \"Right now\" with its exact words and numbers; if it isn't there, say you can't see it.");
    lines.push("- Waking up, every day, weekdays, a time to get up → alarm. A one-off nudge (\"remind me…\") → remind.");
    lines.push("- One action per thing: don't repeat an action, put all of a window's changes in one window action.");
    lines.push("- \"Side by side\" / \"next to each other\" = both windows to one workspace, tiled: no float.");
    lines.push("- \"What did I miss?\" = the notifications in Right now.");
    lines.push("- One app's volume (Spotify, a browser, a game) → appvolume, never volume. \"volume\" alone is the whole system, which stops at 100%.");
    lines.push("- A PERSON in the Discord call (a name from the call) → discordvolume / discorduser, never appvolume.");
    if (json) lines.push("- The exchanges before the real conversation are EXAMPLES of the format. They never happened — never mention them.");
    lines.push("");
    if ((ctx.now || []).length) {
        lines.push("Right now (answer questions about these from here — don't guess, don't make up numbers):");
        for (var q = 0; q < ctx.now.length; q++) lines.push("- " + ctx.now[q]);
        lines.push("");
    }
    if ((ctx.memory || []).length) {
        lines.push("What the user asked you to remember (use it; e.g. their taste in colours):");
        for (var r = 0; r < ctx.memory.length; r++) lines.push("- " + ctx.memory[r]);
        lines.push("");
    }
    // Examples: for the block form (cloud models) written in here; for the JSON form (a small local model)
    // they go as real earlier turns instead (`examples()`, ai-ask.py puts them before the conversation)
    // — measured: qwen3:4b given them as text here repeated one word for word ("wake me at 7" → the
    // "call mum at 6" reminder); as turns, it follows them.
    if (!json) {
        lines.push("Examples (user → you):");
        var ex = examples();
        for (var e = 0; e < ex.length; e++) {
            var acts = ex[e][2];
            lines.push("“" + ex[e][0] + "” → " + ex[e][1] + (acts.length ? "\n```action\n" + JSON.stringify(acts) + "\n```" : ""));
        }
    }
    if (palette && palette.colors) {
        var c = palette.colors, sp = palette.special || {};
        var arr = [];
        for (var i = 0; i < 16; i++) arr.push(c["color" + i] || "?");
        lines.push("");
        lines.push("The current palette: background " + (sp.background || c.color0) + ", foreground " + (sp.foreground || c.color7) + ", colors " + arr.join(" ") + ".");
    }
    return lines.join("\n");
}
