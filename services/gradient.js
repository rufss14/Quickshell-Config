.pragma library

// ── gradient.js ───────────────────────────────────────────────────────────────
// The colour gradient the bar and the islands' faces wear (Config.barGradient), as pure functions so
// `bun scripts/test-gradient.js` can pin them. The blob (Quicktest.Blobs) draws the fill; this decides
// WHAT it draws: three colours, where the middle one sits, and the line they run along.
//
// ── One document, three homes ─────────────────────────────────────────────────
// { on, angle, strength, mid, stops: [a, b, c?], from }. It is Config.barGradient on the shell, a
// scheme file's `gradient` key (so a scheme can ship its own), and what the Gradient view edits. The
// last two are files other people write, so `clean()` is the one door: it never throws and never lets
// a stray value reach a shader.
//
// A stop is either a palette role (a whitelist, as PaletteRoles.role: the gradient follows the
// wallpaper) or a literal #rrggbb (a scheme's own colour, which does not).
// `strength` is how far each stop moves from the plain bar fill toward its colour, 0 to 1 as the slider
// shows it. 1 is STRENGTH_MAX of the way to the colour, not all of it: past about 60% the bar turns garish
// and the text on it loses its ground, so the top of the slider is the strongest that looks right. It is
// applied HERE, in the stops, not in the shader, so the shader stays three colours and a line.
// ─────────────────────────────────────────────────────────────────────────────

var ROLES = ["primary", "focus", "vivid", "primaryContainer", "fg"];

var STRENGTH_MAX = 0.6;

var DEFAULTS = { on: false, angle: 30, strength: 0.6, mid: 0.5, stops: ["primary", "focus"], from: "" };

var HEX6 = /^#[0-9a-f]{6}$/i;

function isStop(s) {
    return typeof s === "string" && (HEX6.test(s) || ROLES.indexOf(s) >= 0);
}

function _num(v, lo, hi, fallback) {
    v = Number(v);
    if (!isFinite(v)) return fallback;
    return Math.max(lo, Math.min(hi, v));
}

// Any value → a complete, valid document. Unknown keys are dropped; a bad field takes its default.
function clean(raw) {
    var r = (raw && typeof raw === "object") ? raw : {};
    var stops = Array.isArray(r.stops) ? r.stops.filter(isStop).slice(0, 3) : [];
    if (stops.length < 2) stops = DEFAULTS.stops.slice();
    var angle = _num(r.angle, -3600, 3600, DEFAULTS.angle) % 360;
    if (angle < 0) angle += 360;
    return {
        on: r.on === true,
        angle: angle,
        strength: _num(r.strength, 0, 1, DEFAULTS.strength),
        mid: _num(r.mid, 0.1, 0.9, DEFAULTS.mid),
        stops: stops,
        from: typeof r.from === "string" ? r.from.slice(0, 64) : ""
    };
}

// The line the colours run along over a w × h surface at `angle` degrees (0 = left to right, 90 = top to
// bottom): [x0, y0, dx, dy], so t = dot(p - (x0, y0), (dx, dy)) / |(dx, dy)|², 0 at the first colour, 1
// at the last. The line is as long as the surface's projection onto it, so the corners reach the ends
// exactly, whatever the angle.
function axis(angle, w, h) {
    var a = angle * Math.PI / 180, cx = Math.cos(a), sy = Math.sin(a);
    var half = (Math.abs(w * cx) + Math.abs(h * sy)) / 2;
    if (!(half > 0)) return [0, 0, 1, 0];
    return [w / 2 - cx * half, h / 2 - sy * half, cx * 2 * half, sy * 2 * half];
}

function _rgb(hex) {
    var s = String(hex).replace("#", "");
    if (s.length === 8) s = s.slice(2);
    var n = parseInt(s, 16);
    return isFinite(n) ? [(n >> 16) & 255, (n >> 8) & 255, n & 255] : [0, 0, 0];
}

function _hex(c) {
    return "#" + c.map(function (v) {
        var h = Math.max(0, Math.min(255, Math.round(v))).toString(16);
        return h.length < 2 ? "0" + h : h;
    }).join("");
}

function mix(a, b, t) {
    var x = _rgb(a), y = _rgb(b);
    return _hex([x[0] + (y[0] - x[0]) * t, x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t]);
}

// The colours a gradient is made of, resolved: [{ hex, ... }] is not needed, apps read the plain stops
// (`raw`) and apply `strength * STRENGTH_MAX` themselves, over their own ground.
function raw(doc, role) {
    var d = clean(doc);
    return d.stops.map(function (s) { return HEX6.test(s) ? s : _hex(_rgb(role(s))); });
}

// The three colours the shader gets, as #rrggbb. `role(name)` is the palette's colour for a role name (a
// hex string); `fill` is the bar's plain fill. Two stops are three with the middle on the line between.
function colours(doc, role, fill) {
    var d = clean(doc);
    var base = _hex(_rgb(fill));
    return _three(d.stops.map(function (s) {
        var hex = HEX6.test(s) ? s : String(role(s));
        return mix(base, hex, d.strength * STRENGTH_MAX);
    }), d.mid);
}

// The same three colours, whole: no ground to mix toward, so `strength` does not apply. For a surface
// with no fill of its own, like the desktop visualiser, which wears the stops as they were picked.
function vivid(doc, role) {
    var d = clean(doc);
    return _three(d.stops.map(function (s) {
        return HEX6.test(s) ? s : _hex(_rgb(String(role(s))));
    }), d.mid);
}

// Two stops are three with the middle on the line between.
function _three(c, mid) {
    return c.length === 2 ? [c[0], mix(c[0], c[1], mid), c[1]] : c;
}

// Is `doc` the one on show, so a scheme card can tell it is wearing it?
function same(a, b) {
    var x = clean(a), y = clean(b);
    return x.on === y.on && Math.round(x.angle) === Math.round(y.angle)
        && Math.abs(x.strength - y.strength) < 0.005 && Math.abs(x.mid - y.mid) < 0.005
        && x.stops.join() === y.stops.join();
}
