.pragma library
.import "contagion.js" as Kinds

// ── workspacetheme.js ─────────────────────────────────────────────────────────
// services/WorkspaceTheme: which windows, terminals and apps must be told which
// palette — each wears the palette of the workspace it is ON (its own wallpaper's,
// else the shared one), told only when that changes.
//
//     bun scripts/test-workspacetheme.js
// ─────────────────────────────────────────────────────────────────────────────

var TERMINALS = ["kitty", "alacritty", "foot", "footclient", "wezterm",
                 "org.wezfurlong.wezterm", "ghostty", "com.mitchellh.ghostty"]

// clients:   `hyprctl clients -j`
// fileFor:   workspace id → the palette file its windows wear ("" = the shared one)
// live:      the shared (committed) palette file
// wears:     { key: file } — what each window ("0x…"), terminal ("pid:N") and app
//            ("app:discord") wears now; absent = the shared one
// Returns { borders: [{ address, file }], terminals: { file: [pid] },
//           apps: { file: [app] }, wears } — `wears` as it will be once told.
// A single-window app (Discord, Spotify) wears its FIRST window's workspace's palette.
function plan(clients, fileFor, live, wears, discordClasses) {
    var next = Object.assign({}, wears || {})
    var out = { borders: [], terminals: {}, apps: {}, wears: next }
    var seenApp = {}
    var alive = {}
    function needs(k, file) { return (next[k] === undefined ? live : next[k]) !== file }
    function wear(k, file) { if (file === live) delete next[k]; else next[k] = file }
    function push(map, file, v) { (map[file] = map[file] || []).push(v) }

    for (var i = 0; i < (clients || []).length; i++) {
        var c = clients[i]
        if (!c || typeof c.address !== "string" || !/^0x[0-9a-fA-F]{1,16}$/.test(c.address)) continue
        var ws = c.workspace && typeof c.workspace.id === "number" ? c.workspace.id : -1
        var file = (ws > 0 && fileFor(ws)) || live
        alive[c.address] = true
        if (needs(c.address, file)) { out.borders.push({ address: c.address, file: file }); wear(c.address, file) }

        var cls = String(c["class"] || "").toLowerCase()
        var pid = Number(c.pid)
        if (TERMINALS.indexOf(cls) >= 0 && pid > 1) {
            var tk = "pid:" + pid
            alive[tk] = true
            if (needs(tk, file) && (out.terminals[file] || []).indexOf(pid) < 0) {
                push(out.terminals, file, pid)
                wear(tk, file)
            }
        }
        var kind = Kinds.kind(cls, discordClasses)
        if ((kind === "discord" || kind === "spotify") && !seenApp[kind]) {
            seenApp[kind] = true
            alive["app:" + kind] = true
            if (needs("app:" + kind, file)) { push(out.apps, file, kind); wear("app:" + kind, file) }
        }
    }
    // Gone windows and processes are forgotten (a reused pid starts clean).
    for (var k in next) if (!alive[k]) delete next[k]
    return out
}

// ── A workspace's own wallpaper: a picture or a Wallpaper Engine scene ────────
// Config.wallWorkspaces values are an absolute image path or "scene:<id>". → { image }
// / { scene } / null for anything else (the file is hand-editable).
var SCENE_ID = /^[A-Za-z0-9._-]{1,64}$/
function parseOwn(v) {
    if (typeof v !== "string") return null
    if (v.indexOf("scene:") === 0) {
        var id = v.slice(6)
        return SCENE_ID.test(id) ? { scene: id } : null
    }
    return v.charAt(0) === "/" && v.indexOf("\n") < 0 ? { image: v } : null
}

// ── Which scene each screen's renderer plays ──────────────────────────────────
// screens:  every screen name
// wsMap:    { screen: "<scene id>" | "" } — what the workspace a screen SHOWS asks for:
//           its own scene, or "" (its own is a picture: no scene there). A screen not in
//           it follows the shared wallpaper.
// shared:   { isScene, defaultId, perScreen: { screen: id }, target: [screens] } — the
//           shared wallpaper when it's a scene: the default scene on `target`, overridden
//           per screen (Config.wpeMonitors).
// → { screen: id } for every screen that should play a scene ({} = none: stop it).
function effectiveScenes(screens, wsMap, shared) {
    var out = {}
    var sh = shared || {}
    for (var i = 0; i < (screens || []).length; i++) {
        var s = screens[i]
        if (wsMap && Object.prototype.hasOwnProperty.call(wsMap, s)) {
            if (wsMap[s]) out[s] = wsMap[s]
            continue
        }
        if (!sh.isScene) continue
        var own = sh.perScreen && sh.perScreen[s]
        if (own) out[s] = own
        else if (sh.defaultId && (sh.target || []).indexOf(s) >= 0) out[s] = sh.defaultId
    }
    return out
}

// A stable key for a map, to tell "already playing this" from "relaunch".
function sceneKey(map) {
    return Object.keys(map || {}).sort().map(function (k) { return k + "=" + map[k] }).join(";")
}
