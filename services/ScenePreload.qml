pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../config"

// ── ScenePreload ──────────────────────────────────────────────────────────────
// Scenes that workspaces own, kept RUNNING so a switch costs nothing.
//
// A Wallpaper Engine scene takes seconds to load, and the layer renderer
// (WallpaperEngine) has to be relaunched for every change of what plays on a screen.
// So each scene a workspace owns gets a renderer of its own, in WINDOW mode, parked on
// a hidden special workspace; WallpaperView draws a live capture of the one its
// screen's workspace wants (a ScreencopyView of that window). Switching workspaces is
// then a swap of which capture is shown.
//
// MEASURED (scripts/probe/, 2026-10-05): a renderer window moved to a special workspace
// kept its CPU use (13% → 13%, ~250 context switches/s both ways) — Hyprland doesn't
// starve it of frame callbacks — and a ScreencopyView of it reported content.
//
//   · The window is sent there by a RUNTIME window rule (title "wallpaperengine", the
//     one title the renderer gives it; its class is empty) put in with `hyprctl eval`,
//     as WallWave does for its layer rule, so it never maps on a workspace you're on.
//     A config reload drops runtime rules: it goes in again on `configreloaded`.
//   · Special-workspace windows are already left out of the dock, Alt+Tab, the
//     overview and the app theming (they all skip negative workspace ids).
//   · Each renderer is `scripts/wpe-window.py`, started DETACHED and adopted by the next
//     shell (found by its command line), so a reload doesn't load the scenes again.
//   · Silent, except for the SHARED scene (below): the shell shows the picture, not the
//     sound. A scene's own mouse reaction and layer depth are the layer renderer's and
//     don't exist here — the parallax is the shell's: WallpaperView pans the whole captured
//     frame with the pointer, which works for every scene, whether or not its author
//     turned camera parallax on (most didn't: 33 of 36 installed here, measured).
//   · A scene that CRASHES in window mode (one with a video layer segfaulted in libmpv
//     setup, measured) is marked failed for the session and falls back to the layer
//     renderer exactly as before: `usable(id)` is what WorkspaceTheme asks.
//
// ── The shared scene ──────────────────────────────────────────────────────────
// The scene applied as THE wallpaper (WallpaperEngine.windowShared) plays this way too,
// so the pointer parallax reaches it: the layer renderer only hears the pointer over a
// bare desktop, and only for scenes that enable parallax themselves. It is always first
// in `assigned`, and the only one with sound (WallpaperEngine.windowArgs). If it can't
// stay up in a window (`failed`, or the rule that parks it was refused), the layer
// renderer plays it exactly as before — WallpaperEngine.windowPlanned is what it asks.
//
// What it costs: every scene a workspace owns renders all the time (up to `cap`), at
// the largest screen's size. Config.wpePreload turns it off.
//
// Diagnose: `qs ipc -c ~/.config/quicktest call scenepreload status` (counts only).
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // How many scenes are kept warm; the rest use the layer renderer.
    readonly property int cap: 4

    readonly property bool enabled:
        Config.wpePreload && (Wallpaper.perWorkspace || WallpaperEngine.windowShared !== "")
        && !Gamemode.wallpaperPaused && WallpaperEngine.blocker() === ""

    // The scene ids to keep running: the shared scene first (so the cap never drops it),
    // then the ones the workspaces own, workspace order, up to `cap`.
    readonly property var assigned: {
        const ids = []
        if (WallpaperEngine.windowShared !== "") ids.push(WallpaperEngine.windowShared)
        for (let n = 1; n <= Wallpaper.pickable; n++) {
            const id = Wallpaper.sceneOf(Wallpaper.wallFor(n))
            if (id !== "" && ids.indexOf(id) < 0) ids.push(id)
        }
        return ids.slice(0, root.cap)
    }

    // id → true: crashed or vanished in window mode this session.
    property var failed: ({})
    // The runtime window rule is in (latched: a runner is never stopped by it).
    property bool ruleOk: false
    // Hyprland refused the rule: nothing can be parked, so nothing is started and the
    // layer renderer keeps every scene (WallpaperEngine.windowPlanned reads this).
    property bool ruleBad: false
    // A config reload happened and the rule hasn't gone back in yet. A reload DROPS every
    // runtime rule, and one runs on every login (autostart.lua → wal-colors.py →
    // wal-reload.sh → `hyprctl reload`) while this shell is starting. `ruleOk` stays
    // latched through it (`usable` must not flap), so this is what holds back STARTING a
    // renderer meanwhile: a scene takes seconds to map, long enough for the reload to land
    // between the rule going in and the window appearing — which maps it tiled, on screen.
    property bool _ruleStale: false
    on_RuleStaleChanged: if (!root._ruleStale && root.ruleOk) scanSoon.restart()
    // Bumped when `usable` may have changed, for the imperative reader (WorkspaceTheme).
    property int version: 0

    readonly property var wanted: root.enabled ? root.assigned.filter(i => !root.failed[i]) : []

    // Does a scene play from a window of its own? → the layer renderer leaves it alone.
    function usable(id) {
        return root.enabled && root.ruleOk && !root.failed[id] && root.assigned.indexOf(id) >= 0
    }
    onFailedChanged: root.version++
    onAssignedChanged: {
        // A scene nobody owns any more gets a fresh chance if it comes back.
        let changed = false
        const keep = {}
        for (const k in root.failed) if (root.assigned.indexOf(k) >= 0) keep[k] = true; else changed = true
        if (changed) root.failed = keep
        root.version++
    }

    // id → the window's Quickshell.Wayland Toplevel (what a ScreencopyView captures),
    // once it has mapped. Reassigned, never mutated, so bindings notify.
    property var windows: ({})

    // ── The window size: the biggest screen, in physical pixels ───────────────
    readonly property size winSize: {
        let w = 1920, h = 1080, best = 0
        for (const s of Quickshell.screens) {
            const d = s.devicePixelRatio > 0 ? s.devicePixelRatio : 1
            const pw = Math.round(s.width * d), ph = Math.round(s.height * d)
            if (pw * ph > best) { best = pw * ph; w = pw; h = ph }
        }
        return Qt.size(w, h)
    }

    // ── The rule that parks the window ────────────────────────────────────────
    readonly property string _rule:
        'hl.window_rule({ name = "quickshell-wpe", match = { title = "^wallpaperengine$" }, '
        + 'workspace = "special:qswpe silent", float = true, no_anim = true, no_focus = true })'
    Process {
        id: ruleProc
        command: ["hyprctl", "eval", root._rule]
        running: root.enabled
        stdout: StdioCollector {
            onStreamFinished: {
                // Judged as WallWave judges its layer rule: only the compositor's complaint
                // (hyprctl says "ok" for a queued eval) is a refusal.
                const out = text.trim()
                root._ruleStale = false
                if (/error|fail|unknown|expected/i.test(out)) {
                    console.warn("ScenePreload: Hyprland refused the window rule —", out)
                    root.ruleBad = true
                } else {
                    root.ruleBad = false
                    root.ruleOk = true
                }
            }
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "configreloaded" || !root.enabled) return
            root._ruleStale = true
            if (!ruleProc.running) ruleProc.running = true
        }
    }

    // ── One renderer per scene — DETACHED, and adopted on the next start ──────
    // A renderer outlives a shell reload (setsid, as WallpaperEngine's layer renderer
    // does): the new shell finds it by its command line and captures it at once, so a
    // reload doesn't load every scene again — and doesn't show a scene's still while it
    // does. What starts, stops and counts as failed is decided by one scan of the
    // running renderers (`_scan` → `_reconcile`); nothing here is a child of the shell.
    //
    // They are left running if the shell goes away for good (they end with the
    // session); turning preload off, reassigning a workspace or Game Mode ends them.
    property var pids: ({})              // id → pid of its renderer
    property var _spawnAt: ({})          // id → when it was last started (ms)
    property var _attempts: ({})         // id → starts without a window ever appearing
    readonly property int graceMs: 5000  // a started renderer is looked for this long

    Component { id: oneShot; Process { onExited: Qt.callLater(destroy) } }
    function _run(argv) {
        const p = oneShot.createObject(root, { command: argv })
        p.running = true
    }

    // Start a scene's renderer again, for options that only apply at launch (volume, fps,
    // particles). Killed here; the next scan finds it missing and starts it, with the
    // grace period that spares it a second start while the first still loads.
    function restart(id) {
        const pid = root.pids[id]
        if (!pid) return
        root._spawnAt[id] = 0
        root._run(["kill", "--", String(pid)])
        const next = Object.assign({}, root.pids)
        delete next[id]
        root.pids = next
        const w = Object.assign({}, root.windows)
        delete w[id]
        root.windows = w
        scanSoon.restart()
    }

    function _spawn(id) {
        const at = root._attempts[id] ?? 0
        if (at >= 3) {
            console.warn("ScenePreload: scene", id, "won't stay up in window mode; it plays from the layer renderer instead")
            const f = Object.assign({}, root.failed)
            f[id] = true
            root.failed = f
            return
        }
        root._attempts[id] = at + 1
        root._spawnAt[id] = Date.now()
        root._run(["setsid", "--fork", "python3", Quickshell.shellPath("scripts/wpe-window.py"),
                   (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell-quicktest-wpe-" + id + ".log"]
                  .concat(WallpaperEngine.windowArgs(id, root.winSize.width, root.winSize.height)))
        recheck.restart()
    }

    // OUR running window-mode renderers: "<pid> <command line>" per line. Ours = writing
    // to one of our log files (scripts/wpe-window.py gives each its own), so a preview
    // window someone started by hand is neither adopted nor killed as stale.
    Process {
        id: scanProc
        command: ["bash", "-c",
                  'for p in $(pgrep -f "$1"); do case "$(readlink /proc/$p/fd/1 2>/dev/null)" in '
                  + '*/quickshell-quicktest-wpe-*.log) echo "$p $(tr "\\0" " " < /proc/$p/cmdline)";; esac; done',
                  "scan", "(^|/)linux-wallpaperengine --window "]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = []
                for (const line of text.split("\n")) {
                    const m = /^(\d+) .*--bg (\S+)/.exec(line)
                    if (m) found.push({ pid: parseInt(m[1]), bg: m[2] })
                }
                root._reconcile(found)
            }
        }
    }
    Timer { id: scanSoon; interval: 250; onTriggered: if (!scanProc.running) scanProc.running = true }
    // A start is looked at again once it has had time to show up, and once it has had
    // time to die: a renderer that exits on load is never seen by an event.
    Timer {
        id: recheck
        interval: 900
        property int n: 0
        onTriggered: {
            scanSoon.restart()
            if (recheck.n++ < 1) recheck.restart(); else recheck.n = 0
        }
    }
    Timer { id: late; interval: root.graceMs + 500; onTriggered: scanSoon.restart() }

    function _reconcile(found) {
        if (!root.ruleOk) return           // never start one before the rule that parks it
        const next = {}
        const stale = []
        const bgOf = {}
        for (const id of root.wanted) bgOf[WallpaperEngine.windowBg(id)] = id
        for (const f of found) {
            const id = bgOf[f.bg]
            if (id && !next[id]) next[id] = f.pid
            else stale.push(f.pid)           // no longer wanted, or a second copy
        }
        for (const pid of stale) root._run(["kill", "--", String(pid)])
        for (const id of root.wanted) {
            if (next[id]) continue
            if (root._ruleStale) continue    // a reload dropped the rule; _ruleStale clearing rescans
            const young = Date.now() - (root._spawnAt[id] ?? 0) < root.graceMs
            if (young) { late.restart(); continue }
            if (root.pids[id]) console.warn("ScenePreload: scene", id, "stopped; starting it again")
            root._spawn(id)
        }
        root.pids = next
        root._windowsFor(next)
    }

    // ── Finding each window ───────────────────────────────────────────────────
    // By the renderer's pid, which Hyprland's record of the window carries.
    function _windowsFor(pids) {
        const tops = Hyprland.toplevels.values
        const w = {}
        let missing = false
        for (const id of root.wanted) {
            const pid = pids[id]
            if (!pid) continue
            let got = null, gotTop = null
            for (const t of tops) {
                const ipc = t.lastIpcObject
                if (ipc && ipc["pid"] === pid && t.wayland) { got = t.wayland; gotTop = t; break }
            }
            if (got) { w[id] = got; root._attempts[id] = 0 } else missing = true
            if (got) root._park(gotTop)
        }
        const same = Object.keys(w).length === Object.keys(root.windows).length
            && Object.keys(w).every(k => root.windows[k] === w[k])
        if (!same) root.windows = w
        if (missing) windowWait.restart()
    }
    // ── The safety net: a renderer window that is NOT on the parking workspace ──
    // The rule is what normally puts it there, but it can be missing when the window maps
    // (see _ruleStale): the window then comes up tiled on the workspace you're on, where it
    // can be dragged around. Whatever the cause, a window we own that is found anywhere
    // else is floated and sent to the parking workspace, silently. At most once per
    // 3 s per window, so a refusal can't turn into a dispatch loop.
    readonly property string _parking: "special:qswpe"
    property var _parkedAt: ({})
    function _park(top) {
        const ipc = top.lastIpcObject
        if (!ipc || !ipc["workspace"] || ipc["workspace"]["name"] === root._parking) return
        const addr = Hypr.addr(top.address)
        const now = Date.now()
        if (now - (root._parkedAt[addr] ?? 0) < 3000) return
        root._parkedAt[addr] = now
        console.warn("ScenePreload: renderer window", addr, "was on", ipc["workspace"]["name"], "— parking it")
        const sel = `window = "address:${addr}"`
        // The toggle, the form ActiveWindow already uses: only sent to a window that ISN'T floating.
        if (!ipc["floating"]) Hyprland.dispatch(`hl.dsp.window.float({ ${sel} })`)
        Hyprland.dispatch(`hl.dsp.window.move({ workspace = "${root._parking}", ${sel}, follow = false })`)
        windowWait.restart()
    }

    // Hyprland learns of a window a moment after it maps.
    Timer {
        id: windowWait
        interval: 500
        onTriggered: { Hyprland.refreshToplevels(); root._windowsFor(root.pids) }
    }
    // A window that closes (its renderer died) is an event.
    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() { if (root.enabled && root.wanted.length > 0) scanSoon.restart() }
    }

    onWantedChanged: { if (root.ruleOk) scanSoon.restart() }
    onRuleOkChanged: {
        root.version++
        if (root.ruleOk) scanSoon.restart(); else root._ruleStale = false
    }
    onEnabledChanged: {
        root.version++
        if (root.enabled) return
        // Off (preload switched off, Game Mode): the renderers go.
        for (const id in root.pids) root._run(["kill", "--", String(root.pids[id])])
        root.pids = ({})
        root.windows = ({})
        root._attempts = ({})
    }
    Component.onCompleted: if (root.ruleOk) scanSoon.restart()

    // Until the first answer (and for a few seconds, if scenes are still loading), a
    // screen whose workspace wants one holds what it shows rather than flashing the
    // still: WallpaperView reads this.
    property bool _firstDone: false
    Timer { interval: 6000; running: true; onTriggered: root._firstDone = true }
    function expects(id) { return root.enabled && !root.failed[id] && root.assigned.indexOf(id) >= 0 }
    readonly property bool settling:
        root.enabled && !root._firstDone && root.assigned.some(i => !root.failed[i] && !root.windows[i])

    IpcHandler {
        target: "scenepreload"
        function status(): string {
            return "enabled=" + root.enabled + " rule=" + root.ruleOk + " assigned=" + root.assigned.length
                + " running=" + Object.keys(root.pids).length + " windows=" + Object.keys(root.windows).length
                + " failed=" + Object.keys(root.failed).length
        }
    }
}
