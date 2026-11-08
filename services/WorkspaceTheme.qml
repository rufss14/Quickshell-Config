pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../config"
import "contagion.js" as Kinds
import "workspacetheme.js" as Plan

// ── WorkspaceTheme ────────────────────────────────────────────────────────────
// A workspace with its own wallpaper (Config.wallWorkspaces, services/Wallpaper) wears
// that wallpaper's colours: the APPS on it always, the shell while you're on it. So does one
// with its own colour SCHEME (Config.schemeWorkspaces, services/ColorScheme), which outranks the
// wallpaper's colours — the picture stays, the colours are the scheme's. Every source is the
// same thing to the rest of this file: a VALUE ("/path", "scene:<id>", "scheme:<name>" or "album") and
// a palette made for it — a picture's by extraction, the others from the colours they already hold.
// The ALBUM's (AlbumScheme under a scope narrower than "all") outranks both, on the workspaces its
// scope names — a chosen set, or wherever Spotify's window is — and changes every track.
//
// ── Fast and clean: nothing here runs the theming pipeline ────────────────────
// (The first cut ran apply-wallpaper.sh per switch — a palette commit and the whole
// 1.7s frozen wave each time; the user: "no rough reloads".)
//   · the picture: WallpaperView reads Wallpaper.pictureFor(its monitor's workspace)
//     and crossfades — per screen, no script;
//   · the palettes: made AHEAD (scripts/workspace-theme.py palette — the very palette
//     apply-wallpaper.sh would make, built into a private cache, never committed): every
//     assigned picture, and the picture you click in the picker the moment you click it,
//     so Apply finds it ready;
//   · the shell, PER SCREEN: each monitor's bar, panels, OSD, widgets wear the palette
//     of the workspace THAT monitor shows (`Colors.screenOverlays`, screen name →
//     palette; config/PaletteRoles per screen, read through `Colors.of(QsWindow.window)`
//     — in memory, under the album scheme). The mouse crossing monitors changes nothing.
//     A palette not ready yet is NOT stood in for by the shared one — that screen keeps
//     what it wears until it lands (the stand-in was the "whole shell changes, then
//     adapts" flash);
//   · the apps: every window wears the palette of the workspace it's ON, whether or
//     not you're looking at it (workspacetheme.js `plan`, `bun scripts/test-
//     workspacetheme.js`) — borders by `set_prop`, terminals by pywal's sequences to
//     their shells' ptys only (workspace-theme.py terminals), Discord and Spotify from
//     that palette (scripts/workspace-apps.sh, the wave's own apps-lib functions). Re-
//     planned when the assignments or a palette change, a window opens or moves, or a
//     wave has recoloured everything to the shared palette; a switch needs nothing.
//     Browsers (Pywalfox reads only the live palette) and GTK/Qt (one system theme)
//     keep the shared colours.
//
// Diagnose: `qs ipc -c ~/.config/quicktest call wstheme status` (counts only).
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // Wallpapers only theme while Config.wallTheming is on; a scheme is the user's own choice of colours.
    readonly property bool wallActive: Wallpaper.perWorkspace && Config.wallTheming
    // The album is being placed on some workspaces (not the whole shell).
    readonly property bool albumOn: AlbumScheme.scoped && AlbumScheme.active && AlbumScheme.scopedPalette !== null
    readonly property bool active: root.wallActive || ColorScheme.perWorkspace || root.albumOn
    readonly property int settleMs: 250
    readonly property string livePalette:
        (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/wal/colors.json"

    // ── Palettes, made ahead ──────────────────────────────────────────────────
    // "<value>|<mode>" → { file, palette, src? } (`src`: the scheme's colours it was made from)
    property var palettes: ({})
    function _key(v) { return v + "|" + Config.themeMode }
    function entryFor(v) { return v !== "" ? (root.palettes[root._key(v)] ?? null) : null }
    // A value whose palette is ALREADY known as colours (a scheme, the album) rather than extracted.
    function _isJson(v) { return v === "album" || v.indexOf("scheme:") === 0 }
    // What such a palette is made from now ("" = it has gone).
    function _src(v) {
        const p = v === "album" ? AlbumScheme.scopedPalette : ColorScheme.schemePalette(v.slice(7))
        return p ? JSON.stringify(p) : ""
    }
    // Is the entry for `v` current? A picture's is until the committed palette moves (that remakes
    // it, `force`); a scheme's or the album's is until its colours change (saved over, the mode
    // flipped, the next track).
    function _fresh(v) {
        const e = root.entryFor(v)
        return !!e && (!root._isJson(v) || e.src === root._src(v))
    }

    // ── Spotify's workspace, for the album's "spotify" scope ──────────────────
    // Read from the `hyprctl clients` this file already runs on window events (-1 = no window).
    property int _spotifyWs: -1
    readonly property int spotifyWorkspace: root._spotifyWs
    readonly property bool _watchSpotify: Config.albumScheme && Config.albumScope === "spotify"
    // The workspaces the album is on now.
    function _albumTargets() {
        if (!root.albumOn) return []
        if (Config.albumScope === "spotify") return root._spotifyWs > 0 ? [root._spotifyWs] : []
        return Config.albumWorkspaces
    }

    // What a workspace's colours come from — a VALUE — or "": its scheme, else its wallpaper's.
    function _valueFor(ws) {
        if (root._albumTargets().indexOf(ws) >= 0) return "album"
        const sch = ColorScheme.schemeFor(ws)
        if (sch) return "scheme:" + sch.name
        return root.wallActive ? Wallpaper.wallFor(ws) : ""
    }
    // A scheme is assigned but the library hasn't been listed yet: not "no scheme" — hold what is worn.
    function _schemeUnknown(ws) { return !ColorScheme.presetsReady && (String(ws) in Config.schemeWorkspaces) }

    // The palette file a workspace's windows wear ("" = the shared one, or not ready).
    function fileFor(ws) {
        if (!root.active) return ""
        const e = root.entryFor(root._valueFor(ws))
        return e ? e.file : ""
    }

    // ── Scenes: what each screen's renderer should play ───────────────────────
    // screen → the scene its workspace's own wallpaper is, or "" for a picture of its
    // own; a screen whose workspace has none isn't listed (it follows the shared
    // wallpaper). WallpaperEngine relaunches its renderer when this settles on a new map.
    // Independent of theming: a scene is a picture first.
    function _sceneScreens() {
        const map = {}
        if (!Wallpaper.perWorkspace) return map
        for (const m of Hyprland.monitors.values) {
            const name = m?.name ?? ""
            if (name === "") continue
            const own = Wallpaper.wallFor(m.activeWorkspace?.id ?? -1)
            if (own === "") continue
            const sid = Wallpaper.sceneOf(own)
            // A scene that plays from a window of its own (ScenePreload) is drawn by
            // WallpaperView; to the layer renderer that screen is a picture screen.
            map[name] = (sid !== "" && ScenePreload.usable(sid)) ? "" : sid
        }
        return map
    }

    // ── The shell, per screen ─────────────────────────────────────────────────
    // Recomputed imperatively — on workspace events, palettes landing, assignments —
    // never as a binding over Hyprland.monitors (a lazy model that re-enters a binding
    // reading it; see CLAUDE.md's API caution).
    function _wear() {
        const next = {}
        const want = []
        for (const m of Hyprland.monitors.values) {
            const name = m?.name ?? ""
            if (name === "") continue
            const ws = m.activeWorkspace?.id ?? -1
            if (root._schemeUnknown(ws)) {                 // the library isn't listed yet: keep what it wears
                if (Colors.screenOverlays[name]) next[name] = Colors.screenOverlays[name]
                continue
            }
            const pic = root.active ? root._valueFor(ws) : ""
            if (pic === "") continue                       // the shared palette
            const e = root.entryFor(pic)
            // A stale one is still worn until the new one lands (a scheme saved over).
            if (e) next[name] = e.palette
            else if (Colors.screenOverlays[name]) next[name] = Colors.screenOverlays[name]
            if (!root._fresh(pic)) want.push(pic)
        }
        if (want.length > 0) root._prepare(want)
        if (JSON.stringify(next) !== JSON.stringify(Colors.screenOverlays)) Colors.screenOverlays = next
        const scenes = root._sceneScreens()
        if (JSON.stringify(scenes) !== JSON.stringify(WallpaperEngine.workspaceScreens))
            WallpaperEngine.workspaceScreens = scenes
    }
    Timer { id: wearSoon; interval: 1; onTriggered: root._wear() }
    Connections {
        target: ScenePreload
        function onVersionChanged() { wearSoon.restart() }
    }
    // Hyprland's rawEvent arrives BEFORE Quickshell has updated the monitor's
    // activeWorkspace, so a _wear() run straight off the event read the old workspace —
    // and a monitor that isn't the focused one has no later event to correct it (the
    // focused one gets a focusedmonv2). So each monitor's own activeWorkspace is
    // watched too: the value changing is the fact, the event only a hint.
    Instantiator {
        model: Hyprland.monitors
        delegate: QtObject {
            required property var modelData
            property Connections watch: Connections {
                target: modelData
                function onActiveWorkspaceChanged() { wearSoon.restart(); root._dressSoon() }
            }
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = event.name
            if (n === "workspacev2" || n === "focusedmonv2" || n === "moveworkspacev2"
                || n === "monitoraddedv2" || n === "monitorremovedv2" || n === "createworkspacev2")
                wearSoon.restart()
            if (n === "openwindow" || n === "movewindowv2" || n === "closewindow") root._dressSoon()
        }
    }

    // ── Making them ───────────────────────────────────────────────────────────
    function _prepareAll(force) {
        const paths = []
        if (Config.wallTheming)
            for (const k in Config.wallWorkspaces) {
                const p = Config.wallWorkspaces[k]
                if (typeof p === "string" && paths.indexOf(p) < 0) paths.push(p)
            }
        for (const k in Config.schemeWorkspaces) {
            const v = "scheme:" + Config.schemeWorkspaces[k]
            if (paths.indexOf(v) < 0) paths.push(v)
        }
        root._prepare(paths, force === true)
    }
    property var _queue: []
    // `force`: make a PICTURE's again even if one is known (the committed palette moved) — the
    // old one stays worn until the new one lands. A scheme's is remade only when its colours differ.
    function _prepare(paths, force) {
        for (const p of paths)
            if (p && (root._isJson(p) ? !root._fresh(p) : (force || !root.palettes[root._key(p)]))
                && root._queue.indexOf(p) < 0) root._queue.push(p)
        root._next()
    }
    // A value is a picture's path or "scene:<id>" — a scene's colours come from its
    // Workshop preview, keyed "scene_<id>" so a palette saved for it wins (as the
    // scene palette apply-wallpaper.sh makes for the shared one).
    function _next() {
        if (paletteProc.running || root._queue.length === 0) return
        const v = root._queue.shift()
        if (root._isJson(v)) {
            // Colours it already holds: no extraction, just a file for the apps to be told about.
            const src = root._src(v)
            if (src === "") { Qt.callLater(root._next); return }
            paletteProc.target = v
            paletteProc.image = "json"
            paletteProc.mode = Config.themeMode
            paletteProc.src = src
            paletteProc.command = ["python3", Quickshell.shellPath("scripts/workspace-theme.py"), "palette-json"]
            paletteProc.running = true
            return
        }
        const scene = Wallpaper.sceneOf(v)
        const image = scene !== "" ? (WallpaperEngine.itemFor(scene)?.preview ?? "") : v
        if (image === "") { Qt.callLater(root._next); return }
        paletteProc.target = v
        paletteProc.image = image
        paletteProc.mode = Config.themeMode
        paletteProc.src = ""
        paletteProc.command = ["python3", Quickshell.shellPath("scripts/workspace-theme.py"), "palette", image]
            .concat(Config.themeMode === "light" ? ["--light"] : [])
            .concat(scene !== "" ? ["--key", "scene_" + scene] : [])
        paletteProc.running = true
    }
    Process {
        id: paletteProc
        property string target: ""
        property string image: ""
        property string mode: ""
        // A scheme's colours as JSON, handed over the environment (not argv: it would be in `ps`).
        property string src: ""
        environment: ({ "WS_PALETTE": paletteProc.src })
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null
                try { r = JSON.parse(text.trim().split("\n").pop()) } catch (e) {}
                if (r && r.file && r.palette && r.image === paletteProc.image) {
                    const m = Object.assign({}, root.palettes)
                    m[paletteProc.target + "|" + paletteProc.mode] = { file: r.file, palette: r.palette, src: paletteProc.src }
                    root.palettes = m
                    root._wear()
                    root._dressSoon()
                } else {
                    console.warn("WorkspaceTheme: no palette for", paletteProc.target.split("/").pop(),
                                 "—", r && r.error ? r.error : "no answer")
                }
                Qt.callLater(root._next)
            }
        }
    }

    // A picture clicked in the picker: made now, so Apply finds it ready.
    Connections {
        target: Wallpaper
        function onPendingChanged() { if (Wallpaper.pending !== "" && Config.wallTheming) root._prepare([Wallpaper.pending]) }
    }
    // wallFor() only answers once the library has loaded.
    Connections {
        target: Wallpaper
        function onWallpapersChanged() { wearSoon.restart(); root._dressSoon() }
    }
    Connections {
        target: WallpaperEngine
        function onItemsChanged() { wearSoon.restart(); root._dressSoon() }
    }
    Connections {
        target: Config
        function onWallWorkspacesChanged() { root._prepareAll(); root._wear(); root._dressSoon() }
        function onSchemeWorkspacesChanged() { root._prepareAll(); root._wear(); root._dressSoon() }
        function onAlbumWorkspacesChanged() { wearSoon.restart(); root._dressSoon() }
        function onAlbumScopeChanged() { wearSoon.restart(); root._dressSoon() }
        function onThemeModeChanged() { root._prepareAll() }
    }
    // The album: a new track (or it starting, stopping, or being re-scoped) changes what it is, and who it is for.
    Connections {
        target: AlbumScheme
        function onScopedPaletteChanged() { wearSoon.restart(); root._dressSoon() }
        function onScopedChanged() { wearSoon.restart(); root._dressSoon() }
    }
    // A scheme saved over, renamed or deleted, and the library arriving: the entries are re-checked
    // against the colours the schemes hold now.
    Connections {
        target: ColorScheme
        function onPresetsChanged() { root._prepareAll(); wearSoon.restart(); root._dressSoon() }
    }
    // The committed palette moved (your held colours, a new shared wallpaper): remade.
    Connections {
        target: Colors
        function onFileDataChanged() { invalidate.restart() }
    }
    Timer {
        id: invalidate
        interval: 600
        onTriggered: root._prepareAll(true)
    }
    onActiveChanged: { root._prepareAll(); root._wear(); root._dressSoon() }
    Component.onCompleted: { root._prepareAll(); root._wear(); if (root._watchSpotify) root._dressSoon() }

    // ── The apps ──────────────────────────────────────────────────────────────
    // What each window / terminal / app wears now (workspacetheme.js `plan`).
    property var _wears: ({})
    function _dressSoon() { settle.restart() }
    Timer {
        id: settle
        interval: root.settleMs
        onTriggered: {
            // Nothing to dress and nothing wearing anything: nothing to ask — unless the album is set to
            // follow Spotify's workspace, which has to be found even while nothing is playing.
            if (!root.active && Object.keys(root._wears).length === 0 && !root._watchSpotify) return
            if (WallWave.active) { settle.restart(); return }    // a real change is running
            clientsProc.running = false
            clientsProc.running = true
        }
    }
    // A real wallpaper change recoloured everything to the committed palette.
    Connections {
        target: WallWave
        function onSettledChanged() {
            if (!WallWave.settled) return
            root._wears = ({})
            root._dressSoon()
        }
    }

    Process {
        id: clientsProc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector { onStreamFinished: root._dress(text) }
    }

    function _bordersOf(file) {
        const e = Object.values(root.palettes).find(x => x.file === file)
        const pal = (e ? e.palette.colors : Colors.fileData.colors) ?? {}
        return { active: Kinds.borderValue(pal["color" + Blend.v.border_active_wal]),
                 inactive: Kinds.borderValue(pal["color" + Blend.v.border_inactive_wal]) }
    }

    function _dress(json) {
        let list
        try { list = JSON.parse(json) } catch (e) { return }
        if (!Array.isArray(list)) return
        // Where Spotify is, for the album's "spotify" scope. A move changes who the album is for, so the
        // shell is re-placed too (and this plan, once it has, runs on the new answer).
        const sp = list.find(c => Kinds.kind(String(c?.["class"] || "").toLowerCase(), []) === "spotify")
        const sws = sp && sp.workspace && typeof sp.workspace.id === "number" && sp.workspace.id > 0 ? sp.workspace.id : -1
        if (sws !== root._spotifyWs) {
            root._spotifyWs = sws
            wearSoon.restart()
            root._dressSoon()
            return
        }
        const p = Plan.plan(list, ws => root.fileFor(ws), root.livePalette, root._wears, Discord.windowClasses)
        root._wears = p.wears
        for (const b of p.borders) {
            const c = root._bordersOf(b.file)
            const sel = "address:" + b.address
            if (c.active !== "")
                Hyprland.dispatch(`hl.dsp.window.set_prop({ prop = "active_border_color", value = "${c.active}", window = "${sel}" })`)
            if (c.inactive !== "")
                Hyprland.dispatch(`hl.dsp.window.set_prop({ prop = "inactive_border_color", value = "${c.inactive}", window = "${sel}" })`)
        }
        for (const file in p.terminals)
            root._run(termProc, ["python3", Quickshell.shellPath("scripts/workspace-theme.py"), "terminals", file]
                                .concat(p.terminals[file].map(String)))
        for (const file in p.apps)
            root._run(appsProc, ["bash", Quickshell.shellPath("scripts/workspace-apps.sh"), file].concat(p.apps[file]))
    }

    // One of each at a time, the rest queued in order (never killed: Vencord's theme
    // must not be left half-written).
    function _run(proc, argv) {
        if (proc.running) { proc.queue = proc.queue.concat([argv]); return }
        proc.command = argv
        proc.running = true
    }
    function _after(proc) {
        if (proc.queue.length === 0) return
        const a = proc.queue[0]
        proc.queue = proc.queue.slice(1)
        root._run(proc, a)
    }
    Process {
        id: termProc
        property var queue: []
        onExited: root._after(termProc)
    }
    Process {
        id: appsProc
        property var queue: []
        stdout: SplitParser { onRead: line => { if (line.indexOf("|fail|") > 0) console.warn("WorkspaceTheme:", line) } }
        onExited: root._after(appsProc)
    }

    IpcHandler {
        target: "wstheme"
        function status(): string {
            return "active=" + root.active + " screensWearingOwn=" + Object.keys(Colors.screenOverlays).length
                 + " palettes=" + Object.keys(root.palettes).length
                 + " albumOn=" + root.albumOn + " albumWs=" + root._albumTargets().join(",") + " spotifyWs=" + root._spotifyWs
                 + " queued=" + root._queue.length + " dressed=" + Object.keys(root._wears).length
        }
    }
}
