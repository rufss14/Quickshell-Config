.pragma library
.import "launcher.js" as L

// ── switcher.js ───────────────────────────────────────────────────────────────
// Alt+Tab and window search over the overview's workspace grid (services/Switcher):
// which windows, in which order, which one is picked, and what Alt+Tab's events say.
//
//     bun scripts/test-switcher.js
//
// Pure: windows come in as plain records { address, title, appClass, appName } —
// the caller reads them off Hypr; nothing here touches Quickshell.
// ─────────────────────────────────────────────────────────────────────────────

var PREFIX = "qs-switch:"
var ORDER_MAX = 64                  // more windows than this and the tail keeps its own order
var ADDR = /^(0x)?[0-9a-f]{1,16}$/

// "562d73b1be60" and "0x562d73b1be60" are the same window (Hypr.addr's rule).
function norm(a) {
    if (typeof a !== "string") return ""
    var s = a.toLowerCase()
    if (!ADDR.test(s)) return ""
    return s.indexOf("0x") === 0 ? s : "0x" + s
}

// ── Alt+Tab's events ──────────────────────────────────────────────────────────
// hypr/binds.lua posts, on the event socket the shell already reads:
//     qs-switch:next:<addr>,<addr>,…     ALT+TAB           (Hyprland's focus history,
//     qs-switch:prev:<addr>,<addr>,…     ALT+SHIFT+TAB      most recent first)
//     qs-switch:up                       Alt let go
// → { kind, order } or null. Anything malformed is null: the socket is readable by
// every process the user runs, so a forged line can at most pick a window.
function parseEvent(data) {
    if (typeof data !== "string" || data.indexOf(PREFIX) !== 0) return null
    var body = data.slice(PREFIX.length)
    if (body === "up") return { kind: "up", order: [] }
    var cut = body.indexOf(":")
    var kind = cut < 0 ? body : body.slice(0, cut)
    if (kind !== "next" && kind !== "prev") return null
    var order = []
    if (cut >= 0 && body.length > cut + 1) {
        var parts = body.slice(cut + 1).split(",")
        for (var i = 0; i < parts.length && order.length < ORDER_MAX; i++) {
            var a = norm(parts[i])
            if (a !== "" && order.indexOf(a) < 0) order.push(a)
        }
    }
    return { kind: kind, order: order }
}

// ── Order ─────────────────────────────────────────────────────────────────────
// Windows by Hyprland's focusHistoryID (0 = focused now). `historyOf(address)` →
// that number, or -1/undefined when unknown; unknown ones go last, by address, so
// the order is stable while they wait for a refresh.
function byHistory(windows, historyOf) {
    var rows = []
    for (var i = 0; i < windows.length; i++) {
        var h = historyOf(windows[i].address)
        rows.push({ w: windows[i], h: (typeof h === "number" && h >= 0) ? h : Infinity })
    }
    rows.sort(function (a, b) {
        if (a.h !== b.h) return a.h < b.h ? -1 : 1
        return a.w.address < b.w.address ? -1 : a.w.address > b.w.address ? 1 : 0
    })
    return rows.map(function (r) { return r.w })
}

// Windows in a GIVEN order (most recent first); any window the order doesn't name
// (never focused since the shell started, or opened since Alt+Tab's list) after them,
// in the order they came in — the caller hands them over by Hyprland's history.
// Addresses in the order with no window (closed since) are skipped.
function arrange(order, windows) {
    var at = {}
    for (var i = 0; i < order.length; i++) at[norm(order[i])] = i
    var named = [], rest = []
    for (var j = 0; j < windows.length; j++) {
        var k = at[norm(windows[j].address)]
        if (k === undefined) rest.push(windows[j])
        else named.push({ w: windows[j], k: k })
    }
    named.sort(function (a, b) { return a.k - b.k })
    return named.map(function (n) { return n.w }).concat(rest)
}

// ── Search ────────────────────────────────────────────────────────────────────
// The launcher's own scorer (launcher.js scoreText — one tier scale shell-wide), over
// a window's title, its app's name and its class. The best field counts; ties keep
// the recency order the list came in. A query of spaces is no query.
function score(win, q) {
    var best = 0
    var fields = [win.title, win.appName, win.appClass]
    for (var i = 0; i < fields.length; i++) {
        var t = (fields[i] || "").toLowerCase()
        if (t === "") continue
        // Words separately, so "zen git" needs both — a title is a sentence.
        var words = q.split(/\s+/).filter(function (s) { return s !== "" })
        var sum = 0, all = true
        for (var k = 0; k < words.length && all; k++) {
            var s = L.scoreText(t, words[k]).tier
            if (s === 0) all = false
            sum += s
        }
        if (all && words.length > 0) best = Math.max(best, Math.round(sum / words.length))
    }
    // A match on the title and another word on the app ("zen github") is common;
    // the joined text catches it.
    if (best === 0) {
        var joined = ((win.appName || "") + " " + (win.title || "")).toLowerCase()
        var ws = q.split(/\s+/).filter(function (s) { return s !== "" })
        var ok = ws.length > 0, tot = 0
        for (var m = 0; m < ws.length && ok; m++) {
            var r = L.scoreText(joined, ws[m]).tier
            if (r === 0) ok = false
            tot += r
        }
        if (ok) best = Math.round(tot / ws.length) - 5
    }
    return Math.max(0, best)
}

// ── Operators ─────────────────────────────────────────────────────────────────
// Words of the query shaped `key:value` narrow the windows before the text scores them:
//     ws:3  ws:1,2     the workspace (any of those)
//     app:kit          the app's name or class (the scorer's own fuzziness)
//     is:floating      a flag — floating, tiled, pinned, fullscreen, audio — by prefix, so
//                      `is:fl` already works while it is being typed
// Every operator must hold (AND); the plain words left over are searched as ever. A word
// that merely LOOKS like one — `is:xyz`, `ws:abc`, a title's "http:" — stays a plain word,
// and a key with nothing after it yet (`ws:`) is dropped, so typing one never blanks the grid.
var FLAGS = ["floating", "tiled", "pinned", "fullscreen", "audio"]
var WS_LIST = /^\d{1,3}(,\d{1,3})*$/

function parseQuery(query) {
    var out = { text: "", ws: [], app: [], flags: [] }
    var words = (query || "").toLowerCase().split(/\s+/)
    var plain = []
    for (var i = 0; i < words.length; i++) {
        var w = words[i]
        if (w === "") continue
        var cut = w.indexOf(":")
        var key = cut > 0 ? w.slice(0, cut) : ""
        var val = cut > 0 ? w.slice(cut + 1) : ""
        if (key === "ws" || key === "app" || key === "is") {
            if (val === "") continue
            if (key === "ws" && WS_LIST.test(val)) {
                out.ws.push(val.split(",").map(Number))
                continue
            }
            if (key === "app") { out.app.push(val); continue }
            if (key === "is") {
                var hit = ""
                for (var f = 0; f < FLAGS.length && hit === ""; f++)
                    if (FLAGS[f].indexOf(val) === 0) hit = FLAGS[f]
                if (hit !== "") { out.flags.push(hit); continue }
            }
        }
        plain.push(w)
    }
    out.text = plain.join(" ")
    return out
}

// Operators that are COMPLETE in `text` (a `ws:` / `app:` / `is:` word followed by whitespace, so `is:fl` is
// still being typed) come out as `ops`, and `rest` is what is left to type: the overview's search turns them into
// chips inside the field. A word that only LOOKS like an operator (`is:xyz`) stays in `rest`, as parseQuery would.
function splitOps(text) {
    var parts = (text || "").split(/(\s+)/)
    var ops = []
    var keep = []
    for (var i = 0; i < parts.length; i += 2) {
        var w = parts[i]
        if (w === "") continue
        var done = i + 1 < parts.length
        var p = done ? parseQuery(w) : null
        var isOp = done && /^(ws|app|is):\S+$/i.test(w) && p.text === ""
        if (isOp) ops.push(w.toLowerCase()); else keep.push(w)
    }
    var rest = keep.join(" ")
    if (rest !== "" && /\s$/.test(text)) rest += " "
    return { ops: ops, rest: rest }
}

// Does `query` carry exactly this flag (the chips' lit state)? And the query with it
// switched: added at the end, or every copy removed.
function hasFlag(query, flag) {
    var words = (query || "").toLowerCase().split(/\s+/)
    return words.indexOf("is:" + flag) >= 0
}
function toggleFlag(query, flag) {
    var tok = "is:" + flag
    var words = (query || "").split(/\s+/).filter(function (s) { return s !== "" })
    var kept = words.filter(function (s) { return s.toLowerCase() !== tok })
    if (kept.length === words.length) kept.push(tok)
    return kept.join(" ")
}

// Windows matching the query, best first. `factsOf(win)` → { floating, pinned, fullscreen, audio }
// is only called when a flag operator needs it — the caller reads Hyprland's live state in it, which a
// window record doesn't carry (and which would rebuild the record list on every refresh if it did).
function filter(windows, query, factsOf) {
    var p = parseQuery(query)
    var narrowed = windows
    if (p.ws.length > 0 || p.app.length > 0 || p.flags.length > 0) {
        narrowed = windows.filter(function (win) {
            for (var a = 0; a < p.ws.length; a++)
                if (p.ws[a].indexOf(win.workspaceId) < 0) return false
            for (var b = 0; b < p.app.length; b++) {
                var hit = false
                var names = [win.appName, win.appClass]
                for (var n = 0; n < names.length && !hit; n++) {
                    var t = (names[n] || "").toLowerCase()
                    hit = t !== "" && L.scoreText(t, p.app[b]).tier > 0
                }
                if (!hit) return false
            }
            if (p.flags.length > 0) {
                var facts = factsOf ? factsOf(win) : {}
                for (var c = 0; c < p.flags.length; c++) {
                    var fl = p.flags[c]
                    var on = fl === "tiled" ? facts.floating === false : facts[fl] === true
                    if (!on) return false
                }
            }
            return true
        })
    }
    var q = p.text
    if (q === "") return narrowed.slice()
    var rows = []
    for (var i = 0; i < narrowed.length; i++) {
        var s = score(narrowed[i], q)
        if (s > 0) rows.push({ w: narrowed[i], s: s, i: i })
    }
    rows.sort(function (a, b) { return a.s !== b.s ? b.s - a.s : a.i - b.i })
    return rows.map(function (r) { return r.w })
}

// ── Picking ───────────────────────────────────────────────────────────────────
// Where Alt+Tab starts: the window you were on BEFORE this one (next), or the
// oldest (prev). One window: itself. None: -1.
function initialIndex(count, kind) {
    if (count <= 0) return -1
    if (count === 1) return 0
    return kind === "prev" ? count - 1 : 1
}

// One step, wrapping; -1 (nothing picked) steps onto the first or last.
function step(index, count, dir) {
    if (count <= 0) return -1
    if (index < 0 || index >= count) return dir < 0 ? count - 1 : (count > 1 ? 1 : 0)
    return ((index + dir) % count + count) % count
}

// After the list changed under a pick: the same window if it's still there, else
// the nearest place it was.
function keep(prevAddress, list, prevIndex) {
    if (list.length === 0) return -1
    var a = norm(prevAddress)
    for (var i = 0; i < list.length; i++) if (norm(list[i].address) === a) return i
    if (prevIndex < 0) return -1
    return Math.min(prevIndex, list.length - 1)
}

// ── How long ago ──────────────────────────────────────────────────────────────
// The picked window's label: when you last left it. `at` = ms it lost focus (0 =
// not since the shell started → ""). Minutes are as fine as it gets: the label
// follows Clock, which ticks once a minute.
function ago(at, now) {
    if (!(at > 0) || !(now > 0)) return ""
    var m = Math.floor(Math.max(0, now - at) / 60000)
    if (m < 1) return "just now"
    if (m < 60) return m + " min ago"
    var h = Math.floor(m / 60)
    if (h < 24) return h + " h ago"
    return Math.floor(h / 24) + " d ago"
}

// ── Arrow keys: the next window ON THE GRID in that direction ─────────────────
// `from` and each candidate are { address, x, y } — a centre, in any one space (the grid's
// board). (dx, dy) is the direction: (1, 0) right, (0, -1) up. The nearest one ahead of
// `from` wins, with sideways distance counting double, so ↓ from the top-left window
// takes the one under it rather than a nearer one off to the side. "" when nothing lies
// that way. Ahead means more than a pixel along the direction, so a window doesn't pick
// itself or its twin at the same centre.
function nearest(from, cands, dx, dy) {
    var best = "", bestCost = Infinity
    for (var i = 0; i < cands.length; i++) {
        var c = cands[i]
        if (c.address === from.address) continue
        var ax = c.x - from.x, ay = c.y - from.y
        var along = ax * dx + ay * dy
        if (along <= 1) continue
        var side = Math.abs(ax * dy - ay * dx)
        var cost = along + side * 2
        if (cost < bestCost) { bestCost = cost; best = c.address }
    }
    return best
}
