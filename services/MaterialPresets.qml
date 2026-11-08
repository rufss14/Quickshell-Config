pragma Singleton
import Quickshell
import QtQuick
import "../config"
import "materialwall.js" as MW
import "palette.js" as Palette

// ── MaterialPresets ───────────────────────────────────────────────────────────
// Saved looks for the Material Wallpaper, and which colour scheme wears which.
//
// A LOOK is a whole style (services/materialwall.js STYLE): the six built-in ones, and the ones the
// user saved (Config.wallMaterialSaved, seed included — the arrangement is part of what they liked).
// A look has a KEY: a built-in's id ("calm"), or "my:<name>" for a saved one.
//
// ── The lock, here too ────────────────────────────────────────────────────────
// The colours panel's lock holds what is showing. This is its twin for the picture: LINK the look in
// use to the colour scheme the shell is wearing (Config.wallMaterialLinks), and whenever that scheme
// is applied again — with the Material Wallpaper on — the look loads by itself.
//
// ── Which scheme is worn ──────────────────────────────────────────────────────
// Nothing records it (an unlocked scheme is a staged palette the next wallpaper replaces), so
// `wornScheme` reads it back: the saved scheme whose palette the live one is (palette.js findScheme).
// A wallpaper change makes it "" until a scheme is applied again, and a light/dark switch re-reads it
// in the new mode, so neither counts as applying anything.
//
// ── When a link loads ─────────────────────────────────────────────────────────
//   · a scheme is applied (it becomes the worn one) while the Material Wallpaper is on;
//   · the Material Wallpaper is applied while a linked scheme is worn — but only when the style in
//     the panel is one of the looks (saved or built-in): a mix the user is still working on and has
//     not saved is theirs, and Apply puts it on screen as it is.
// Never at start-up: the style on disk is what the user left, and the library is still being read.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── The looks ─────────────────────────────────────────────────────────────
    // What the user saved, as the config holds it — cleaned (it can be hand-edited): a name is one
    // short line and unique, a style is whole and in range.
    readonly property var saved: {
        const raw = Array.isArray(Config.wallMaterialSaved) ? Config.wallMaterialSaved : []
        const out = [], seen = ({})
        for (const r of raw) {
            const name = MW.cleanName(r && r.name)
            if (name === "" || seen[name.toLowerCase()]) continue
            seen[name.toLowerCase()] = true
            out.push({ name: name, style: MW.normaliseStyle(r.style) })
        }
        return out
    }

    // [{ key, label, icon, builtIn }], the built-in looks then the saved ones.
    readonly property var looks: MW.PRESETS
        .map(p => ({ key: p.id, label: p.label, icon: p.icon, builtIn: true }))
        .concat(root.saved.map(s => ({ key: "my:" + s.name, label: s.name, icon: "star", builtIn: false })))

    function hasLook(key) { return root.looks.some(l => l.key === key) }
    function labelOf(key) { return root.looks.find(l => l.key === key)?.label ?? "" }

    // The style a look stands for. A built-in leaves the arrangement as it is.
    function styleOf(key) {
        if (key.startsWith("my:")) return root.saved.find(s => "my:" + s.name === key)?.style ?? null
        return MW.PRESETS.some(p => p.id === key) ? MW.lookStyle(key, Config.wallMaterialSeed) : null
    }

    // The style in use now, as one object.
    readonly property var current: {
        const o = ({})
        for (const k in MW.CONFIG_KEY) o[k] = Config[MW.CONFIG_KEY[k]]
        if (o.role === "primary") o.role = ""
        return o
    }
    // Which look it is, or "" for a mix of the user's own that is not saved. A saved look has to match
    // to the seed; a built-in one ignores the seed.
    readonly property string currentKey: {
        const mine = root.saved.find(s => MW.sameStyle(s.style, root.current, true))
        if (mine) return "my:" + mine.name
        return MW.lookOf(root.current)
    }

    function apply(key) {
        const s = root.styleOf(key)
        if (!s) return
        for (const k in MW.CONFIG_KEY) Config[MW.CONFIG_KEY[k]] = s[k]
    }

    // Save the style in use as `name` (replacing a saved look of that name). The key, or "" for no name.
    function save(name) {
        const n = MW.cleanName(name)
        if (n === "") return ""
        const rest = root.saved.filter(s => s.name.toLowerCase() !== n.toLowerCase())
        // Written over a saved look of that name, keeping the spelling of the one it replaces.
        const was = root.saved.find(s => s.name.toLowerCase() === n.toLowerCase())
        const name2 = was ? was.name : n
        Config.wallMaterialSaved = rest.concat([{ name: name2, style: root.current }])
            .sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()))
        return "my:" + name2
    }

    // A saved look, and every link that wore it.
    function remove(key) {
        if (!key.startsWith("my:")) return
        const n = key.slice(3)
        Config.wallMaterialSaved = root.saved.filter(s => s.name !== n)
        root._dropLinks(k => k === key)
    }

    // ── The links ─────────────────────────────────────────────────────────────
    // { "<scheme>": "<look key>" }, cleaned the same way: only a string to a look that exists counts.
    readonly property var links: {
        const raw = Config.wallMaterialLinks
        const out = ({})
        if (raw && typeof raw === "object" && !Array.isArray(raw))
            for (const s in raw)
                if (typeof raw[s] === "string" && root.hasLook(raw[s])) out[s] = raw[s]
        return out
    }
    function linkFor(scheme) { return scheme !== "" ? (root.links[scheme] ?? "") : "" }
    // The schemes that wear a look (for marking it in the list).
    function schemesOf(key) { return Object.keys(root.links).filter(s => root.links[s] === key) }

    function link(scheme, key) {
        if (scheme === "" || !root.hasLook(key)) return
        const next = Object.assign({}, root.links)
        next[scheme] = key
        Config.wallMaterialLinks = next
    }
    function unlink(scheme) {
        if (!(scheme in root.links)) return
        const next = Object.assign({}, root.links)
        delete next[scheme]
        Config.wallMaterialLinks = next
    }
    function _dropLinks(test) {
        const next = ({})
        for (const s in root.links) if (!test(root.links[s], s)) next[s] = root.links[s]
        Config.wallMaterialLinks = next
    }

    // ── The scheme in force ───────────────────────────────────────────────────
    function _worn() { return Palette.findScheme(ColorScheme.live, ColorScheme.presets, Config.themeMode) }
    readonly property string wornScheme: root._worn()
    readonly property string linkedKey: root.linkFor(root.wornScheme)

    // "" when the look in use can be linked to the scheme worn, else why not.
    function linkBlocker() {
        return root.wornScheme === "" ? "Apply a saved colour scheme first — a wallpaper's own colours aren't one" : ""
    }

    // The lock button: link the look in use to the scheme worn, or let it go. A mix that is not saved
    // is saved first, under the scheme's name, so a link always names something that will be there.
    function toggleLink() {
        const scheme = root.wornScheme
        if (scheme === "") return
        if (root.linkedKey !== "") { root.unlink(scheme); return }
        let key = root.currentKey
        if (key === "") key = root.save(MW.freeName(scheme, root.looks.map(l => l.label)))
        root.link(scheme, key)
    }

    // ── Loading a link ────────────────────────────────────────────────────────
    // `_ready` once the scheme library AND the live palette have been read; the scheme worn at that
    // moment is the baseline, not an event (the style on disk is what the user left). `_last` is the last scheme worn: a wallpaper change or a light/dark switch makes
    // `wornScheme` "" for a moment and then the same scheme again, which is not applying it, so `_last`
    // is only forgotten after it has been gone a while.
    property bool   _ready: false
    property string _last: ""

    // Read straight from the sources, not from `wornScheme`, which may not have followed them yet.
    function _tryReady() {
        const live = ColorScheme.live
        if (root._ready || ColorScheme.presets.length === 0 || !live || !live.colors || !live.colors.color15) return
        root._ready = true
        root._last = root._worn()
    }
    Component.onCompleted: root._tryReady()

    Connections {
        target: ColorScheme
        function onPresetsChanged() { root._tryReady(); root._prune() }
        function onLiveChanged() { root._tryReady() }
    }
    onWornSchemeChanged: {
        if (!root._ready) return
        if (root.wornScheme === "") { forget.restart(); return }
        forget.stop()
        const fresh = root.wornScheme !== root._last
        root._last = root.wornScheme
        if (fresh && Config.wallMaterial) root._load()
    }
    Timer { id: forget; interval: 8000; onTriggered: root._last = "" }

    Connections {
        target: Config
        function onWallMaterialChanged() {
            // Applying Material over a style that is one of the looks: wear the linked one. A mix of the
            // user's own is left as it is.
            if (Config.wallMaterial && root._ready && root.currentKey !== "") root._load()
        }
    }

    // Read from `wornScheme` itself, never from `linkedKey`: this runs inside wornScheme's change signal,
    // and a binding that depends on it may not have followed yet (it would hand back the OLD scheme's link).
    function _load() {
        const key = root.linkFor(root.wornScheme)
        if (key !== "" && key !== root.currentKey) root.apply(key)
    }

    // A link to a scheme that is gone (deleted from the library) is dropped — only once the library
    // has said it has something, so a failed read does not forget every link.
    function _prune() {
        if (ColorScheme.presets.length === 0) return
        const names = ColorScheme.presets.map(p => p.name)
        if (Object.keys(root.links).some(s => names.indexOf(s) < 0))
            root._dropLinks((k, s) => names.indexOf(s) < 0)
    }
}
