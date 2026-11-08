pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "workspacetheme.js" as WsJs
import "wallpaperlib.js" as Lib

// ── Wallpaper ─────────────────────────────────────────────────────────────────
// The wallpaper library, and applying one.
//
// ── Why this is a singleton and not part of the panel ─────────────────────────
// Applying a wallpaper repaints fourteen applications and takes several seconds. It used
// to be a `Process` living inside WallpaperPanel, so closing the panel mid-apply killed
// the run — leaving the palette half-written, some apps recoloured and some not. The run
// belongs to the shell, not to a popup that happens to be open. Same reasoning as Updates.
//
// ── The pipeline is a SCRIPT, not a string built here ─────────────────────────
// It used to be ~110 lines of bash concatenated in QML with Python heredocs inside it.
// That could not be read, could not be run on its own to debug, and interpolated the
// filename into shell — so an apostrophe in a wallpaper name broke it. It's now
// `scripts/apply-wallpaper.sh`, which reports progress in a small line protocol.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── The library ───────────────────────────────────────────────────────────
    readonly property var  wallpapers: root._wallpapers
    readonly property bool scanning:   listProc.running
    readonly property string current:  root._current

    // ── The current wallpaper's full path ─────────────────────────────────────
    // `current` is only the FILENAME, because that is what the marker file records.
    // Resolving it against the library was already being done inline in `repalette()`;
    // it is a property now because the desktop's glass needs the actual file to sample,
    // and two copies of the same lookup is how they drift.
    //
    // Empty when the library has not loaded yet, or when the name does not match
    // anything in it — which is the normal state while Wallpaper Engine is driving a
    // video, since there is then no still image to point at. Consumers must treat "" as
    // "no wallpaper texture available" rather than as an error.
    readonly property string currentPath: {
        if (root._current === "") return ""
        return root.wallpapers.find(p => p.split("/").pop() === root._current) ?? ""
    }

    // File time per path (epoch seconds), read by the same `find` — the gallery's "newest" order.
    readonly property var  mtimes: root._mtimes
    property var    _mtimes: ({})
    property var    _wallpapers: []
    property string _current: ""

    // ── pywal, the one hard dependency of the theming pipeline ────────────────
    // apply-wallpaper.sh and reload-theme.sh both call `wal`; without it the
    // palette step fails and nothing downstream runs. It is an AUR package
    // (python-pywal16), so — like every other optional tool — a missing one
    // disables the action with a reason rather than failing on click. Same
    // blocker() contract as WallpaperEngine / NightLight.
    property bool _walOk: true      // optimistic until the probe answers
    readonly property bool pywalReady: root._walOk
    function pywalBlocker() {
        return root._walOk ? "" : "pywal isn't installed — the palette can't be "
             + "extracted. Install it: yay -S python-pywal16"
    }
    property Process _walProbe: Process {
        running: true
        command: ["bash", "-c", "command -v wal >/dev/null 2>&1 && echo 1 || echo 0"]
        stdout: StdioCollector {
            onStreamFinished: { root._walOk = text.trim() === "1"; root._walProbed = true }
        }
    }

    // ── Resolving the configured paths ────────────────────────────────────────
    // The one place that turns Config's preferences into real paths. Everything else
    // — the scan below, the apply script's arguments, ColorScheme.regenerate() — goes
    // through these rather than rebuilding `$HOME/wallpapers/...` for itself, which is
    // how the three copies that used to exist drifted from each other.
    //
    // `env("HOME")` is a QVariant and is `undefined` when unset, never "" — so it
    // needs the `|| ""` idiom the rest of the repo uses, not a truthiness test that
    // would concatenate the string "undefined" into a path and then silently find
    // nothing there.
    readonly property string _home: Quickshell.env("HOME") || ""

    // Expands a leading `~`, so a hand-typed "~/pictures/walls" in the settings field
    // works the way the user expects instead of looking for a directory literally
    // named "~". Anything else is passed through untouched: an absolute path is
    // already what we want, and a relative one is the user's business.
    function _expand(p) {
        if (!p) return ""
        if (p === "~")             return root._home
        if (p.startsWith("~/"))    return root._home + p.slice(1)
        return p
    }

    // Where the gallery scans. "" in Config means the default layout.
    readonly property string libraryDir:
        root._expand(Config.wallLibraryDir) || (root._home + "/wallpapers/walls")

    // The stable copy for tools outside the shell. See Config.wallExportPath.
    readonly property string exportPath:
        root._expand(Config.wallExportPath) || (root._home + "/wallpapers/pywallpaper.jpg")

    // Kept as the old name so nothing outside had to change when this became
    // configurable; `libraryDir` is what new code should say.
    readonly property string wallpaperDir: root.libraryDir

    function rescan() {
        if (listProc.running) return
        listProc._rows = []
        listProc._times = ({})
        listProc.running = true
    }

    // Pointing the library somewhere else has to re-scan. `listProc.command` is bound to
    // the directory, so it would pick the new path up on its own — but only at its NEXT
    // run, which nothing was triggering. Without this the gallery kept showing the old
    // directory's files until something else happened to rescan, and clicking one of
    // them applied a wallpaper from a library the user had just navigated away from.
    onLibraryDirChanged: root.rescan()

    Process {
        id: listProc
        running: true
        // -print0 would be safer still, but SplitParser splits on newline; a wallpaper
        // filename containing a newline is not a case worth carrying complexity for, and
        // `find` output is consumed as whole lines.
        command: ["find", root.wallpaperDir, "-type", "f",
                  "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg",
                       "-o", "-iname", "*.png", "-o", "-iname", "*.gif", ")",
                  "-printf", "%T@\t%p\n"]

        property var _rows: []
        property var _times: ({})

        stdout: SplitParser {
            onRead: function(line) {
                const r = Lib.parseFindRow(line)
                if (r === null) return
                listProc._rows = listProc._rows.concat([r.p])
                listProc._times[r.p] = r.t
            }
        }

        // Sorted HERE rather than by piping through `sort`, which is what the old version
        // did: one process instead of two, and it sorts by the visible name rather than by
        // full path, which is what the gallery is ordered by.
        onExited: function(code) {
            const rows = listProc._rows.slice()
            rows.sort((a, b) => a.split("/").pop().localeCompare(b.split("/").pop()))
            root._wallpapers = rows
            root._mtimes = listProc._times
            listProc._times = ({})
            listProc._rows = []
            root._scanned = true
            prefetchDelay.restart()
        }
    }

    // ── Palettes ahead of time ────────────────────────────────────────────────
    // A picture pywal has never seen costs its whole extraction at apply time — 1.4s
    // for a 1080p PNG, 3.2s for a 5.6K JPEG here — before the wave can start. A cached
    // one is ~0.1s, and the cache is pywal's own, so scripts/palette-prefetch.py fills
    // it for the library at idle: the exact entry `wal -i` would write, full-res (the
    // user's call: a downscaled proxy shifted palettes), skipping what's cached.
    // Lowest CPU and IO priority, ImageMagick held to one thread, never while a change
    // is in flight; once per library scan and per light/dark mode.
    Timer {
        id: prefetchDelay
        interval: 5000
        onTriggered: root._prefetch()
    }
    Connections {
        target: Config
        function onThemeModeChanged() { prefetchDelay.restart() }
    }
    function _prefetch() {
        if (!Config.wallTheming || root._wallpapers.length === 0 || prefetchProc.running) return
        if (runnerInstance.running || WallWave.active) { prefetchDelay.restart(); return }
        prefetchProc._done = 0
        prefetchProc.command = ["bash", "-c",
            'printf "%s\\n" "${@:3}" | MAGICK_THREAD_LIMIT=1 nice -n 19 '
            + '$(command -v ionice >/dev/null && echo ionice -c 3) python3 "$1" $2',
            "_", Quickshell.shellPath("scripts/palette-prefetch.py"),
            Config.themeMode === "light" ? "--light" : ""].concat(root._wallpapers)
        prefetchProc.running = true
    }
    Process {
        id: prefetchProc
        property int _done: 0
        stdout: SplitParser { onRead: prefetchProc._done++ }
        stderr: SplitParser { onRead: function(line) { console.warn("Wallpaper:", line) } }
        onExited: if (prefetchProc._done > 0)
            console.info("Wallpaper: prefetched", prefetchProc._done, "palette(s) for the library")
    }

    // Which one is active. Written by the apply script; read here so the gallery can mark
    // it, and so the mark survives a shell restart (the old panel had no idea).
    FileView {
        id: currentFile
        // XDG_CACHE_HOME, not a literal ~/.cache — same idiom as Clipboard/Updates/
        // Storage, and the apply script writes it to exactly this resolution.
        path: (Quickshell.env("XDG_CACHE_HOME") || (root._home + "/.cache"))
              + "/current_wallpaper_name"
        watchChanges: true
        onFileChanged: currentFile.reload()
        onLoaded: { root._current = currentFile.text().trim(); root._currentSettled = true }
        // No marker: nothing has ever been applied. Settled all the same — the palette
        // bootstrap below waits on this to tell "not read yet" from "there is none".
        onLoadFailed: root._currentSettled = true
    }

    // ── Applying ──────────────────────────────────────────────────────────────
    // All of the run/parse/restart/notify machinery lives in ThemeRunner, shared with the
    // colour-scheme editor. This used to be its own copy of the same ~120 lines, which is
    // how the two halves of the theming pipeline drifted apart in the first place.
    //
    // The properties below are aliases onto the runner, so WallpaperPanel binds to the same
    // names it always did.
    ThemeRunner {
        id: runnerInstance
        appName: "Wallpaper"
        icon: "wallpaper"

        onFinished: function(code) {
            const name = root._applyingPath.split("/").pop()

            // The palette bootstrap's run on a fresh install: ~/.cache/wal did not exist,
            // so the FileView's directory watch never armed and inotify will not report
            // the new colors.json. Ask for it.
            if (Colors.fileState !== "ok") Colors.reload()

            // The scene still has to go if its water never landed (a later change took
            // the channel over) — the run is long past the water by now.
            if (root._stopSceneOnLanding > 0) {
                root._stopSceneOnLanding = -1
                if (WallpaperEngine.running) WallpaperEngine.stop()
            }

            // Re-read who's current rather than trusting the file watcher alone. We know
            // exactly when it changes — the run just ended — and an inotify watch on a file
            // rewritten by another process can be missed depending on how it was written.
            currentFile.reload()

            // Reports what actually happened rather than a flat "applied!". The pipeline
            // this replaced chained every step with `|| true`, so it claimed success even
            // when a step had failed — which is how GTK theming stayed broken for a month
            // without anyone being told. `failed` (not raw `code`) so a run that finished
            // its work and then tripped a late non-zero exit isn't reported as a failure —
            // see ThemeRunner.onExited.
            if (runnerInstance.failed && runnerInstance.failedCount === 0)
                runnerInstance.notify("Wallpaper failed", "Could not apply " + name + ".", "critical")
            else if (runnerInstance.failedCount > 0)
                runnerInstance.notify("Wallpaper applied, partly",
                              name + " is set, but " + runnerInstance.failedCount + " app"
                              + (runnerInstance.failedCount !== 1 ? "s" : "") + " could not be "
                              + "recoloured. Open the wallpaper panel for details.", "normal")
            else
                runnerInstance.notify("Wallpaper applied",
                              name + " is set and everything recoloured.", "low")

            if (root._queued !== "") {
                const next = root._queued
                root._queued = ""
                Qt.callLater(() => root.apply(next))
            }
        }
    }

    // ── IPC ───────────────────────────────────────────────────────────────────
    // `qs ipc -c ~/.config/quicktest call wallpaper apply <path>` — the same apply as
    // the gallery (a keybind, a script, a timing run). `status` is states only.
    IpcHandler {
        target: "wallpaper"
        function apply(path: string): string {
            if (!path || path[0] !== "/") return "an absolute path, please"
            root.apply(path)
            // Not `applying`: Process.running only turns true once the child has started.
            return root._queued === path ? "queued behind the current change"
                 : root._applyingPath === path ? "applying " + path.split("/").pop()
                 : "not applied (paused by Game Mode?)"
        }
        // `qs ipc … call wallpaper theme light|dark` — the launcher's Theme action, for a
        // keybind or a script: the mode, then the palette re-derived in it.
        function theme(mode: string): string {
            if (mode !== "light" && mode !== "dark") return "light or dark, please"
            if (Config.themeMode === mode) return "already " + mode
            ColorScheme.switchMode(mode)
            return "switching to " + mode
        }
        function status(): string {
            return "current=" + root.current + " applying=" + root.applying
                 + " queued=" + (root._queued !== "") + " library=" + root._wallpapers.length
                 + " ownWallpapers=" + root.marked.length + " choosing=" + (root.pending !== "")
                 + " prefetching=" + prefetchProc.running
        }
    }

    // ── Switching renderer at runtime ────────────────────────────────────────
    // shell → awww: the daemon has never been told the current picture, so hand
    // it over — WITHOUT re-running the palette, which hasn't changed. shell is the
    // other direction and needs nothing: WallpaperView binds currentPath.
    Connections {
        target: Config
        function onWallShellRenderChanged() {
            if (Config.wallShellRender) return
            if (root.currentPath === "" || runnerInstance.running) return
            runnerInstance.run(["bash", Quickshell.shellPath("scripts/apply-wallpaper.sh"),
                                "--no-theme", root.currentPath], "Handing the wallpaper to awww")
        }
    }

    // Exposed so the panel (and tests) can reach the shared machinery directly, matching
    // ColorScheme. The aliases below stay because the panel has always used these names.
    readonly property ThemeRunner runner: runnerInstance

    readonly property bool applying:    runnerInstance.running
    readonly property var  steps:       runnerInstance.steps
    readonly property bool lastFailed:  runnerInstance.failed
    readonly property int  failedCount: runnerInstance.failedCount
    readonly property var  restartApps: runnerInstance.restartApps
    readonly property bool needsRestart: runnerInstance.needsRestart
    readonly property string applyingPath: root._applyingPath

    property string _applyingPath: ""
    property string _queued: ""

    function clearResult()   { runnerInstance.clearResult() }
    function dismissRestart(){ runnerInstance.dismissRestart() }
    function restartAll()    { runnerInstance.restartAll() }

    // ── The transition ───────────────────────────────────────────────────────
    // A new wallpaper arrives as water from the bottom middle, with the new colours
    // eating the old look off the shell on the same front (services/WallWave.qml,
    // driven through ThemeRunner). It replaced a light band that swept the bar,
    // frame and widgets left to right while the colours simply snapped.

    // A scene running under a change to a still is stopped only once the water
    // covers the screen: stopped first, the old still under it flashed through the
    // gap before the new picture arrived. The token whose landing stops it:
    property int _stopSceneOnLanding: -1
    // …and so is the Material Wallpaper (below): a picture chosen over it arrives as water OVER
    // the shapes, which only go once the water has covered them.
    property int _materialOffOnLanding: -1
    Connections {
        target: WallWave
        function onLanded(token) {
            if (token === root._materialOffOnLanding) {
                root._materialOffOnLanding = -1
                Config.wallMaterial = false
            }
            if (token !== root._stopSceneOnLanding) return
            root._stopSceneOnLanding = -1
            if (WallpaperEngine.running) WallpaperEngine.stop()
        }
    }

    // ── The Material Wallpaper (Config.wallMaterial) ─────────────────────────────
    // A third kind of wallpaper beside pictures and scenes, drawn by WallpaperView
    // (components/MaterialWallpaper). It is ON or OFF as a whole, and the last thing applied wins:
    //   · applyMaterial() stops a running scene, forgets the workspaces' own pictures and turns
    //     autostart off (so a scene does not come back over it at the next login) — the same three
    //     things choosing a still image does;
    //   · a picture applied over it takes it off as its water lands (_materialOffOnLanding);
    //   · a scene starting takes it off (the Connections below), so the flag is never left on under
    //     something that covers it.
    function materialBlocker() {
        if (!Config.wallShellRender) return "Needs the shell to draw the wallpaper — Settings › Wallpaper › Drawn by"
        if (Gamemode.wallpaperPaused) return "Paused for Game Mode"
        return ""
    }
    function applyMaterial() {
        if (root.materialBlocker() !== "") return
        root._remember("material")
        if (root.perWorkspace) Config.wallWorkspaces = ({})
        Config.wpeAutoStart = false
        Config.wallMaterial = true
        if (WallpaperEngine.running) WallpaperEngine.stop()
    }
    Connections {
        target: WallpaperEngine
        function onRunningChanged() { if (WallpaperEngine.running) Config.wallMaterial = false }
    }

    // Suppressed the same way WallpaperEngine.apply() is: while Gamemode is
    // holding the wallpaper paused, a public apply() queues instead of running —
    // otherwise this function's own job (stopping the scene renderer so the
    // image actually wins, see below) would silently UNDO the pause the instant
    // anything called it, whether that's a panel click or Wallpaper's own
    // periodic shuffle timer. Gamemode's own restore bypasses this via
    // `_applyNow` once it's actually time to apply the queued pick.
    function apply(path) {
        if (Gamemode.wallpaperPaused) { Gamemode.queueImage(path); return }
        root._remember(path)
        root._applyNow(path)
    }

    // ── Undo ──────────────────────────────────────────────────────────────────────
    // What was on screen before the last change made from here (a picture, a scene or the Material
    // wallpaper), so a wrong click costs one click and not a hunt through the gallery plus another
    // 7-second theming run. A value like a workspace's own: a path, "scene:<id>" or "material".
    // In memory only — it is for the mistake you just made, not a history. Undoing is itself a change,
    // so it swaps: undo again and you are back. It puts the SHARED wallpaper back; a workspace's own
    // picture that the change forgot (a left click clears them) is not restored.
    property string previous: ""

    function _shownNow() {
        if (WallpaperEngine.running) return WallpaperEngine.current !== "" ? "scene:" + WallpaperEngine.current : ""
        return Config.wallMaterial ? "material" : root.currentPath
    }
    function _remember(target) {
        const now = root._shownNow()
        if (now !== "" && now !== target) root.previous = now
    }
    // Still there to go back to: the picture in the library, the scene installed, Material allowed.
    readonly property bool canUndo: {
        const v = root.previous
        if (v === "") return false
        if (v === "material") return root.materialBlocker() === ""
        const sc = root.sceneOf(v)
        if (sc !== "") return !!WallpaperEngine.itemFor(sc) && WallpaperEngine.blocker() === ""
        return root.wallpapers.indexOf(v) >= 0
    }
    readonly property string previousName: {
        const v = root.previous
        if (v === "") return ""
        if (v === "material") return "Material Wallpaper"
        const sc = root.sceneOf(v)
        return sc !== "" ? WallpaperEngine.titleFor(sc) : v.split("/").pop()
    }
    function undo() {
        if (!root.canUndo) return
        const v = root.previous
        if (v === "material") root.applyMaterial()
        else if (root.sceneOf(v) !== "") root.pickScene(root.sceneOf(v))
        else root.pick(v)
    }

    // ══ A wallpaper per workspace ═════════════════════════════════════════════
    // In the gallery a LEFT click applies a picture or a Wallpaper Engine scene
    // everywhere (and forgets every workspace's own); a RIGHT click (`choose`) makes it
    // `pending` (a path, or "scene:<id>") and the gallery folds into a workspace picker
    // (components/WorkspacePicker) asking which workspaces get it. Those get it as THEIR
    // OWN (Config.wallWorkspaces); the rest keep what they show — the shared wallpaper,
    // applied as always (a picture, or the scene WallpaperEngine plays as the wallpaper). A workspace's own scene is played by WallpaperEngine on the
    // screen showing it (its `workspaceScreens`, set by WorkspaceTheme).
    //
    // Being on a workspace with its own runs NO theming job: WallpaperView shows
    // `pictureFor(its monitor's workspace)` and crossfades, and services/WorkspaceTheme
    // wears that picture's palette (made ahead, in memory) and dresses the apps on it.
    property string pending: ""
    readonly property int pickable: 10        // the workspaces the picker offers (1…10)
    readonly property bool perWorkspace: Object.keys(Config.wallWorkspaces).length > 0
    // The workspaces that have their own picture, sorted.
    readonly property var marked: Object.keys(Config.wallWorkspaces).map(Number)
        .filter(n => n > 0).sort((a, b) => a - b)

    // A workspace's own wallpaper — a path or "scene:<id>" — if it has one AND it's
    // still there (the picture in the library, the scene installed). "" otherwise.
    function wallFor(ws) {
        const v = Config.wallWorkspaces[String(ws)] ?? ""
        const own = WsJs.parseOwn(v)
        if (!own) return ""
        if (own.scene) return WallpaperEngine.itemFor(own.scene) ? v : ""
        return root.wallpapers.indexOf(own.image) >= 0 ? v : ""
    }
    function sceneOf(v) { return WsJs.parseOwn(v)?.scene ?? "" }
    // A picture standing for a wallpaper value: the picture itself, or a scene's still
    // (its first frame, once it has played) / Workshop preview.
    function displayOf(v) {
        const own = WsJs.parseOwn(v)
        if (!own) return ""
        return own.scene ? WallpaperEngine.stillFor(own.scene) || (WallpaperEngine.itemFor(own.scene)?.preview ?? "")
                         : own.image
    }
    // The shared wallpaper as a picture: the shared scene's still, or the image.
    readonly property string sharedPicture: WallpaperEngine.sharedIsScene && Config.wpeCurrent !== ""
        ? root.displayOf("scene:" + Config.wpeCurrent) : root.currentPath
    // What a workspace shows: its own, else the shared one.
    function shownFor(ws) { return root.displayOf(root.wallFor(ws)) || root.sharedPicture }
    // What a screen showing workspace `ws` draws (WallpaperView) — for a scene, the
    // still it shows until the renderer covers that screen.
    function pictureFor(ws) { return root.perWorkspace ? root.shownFor(ws) : root.currentPath }

    // A gallery LEFT click: everywhere — a picture…
    function pick(path) {
        if (!path) return
        if (root.perWorkspace) Config.wallWorkspaces = ({})
        root.apply(path)
    }
    // …or a Wallpaper Engine scene.
    function pickScene(id) {
        if (!id) return
        root._remember("scene:" + id)
        if (root.perWorkspace) Config.wallWorkspaces = ({})
        WallpaperEngine.apply(id)
    }
    // A gallery RIGHT click: choose its workspaces (the picker). `value` is a path or
    // "scene:<id>".
    function choose(value) { if (WsJs.parseOwn(value)) root.pending = value }

    // Is `value` (a path or "scene:<id>") already on EVERY workspace — the shared one,
    // with no workspace showing anything else? Only then has "apply everywhere" nothing
    // left to do (the gallery hides its Apply then).
    function everywhere(value, isShared) {
        if (!isShared) return false
        for (const k in Config.wallWorkspaces)
            if (Config.wallWorkspaces[k] !== value) return false
        return true
    }
    function cancelPick() { root.pending = "" }

    // The picker's Apply: `path` for these workspaces, the rest as they are. Every one
    // of them is the same as a plain pick (the wallpaper everywhere).
    function assign(path, list) {
        root.pending = ""
        const ws = []
        for (const v of list || []) {
            const n = Math.floor(Number(v))
            if (n > 0 && ws.indexOf(n) < 0) ws.push(n)
        }
        if (!WsJs.parseOwn(path) || ws.length === 0) return
        if (ws.length >= root.pickable && ws.every(n => n <= root.pickable)) {
            if (root.perWorkspace) Config.wallWorkspaces = ({})
            const scene = root.sceneOf(path)
            if (scene !== "") WallpaperEngine.apply(scene)
            else root.apply(path)
            return
        }
        const m = Object.assign({}, Config.wallWorkspaces)
        for (const n of ws) m[String(n)] = path
        Config.wallWorkspaces = m
        Config.wallMaterial = false     // a picture for those workspaces: nothing to show them under shapes
    }

    // Every workspace back to the shared picture (the settings page's Reset all).
    function forgetAllWorkspaces() {
        if (root.perWorkspace) Config.wallWorkspaces = ({})
    }

    // A workspace back to the shared picture.
    function forgetWorkspace(ws) {
        if (!(String(ws) in Config.wallWorkspaces)) return
        const m = Object.assign({}, Config.wallWorkspaces)
        delete m[String(ws)]
        Config.wallWorkspaces = m
    }

    function _applyNow(path) {
        if (!path) return
        // ── A pick made mid-run is kept, not dropped ──────────────────────────
        // One theming job at a time; a second click during the first used to do
        // nothing at all. The NEWEST pick waits and runs as the current one finishes.
        if (runnerInstance.running) { root._queued = path; return }

        // ── A static wallpaper must actually WIN ──────────────────────────────
        // The scene renderer draws over the background layer, so setting an image
        // underneath it changes nothing you can see — the old behaviour was that
        // "applying a normal wallpaper doesn't override wallpaperengine", verbatim
        // a bug report. Applying an image stops the renderer — once the new picture's
        // water covers the screen, or at once when there is no water (see
        // _stopSceneOnLanding, below the run). (stop() no-ops if the engine is
        // mid-restart; that race loses a stop, not the wallpaper — the next engine
        // apply is explicit anyway.)
        const sceneUp = WallpaperEngine.running

        // ── ...and STAY won ─────────────────────────────────────────────────
        // Stopping the renderer only holds until the next shell reload: if "Start
        // with the shell" is still on, the autostart timer relaunches the scene a
        // few seconds later, straight back over the image just chosen. That read as
        // "wallpaper engine keeps applying itself without my input". Choosing a still
        // image turns autostart off, so the image survives a login; picking a scene
        // again, or the toggle in Settings, turns it back on. (No-op write when it's
        // already off — QML dedupes equal assignments.) Written AFTER the run is queued
        // and its landing noted (below): a scene that plays from a window of its own is
        // let go by autostart going false, and must stay under the water until it lands.

        root._applyingPath = path
        // A monitor target rides along when set — but only with the awww renderer,
        // which is the thing that honours --output. The shell renderer draws
        // currentPath on every screen. Guarded against a stale name too: a monitor
        // unplugged since the pref was written must not turn every apply into a
        // no-op on a screen that doesn't exist.
        let target = []
        if (!Config.wallShellRender && Config.wallTarget !== "") {
            const alive = [...Quickshell.screens].some(s => s.name === Config.wallTarget)
            if (alive) target = ["--output", Config.wallTarget]
            else Config.wallTarget = ""
        }
        const token = runnerInstance.run(["bash", Quickshell.shellPath("scripts/apply-wallpaper.sh")]
                   .concat(target).concat(root.daemonFlags()).concat(root.modeFlags()).concat(root.exportFlags())
                   .concat([path]),
                   path.split("/").pop(),
                   { image: path,
                     output: target.length > 0 ? Config.wallTarget : "",
                     recolor: Config.wallTheming,
                     // The shell draws it from here on (its water hands over),
                     // unless awww does (its water fades off awww's picture).
                     keep: Config.wallShellRender })
        if (sceneUp) {
            if (token > 0) root._stopSceneOnLanding = token
            else           WallpaperEngine.stop()
        }
        if (Config.wallMaterial) {
            if (token > 0) root._materialOffOnLanding = token
            else           Config.wallMaterial = false
        }
        Config.wpeAutoStart = false
    }

    // Where the script should drop the stable copy. Passed as an argument rather than
    // read from the environment inside the script, so the resolution lives in exactly
    // one place (see exportPath) and the script stays runnable by hand.
    //
    // Only the real apply needs it: `--palette-only` runs don't touch the picture, so
    // they have no copy to make and don't pass this at all.
    function exportFlags() {
        return root.exportPath ? ["--export", root.exportPath] : []
    }

    // With the shell renderer on, the script must NOT hand the picture to awww —
    // modules/desktop/WallpaperView draws it. See apply-wallpaper.sh --no-daemon.
    function daemonFlags() {
        return Config.wallShellRender ? ["--no-daemon"] : []
    }

    // The theming flags travel with EVERY palette run — here and in the
    // scene-palette path — or a toggle would only hold until the next wallpaper
    // change quietly overrode it. Theming off beats everything: the script sets
    // the picture and touches nothing else.
    function modeFlags() {
        if (!Config.wallTheming) return ["--no-theme"]
        return Config.themeMode === "light" ? ["--light"] : []
    }

    // ── Re-derive the palette in the current mode, changing nothing else ──────
    // What the Light/Dark toggle calls: same picture (or same scene), new
    // palette. Routes to whichever thing is actually colouring the shell.
    function reapplyPalette() {
        if (!Config.wallTheming) return
        // A scene gamemode has paused is still the real subject — repalette()
        // already knows how to reach its preview without the process running.
        // wallpaperPaused alone doesn't prove there IS a scene though — a
        // plain static-wallpaper session holds the card too now.
        const pausedSceneId = Gamemode.wallpaperPaused ? Config.wpeCurrent : ""
        if ((WallpaperEngine.running || pausedSceneId !== "") && Config.wpeScenePalette) {
            WallpaperEngine.repalette()
            return
        }
        if (runnerInstance.running) return
        const hit = root.wallpapers.find(p => p.split("/").pop() === root.current)
        if (!hit) return
        root._applyingPath = hit
        runnerInstance.run(["bash", Quickshell.shellPath("scripts/apply-wallpaper.sh"),
                            "--palette-only"].concat(root.modeFlags()).concat([hit]),
                   "Recolouring", { image: "", recolor: true })
    }

    // ── No palette at all: extract one ────────────────────────────────────────
    // The shell never wears a built-in colour scheme. When colors.json is missing or
    // not a palette (a fresh install, a cleared cache), pywal runs on the current
    // wallpaper — reapplyPalette(), the Light/Dark toggle's own path, so the run is the
    // ordinary one with its wave. Once per session, and only once the three things it
    // depends on have SETTLED rather than merely being empty: the library scan, the
    // current-wallpaper marker, the pywal probe. Deciding earlier would read "no
    // wallpaper" off a scan still in flight.
    //
    // When it can't run — pywal missing, nothing ever applied, theming switched off
    // (the user's no to pywal touching anything), or the run fails — the shell stays in
    // PaletteRoles' monochrome fallback. It never needs to be told to: the fallback is
    // what an empty palette already is.
    property bool _scanned: false
    property bool _currentSettled: false
    property bool _walProbed: false
    property bool _bootstrapped: false

    function _bootstrapPalette() {
        if (root._bootstrapped || Colors.fileState !== "missing") return
        if (!root._scanned || !root._currentSettled || !root._walProbed) return
        root._bootstrapped = true
        const why = !Config.wallTheming ? "theming is off"
                  : !root._walOk        ? "pywal isn't installed"
                  : root.currentPath === "" && !WallpaperEngine.running ? "no wallpaper has been applied"
                  : ""
        if (why !== "") {
            console.warn("Wallpaper: no palette and can't extract one (" + why + ") — monochrome")
            return
        }
        console.info("Wallpaper: no palette — extracting one from", root.current || "the scene")
        root.reapplyPalette()
    }
    Connections {
        target: Colors
        function onFileStateChanged() { root._bootstrapPalette() }
    }
    on_ScannedChanged:        root._bootstrapPalette()
    on_CurrentSettledChanged: root._bootstrapPalette()
    on_WalProbedChanged:      root._bootstrapPalette()

    // ── Shuffle ───────────────────────────────────────────────────────────────
    // The slideshow. The timer variant refuses to fire while a scene is running or the
    // Material Wallpaper is on — a timer that silently killed the animated wallpaper you chose
    // would be the shell overruling you on a schedule. The button variant (`force`) is you
    // asking, so it wins over the scene like any explicit image apply.
    function shuffleNow(force) {
        if (runnerInstance.running || root.wallpapers.length === 0) return
        if (!force && (WallpaperEngine.running || Config.wallMaterial)) return
        let pool = root.wallpapers.filter(p => p.split("/").pop() !== root.current)
        // "Favourites only" narrows the draw — but a library with none starred still shuffles.
        if (Config.wallShuffleFavs) {
            const fav = pool.filter(p => Config.wallFavorites.indexOf(p.split("/").pop()) !== -1)
            if (fav.length > 0) pool = fav
        }
        const pick = pool.length > 0
            ? pool[Math.floor(Math.random() * pool.length)]
            : root.wallpapers[0]
        root.apply(pick)
    }

    Timer {
        interval: Math.max(1, Config.wallShuffleMins) * 60 * 1000
        repeat: true
        running: Config.wallShuffle && root.wallpapers.length > 1
        onTriggered: root.shuffleNow(false)
    }

    // ── Importing images ──────────────────────────────────────────────────────
    // zenity is the one graphical picker installed (checked, not assumed). Files
    // are COPIED in — `cp -n`, so an import can never overwrite an existing
    // wallpaper that happens to share a name.
    readonly property bool importing: pickProc.running || copyProc.running

    function importImages() {
        if (root.importing) return
        pickProc._picked = []
        pickProc.running = true
    }

    Process {
        id: pickProc
        command: ["zenity", "--file-selection", "--multiple", "--separator=\n",
                  "--title=Add wallpapers",
                  "--file-filter=Images | *.jpg *.jpeg *.png *.gif *.webp"]

        property var _picked: []

        stdout: SplitParser {
            onRead: function(line) {
                const t = line.trim()
                if (t !== "") pickProc._picked = pickProc._picked.concat([t])
            }
        }

        onExited: function(code) {
            // 1 = the user cancelled the dialog. Not an error, just a no.
            if (code !== 0 || pickProc._picked.length === 0) return
            copyProc.command = ["cp", "-n"].concat(pickProc._picked)
                                           .concat([root.wallpaperDir + "/"])
            pickProc._picked = []
            copyProc.running = true
        }
    }

    // ── Adding images the browser already found ────────────────────────────────
    // The in-page file browser hands us the paths directly (as file:// URLs from
    // FolderListModel, or bare paths), so there's no dialog to open — just the same
    // `cp -n` copy the zenity path ends in. Scheme is stripped once, here, so the
    // browser never has to care. `-n` keeps an import from clobbering a same-named
    // wallpaper already in the library.
    function addPaths(paths) {
        if (root.importing || !paths || paths.length === 0) return
        const files = paths.map(p => String(p).replace(/^file:\/\//, ""))
        copyProc.command = ["cp", "-n"].concat(files)
                                        .concat([root.wallpaperDir + "/"])
        copyProc.running = true
    }

    Process {
        id: copyProc
        onExited: function(code) { root.rescan() }
    }

    // ── Deleting an image ─────────────────────────────────────────────────────
    // `gio trash`, not rm: these are the user's own files, and the Storage page's
    // whole philosophy is that user files get recoverable treatment. The
    // two-step confirm lives in the UI; this just does the deed.
    function remove(path) { root.removeMany([path]) }

    // Several at once (the panel's select mode): one `gio trash` for the lot, and one
    // rescan when it exits. Anything outside the library is dropped, not trusted.
    function removeMany(paths) {
        const ok = (paths || []).filter(p => p && p.startsWith(root.wallpaperDir + "/"))
        if (ok.length === 0 || trashProc.running) return
        trashProc.command = ["gio", "trash"].concat(ok)
        trashProc.running = true
    }

    Process {
        id: trashProc
        onExited: function(code) { root.rescan() }
    }
}
