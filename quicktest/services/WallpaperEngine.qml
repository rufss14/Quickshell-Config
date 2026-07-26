pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// ── WallpaperEngine ───────────────────────────────────────────────────────────
// The Steam Workshop wallpaper library (linux-wallpaperengine), and running one.
//
// ── There is no IPC. Changing wallpaper means RESTARTING the process ──────────
// Checked against `--help` rather than assumed: every option this renderer has —
// the background, volume, fps, layer, the lot — is a startup argument. There is no
// socket, no control file, no signal. So "apply" here is genuinely kill-and-relaunch,
// and the UI has to be honest that a change costs a visible restart of the wallpaper.
//
// ── The SIGPIPE trap: why the child's output is redirected to a file ──────────
// The first version launched with a bare `setsid --fork <renderer>` and every
// apply produced a renderer that died ~1.6 seconds later. Measured, not guessed:
// a 150ms trace showed running at t+450ms and dead by t+2100ms. The detached
// child INHERITS the Process's stdout/stderr pipes; once setsid exits, Quickshell
// closes the read ends; the renderer logs chattily during startup, and its first
// write into the closed pipe is a SIGPIPE — silent death, nothing in any log.
// The launch now routes the child's output into a real file, which both breaks
// the pipe dependency and finally makes failures diagnosable (see lastError).
//
// ── Killing it safely is the other dangerous part of this file ────────────────
// There are TWO similarly named programs on this machine:
//
//     linux-wallpaperengine    the layer-shell renderer  (what we drive)
//     linux-wallpaper-engine   a separate Electron GUI   (leave alone)
//
// Linux truncates a process's `comm` to 15 characters, and BOTH become exactly
// "linux-wallpaper" — `pkill -x` on that name matches EIGHT processes here,
// including the Electron app. So we match the full command line on the
// UNHYPHENATED spelling, anchored so a process that merely MENTIONS the name
// (like the bash stage of our own launcher, where the name follows a space)
// can never match. Every command is an argv array — no shell string ever
// contains an unquoted path.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string _procPattern: "(^|/)linux-wallpaperengine( |$)"

    readonly property string workshopDir:
        Quickshell.env("HOME") + "/.local/share/Steam/steamapps/workshop/content/431960"
    readonly property string assetsDir:
        Quickshell.env("HOME") + "/.local/share/Steam/steamapps/common/wallpaper_engine/assets"
    // Where the renderer's own output goes. Truncated on every launch, so it only
    // ever describes the CURRENT (or most recent) run.
    readonly property string logFile:
        Quickshell.env("HOME") + "/.cache/quicktest-wpe.log"

    // ── The library ───────────────────────────────────────────────────────────
    // [{ id, title, type, preview }] — `type` normalised to lowercase, `preview` an
    // absolute path. Sorted by title, which is what the filmstrip is ordered by.
    readonly property var  items:    root._items
    readonly property bool scanning: scanProc.running
    // Workshop items that are NOT standalone wallpapers — see the scanner below.
    readonly property int  skipped:  root._skipped

    property var _items: []
    property int _skipped: 0

    function rescan() {
        if (scanProc.running) return
        scanProc.running = true
    }

    // ── Scanning ──────────────────────────────────────────────────────────────
    // One python pass over every project.json rather than a process per item.
    // Two things this has to get right, both found by reading the REAL library:
    // `type` is inconsistently cased ("scene"/"Scene", "video"/"Video"), and some
    // items are PRESETS — a `dependency` on another workshop item plus a settings
    // blob, with no file to render. Those are excluded and counted, not silently
    // dropped: two items visible in Steam vanishing here would read as a bug.
    Process {
        id: scanProc
        running: true
        command: ["python3", "-c", `
import json, os, sys
W = sys.argv[1]
rows, skipped = [], 0
for d in sorted(os.listdir(W)):
    p = os.path.join(W, d, "project.json")
    if not os.path.exists(p):
        continue
    try:
        j = json.load(open(p, encoding="utf-8", errors="replace"))
    except Exception:
        skipped += 1
        continue
    if not j.get("file"):
        skipped += 1
        continue
    prev = j.get("preview") or ""
    prev = os.path.join(W, d, prev) if prev else ""
    if prev and not os.path.exists(prev):
        prev = ""
    title = (j.get("title") or d).replace("\\t", " ").strip()
    typ   = str(j.get("type") or "").lower()
    rows.append((title, d, typ, prev))
rows.sort(key=lambda r: r[0].lower())
print("SKIPPED\\t%d" % skipped)
for t, d, ty, pv in rows:
    print("ITEM\\t%s\\t%s\\t%s\\t%s" % (d, ty, pv, t))
`, root.workshopDir]

        property var _rows: []
        property int _skip: 0

        stdout: SplitParser {
            onRead: function(line) {
                const parts = line.split("\t")
                if (parts[0] === "SKIPPED") {
                    scanProc._skip = parseInt(parts[1]) || 0
                } else if (parts[0] === "ITEM" && parts.length >= 5) {
                    scanProc._rows = scanProc._rows.concat([{
                        id:      parts[1],
                        type:    parts[2],
                        preview: parts[3],
                        // Title last: it's the only field that can contain anything,
                        // so a tab inside it can't shift the others.
                        title:   parts.slice(4).join(" ")
                    }])
                }
            }
        }

        onExited: function(code) {
            root._items   = scanProc._rows.slice()
            root._skipped = scanProc._skip
            scanProc._rows = []
            scanProc._skip = 0
        }
    }

    function itemFor(id) { return root._items.find(i => i.id === id) ?? null }

    function titleFor(id) {
        const it = root.itemFor(id)
        return it ? it.title : (id === "" ? "" : id)
    }

    // ── Is it running, and on what? ───────────────────────────────────────────
    // Read back from the RUNNING process's own command line, not from what we last
    // asked for — the user can (and does) start this renderer by hand, and a page
    // reporting our own last request as truth would confidently show the wrong
    // wallpaper. Config.wpeCurrent is only the restore-on-login value.
    readonly property bool running:   root._running
    readonly property string current: root._current

    property bool   _running: false
    property string _current: ""

    // Refcounted like the other on-demand services: an external process has nothing
    // to subscribe to, so this is a genuine poll and must not run while nobody is
    // looking. Acquired by the settings page while visible.
    property int _refs: 0
    function acquire() { root._refs++; if (root._refs === 1) { poll.start(); root.probe() } }
    function release() { root._refs = Math.max(0, root._refs - 1); if (root._refs === 0) poll.stop() }

    Timer {
        id: poll
        interval: 2000
        repeat: true
        onTriggered: root.probe()
    }

    function probe() {
        if (probeProc.running) return
        probeProc._line = ""
        probeProc.running = true
    }

    Process {
        id: probeProc
        command: ["pgrep", "-a", "-f", root._procPattern]

        property string _line: ""

        stdout: SplitParser {
            onRead: function(line) { if (probeProc._line === "") probeProc._line = line }
        }

        onExited: function(code) {
            // pgrep exits 1 when nothing matched — "not running", not an error.
            root._running = (code === 0 && probeProc._line !== "")
            root._current = root._running ? root._idFromCmdline(probeProc._line) : ""
            root._verifyStep()
        }
    }

    // The workshop id is the last path segment of --bg.
    function _idFromCmdline(line) {
        const m = / --bg (\S+)/.exec(line)
        if (!m) return ""
        const parts = m[1].replace(/\/+$/, "").split("/")
        return parts[parts.length - 1] ?? ""
    }

    // ── Running one: an explicit state machine ────────────────────────────────
    // The first version derived `busy` from the two Processes' running flags, and
    // since pkill and a forking setsid each exit within milliseconds, busy was
    // false for essentially the whole apply — the UI showed nothing happening
    // while everything happened. The phase is explicit now, and covers the whole
    // journey: stop → gap → start → VERIFIED up (or failed, with the reason).
    //
    //   idle | stopping | starting | verifying
    readonly property bool busy: root._phase !== "idle"
    property string _phase: "idle"

    // Why the last apply failed, or "" — the tail of the renderer's own log,
    // surfaced in the UI. A start that dies is no longer silent.
    property string lastError: ""

    property string _pendingId: ""   // queued behind the stop
    property string _verifyId:  ""   // being verified; used to kick the palette
    property int    _verifyTries: 0
    property int    _drainTries:  0

    function apply(id) {
        if (!id || root.busy) return
        Config.wpeCurrent = id
        // The mirror of Wallpaper.apply disabling autostart for a still image: picking
        // a scene means the scene is the wallpaper, so it should come back on login.
        // "Start with the shell" stays the explicit override. The autostart timer only
        // calls this when it's already on, so that path is a no-op (QML dedupes).
        Config.wpeAutoStart = true
        root.lastError  = ""
        root._pendingId = id
        root._phase = "stopping"
        stopProc.running = true
    }

    function stop() {
        if (root.busy) return
        root.lastError  = ""
        root._pendingId = ""
        root._phase = "stopping"
        stopProc.running = true
    }

    Process {
        id: stopProc
        command: ["pkill", "-f", root._procPattern]
        onExited: function(code) {
            // pkill only SIGNALS the renderer; it can keep holding the audio
            // device for a moment while it tears down. Starting the replacement
            // now (as the old code did, on a flat 350ms timer) briefly runs TWO
            // instances, and the scene's soundtrack plays twice — an audible
            // echo. So we DRAIN first: poll until nothing matches the pattern,
            // and only then continue. 1 = nothing was running, which is fine.
            root._drainTries = 0
            drainTimer.start()
        }
    }

    // ── Draining: wait for the old renderer to actually be GONE ────────────────
    // Not just signalled — gone. This is what guarantees a single instance, which
    // is what guarantees the audio plays once.
    Timer {
        id: drainTimer
        interval: 150
        repeat: true
        onTriggered: { if (!drainProc.running) drainProc.running = true }
    }

    Process {
        id: drainProc
        command: ["pgrep", "-f", root._procPattern]
        onExited: function(code) {
            // pgrep exits 1 when nothing matched — the old renderer has exited.
            if (code !== 0) { drainTimer.stop(); root._afterDrain(); return }
            root._drainTries++
            // Still alive after a few polls means it's ignoring SIGTERM (stuck in
            // audio teardown). Escalate once to SIGKILL.
            if (root._drainTries === 4) killProc.running = true
            // If even that won't clear it, stop waiting rather than hang the apply
            // forever — one stubborn instance beats a frozen UI.
            if (root._drainTries >= 12) { drainTimer.stop(); root._afterDrain() }
        }
    }

    Process {
        id: killProc
        command: ["pkill", "-9", "-f", root._procPattern]
    }

    function _afterDrain() {
        if (root._pendingId !== "") {
            root._phase = "starting"
            startTimer.start()
        } else {
            root._phase = "idle"
            root.probe()
        }
    }

    // A short settle after the process is confirmed gone: the compositor releases
    // the dead renderer's layer surface a beat later, and starting into that gap
    // gave two surfaces fighting for the screen.
    Timer {
        id: startTimer
        interval: 250
        repeat: false
        onTriggered: {
            startProc.command = root._launchCommand(root._pendingId)
            root._verifyId  = root._pendingId
            root._pendingId = ""
            // The launch command was just built from the CURRENT options, so the
            // running scene is about to match Config again — nothing pending.
            root._optionsDirty = false
            startProc.running = true
        }
    }

    // ── Live options: applied on demand, not on every change ───────────────────
    // The renderer has no IPC, so changing a render option genuinely means
    // RELAUNCHING the scene — a visible flicker. Doing that on every slider tick or
    // toggle is jarring, so a change to a running scene is only MARKED pending; the
    // settings page's Refresh button relaunches with the collected options. That
    // also lets a run of edits (fps + volume + monitor) cost ONE restart instead of
    // one each. wpeCurrent (the scene itself) is handled by apply() and the scene
    // palette is a separate path — neither belongs here; everything below is a
    // genuine launch argument.
    property bool _optionsDirty: false
    readonly property bool needsRefresh: root.running && !root.busy && root._optionsDirty

    function _optionChanged() {
        // Only meaningful while a scene is up — options for a stopped renderer just
        // ride along on the next Start, so there is nothing to refresh.
        if (root.running) root._optionsDirty = true
    }

    // Relaunch the running scene so the changed options take effect. The page's
    // Refresh button. A no-op unless a scene is up and something actually changed.
    function refresh() {
        if (!root.needsRefresh || root.current === "") return
        // The SCENE hasn't changed, only render options — so the palette already on
        // disk is still correct. Skip re-deriving it, or a refresh would repaint
        // fourteen apps for an identical result. (Light/dark takes repalette().)
        root._skipPaletteOnce = true
        root.apply(root.current)
    }

    Connections {
        target: Config
        function onWpeFpsChanged()             { root._optionChanged() }
        function onWpeVsyncChanged()           { root._optionChanged() }
        function onWpeTargetChanged()          { root._optionChanged() }
        function onWpeMuteChanged()            { root._optionChanged() }
        function onWpeVolumeChanged()          { root._optionChanged() }
        function onWpeKeepAudioChanged()       { root._optionChanged() }
        function onWpePauseFullscreenChanged() { root._optionChanged() }
        function onWpeAudioProcessingChanged() { root._optionChanged() }
        function onWpeMouseChanged()           { root._optionChanged() }
        function onWpeParallaxChanged()        { root._optionChanged() }
    }

    Process {
        id: startProc
        onExited: function(code) {
            // setsid has forked and gone; the renderer is now on its own. Whether
            // it SURVIVED is a separate question — hence verification.
            root._phase = "verifying"
            root._verifyTries = 0
            verifyTimer.start()
        }
    }

    // ── Verification ──────────────────────────────────────────────────────────
    // The SIGPIPE bug above is exactly why this exists: a launch can succeed and
    // the renderer still die moments later. Probe once a second; alive → done,
    // and the scene palette kicks off. Still dead after 5 tries → declare failure
    // and read the renderer's log for the reason.
    Timer {
        id: verifyTimer
        interval: 1000
        repeat: true
        onTriggered: root.probe()
    }

    function _verifyStep() {
        if (root._phase !== "verifying") return
        if (root._running) {
            verifyTimer.stop()
            root._phase = "idle"
            root.lastError = ""
            const id = root._verifyId
            root._verifyId = ""
            root._kickScenePalette(id)
            return
        }
        root._verifyTries++
        if (root._verifyTries >= 5) {
            verifyTimer.stop()
            root._phase = "idle"
            root._verifyId = ""
            tailProc.running = true
        }
    }

    Process {
        id: tailProc
        command: ["tail", "-n", "4", root.logFile]

        property var _lines: []
        stdout: SplitParser {
            onRead: function(line) { tailProc._lines = tailProc._lines.concat([line]) }
        }
        onExited: function(code) {
            const t = tailProc._lines.join("\n").trim()
            root.lastError = t !== "" ? t : "The renderer exited without logging anything."
            tailProc._lines = []
        }
    }

    // ── Colours from the scene ────────────────────────────────────────────────
    // The scene is animated, but its Workshop preview is an honest still of it —
    // so the shell's palette can follow an animated wallpaper the same way it
    // follows a static one: pywal on the preview, then the shared reload
    // pipeline. `--palette-only` stops the script from touching the actual
    // wallpaper (the scene is covering it) or recording the preview as the
    // current static image (which would make the images tab lie).
    readonly property bool paletteApplying: paletteRunner.running

    ThemeRunner {
        id: paletteRunner
        appName: "Scene colours"
        icon: "wallpaper"

        onFinished: function(code) {
            if (code !== 0)
                paletteRunner.notify("Scene colours failed",
                    "Could not derive a palette from the scene's preview.", "normal")
        }
    }

    // Set for the autostart path: on login the palette on disk already IS this
    // scene's, so re-deriving it would repaint every themed app for an identical
    // result — pure churn at the worst moment.
    property bool _skipPaletteOnce: false

    function _kickScenePalette(id) {
        if (root._skipPaletteOnce) { root._skipPaletteOnce = false; return }
        if (!Config.wallTheming) return
        if (!Config.wpeScenePalette || paletteRunner.running) return
        const it = root.itemFor(id)
        if (!it || it.preview === "") return
        const flags = Config.themeMode === "light" ? ["--light"] : []
        paletteRunner.run(["bash", Quickshell.shellPath("scripts/apply-wallpaper.sh"),
                           "--palette-only"].concat(flags).concat([it.preview]), it.title)
    }

    // Re-derive the palette from the RUNNING scene — the theme-mode switch's
    // route when a scene is what's colouring the shell.
    function repalette() {
        if (root.running) root._kickScenePalette(root.current)
    }

    // ── Autostart ─────────────────────────────────────────────────────────────
    // NOTE: a lazy singleton's timers only exist once something references it —
    // shell.qml holds that reference now, which is the only reason this can fire
    // on login rather than on first opening the settings page.
    //
    // The delay outwaits Config's async JSON load: firing at onCompleted would
    // read wpeAutoStart's default (false) and the setting would never work — the
    // same restore-before-load trap that broke the remembered settings page.
    Timer {
        interval: 4000
        repeat: false
        running: true
        onTriggered: {
            if (!Config.wpeAutoStart || Config.wpeCurrent === "") return
            autoProbe.running = true
        }
    }

    Process {
        id: autoProbe
        command: ["pgrep", "-f", root._procPattern]
        onExited: function(code) {
            // 0 = already running. Leave it alone; the user's wallpaper is up.
            if (code === 0) { root.probe(); return }
            root._skipPaletteOnce = true
            root.apply(Config.wpeCurrent)
        }
    }

    // ── The command ───────────────────────────────────────────────────────────
    // `setsid --fork` detaches it (the wallpaper must outlive a shell reload);
    // the bash stage exists ONLY to point the child's output at a real file —
    // see the SIGPIPE note at the top. "$0"/"$@" keep every argument out of the
    // shell string, so no path is ever re-parsed.
    //
    // `--layer background` is deliberate and load-bearing: the renderer defaults
    // to `bottom`, which is ABOVE the background layer — that is what buried
    // CavaBG. With the shell owning the launch, the ordering is a fact, not a
    // race against whoever mapped last.
    function _launchCommand(id) {
        const dir = root.workshopDir + "/" + id
        let args = ["--layer", "background",
                    "--assets-dir", root.assetsDir]

        // One --bg per --screen-root: the flag applies to the screen named before
        // it. No screens with usable names → a bare --bg, not `--screen-root ""`.
        // When the user has pinned a single monitor, only that screen is rendered
        // — which is also what stops a scene's audio doubling across monitors.
        const screens = root.targetScreens()
        if (screens.length === 0) {
            args = args.concat(["--bg", dir])
        } else {
            for (const s of screens)
                args = args.concat(["--screen-root", s, "--bg", dir])
        }

        args = args.concat(["--fps", String(Config.wpeFps)])

        if (Config.wpeMute) {
            args = args.concat(["--silent"])
        } else {
            args = args.concat(["--volume", String(Config.wpeVolume)])
            // Without this the renderer silences itself whenever ANY other app
            // plays a sound — which reads as "audio doesn't work", because
            // something is nearly always making a sound.
            if (Config.wpeKeepAudio) args = args.concat(["--noautomute"])
        }

        if (!Config.wpePauseFullscreen) args = args.concat(["--no-fullscreen-pause"])
        if (!Config.wpeAudioProcessing) args = args.concat(["--no-audio-processing"])
        if (!Config.wpeMouse)    args = args.concat(["--disable-mouse"])
        if (!Config.wpeParallax) args = args.concat(["--disable-parallax"])

        // ── V-Sync is a driver setting, so it rides on the ENVIRONMENT ─────────
        // The renderer has no vsync flag; the GL driver does. `env` prepends the
        // assignments to the process, covering both stacks — Mesa's vblank_mode=3
        // (always sync) and NVIDIA's __GL_SYNC_TO_VBLANK=1. Off: no env at all,
        // so the driver keeps its own default.
        const vsyncEnv = Config.wpeVsync
            ? "vblank_mode=3 __GL_SYNC_TO_VBLANK=1 "
            : ""

        return ["setsid", "--fork", "bash", "-c",
                'exec env ' + vsyncEnv + '"$0" "$@" > ' + '"' + root.logFile + '"' + " 2>&1",
                "linux-wallpaperengine"].concat(args)
    }

    // The screens the scene should render on. "" = all named screens; a pinned
    // name = just that one, unless it has been unplugged since — in which case the
    // pref is reset and every screen renders, rather than the wallpaper silently
    // landing on a monitor that no longer exists (the wallTarget lesson).
    function targetScreens() {
        const all = root.screenNames()
        if (Config.wpeTarget === "") return all
        if (all.indexOf(Config.wpeTarget) !== -1) return [Config.wpeTarget]
        Config.wpeTarget = ""
        return all
    }

    function screenNames() {
        const out = []
        for (const s of Quickshell.screens)
            if (s.name && s.name !== "") out.push(s.name)
        return out
    }

    // ── Removing a workshop wallpaper from disk ───────────────────────────────
    // What this CAN'T do is unsubscribe — that's a Steam-account action with no
    // local API, and a deleted-but-still-subscribed item comes back on Steam's
    // next workshop sync. So removal also opens the item's workshop page in the
    // browser, where Unsubscribe is one click; the UI says so rather than letting
    // the reappearance read as a bug.
    readonly property bool removing: rmProc.running

    function remove(id) {
        // The id becomes part of an `rm -rf` path, so it is validated to be a
        // bare workshop id — digits, nothing else — no matter what the caller
        // passes. A path fragment smuggled in here would be catastrophic.
        if (!/^[0-9]+$/.test(id) || rmProc.running) return

        // Removing the scene that's on screen: stop the renderer first, or it
        // keeps painting from open file handles while the files vanish.
        if (root.running && root.current === id) root.stop()
        if (Config.wpeCurrent === id) Config.wpeCurrent = ""

        rmProc.command = ["rm", "-rf", root.workshopDir + "/" + id]
        rmProc.running = true
    }

    Process {
        id: rmProc
        onExited: function(code) { root.rescan() }
    }

    function openWorkshop(id) {
        if (!/^[0-9]+$/.test(id)) return
        Quickshell.execDetached(["xdg-open",
            "https://steamcommunity.com/sharedfiles/filedetails/?id=" + id])
    }

    // The Workshop's front page for Wallpaper Engine — where new scenes come from.
    function openWorkshopHub() {
        Quickshell.execDetached(["xdg-open",
            "https://steamcommunity.com/app/431960/workshop/"])
    }
}
