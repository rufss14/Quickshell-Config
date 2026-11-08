.pragma library

// ── gamemodefx.js ─────────────────────────────────────────────────────────────
// Game Mode's "compositor effects off" (Config.gamemodeCompositor): which Hyprland options it
// turns off, the Lua that does it, and the Lua that puts them back from a snapshot.
//
//     bun scripts/test-gamemodefx.js
//
// ── Why a snapshot, not "turn them on" ────────────────────────────────────────
// The user may already run with blur or shadows off. Restoring to a hardcoded `true` would
// turn on something they never had; restoring what was READ before is the only exit that
// leaves the compositor as it was. The snapshot also goes to disk (Gamemode writes it) so a
// crash or a shell restart while the mode is on can still put things back next start.
//
// Only booleans from a fixed list ever reach the Lua text, so nothing read from hyprctl can
// inject anything into it.
// ─────────────────────────────────────────────────────────────────────────────

// Colon paths, exactly as `hyprctl getoption` spells them. Fixed: the Lua below is built
// from these and nothing else.
var OPTIONS = ["animations:enabled", "decoration:blur:enabled", "decoration:shadow:enabled"]

// The shell script's argv tail: one `hyprctl -j getoption` per option, one JSON object a line.
var READ_SCRIPT = 'for o in "$@"; do hyprctl -j getoption "$o" 2>/dev/null; echo; done; exit 0'

// `getoption` output (one JSON object per line) → { "<option>": bool }. An option that did
// not answer, answered with something else, or is not on the list is simply absent — the
// restore skips what it has no value for.
function snapshotFrom(text) {
    var out = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (line === "") continue
        var o
        try { o = JSON.parse(line) } catch (e) { continue }
        if (o && OPTIONS.indexOf(o.option) !== -1 && typeof o.bool === "boolean") out[o.option] = o.bool
    }
    return out
}

// A snapshot read back off disk: only the listed options, only booleans.
function cleanSnapshot(raw) {
    var out = {}
    if (!raw || typeof raw !== "object") return out
    for (var i = 0; i < OPTIONS.length; i++)
        if (typeof raw[OPTIONS[i]] === "boolean") out[OPTIONS[i]] = raw[OPTIONS[i]]
    return out
}

// { a:b:c: true } → `{ a = { b = { c = true } } }`, merged where paths share a prefix.
function _nest(values) {
    var tree = {}
    for (var name in values) {
        var parts = name.split(":")
        var node = tree
        for (var i = 0; i < parts.length - 1; i++) node = node[parts[i]] = node[parts[i]] || {}
        node[parts[parts.length - 1]] = values[name] === true
    }
    function lua(n) {
        var keys = Object.keys(n)
        return "{ " + keys.map(function (k) {
            return k + " = " + (typeof n[k] === "object" ? lua(n[k]) : (n[k] ? "true" : "false"))
        }).join(", ") + " }"
    }
    return lua(tree)
}

// The Lua for the `hyprctl eval` that turns every listed option off. "" when there is none.
function offLua() {
    var v = {}
    for (var i = 0; i < OPTIONS.length; i++) v[OPTIONS[i]] = false
    return "hl.config(" + _nest(v) + ")"
}

// The Lua that puts a snapshot back. "" when it holds nothing to restore.
function restoreLua(snapshot) {
    var snap = cleanSnapshot(snapshot)
    return Object.keys(snap).length === 0 ? "" : "hl.config(" + _nest(snap) + ")"
}
