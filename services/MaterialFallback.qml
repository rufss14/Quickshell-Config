pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// ── MaterialFallback ──────────────────────────────────────────────────────────
// Keeps a still of the Material Wallpaper on screen while the shell is not running.
//
// The Material Wallpaper is drawn by the shell (WallpaperView), so with the shell down — a crash, a
// quit, the seconds of a reload — the desktop under it is whatever the compositor has, which is
// black. awww is a daemon of its own and outlives the shell, so each WallpaperView renders a still
// of what it shows (its screen's palette, its style) and hands it here; the work of starting the
// daemon and sending the picture is scripts/material-fallback.sh, which has a test.
//
// ── One picture per monitor, the latest only ──────────────────────────────────
// Stills are PNGs in the cache, one per output, replaced in place. They queue (one script at a time)
// and a newer still for an output replaces an older one still waiting.
//
// ── Mapping order ─────────────────────────────────────────────────────────────
// awww draws on the background layer, and so does WallpaperView; the later of the two to map is on
// top. A daemon started AFTER the shell's surface would therefore cover the live wallpaper with the
// still, so the script says "started" when it had to start one and `remap` tells every WallpaperView
// to map again — over a daemon that is showing the very same picture, so nothing is seen to happen.
//
// ── Letting go ────────────────────────────────────────────────────────────────
// Turning the Material Wallpaper (or this) off stops the daemon IF this started it: a stale still
// kept behind a picture would be what shows when the shell goes. Only on a change — a shell that
// starts with it off touches nothing — and a daemon the user runs themselves is never touched.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string cacheDir:
        (Quickshell.env("XDG_CACHE_HOME") || ((Quickshell.env("HOME") || "") + "/.cache"))
        + "/quickshell-quicktest/material"

    // Where the still for a monitor lives. Output names are plain (DP-1, HDMI-A-1); anything else
    // is made safe for a filename.
    // The folder the stills are written into. QImage.saveToFile never creates one, so without this the first
    // still of a fresh install failed with "could not save the Material Wallpaper still" — and the surface
    // asks `dirReady` before it tries.
    property bool dirReady: false
    Process {
        running: true
        command: ["mkdir", "-p", root.cacheDir]
        onExited: function (code) { root.dirReady = code === 0 }
    }

    function pathFor(output) { return root.cacheDir + "/" + String(output).replace(/[^A-Za-z0-9._-]/g, "_") + ".png" }

    // ── awww present? ─────────────────────────────────────────────────────────
    // Assumed until the probe says otherwise, so a still made in the first second is not dropped.
    property bool installed: true
    Process {
        running: true
        command: ["sh", "-c", "command -v awww >/dev/null && command -v awww-daemon >/dev/null"]
        onExited: function (code) { root.installed = code === 0 }
    }
    // For the control that turns this on: "" when it can work, else why not.
    function blocker() { return root.installed ? "" : "awww isn't installed" }

    // A daemon was just started: every WallpaperView should map again (see above).
    signal remap()

    // ── The queue ─────────────────────────────────────────────────────────────
    property var _queue: []                 // [{ output, png }] or [{ clear: true }]

    function publish(output, png) {
        if (!Config.wallMaterialFallback || !root.installed || output === "" || png === "") return
        const q = root._queue.filter(j => j.output !== output)
        q.push({ output: output, png: png })
        root._queue = q
        root._next()
    }

    function release() {
        // Anything still waiting would only put the still back.
        root._queue = [{ clear: true }]
        root._next()
    }

    function _next() {
        if (run.running || root._queue.length === 0) return
        const job = root._queue[0]
        root._queue = root._queue.slice(1)
        run.command = job.clear
            ? ["bash", Quickshell.shellPath("scripts/material-fallback.sh"), "clear"]
            : ["bash", Quickshell.shellPath("scripts/material-fallback.sh"), "set", job.output, job.png]
        run.running = true
    }

    Process {
        id: run
        // The script says "started" when it had to start the daemon. Read when the stream ends,
        // which can be after the exit.
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() === "started") root.remap()
        }
        onExited: function (code) {
            if (code === 3) root.installed = false
            else if (code !== 0) console.warn("MaterialFallback: material-fallback.sh exited", code)
            root._next()
        }
    }

    // Off means the daemon goes — on a CHANGE only, and only while the shell is the one drawing.
    Connections {
        target: Config
        function onWallMaterialChanged()         { root._maybeRelease() }
        function onWallMaterialFallbackChanged() { root._maybeRelease() }
    }
    function _maybeRelease() {
        if (!(Config.wallMaterial && Config.wallMaterialFallback) && Config.wallShellRender) root.release()
    }
}
