pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

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

    property var    _wallpapers: []
    property string _current: ""

    readonly property string wallpaperDir: Quickshell.env("HOME") + "/wallpapers/walls"

    function rescan() {
        if (listProc.running) return
        listProc._rows = []
        listProc.running = true
    }

    Process {
        id: listProc
        running: true
        // -print0 would be safer still, but SplitParser splits on newline; a wallpaper
        // filename containing a newline is not a case worth carrying complexity for, and
        // `find` output is consumed as whole lines.
        command: ["find", root.wallpaperDir, "-type", "f",
                  "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg",
                       "-o", "-iname", "*.png", "-o", "-iname", "*.gif", ")"]

        property var _rows: []

        stdout: SplitParser {
            onRead: function(line) {
                const t = line.trim()
                if (t !== "") listProc._rows = listProc._rows.concat([t])
            }
        }

        // Sorted HERE rather than by piping through `sort`, which is what the old version
        // did: one process instead of two, and it sorts by the visible name rather than by
        // full path, which is what the gallery is ordered by.
        onExited: function(code) {
            const rows = listProc._rows.slice()
            rows.sort((a, b) => a.split("/").pop().localeCompare(b.split("/").pop()))
            root._wallpapers = rows
            listProc._rows = []
        }
    }

    // Which one is active. Written by the apply script; read here so the gallery can mark
    // it, and so the mark survives a shell restart (the old panel had no idea).
    FileView {
        id: currentFile
        path: Quickshell.env("HOME") + "/.cache/current_wallpaper_name"
        watchChanges: true
        onFileChanged: currentFile.reload()
        onLoaded: root._current = currentFile.text().trim()
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

            // Re-read who's current rather than trusting the file watcher alone. We know
            // exactly when it changes — the run just ended — and an inotify watch on a file
            // rewritten by another process can be missed depending on how it was written.
            currentFile.reload()

            // Reports what actually happened rather than a flat "applied!". The pipeline
            // this replaced chained every step with `|| true`, so it claimed success even
            // when a step had failed — which is how GTK theming stayed broken for a month
            // without anyone being told.
            if (code !== 0)
                runnerInstance.notify("Wallpaper failed", "Could not apply " + name + ".", "critical")
            else if (runnerInstance.failedCount > 0)
                runnerInstance.notify("Wallpaper applied, partly",
                              name + " is set, but " + runnerInstance.failedCount + " app"
                              + (runnerInstance.failedCount !== 1 ? "s" : "") + " could not be "
                              + "recoloured. Open the wallpaper panel for details.", "normal")
            else
                runnerInstance.notify("Wallpaper applied",
                              name + " is set and everything recoloured.", "low")
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

    function clearResult()   { runnerInstance.clearResult() }
    function dismissRestart(){ runnerInstance.dismissRestart() }
    function restartAll()    { runnerInstance.restartAll() }

    function apply(path) {
        if (runnerInstance.running || !path) return

        // ── A static wallpaper must actually WIN ──────────────────────────────
        // The scene renderer draws over the background layer, so setting an image
        // underneath it changes nothing you can see — the old behaviour was that
        // "applying a normal wallpaper doesn't override wallpaperengine", verbatim
        // a bug report. Applying an image now stops the renderer first. (stop()
        // no-ops if the engine is mid-restart; that race loses a stop, not the
        // wallpaper — the next engine apply is explicit anyway.)
        if (WallpaperEngine.running) WallpaperEngine.stop()

        // ── ...and STAY won ─────────────────────────────────────────────────
        // Stopping the renderer only holds until the next shell reload: if "Start
        // with the shell" is still on, the autostart timer relaunches the scene a
        // few seconds later, straight back over the image just chosen. That read as
        // "wallpaper engine keeps applying itself without my input". Choosing a still
        // image turns autostart off, so the image survives a login; picking a scene
        // again, or the toggle in Settings, turns it back on. (No-op write when it's
        // already off — QML dedupes equal assignments.)
        Config.wpeAutoStart = false

        root._applyingPath = path
        // A monitor target rides along when set. Guarded against a stale name —
        // a monitor that was unplugged since the pref was written must not turn
        // every apply into a no-op on a screen that doesn't exist.
        let target = []
        if (Config.wallTarget !== "") {
            const alive = [...Quickshell.screens].some(s => s.name === Config.wallTarget)
            if (alive) target = ["--output", Config.wallTarget]
            else Config.wallTarget = ""
        }
        runnerInstance.run(["bash", Quickshell.shellPath("scripts/apply-wallpaper.sh")]
                   .concat(target).concat(root.modeFlags()).concat([path]),
                   path.split("/").pop())
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
        if (WallpaperEngine.running && Config.wpeScenePalette) {
            WallpaperEngine.repalette()
            return
        }
        if (runnerInstance.running) return
        const hit = root.wallpapers.find(p => p.split("/").pop() === root.current)
        if (!hit) return
        root._applyingPath = hit
        runnerInstance.run(["bash", Quickshell.shellPath("scripts/apply-wallpaper.sh"),
                            "--palette-only"].concat(root.modeFlags()).concat([hit]),
                   "Recolouring")
    }

    // ── Shuffle ───────────────────────────────────────────────────────────────
    // The slideshow. The timer variant refuses to fire while a scene is running —
    // a timer that silently killed the animated wallpaper you chose would be the
    // shell overruling you on a schedule. The button variant (`force`) is you
    // asking, so it wins over the scene like any explicit image apply.
    function shuffleNow(force) {
        if (runnerInstance.running || root.wallpapers.length === 0) return
        if (!force && WallpaperEngine.running) return
        const pool = root.wallpapers.filter(p => p.split("/").pop() !== root.current)
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
    function remove(path) {
        if (!path || !path.startsWith(root.wallpaperDir + "/")) return
        trashProc.command = ["gio", "trash", path]
        trashProc.running = true
    }

    Process {
        id: trashProc
        onExited: function(code) { root.rescan() }
    }
}
