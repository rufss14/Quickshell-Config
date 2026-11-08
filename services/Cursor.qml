pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../config"

// ── Cursor ────────────────────────────────────────────────────────────────────
// The system cursor belongs to the compositor, so "a cursor that follows the colour
// scheme" is a cursor THEME that is regenerated when the scheme moves. This service
// is the watcher: it hands the current accent and background to
// scripts/generate-cursor-theme (drawing and the XCursor format live there, tested by
// scripts/test-cursor-theme.py) and lets Hyprland reload it.
//
// ── The shell passes the colours, the script never reads a palette ────────────────
// `Colors.primary` is pywal's color1 pushed to a contrast floor, and a Material You
// scheme or an album overlay reaches it too. Re-deriving that in Python would be a
// second opinion about what "the accent" is; passing the resolved value cannot
// disagree. It also means the album scheme recolours the cursor even in shell-only
// mode, where nothing is written to colors.json.
//
// ── Inert while it's off ──────────────────────────────────────────────────────────
// Off (the default) writes nothing into ~/.local/share/icons and never touches the
// live cursor. Turning it off AFTER it was applied hands the cursor back to Hyprland's
// default theme; it does not do that on a fresh start, or a user's own cursor theme
// would be reset by a feature they never used.
//
// ── A Hyprland reload undoes it, so it is applied again after every one ──────────
// This shell reloads the compositor on EVERY palette change (reload-theme.sh →
// wal-reload.sh → `hyprctl reload`), moments AFTER this service has asked for the new
// cursor. So the regenerated theme could be on disk and applied, and then the reload
// hands the cursor back to whatever the config says. `configreloaded` arrives over
// Hyprland's event socket, and re-asking is one cheap `hyprctl setcursor` — the theme
// is already on disk, so nothing is regenerated.
//
// ── Hyprland won't re-read a theme it thinks it already has ───────────────────────
// Its XCursor loader remembers the last theme NAME, size and scale and skips a load that
// repeats them — so rewriting the files under `quicktest` and asking for `quicktest`
// again changed nothing on screen, however fresh the files were. The theme is therefore
// reachable under two names (the directory and a `-b` symlink to it, see
// generate-cursor-theme) and every apply alternates, so to Hyprland it is always a
// different theme. `_flip` is that alternation; both the regenerate path and the
// after-a-reload path go through `nextName()`.
//
// ── Clients that already loaded the theme keep the old colours ───────────────────
// `hyprctl setcursor` repaints Hyprland's own cursor at once. XWayland, GTK and Qt
// windows re-read the theme when they next ask for a cursor — usually a restart.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property bool enabled: Config.cursorTheme

    // ── The colours ───────────────────────────────────────────────────────────
    function hex(c) {
        const q = Qt.color(c)
        const h = v => Math.round(v * 255).toString(16).padStart(2, "0")
        return "#" + h(q.r) + h(q.g) + h(q.b)
    }

    // The outline is always the shell's background, so the cursor reads on a window
    // that is the same hue as its own fill.
    readonly property string edge: hex(Colors.base)
    readonly property string fill: hex(Config.cursorColor === "text"   ? Colors.fg
                                     : Config.cursorColor === "custom" ? Config.cursorCustom
                                     :                                   Colors.primary)

    // ── The preview sheet the settings page shows ─────────────────────────────
    // Drawn by the same code that draws the cursors, so the page can't show a design
    // the theme doesn't have. Only produced while a page is looking (acquirePreview).
    readonly property string previewFile:
        (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
        + "/quickshell-quicktest/cursor-preview.png"
    // The query string is what makes an Image re-read a file whose path never changes.
    // Empty until this session has drawn one: on a fresh install the file doesn't exist
    // yet, and an Image pointed at it logged "Cannot open" every time the page opened.
    readonly property string previewUrl: root._rev > 0 ? "file://" + root.previewFile + "?v=" + root._rev : ""
    property int _rev: 0
    property int previewUsers: 0
    function acquirePreview() { root.previewUsers++ }
    function releasePreview() { root.previewUsers = Math.max(0, root.previewUsers - 1) }

    // ── State the page reads ──────────────────────────────────────────────────
    property string lastError: ""
    readonly property bool busy: gen.running
    readonly property string statusText:
        root.lastError !== "" ? root.lastError
        : !root.enabled       ? "Off — the system cursor is untouched"
        : "Following the colour scheme"

    // ── Regenerate, debounced ─────────────────────────────────────────────────
    // A wallpaper change or an album change can move the palette several times in
    // quick succession (reload-theme.sh rewrites colors.json in more than one step). The
    // generator now takes about half a second and draws nothing at all when the colours
    // haven't changed, so this only has to swallow one burst — it was 600ms when a run
    // cost two seconds, and that was most of what "it takes a while to refresh" was.
    property bool _again: false
    property bool _applied: false      // did THIS session ever hand the cursor to us

    // ── Not during the wave ───────────────────────────────────────────────────
    // A palette change lands mid-wave (WallWave's commit), and the generator forks a
    // pool across every core for ~0.5s — right inside the 1.15s spread the user is
    // watching, along with a cursor-theme flip. So while a change is in flight the
    // request is noted and run the moment it settles; the generator also runs at
    // lower priority (nice 10), so a wave that starts during it keeps the CPU.
    property bool _afterWave: false
    function queue() {
        if (WallWave.active) { root._afterWave = true; return }
        debounce.restart()
    }
    Connections {
        target: WallWave
        function onSettledChanged() {
            if (WallWave.settled && root._afterWave) { root._afterWave = false; debounce.restart() }
        }
    }

    property bool _flip: false
    function nextName() {
        root._flip = !root._flip
        return root._flip ? "quicktest-b" : "quicktest"
    }

    onFillChanged:          queue()
    onEdgeChanged:          queue()
    onEnabledChanged:       queue()
    onPreviewUsersChanged:  queue()
    Connections {
        target: Config
        function onCursorSizeChanged() { root.queue() }
    }
    Component.onCompleted: queue()

    Timer {
        id: debounce
        interval: 150
        onTriggered: root._run()
    }

    function _run() {
        console.log("Cursor: run — enabled", root.enabled, "applied", root._applied,
                    "previewUsers", root.previewUsers, "busy", gen.running)
        if (gen.running) { root._again = true; return }

        const wantPreview = root.previewUsers > 0

        if (!root.enabled) {
            if (root._applied) {                    // switched off: give the cursor back
                root._applied = false
                gen.command = ["nice", "-n", "10", "python3", root.script, "--revert", "--size", String(Config.cursorSize)]
                gen.running = true
                return
            }
            if (!wantPreview) return
        }

        const cmd = ["nice", "-n", "10", "python3", root.script, "--fill", root.fill, "--edge", root.edge,
                     "--size", String(Config.cursorSize)]
        if (wantPreview) cmd.push("--preview", root.previewFile)
        if (root.enabled) { cmd.push("--apply", "--name", root.nextName()); root._applied = true }
        else cmd.push("--preview-only")
        gen.command = cmd
        console.log("Cursor: generating", root.fill, "on", root.edge,
                    root.enabled ? "and applying" : "(preview only)")
        gen.running = true
    }

    readonly property string script: Quickshell.shellPath("scripts/generate-cursor-theme")

    // Only once it's been handed to Hyprland this session: a reload on a machine that
    // never turned this on must not touch the user's own cursor.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" && root._applied && root.enabled) reapply.restart()
        }
    }
    Timer {
        id: reapply
        interval: 200                     // a palette change can reload more than once
        onTriggered: {
            if (gen.running) return       // a fresh apply is already on its way
            setcursor.command = ["hyprctl", "setcursor", root.nextName(), String(Config.cursorSize)]
            setcursor.running = true
        }
    }
    Process { id: setcursor }

    // Ask the service before theorising: `qs ipc -c ~/.config/quicktest call cursor status`.
    // Read-only — it reports, it doesn't run anything.
    IpcHandler {
        target: "cursor"
        function status(): string {
            return "enabled=" + root.enabled + " applied=" + root._applied
                 + " fill=" + root.fill + " edge=" + root.edge
                 + " size=" + Config.cursorSize + " next=" + (root._flip ? "quicktest" : "quicktest-b")
                 + " busy=" + gen.running + " previewUsers=" + root.previewUsers
                 + " lastError=" + (root.lastError || "none")
        }
    }

    Process {
        id: gen
        stderr: StdioCollector { id: err }
        onExited: function (code) {
            root.lastError = code === 0 ? "" : (err.text.trim().split("\n").pop() || ("failed (" + code + ")"))
            // The page only shows lastError while it is open; a run that fails with it
            // closed must still be findable in the log.
            if (code !== 0) console.warn("Cursor: generate-cursor-theme exited", code, "-", err.text.trim())
            root._rev++
            if (root._again) { root._again = false; root._run() }
        }
    }
}
