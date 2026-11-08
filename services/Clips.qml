pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../config"
import "../state"
import "clips.js" as ClipsJs

// ── Clips ─────────────────────────────────────────────────────────────────────
// Clip it and record it, Medal-style, on gpu-screen-recorder: a replay buffer you
// turn on, one key that saves its last N seconds, plain recordings (a monitor or a
// dragged region), and the library of what you've saved. The sidebar button
// (modules/bar/SideClips), its panels (modules/panels/ClipsPanel, ClipsTargetPanel,
// ClipsPeek) and the gallery (modules/panels/ClipsGallery) show it; everything they
// do is a function here.
//
// ── Where the work happens ────────────────────────────────────────────────────
//   services/clips.js     the recorder's argv (validated), formatting — pure
//   scripts/clips-run.py  the DETACHED runner: owns the recorder, state.json,
//                         signals, the -sc hook's events.jsonl
//   scripts/clips-lib.py  the library: ffprobe, thumbnails, filmstrip, trim, rename
// Tests: bun scripts/test-clips.js, python3 scripts/test-clips-run.py and
// scripts/test-clips-lib.py (all safe: pure, a fake recorder, generated clips).
//
// ── The buffer survives a reload ──────────────────────────────────────────────
// The runner is setsid-detached (update-run.sh's rule), so ALT+Q — or any QML
// save, which hot-reloads — never drops the buffer you were about to clip from.
// This side only reads state.json; after a reload it picks the buffer back up.
//
// ── Off unless you turn it on — twice ────────────────────────────────────────
// Config.clips gates the button. Clipping (Config.clipsBuffer) is its own switch:
// while it's on, the replay buffer is KEPT running — started with the shell,
// restarted if it dies (three failures in a row and it stops and says why) — so a
// clip is always one key away. Never switched on by anything but the user: no
// auto-start on games — except Config.gamemodeClips (2026-11-07, the user's ask, off by
// default), which holds the buffer for as long as Game Mode is on without touching the
// switch. Turning either off stops the buffer. Missing gpu-screen-recorder DISABLES the
// controls with a reason (`blocker()`).
//
// ── Added 2026-10-18 ──────────────────────────────────────────────────────────
//   clip-ahead       "Clip it" + N more seconds (Config.clipsAhead; aheadPlan, headtrim in the lib)
//   game names       clips named after the window (the runner's hook; Config.clipsNameByWindow)
//   health           free RAM / disk, the recorder's own memory, the capture capability — probed
//                    only while something is looking (`acquireHealth`), and `diagnosis`: what is
//                    wrong, in words (clips.js diagnose)
//   record limits    "stop after 10 min / 2 GB" (Config.clipsRecordLimit)
//   presets          one click sets the recording profile (clips.js PRESETS)
//   quick actions    edit a clip in the gallery's editor, send it to Discord
//
// ── Diagnose it with ─────────────────────────────────────────────────────────
//     qs ipc -c ~/.config/quicktest call clips status
//     python3 scripts/clips-run.py status "$XDG_RUNTIME_DIR/quickshell-quicktest-clips"
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ══ Can it run ════════════════════════════════════════════════════════════
    property bool installed: false
    property bool probed: false
    property bool hasSlurp: false

    // "" when usable, else why not — the button, panel and page show this instead of acting.
    function blocker() {
        if (!root.probed) return "Checking for gpu-screen-recorder…"
        if (!root.installed) return "gpu-screen-recorder isn't installed"
        return ""
    }

    // ══ Where things live ═════════════════════════════════════════════════════
    readonly property string _home: Quickshell.env("HOME") || ""
    readonly property string saveDir: {
        const c = (Config.clipsDir || "").trim()
        if (c === "")           return root._home + "/Videos/Clips"
        if (c === "~")          return root._home
        if (c.startsWith("~/")) return root._home + c.slice(1)
        return c
    }
    readonly property string _runDir:
        (Quickshell.env("XDG_RUNTIME_DIR")
         || (Quickshell.env("XDG_CACHE_HOME") || (root._home + "/.cache"))) + "/quickshell-quicktest-clips"
    readonly property string _cacheDir:
        (Quickshell.env("XDG_CACHE_HOME") || (root._home + "/.cache")) + "/quickshell-quicktest/clips"
    readonly property string _runner: Quickshell.shellPath("scripts/clips-run.py")
    readonly property string _lib:    Quickshell.shellPath("scripts/clips-lib.py")

    // ══ The recorder, as the runner reports it ════════════════════════════════
    property var _d: ({})
    readonly property string mode: root._d.state === "replay" || root._d.state === "record" ? root._d.state : "idle"
    readonly property bool buffering: root.mode === "replay"
    // A plain recording, or a regular one running during the buffer.
    readonly property bool recording: root.mode === "record" || (root.buffering && root._d.recording === true)
    readonly property bool paused: root.mode === "record" && root._d.paused === true
    readonly property bool busy: root.mode !== "idle"
    readonly property real since: root._d.since ?? 0
    readonly property real recordSince: root._d.recordSince ?? 0
    // The runner's last error, or a local one (nothing to capture, slurp cancelled…).
    readonly property string lastError: root._localError !== "" ? root._localError : (root._d.error ?? "")
    property string _localError: ""

    // A start asked for and not yet reported, so a double-click doesn't start two
    // (the runner's flock would refuse the second anyway; this keeps the UI honest).
    property bool starting: false
    Timer {
        id: startingTimer
        interval: 4000
        onTriggered: { root.starting = false; root._reconcile() }
    }

    // ══ What the settings amount to ═══════════════════════════════════════════
    readonly property var opts: ({
        fps: Config.clipsFps, quality: Config.clipsQuality, bitrateMode: Config.clipsBitrateMode,
        kbps: Config.clipsKbps, codec: Config.clipsCodec, container: Config.clipsContainer,
        resolution: Config.clipsResolution, cursor: Config.clipsCursor,
        desktopAudio: Config.clipsDesktopAudio, mic: Config.clipsMic, splitAudio: Config.clipsSplitAudio,
        bufferSeconds: Config.clipsBufferSeconds, storage: Config.clipsStorage
    })
    readonly property var settings: ClipsJs.settings(root.opts)
    readonly property int bufferSeconds: root.settings.buffer

    // ── Presets ───────────────────────────────────────────────────────────────
    // The recording profile as one click (clips.js PRESETS); `preset` is the one the settings
    // are exactly now, null for anything the user tuned by hand. Settings are startup arguments, so a
    // running buffer keeps the old ones until it restarts — `stale` says so, `restartBuffer()` fixes it.
    readonly property var presets: ClipsJs.PRESETS
    readonly property var preset: ClipsJs.matchPreset(root.opts)
    function applyPreset(id) {
        const p = ClipsJs.PRESETS.find(x => x.id === id)
        if (!p) return
        Config.clipsFps = p.v.fps
        Config.clipsQuality = p.v.quality
        Config.clipsBitrateMode = p.v.cbr ? "cbr" : "auto"
        Config.clipsCodec = p.v.codec
        Config.clipsResolution = p.v.resolution
        Config.clipsBufferSeconds = p.v.buffer
        Config.clipsDesktopAudio = p.v.desktop
        Config.clipsMic = p.v.mic
        Config.clipsSplitAudio = p.v.split
    }
    // What the running buffer was started with ("" = not by this shell: unknown, so not stale).
    property string _launchedSettings: ""
    readonly property bool stale: root.buffering && root._launchedSettings !== ""
                                  && root._launchedSettings !== JSON.stringify(root.settings)

    // The monitor a start captures: the configured one, or the focused one NOW.
    function _target() {
        const t = (Config.clipsTarget || "").trim()
        return t !== "" ? t : (Hyprland.focusedMonitor?.name ?? "")
    }

    // ══ Targets — what the hold-to-pick menus choose ══════════════════════════
    // Keys, as the target picker hands them over:
    //   "focused"     the monitor focused when the buffer starts   (persisted)
    //   "mon:DP-2"    that monitor                                 (persisted)
    //   "portal"      the desktop portal's picker — a window that follows (persisted)
    //   "win:0x…"     that window's AREA, as it is now             (this session)
    //   "region"      a rectangle dragged with slurp               (this session)
    // A window or region is a rectangle on screen, not worth persisting: after a
    // reload it's somewhere else. It lives in `sessionTarget` until changed.
    property var sessionTarget: null          // { kind: "window"|"region", geom, label, key }
    readonly property string targetKey:
        root.sessionTarget ? root.sessionTarget.key
        : (Config.clipsTarget || "") === ""      ? "focused"
        : Config.clipsTarget === "portal"        ? "portal"
        :                                          "mon:" + Config.clipsTarget
    readonly property string targetLabel: {
        if (root.sessionTarget) return root.sessionTarget.label
        const t = (Config.clipsTarget || "").trim()
        return t === "" ? "Focused monitor" : t === "portal" ? "Portal picker" : t
    }

    // What the buffer captures: [what, geom] for recorderArgv.
    function _bufferWhat() {
        return root.sessionTarget ? ["region", root.sessionTarget.geom] : [root._target(), ""]
    }

    // A key → { what, geom, label } to capture, or null (a window that's gone).
    function _resolve(key) {
        if (key === "focused") return { what: Hyprland.focusedMonitor?.name ?? "", geom: "", label: "Focused monitor" }
        if (key === "portal")  return { what: "portal", geom: "", label: "Portal picker" }
        if (key.startsWith("mon:")) return { what: key.slice(4), geom: "", label: key.slice(4) }
        if (key.startsWith("win:")) {
            const w = Hypr.windows.find(x => x.address === key.slice(4))
            const g = w ? ClipsJs.windowGeom(w.at, w.size) : ""
            return g === "" ? null
                 : { what: "region", geom: g, label: (w.appClass || "Window") + " (its area)" }
        }
        return null
    }

    // What the buffer captures from now on (the target picker, "Clip from"). Picking is
    // wanting it, so clipping comes on; a running buffer restarts on the new
    // target (its contents go — it was recording something else).
    function retarget(key) {
        root._localError = ""
        if (key === "region") { root._slurpFor = "buffer"; root._slurp(); return }
        if (key.startsWith("win:")) {
            const r = root._resolve(key)
            if (!r) { root._localError = "That window is gone"; return }
            root.sessionTarget = { kind: "window", geom: r.geom, label: r.label, key: key }
        } else {
            root.sessionTarget = null
            Config.clipsTarget = key === "focused" ? "" : key === "portal" ? "portal" : key.slice(4)
        }
        root._applyTarget()
    }
    // ── Every target there is right now, for a picker ─────────────────────────
    // [{ key, glyph, label, kind, enabled }], kind "monitor" | "window" | "other".
    // CALL IT, never bind it: the window list reads which workspaces are VISIBLE,
    // which walks Hyprland.monitors — a lazy model that notifies mid-evaluation and
    // re-enters a binding (CLAUDE.md). A picker fills itself when it opens and again
    // on Hypr.windowsChanged while it's up, holding Hypr.acquireEvents() meanwhile.
    readonly property int pickWindows: 8
    function targetChoices() {
        const out = [{ key: "focused", glyph: "\u{F0379}", label: "Focused monitor",   // 󰍹 monitor
                       kind: "monitor", enabled: true }]
        for (const sc of Quickshell.screens)
            out.push({ key: "mon:" + sc.name, glyph: "\u{F0379}", kind: "monitor", enabled: true,
                       label: sc.name + "  ·  " + sc.width + "×" + sc.height })
        const visible = Hyprland.monitors.values.map(m => m.activeWorkspace?.id ?? -1)
        const wins = Hypr.windows.filter(w => visible.indexOf(w.workspaceId) >= 0 && w.size[0] > 1)
        for (const w of wins.slice(0, root.pickWindows)) {
            const t = (w.title || "").length > 28 ? w.title.slice(0, 27) + "…" : (w.title || "")
            out.push({ key: "win:" + w.address, glyph: "\u{F08C6}", kind: "window", enabled: true,  // 󰣆 application
                       label: (w.appClass || "Window") + (t ? " — " + t : "") })
        }
        out.push({ key: "region", glyph: "\u{F019E}", kind: "other", enabled: root.hasSlurp,    // 󰆞 crop
                   label: root.hasSlurp ? "Drag a region…" : "Drag a region — needs slurp" })
        out.push({ key: "portal", glyph: "\u{F0CFD}", kind: "other", enabled: true,             // 󰳽 cursor-click
                   label: "Choose in portal…" })
        return out
    }

    function _applyTarget() {
        // A new target is a fresh start: whatever failed before may not now.
        root.gaveUp = false
        root._failures = 0
        if (!Config.clipsBuffer) Config.clipsBuffer = true
        else if (root.buffering) root._signal("stop")   // _reconcile restarts it on the new target
        else root._reconcile()
    }

    // Record that, now (the target picker, "Record"). During the buffer, a pick that
    // IS the buffer's target records beside it (SIGRTMIN, nothing lost); anything
    // else needs the recorder to itself — the buffer stops for it and clipping
    // picks back up when the recording ends.
    function recordTarget(key) {
        root._localError = ""
        if (root.mode === "record" || root.starting) return
        if (key === "region") { root._slurpFor = "record"; root._slurp(); return }
        const r = root._resolve(key)
        if (!r || r.what === "") { root._localError = "Nothing to capture there"; return }
        root._recordWhat(r.what, r.geom, key === root.targetKey)
    }
    // Record one window's area once the screen is clear: the overview's inspector closes
    // the overview and goes to the window first, so recording at once would film the
    // overview. Its rectangle is resolved when the wait ends (where the window is THEN).
    function recordWindowSoon(address) {
        root._soonKey = "win:" + Hypr.addr(address)
        recordSoon.restart()
    }
    property string _soonKey: ""
    Timer {
        id: recordSoon
        interval: 700
        onTriggered: root.recordTarget(root._soonKey)
    }

    function _recordWhat(what, geom, sameAsBuffer) {
        if (root.buffering && sameAsBuffer && !root.recording) { root._signal("record"); return }
        if (root.buffering) {
            root._pendingRecord = { what: what, geom: geom }
            root._signal("stop")
            return
        }
        root._startRecord(what, geom)
    }

    // ══ Controls ══════════════════════════════════════════════════════════════
    // ══ Clipping — the switch that keeps the buffer running ═══════════════════
    readonly property bool clipping: Config.clipsBuffer
    function setClipping(on) { Config.clipsBuffer = on }
    function toggleClipping() { Config.clipsBuffer = !Config.clipsBuffer }

    // What should be true, and whether we know enough yet to act on it: the run
    // dir made, the recorder probed, and the runner's state read (a buffer left
    // running by the last shell must be found, not started twice).
    // `Gamemode.holdsClips` (Config.gamemodeClips, off by default) is the one thing besides the
    // user's own switch that wants it: a HOLD that lasts as long as game mode, and never writes
    // Config.clipsBuffer — so the buffer stops with the mode unless the user also left it on.
    readonly property bool wantBuffer: Config.clips && (Config.clipsBuffer || Gamemode.holdsClips) && root.installed
    readonly property bool ready: root._dirReady && root.probed && root._stateSeen
    property bool _stateSeen: false

    // A recorder that dies on start (a monitor that went away, a codec the GPU
    // lacks) would otherwise be relaunched forever: retry after a pause, and after
    // three failures in a row stop trying until the switch is flipped again. A
    // buffer that has run for 30s resets the count.
    readonly property int _maxFailures: 3
    property int _failures: 0
    property bool gaveUp: false
    property real _launchedAt: 0
    property real _lastFailAt: 0
    Timer { id: retryTimer; interval: 5000; onTriggered: root._reconcile() }
    Timer { interval: 30000; running: root.buffering; onTriggered: root._failures = 0 }

    onWantBufferChanged: {
        root.gaveUp = false
        root._failures = 0
        retryTimer.stop()
        root._reconcile()
    }
    onReadyChanged: root._reconcile()
    // "Focused monitor" can't resolve before Hyprland names one (at login).
    Connections {
        target: Hyprland
        function onFocusedMonitorChanged() { if (root.wantBuffer && !root.busy) root._reconcile() }
    }

    function _reconcile() {
        if (!root.ready || root.starting || root._pendingRecord !== null) return
        if (root.wantBuffer) {
            if (root.mode === "idle" && !root.gaveUp && !retryTimer.running) root._startBuffer()
        } else if (root.buffering) {
            root._signal("stop")
        }
    }

    // Every state the runner writes lands here.
    function _onState() {
        if (root.busy) root.starting = false
        // A launch of ours that ended in an error (not a stop we asked for).
        const at = root._d.at ?? 0
        const failed = root.mode === "idle" && (root._d.error ?? "") !== ""
                       && root._launchedAt > 0 && at >= root._launchedAt && at !== root._lastFailAt
        if (failed) {
            root._lastFailAt = at
            root.starting = false
            if (root.wantBuffer && root._pendingRecord === null) {
                root._failures++
                if (root._failures >= root._maxFailures) {
                    root.gaveUp = true
                    Quickshell.execDetached(["notify-send", "--app-name=Clips", "--icon=media-record",
                                             "Clipping stopped", root._d.error])
                } else {
                    retryTimer.restart()
                }
                return
            }
        }
        // A recording was picked while the buffer ran: it has stopped, record now.
        if (root._pendingRecord !== null && root.mode === "idle") {
            const p = root._pendingRecord
            root._pendingRecord = null
            root._startRecord(p.what, p.geom)
            return
        }
        root._reconcile()
    }

    function _startBuffer() {
        if (root.blocker() !== "" || root.busy || root.starting) return
        const w = root._bufferWhat()
        root._launchedSettings = JSON.stringify(root.settings)
        root._launch("replay", ClipsJs.recorderArgv(root.opts, "replay", w[0], root.saveDir, w[1]))
    }
    // The button, the panel, the gallery, the page and the keybind all mean the switch.
    function toggleBuffer() { root.toggleClipping() }
    // Settings apply when the recorder starts; this is that, on purpose. The
    // buffer's contents go with it.
    function restartBuffer() {
        if (!root.buffering) return
        root._signal("stop")
    }

    // Save the buffer: `seconds` (0/undefined = Config.clipsSaveSeconds; that 0 =
    // the whole buffer). Only lengths the recorder can cut on a signal are exact.
    function saveClip(seconds) {
        if (!root.buffering) {
            // Said out loud: this is usually a keybind pressed mid-game, with no
            // card on screen, and a silent no-op reads as a broken key.
            const why = !Config.clips        ? "Clips is off — Settings › Sidebar & dock › Clips."
                      : root.blocker() !== "" ? root.blocker() + "."
                      : !Config.clipsBuffer  ? "Clipping is off — Alt+Shift+F10 turns it on."
                      : root.gaveUp          ? "The recorder keeps failing: " + root.lastError
                      :                        "The replay buffer is still starting."
            root._localError = why
            Quickshell.execDetached(["notify-send", "--app-name=Clips", "--icon=media-record",
                                     "Nothing to clip", why])
            return
        }
        const n = seconds > 0 ? seconds : Config.clipsSaveSeconds
        root._signal(ClipsJs.saveCommand(n, root.bufferSeconds))
    }

    // ══ Clip it, and what comes next ══════════════════════════════════════════
    // `clipIt` is what the buttons mean: with Config.clipsAhead > 0 it keeps recording that many
    // more seconds and THEN saves (`ahead` = { at, delay, plan } while it waits), otherwise it saves
    // at once. The recorder can only cut a few fixed lengths on a signal, so the save asks for the
    // next length up and, when that is more than wanted, the file is cut down to size as it lands
    // (clips.js aheadPlan → `_trim`, clips-lib.py headtrim). The keybind and IPC stay plain
    // `saveClip`: pressing a key mid-game means NOW.
    property var ahead: null
    readonly property bool aheadWaiting: root.ahead !== null
    function clipIt(seconds) { root.clipAhead(seconds, Config.clipsAhead) }
    // `after` seconds more, whatever the setting says (the IPC call, a preset button).
    function clipAhead(seconds, after) {
        if (root.ahead !== null) return
        if (!root.buffering || !(after > 0)) { root.saveClip(seconds); return }
        const n = seconds > 0 ? seconds : Config.clipsSaveSeconds
        const plan = ClipsJs.aheadPlan(n, after, root.bufferSeconds)
        if (plan.delay <= 0) { root.saveClip(seconds); return }
        root.ahead = { at: Date.now(), delay: plan.delay, plan: plan, seconds: n }
        aheadTimer.interval = plan.delay * 1000
        aheadTimer.restart()
    }
    Timer { id: aheadTimer; onTriggered: root._finishAhead() }
    function _finishAhead() {
        const a = root.ahead
        root.ahead = null
        if (!a) return
        if (!root.buffering) {
            Quickshell.execDetached(["notify-send", "--app-name=Clips", "--icon=media-record",
                                     "Nothing to clip", "The replay buffer stopped before the clip could be saved."])
            return
        }
        // Only the NEXT replay file is ours to cut.
        root._trim = a.plan.keep > 0 ? { keep: a.plan.keep, since: Date.now() - 500 } : null
        trimExpiry.restart()
        root._signal(a.plan.command)
    }
    // Changed your mind: nothing is saved.
    function cancelAhead() { aheadTimer.stop(); root.ahead = null }
    // Don't wait any longer: save what the buffer holds now.
    function saveAheadNow() {
        const a = root.ahead
        root.cancelAhead()
        if (a) root.saveClip(a.seconds)
    }

    property var _trim: null                  // { keep, since } — the next replay file gets cut
    Timer { id: trimExpiry; interval: 30000; onTriggered: root._trim = null }
    Process {
        id: trimProc
        property string forPath: ""
        onExited: function (code) {
            if (code !== 0) root._localError = "Couldn't cut the clip to length"
            root.refresh()
        }
    }
    function _trimSaved(path) {
        const t = root._trim
        root._trim = null
        trimExpiry.stop()
        if (!t) return
        trimProc.forPath = path
        trimProc.command = ["nice", "-n", "10", "python3", root._lib, "headtrim", path, String(t.keep)]
        trimProc.running = false
        trimProc.running = true
    }

    // Record: during the buffer, a regular recording beside it (into the same
    // folder); otherwise a recording of its own.
    function toggleRecord() {
        if (root.buffering)            root._signal("record")
        else if (root.mode === "record") root._signal("stop")
        else                            root._startRecord(root._target(), "")
    }
    function stopRecord() {
        if (root.mode === "record") root._signal("stop")
        else if (root.buffering && root.recording) root._signal("record")
    }
    function pause() { if (root.mode === "record") root._signal("pause") }

    // Drag a region with slurp, then record it (or, from the clip cell's picker,
    // clip it from now on). A recording of something other than the buffer's
    // target needs the recorder to itself: the buffer is stopped for it (its
    // contents go) and clipping picks back up when the recording ends.
    property var _pendingRecord: null         // { what, geom } waiting for the buffer to stop
    property string _slurpFor: "record"       // "record" | "buffer"
    function recordRegion() {
        if (root.blocker() !== "" || root.mode === "record" || root.starting) return
        root._slurpFor = "record"
        root._slurp()
    }
    // Record a region that is already chosen (the snip tool's): "WxH+X+Y", global and logical.
    function recordArea(geom) {
        const g = ClipsJs.region(geom)
        if (g === "" || root.blocker() !== "" || root.mode === "record" || root.starting) return
        root._recordWhat("region", g, false)
    }
    function _slurp() {
        if (root.blocker() !== "") return
        if (!root.hasSlurp) { root._localError = "slurp isn't installed"; return }
        slurpProc.running = false
        slurpProc.running = true
    }
    Process {
        id: slurpProc
        command: ["slurp", "-f", "%wx%h+%x+%y"]
        stdout: StdioCollector {
            // A cancelled drag prints nothing and exits non-zero: not an error.
            onStreamFinished: {
                const g = ClipsJs.region(text)
                if (g === "") return
                if (root._slurpFor === "buffer") {
                    root.sessionTarget = { kind: "region", geom: g, label: "Region " + g.split("+")[0], key: "region" }
                    root._applyTarget()
                } else {
                    root._recordWhat("region", g, false)
                }
            }
        }
    }

    function _startRecord(what, geom) {
        if (root.blocker() !== "" || root.busy || root.starting) return
        const name = "Recording_" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_hh-mm-ss")
                   + "." + root.settings.container
        root._launch("record", ClipsJs.recorderArgv(root.opts, "record", what, root.saveDir + "/" + name, geom))
    }

    function _launch(mode, argv) {
        // The keybinds reach here too. With the feature off there is no button to
        // show that the screen is being recorded, so nothing starts.
        if (!Config.clips) {
            root._localError = "Clips is off — Settings › Sidebar & dock › Clips"
            return
        }
        if (!argv) {
            root._localError = "Nothing to capture — no focused monitor, or an invalid target"
            return
        }
        root._localError = ""
        root.starting = true
        root._launchedAt = Date.now()
        startingTimer.restart()
        // setsid + disown: the runner outlives this shell (see the header).
        launchProc.command = ["bash", "-c",
            'mkdir -p "$1" && setsid python3 "$0" start "$1" "$2" "$3" < /dev/null > /dev/null 2>&1 & disown; exit 0',
            root._runner, root._runDir, mode, JSON.stringify(argv)]
        launchProc.running = false
        launchProc.running = true
    }
    Process { id: launchProc; running: false }

    // Signals return at once; detached so two in a row don't cancel each other.
    function _signal(what) {
        root._localError = ""
        Quickshell.execDetached(["python3", root._runner, "signal", root._runDir, what])
    }

    // Turning the feature off stops what's running — a buffer nobody can see is a
    // screen recording nobody knows about.
    // Turning it on indexes the library.
    readonly property bool enabled: Config.clips
    onEnabledChanged: {
        if (root.enabled) root.refresh()
        else if (root.busy) root._signal("stop")
    }

    // ══ The state files ═══════════════════════════════════════════════════════
    // FileView watches a file's DIRECTORY to see it created, and only if the
    // directory exists when the watch is set up — so the run dir is made first,
    // a dead daemon's state reconciled (`check`), and only then the paths set.
    property bool _dirReady: false
    Process {
        id: prepProc
        running: true
        command: ["bash", "-c", 'mkdir -p "$1" && python3 "$0" check "$1"', root._runner, root._runDir]
        onExited: root._dirReady = true
    }

    // The runner's hook names a clip after the window while `naming` is "window"; it reads that from
    // the state file (the daemon is started once), so the setting is handed over here — when the
    // run dir exists, and whenever the switch moves.
    function _syncNaming() {
        if (!root._dirReady) return
        Quickshell.execDetached(["python3", root._runner, "set", root._runDir, "naming",
                                 Config.clipsNameByWindow ? "window" : "plain"])
    }
    on_DirReadyChanged: root._syncNaming()
    Connections { target: Config; function onClipsNameByWindowChanged() { root._syncNaming() } }

    FileView {
        id: stateFile
        path: root._dirReady ? root._runDir + "/state.json" : ""
        watchChanges: true
        onFileChanged: stateFile.reload()
        onLoaded: {
            try { root._d = JSON.parse(stateFile.text()) || {} }
            catch (e) { /* a torn read; the rename makes it rare — keep the last good state */ }
            root._stateSeen = true
            root._onState()
        }
        onLoadFailed: { root._d = ({}); root._stateSeen = true; root._onState() }
    }

    // Saved files. Read by TIME: every event after the newest one seen when this
    // started is new (the runner trims the file, so a line count would drift).
    property real _seen: -1
    FileView {
        id: eventsFile
        path: root._dirReady ? root._runDir + "/events.jsonl" : ""
        watchChanges: true
        onFileChanged: eventsFile.reload()
        onLoaded: {
            const all = ClipsJs.parseEvents(eventsFile.text())
            if (root._seen < 0) {
                root._seen = all.reduce((m, e) => Math.max(m, e.t), 0)
                return
            }
            for (const e of ClipsJs.newEvents(all, root._seen)) root._announce(e)
            root._seen = all.reduce((m, e) => Math.max(m, e.t), root._seen)
        }
        onLoadFailed: if (root._seen < 0) root._seen = 0
    }

    // ══ A clip was saved ══════════════════════════════════════════════════════
    // `lastSaved` is kept (never cleared) so the peek card still has it while it
    // fades out; `savedId` bumps per save so the same path twice still peeks.
    property var lastSaved: null
    property int savedId: 0
    signal saved(string path, string type)

    function _announce(e) {
        if (e.type === "screenshot") return
        if (e.type === "replay" && root._trim && e.t >= root._trim.since) root._trimSaved(e.path)
        root.lastSaved = e
        root.savedId++
        root.saved(e.path, e.type)
        Sfx.play("clipsaved")
        refreshSoon.restart()
        if (Config.clipsNotify) {
            const name = e.path.substring(e.path.lastIndexOf("/") + 1)
            Quickshell.execDetached(["notify-send", "--app-name=Clips", "--icon=media-record",
                                     e.type === "replay" ? "Clip saved" : "Recording saved", name])
        }
    }

    // ══ The library ═══════════════════════════════════════════════════════════
    // [{ path, name, ext, size, mtime, ok, duration, width, height, thumb, key }],
    // newest first (clips-lib.py index). Refreshed on a save, on the gallery
    // opening, and when the feature comes on — never polled.
    property var clips: []
    readonly property var latest: root.clips.length > 0 ? root.clips[0] : null
    property bool indexing: false
    property bool _again: false

    function refresh() {
        if (!Config.clips) return
        if (indexProc.running) { root._again = true; return }
        root.indexing = true
        indexProc.command = ["nice", "-n", "10", "python3", root._lib, "index", root.saveDir, root._cacheDir]
        indexProc.running = true
    }
    Timer { id: refreshSoon; interval: 400; onTriggered: root.refresh() }
    Process {
        id: indexProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(text)
                    if (Array.isArray(list)) root.clips = list
                } catch (e) {
                    console.warn("Clips: unreadable index")
                }
            }
        }
        onExited: {
            root.indexing = false
            if (root._again) { root._again = false; root.refresh() }
        }
    }

    // One clip's filmstrip, for the trimmer: `strip` = { path, frames: [file…] }.
    property var strip: ({ path: "", frames: [] })
    function loadStrip(path, n) {
        if (root.strip.path === path && root.strip.frames.length > 0) return
        root.strip = { path: path, frames: [] }
        stripProc.command = ["nice", "-n", "10", "python3", root._lib, "strip", path, root._cacheDir, String(n)]
        stripProc.running = false
        stripProc.running = true
    }
    Process {
        id: stripProc
        property string forPath: ""
        onStarted: stripProc.forPath = root.strip.path
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const f = JSON.parse(text)
                    if (Array.isArray(f) && stripProc.forPath === root.strip.path)
                        root.strip = { path: stripProc.forPath, frames: f }
                } catch (e) { }
            }
        }
    }

    // ══ File actions ══════════════════════════════════════════════════════════
    // Rename and save-frame run in clips-lib.py (validated there — the trust
    // boundary is its argv); the result lands in `actionResult` = { ok, text, path,
    // id, select } — `select` false for a file that isn't a clip (a PNG frame).
    property var actionResult: ({ ok: true, text: "", path: "", id: 0, select: false })
    property bool acting: false

    function rename(path, name) {
        root._act(["python3", root._lib, "rename", path, String(name)], "Renamed", path, true)
    }
    // One frame as a PNG beside the clip.
    function saveFrame(path, seconds) {
        root._act(["python3", root._lib, "frame", path, String(Math.max(0, seconds))], "Saved frame", path, false)
    }
    function _act(cmd, verb, from, select) {
        if (actProc.running) return
        root.acting = true
        actProc.verb = verb
        actProc.from = from
        actProc.select = select
        actProc.command = cmd
        actProc.running = true
    }
    function _result(ok, path, text, select) {
        root.actionResult = { ok: ok, path: ok ? path : "", id: root.actionResult.id + 1,
                              select: ok && select, text: text }
    }
    Process {
        id: actProc
        property string verb: ""
        property string from: ""
        property bool select: false
        stdout: StdioCollector { id: actOut }
        stderr: StdioCollector { id: actErr }
        onExited: function (code) {
            root.acting = false
            const ok = code === 0
            const p = actOut.text.trim()
            if (ok && actProc.verb === "Renamed") root._moveFavourite(actProc.from, p)
            root._result(ok, p, ok ? actProc.verb + " — " + p.substring(p.lastIndexOf("/") + 1)
                                   : (actErr.text.trim() || "Failed"), actProc.select)
            root.refresh()
        }
    }

    // ══ Export — the editor's one command ═════════════════════════════════════
    // clips-lib.py `export` (see its header for the options): streams progress,
    // ends with the new file's path. Cancelling kills the runner, which takes
    // ffmpeg down and removes the half-written file itself.
    property bool exporting: false
    property real exportProgress: 0
    function exportClip(path, start, end, options) {
        if (exportProc.running || !path) return
        root.exporting = true
        root.exportProgress = 0
        exportProc.out = ""
        exportProc.command = ["nice", "-n", "10", "python3", root._lib, "export", path,
                              String(start), String(end), JSON.stringify(options || {})]
        exportProc.running = true
    }
    function cancelExport() {
        if (!exportProc.running) return
        exportProc.cancelled = true
        root._exportQueue = []
        exportProc.signal(15)
    }

    // Several at once (the gallery's bulk "shrink"): one after another through the same export, each
    // whole clip with the same options. `exportBatch` says one is in progress, `exportTotal` / `exportDone`
    // how far. Cancelling drops what is still waiting.
    property var _exportQueue: []
    property int exportTotal: 0
    property int exportDone: 0
    readonly property bool exportBatch: root.exportTotal > 0
    function exportMany(entries, options) {
        if (root.exporting || root.exportTotal > 0) return
        const jobs = (entries || []).filter(e => e && e.ok && e.duration > 0)
                                    .map(e => ({ path: e.path, end: e.duration, options: options }))
        if (jobs.length === 0) return
        root._exportQueue = jobs
        root.exportTotal = jobs.length
        root.exportDone = 0
        root._exportNext()
    }
    function _exportNext() {
        if (exportProc.running) return
        if (root._exportQueue.length === 0) { root.exportTotal = 0; return }
        const j = root._exportQueue[0]
        root._exportQueue = root._exportQueue.slice(1)
        root.exportClip(j.path, 0, j.end, j.options)
    }
    Process {
        id: exportProc
        property string out: ""
        property bool cancelled: false
        stdout: SplitParser {
            onRead: function (line) {
                if (line.startsWith("progress ")) root.exportProgress = parseFloat(line.slice(9)) || 0
                else if (line.startsWith("done ")) exportProc.out = line.slice(5)
            }
        }
        stderr: StdioCollector { id: exportErr }
        onExited: function (code) {
            root.exporting = false
            const ok = code === 0 && exportProc.out !== ""
            const p = exportProc.out
            root._result(ok, p,
                         ok ? "Exported — " + p.substring(p.lastIndexOf("/") + 1)
                            : exportProc.cancelled ? "Export cancelled"
                            : (exportErr.text.trim() || "Export failed"),
                         ok && !p.endsWith(".gif"))
            exportProc.cancelled = false
            root.refresh()
            if (root.exportTotal > 0) { root.exportDone++; Qt.callLater(root._exportNext) }
        }
    }

    // ══ Favourites ════════════════════════════════════════════════════════════
    // Paths, in their own small document (never config.json — see Guardrails).
    // Hand-editable, so what's read is filtered to absolute paths. A rename moves
    // the star; a delete takes it.
    JsonStore {
        id: favStore
        path: Quickshell.statePath("clip-favourites.json")
        defaults: ({ paths: [] })
    }
    readonly property var favourites:
        (Array.isArray(favStore.value.paths) ? favStore.value.paths : []).filter(p => typeof p === "string" && p.startsWith("/"))
    function isFavourite(path) { return root.favourites.indexOf(path) >= 0 }
    function toggleFavourite(path) {
        if (!path) return
        const on = root.isFavourite(path)
        favStore.value = { paths: on ? root.favourites.filter(p => p !== path) : root.favourites.concat([path]) }
    }
    function _moveFavourite(from, to) {
        if (!root.isFavourite(from) || !to) return
        favStore.value = { paths: root.favourites.map(p => p === from ? to : p) }
    }

    // `gio`, as Places does: trash rather than delete (a mis-click on a clip you
    // meant to keep is exactly where "gone forever" is wrong), open in the user's
    // own player, show the folder.
    function trashClip(path) {
        if (!path || !path.startsWith("/")) return
        Quickshell.execDetached(["gio", "trash", "--", path])
        root.clips = root.clips.filter(c => c.path !== path)
        if (root.isFavourite(path)) favStore.value = { paths: root.favourites.filter(p => p !== path) }
        refreshSoon.restart()
    }
    // Many at once: one `gio trash`, one favourites write.
    function trashClips(paths) {
        const list = (paths || []).filter(p => typeof p === "string" && p.startsWith("/"))
        if (list.length === 0) return
        Quickshell.execDetached(["gio", "trash", "--"].concat(list))
        root.clips = root.clips.filter(c => list.indexOf(c.path) < 0)
        favStore.value = { paths: root.favourites.filter(p => list.indexOf(p) < 0) }
        refreshSoon.restart()
    }
    // Star all of them, or take the star off all of them.
    function setFavourites(paths, on) {
        const list = (paths || []).filter(p => typeof p === "string" && p.startsWith("/"))
        const rest = root.favourites.filter(p => list.indexOf(p) < 0)
        favStore.value = { paths: on ? rest.concat(list) : rest }
    }
    // Play a clip: in THIS shell — the gallery opens on its player (the editor, view-only) — not in
    // whatever app the system calls the default for video (mpv, here). Only when the shell can't play
    // (qt6-multimedia missing) does it hand the file to that app, as it always did. `openClip` is that
    // external open, kept for the editor's "open in the default app".
    property string playRequest: ""
    function playClip(path) {
        if (!path) return
        if (Media.checked && !Media.available) { root.openClip(path); return }
        root.playRequest = path
        UiState.clipsGalleryOpen = true
        root.refresh()
    }
    function openClip(path)  { if (path) Quickshell.execDetached(["gio", "open", "--", path]) }
    // ── Folders open in a FILE MANAGER ────────────────────────────────────────
    // Not `gio open`: the default handler for a directory can be a terminal browser, and "open the
    // folder" must not mean a `cd` in a terminal. `fileManager` is the preferred one (Config.clipsFileManager)
    // or the first installed (clips.js pickFileManager — Nautilus first); only when none is known does it
    // fall back to `gio open`. `showInFolder` selects the file where the manager can.
    property var fileManagers: []             // the ids of the installed ones
    readonly property string fileManager: ClipsJs.pickFileManager(Config.clipsFileManager, root.fileManagers)
    function _showIn(dir, select) {
        const argv = root.fileManager !== "" ? ClipsJs.fileManagerArgv(root.fileManager, dir, select) : null
        // The folder is made first (a library that doesn't exist yet), then the manager runs in its place.
        if (argv) Quickshell.execDetached(["bash", "-c", 'mkdir -p "$1"; shift; exec "$@"', "bash", dir].concat(argv))
        else      Quickshell.execDetached(["bash", "-c", 'mkdir -p "$1" && exec gio open -- "$1"', "bash", dir])
    }
    function showInFolder(path) {
        if (path) root._showIn(path.substring(0, path.lastIndexOf("/")), path)
    }
    function openFolder() { root._showIn(root.saveDir, "") }
    // As files, the way a file manager copies them: a paste into a chat attaches it.
    function copyClip(path) {
        if (!path) return
        // encodeURI leaves # and ? alone, and in a URI those end the path.
        const uri = "file://" + encodeURI(path).replace(/#/g, "%23").replace(/\?/g, "%3F")
        Clipboard.copyText(uri + "\r\n", "text/uri-list")
    }

    function openGallery() { UiState.clipsGalleryOpen = true; root.refresh() }

    // ══ Health: what the machine has, and what is wrong ═══════════════════════
    // Free RAM and disk, the recorder's own memory (the replay buffer lives in it) and whether
    // gsr-kms-server may capture — probed by ONE small script, and only while something is looking:
    // the Clips panel holds `acquireHealth()` while it is open (every 5s), and a failed start
    // refreshes it once so `diagnosis` can say why. Nothing here runs in the background.
    property var health: ({ memAvailMiB: 0, ramMiB: 0, diskFreeMiB: 0, kms: null })
    property int _healthRefs: 0
    function acquireHealth() { root._healthRefs++ }
    function releaseHealth() { root._healthRefs = Math.max(0, root._healthRefs - 1) }
    Timer {
        interval: 5000
        repeat: true
        running: root._healthRefs > 0 && Config.clips
        triggeredOnStart: true
        onTriggered: root.refreshHealth()
    }
    function refreshHealth() {
        if (healthProc.running) return
        healthProc.command = ["bash", "-c",
            'd="$1"; while [ ! -d "$d" ] && [ "$d" != / ]; do d=$(dirname "$d"); done\n'
          + 'echo "mem=$(awk \'/MemAvailable/ {printf "%d", $2/1024}\' /proc/meminfo)"\n'
          + 'echo "disk=$(df -Pm "$d" 2>/dev/null | awk \'NR==2 {print $4}\')"\n'
          + 'pid="$2"; if [ "$pid" -gt 1 ] 2>/dev/null; then echo "ram=$(awk \'/VmRSS/ {printf "%d", $2/1024}\' /proc/$pid/status 2>/dev/null)"; fi\n'
          + 'k=$(command -v gsr-kms-server); if [ -z "$k" ]; then echo kms=?; elif getcap "$k" 2>/dev/null | grep -q cap_sys_admin; then echo kms=1; else echo kms=0; fi',
            "_", root.saveDir, String(root._d.pid ?? 0)]
        healthProc.running = true
    }
    Process {
        id: healthProc
        stdout: StdioCollector {
            onStreamFinished: {
                const h = { memAvailMiB: 0, ramMiB: 0, diskFreeMiB: 0, kms: null }
                for (const line of text.split("\n")) {
                    const i = line.indexOf("=")
                    if (i < 0) continue
                    const k = line.slice(0, i), v = line.slice(i + 1).trim()
                    if (k === "mem") h.memAvailMiB = parseInt(v) || 0
                    else if (k === "disk") h.diskFreeMiB = parseInt(v) || 0
                    else if (k === "ram") h.ramMiB = parseInt(v) || 0
                    else if (k === "kms") h.kms = v === "1" ? true : v === "0" ? false : null
                }
                root.health = h
            }
        }
    }
    // A buffer that failed to start: look again, so the explanation is of NOW.
    onGaveUpChanged: if (root.gaveUp) root.refreshHealth()

    function _screenNames() {
        const out = []
        for (let i = 0; i < Quickshell.screens.length; i++) out.push(Quickshell.screens[i].name)
        return out
    }
    // [{ id, level: "error" | "warn", text, fix }], worst first (clips.js diagnose). The panel shows the
    // first one under its state line, with a button for `fix` where there is one.
    readonly property var diagnosis: ClipsJs.diagnose({
        probed: root.probed, installed: root.installed, wanted: root.wantBuffer, buffering: root.buffering,
        gaveUp: root.gaveUp, error: root._d.error ?? "",
        target: root.sessionTarget ? "" : (Config.clipsTarget || ""), screens: root._screenNames(),
        kms: root.health.kms, memAvailMiB: root.health.memAvailMiB, diskFreeMiB: root.health.diskFreeMiB,
        opts: root.opts
    })
    readonly property var topIssue: root.diagnosis.length > 0 ? root.diagnosis[0] : null
    // The fixes the service can make itself; the panel handles the ones that need a picker.
    function fixLabel(fix) {
        return fix === "portal" ? "Use the portal" : fix === "codec" ? "Use Auto codec"
             : fix === "buffer" ? "Keep it on disk" : fix === "target" ? "Pick a target"
             : fix === "folder" ? "Open settings" : ""
    }
    function applyFix(fix) {
        if (fix === "portal") root.retarget("portal")
        else if (fix === "codec") { Config.clipsCodec = "auto"; root.restartBuffer() }
        else if (fix === "buffer") { Config.clipsStorage = "disk"; root.restartBuffer() }
    }

    // ══ Stop after… ═══════════════════════════════════════════════════════════
    // `Config.clipsRecordLimit` — a time or a size, for the recording you might forget about.
    // Checked every 3s while one runs (a pause counts: it is wall-clock). A SIZE needs the file's
    // size, which the lib reports (`size`): a plain recording by its path, one started during the buffer
    // by the newest Video_* since it began.
    readonly property var limit: ClipsJs.limitOf(Config.clipsRecordLimit)
    property real recordBytes: 0
    Timer {
        interval: 3000
        repeat: true
        running: root.recording && root.limit.id !== "off"
        onTriggered: root._checkLimit()
    }
    function _checkLimit() {
        const secs = root.recordSince > 0 ? (Date.now() - root.recordSince) / 1000 : 0
        if (root.limit.bytes > 0) {
            if (sizeProc.running) return
            sizeProc.command = ["python3", root._lib, "size", root.saveDir, String(root.recordSince),
                                root.mode === "record" ? (root._d.output ?? "") : ""]
            sizeProc.running = true
            return
        }
        root._limitCheck(ClipsJs.limitHit(root.limit.id, secs, 0))
    }
    Process {
        id: sizeProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.recordBytes = parseInt(text.trim()) || 0
                const secs = root.recordSince > 0 ? (Date.now() - root.recordSince) / 1000 : 0
                root._limitCheck(ClipsJs.limitHit(root.limit.id, secs, root.recordBytes))
            }
        }
    }
    function _limitCheck(hit) {
        if (hit === "" || !root.recording) return
        Quickshell.execDetached(["notify-send", "--app-name=Clips", "--icon=media-record", "Recording stopped",
                                 "It reached its limit (" + root.limit.label + ")."])
        root.stopRecord()
    }

    // ══ Quick actions on a clip ═══════════════════════════════════════════════
    // Open the gallery's editor on it (the gallery consumes `editRequest` and clears it).
    property string editRequest: ""
    function editClip(path) {
        if (!path) return
        root.editRequest = path
        UiState.clipsGalleryOpen = true
        root.refresh()
    }
    // To Discord: the file goes on the clipboard the way a file manager copies it, and Discord's
    // window comes forward if it is open — a paste into a chat attaches the clip.
    function sendToDiscord(path) {
        if (!path) return
        root.copyClip(path)
        const open = Discord.windowAddress !== ""
        if (open) Discord.focusWindow()
        Quickshell.execDetached(["notify-send", "--app-name=Clips", "--icon=media-record",
                                 "Clip copied", open ? "Paste it into a Discord chat." : "Discord isn't open — paste it wherever you like."])
    }
    // A text/uri-list for these files (what a file manager copies and what a drag carries); "" for none.
    function uriList(paths) {
        const list = (paths || []).filter(p => typeof p === "string" && p.startsWith("/"))
        // encodeURI leaves # and ? alone, and in a URI those end the path.
        return list.length === 0 ? ""
            : list.map(p => "file://" + encodeURI(p).replace(/#/g, "%23").replace(/\?/g, "%3F")).join("\r\n") + "\r\n"
    }
    // Several files at once, as a file manager copies them.
    function copyClips(paths) {
        const u = root.uriList(paths)
        if (u !== "") Clipboard.copyText(u, "text/uri-list")
    }

    // ══ Probes ════════════════════════════════════════════════════════════════
    Process {
        running: true
        command: ["bash", "-c", 'command -v gpu-screen-recorder >/dev/null; a=$?; command -v slurp >/dev/null; echo "$a $?"']
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(" ")
                root.installed = p[0] === "0"
                root.hasSlurp = p[1] === "0"
                root.probed = true
            }
        }
    }
    Process {
        running: true
        command: ["bash", "-c", 'for b in "$@"; do command -v "$b" >/dev/null 2>&1 && echo "$b"; done', "bash"]
                 .concat(ClipsJs.FILE_MANAGERS.map(f => f.bin))
        stdout: StdioCollector {
            onStreamFinished: root.fileManagers = text.split("\n").map(l => l.trim()).filter(l => l !== "")
        }
    }
    Component.onCompleted: if (Config.clips) root.refresh()

    // ══ IPC — for keybinds ════════════════════════════════════════════════════
    //   qs ipc -c ~/.config/quicktest call clips save        clip it
    //   qs ipc -c ~/.config/quicktest call clips saveLast 30 the last 30 seconds
    //   qs ipc -c ~/.config/quicktest call clips saveAhead 30 10   the last 30s plus the next 10s
    //   qs ipc -c ~/.config/quicktest call clips buffer      clipping on/off (clippingOn / clippingOff)
    //   qs ipc -c ~/.config/quicktest call clips record      start/stop a recording
    //   qs ipc -c ~/.config/quicktest call clips region      record a dragged region
    //   qs ipc -c ~/.config/quicktest call clips gallery     open the library
    IpcHandler {
        target: "clips"
        function save(): void { root.saveClip(0) }
        function saveLast(seconds: int): void { root.saveClip(seconds) }
        function saveAhead(seconds: int, after: int): void { root.clipAhead(seconds, after) }
        function buffer(): void { root.toggleClipping() }        // clipping on/off
        function clippingOn(): void { root.setClipping(true) }
        function clippingOff(): void { root.setClipping(false) }
        function record(): void { root.toggleRecord() }
        function region(): void { root.recordRegion() }
        function gallery(): void { root.openGallery() }
        // States and counts only — never a file name.
        function status(): string {
            return JSON.stringify({
                enabled: Config.clips, installed: root.installed, blocker: root.blocker(),
                clipping: Config.clipsBuffer, gaveUp: root.gaveUp, failures: root._failures,
                player: Media.checked ? Media.available : "unknown", target: root.targetKey.split(":")[0],
                mode: root.mode, recording: root.recording, paused: root.paused,
                starting: root.starting, error: root.lastError !== "",
                ahead: root.aheadWaiting, stale: root.stale, limit: root.limit.id, fileManager: root.fileManager,
                issues: root.diagnosis.map(d => d.id),
                clips: root.clips.length, runDir: root._dirReady
            })
        }
    }
}
