import Quickshell
import Quickshell.Io
import QtQuick

// ── ThemeRunner ───────────────────────────────────────────────────────────────
// Runs a theming script and parses its progress protocol.
//
// NOT a singleton — one instance per caller. The wallpaper gallery and the colour-scheme
// editor both run scripts that emit the same protocol, and both need the same live step
// list, the same "these apps must restart" prompt and the same notification behaviour.
// Writing that twice is how the two halves of the theming pipeline drifted apart in the
// first place (one still ran `pkill zen` months after the other stopped).
//
// `Item`, not `QtObject`: QtObject has no default property, so a `Process` child is a hard
// error that cascades through every service. That mistake took the whole shell down once —
// see the note in CavaStream.qml.
//
// ── Protocol ──────────────────────────────────────────────────────────────────
//   STEP=<id>|<status>|<text>     status: run | ok | skip | fail
//   RESTART=<process>|<label>     an app that must restart to repaint
//   WAVE=ready | go | done        the change's wave (services/WallWave.qml)
//
// Anything else on stdout is ignored, so a chatty tool can't corrupt the display.
//
// ── The wave ──────────────────────────────────────────────────────────────────
// A run given a `wave` ({ image, output, recolor, keep }) arrives as ONE front from the
// bottom middle of the screen — the new picture as water, the new colours eating
// the old look off the shell. This is where every theming run gets it, so a
// wallpaper, a scheme, a pinned colour and a rebuild all arrive the same way with no
// per-caller code. The script is told it has an audience through QS_WAVE* in its
// environment and paces itself (see the header of apply-wallpaper.sh); unset, it
// runs the old way. Animations off → no wave (WallWave.enabled).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Shown as the notification's source, so "Wallpaper" and "Colors" stay distinguishable
    // in the tray even though they share this machinery.
    property string appName: "Theme"
    // Icon name resolved against the shell's own assets. An absolute SVG path scales to any
    // size the toast asks for; a THEME NAME does not — Papirus tops out at a 64px bucket and
    // an 80px request logs "Could not load icon".
    property string icon: "Palette"

    // What this run is, for the notification that arrives after attention has moved on.
    property string label: ""

    readonly property bool running: proc.running
    readonly property var  steps:   root._steps
    readonly property bool failed:  root._failed
    readonly property int  failedCount: root._steps.filter(s => s.status === "fail").length

    // [{ proc, label }] — only apps that were actually running when the script checked.
    readonly property var  restartApps:  root._restartApps
    readonly property bool needsRestart: root._restartApps.length > 0

    property var  _steps: []
    property var  _restartApps: []
    property bool _failed: false

    signal finished(int code)

    // The wave this run is driving, -1 for none. See the header.
    property int _wave: -1

    // The script waits for this file before its after-the-wave work (the wallpaper
    // daemon, the app fan-out) rather than sleeping a worst case: the spread can be
    // held while a slow app repaints, and nothing may change ahead of the front.
    // Created on WallWave.landed; one per wave token (the script clears a stale one).
    property string _landedFlag: ""
    // The shell's word that every window has taken its snapshot (WallWave.snapped): the
    // script waits for this file instead of sleeping a fixed time.
    property string _frozenFlag: ""
    readonly property string _runDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp")
    Connections {
        target: WallWave
        function onLanded(token) {
            if (token === root._wave && root._landedFlag !== "")
                Quickshell.execDetached(["touch", root._landedFlag])
        }
    }

    Connections {
        target: WallWave
        function onSnapped(token) {
            if (token === root._wave && root._frozenFlag !== "")
                Quickshell.execDetached(["touch", root._frozenFlag])
        }
    }

    // Returns the wave's token (-1 without one), for a caller that has to act when
    // its water lands — Wallpaper stops a running scene only once it is covered.
    function run(command, runLabel, wave) {
        if (proc.running) return -1
        root._steps = []
        root._restartApps = []
        root._failed = false
        root.label = runLabel ?? root.label
        root._wave = (wave && WallWave.enabled)
            ? WallWave.prepare(wave.image ?? "", wave.output ?? "", wave.recolor === true, wave.keep === true)
            : -1
        root._landedFlag = root._wave > 0
            ? root._runDir + "/quickshell-quicktest-wave-" + root._wave + ".landed"
            : ""
        // Set on EVERY run, not only a waving one: environment persists on the Process,
        // and a stale QS_WAVE=1 would make an unwatched run sleep for an animation
        // nobody is playing.
        root._frozenFlag = root._wave > 0
            ? root._runDir + "/quickshell-quicktest-wave-" + root._wave + ".frozen"
            : ""
        proc.environment = root._wave > 0
            ? ({ "QS_WAVE": "1",
                 "QS_WAVE_FREEZE_MS": String(WallWave.freezeMs),
                 "QS_WAVE_LAND_MS":   String(WallWave.landMs),
                 "QS_WAVE_LANDED":    root._landedFlag,
                 "QS_WAVE_FROZEN":    root._frozenFlag })
            : ({ "QS_WAVE": "", "QS_WAVE_FREEZE_MS": "", "QS_WAVE_LAND_MS": "", "QS_WAVE_LANDED": "",
                 "QS_WAVE_FROZEN": "" })
        proc.command = command
        proc.running = true
        return root._wave
    }

    function _onWave(what) {
        if (root._wave <= 0) return
        if (what === "ready")     WallWave.freeze(root._wave)
        else if (what === "go")   WallWave.commit(root._wave)
        else if (what === "done") WallWave.done(root._wave)
    }

    // Dismisses a finished-with-errors result. A clean run is cleared by the caller; a run
    // with failures waits to be acknowledged, so the account of what broke isn't swept away
    // before it's read.
    function clearResult() {
        root._steps = []
        root._failed = false
    }

    function dismissRestart() { root._restartApps = [] }

    Process {
        id: proc
        running: false

        stdout: SplitParser {
            onRead: function(line) {
                if (line.indexOf("WAVE=") === 0) {
                    root._onWave(line.substring(5).trim())
                    return
                }
                if (line.indexOf("RESTART=") === 0) {
                    const r = line.substring(8).split("|")
                    if (r.length >= 2)
                        root._restartApps = root._restartApps.concat([{ proc: r[0], label: r[1] }])
                    return
                }
                if (line.indexOf("STEP=") !== 0) return
                const p = line.substring(5).split("|")
                if (p.length < 3) return
                const row = { id: p[0], status: p[1], text: p.slice(2).join("|") }

                // A step already listed is UPDATED in place — the script emits "run" then
                // "ok"/"fail" for the same id, and appending both would list everything twice.
                const next = root._steps.slice()
                const at = next.findIndex(s => s.id === row.id)
                if (at >= 0) next[at] = row
                else next.push(row)
                root._steps = next
            }
        }

        // The scripts log their own command output; anything here is unexpected and worth
        // keeping rather than discarding.
        stderr: SplitParser {
            onRead: function(line) {
                if (line.trim() !== "") console.warn("[" + root.appName + "]", line)
            }
        }

        onExited: function(code) {
            // Step failures travel in the STEP protocol — every script here says so
            // in its own header, and both emit `STEP=done` as their last line before
            // `exit 0`. So a non-zero $? only counts as a failure when the run never
            // reached `done`: a script that finished its work and then tripped over a
            // late `set -u` or a trailing pipe (the bug apply-wallpaper.sh and
            // reload-theme.sh each hit once) was reporting "finished with errors" on
            // a run where nothing the user cares about actually broke.
            const reachedEnd = root._steps.some(s => s.id === "done" && s.status === "ok")
            root._failed = root.failedCount > 0 || (code !== 0 && !reachedEnd)
            // Whatever the script managed to say, its wave ends with it: a run that
            // died before WAVE=go must not leave the shell frozen under its snapshot.
            if (root._wave > 0) {
                WallWave.finish(root._wave)
                root._wave = -1
            }
            root.finished(code)
        }
    }

    // ── Restarting what can't repaint in place ────────────────────────────────
    // Always the user's button. The pipeline this replaced ran `pkill zen` on every single
    // change, destroying the session as a side effect of picking a colour.
    //
    // Relaunched with setsid + nohup so they aren't children of the shell — otherwise
    // reloading Quickshell would take them all down with it.
    Process { id: restartProc; running: false }

    // Keyed by process name, so an app we can stop but don't know how to start again is
    // never killed and left dead.
    readonly property var _relaunch: ({
        "zen-bin":       "zen-browser",
        "nautilus":      "nautilus",
        "missioncenter": "missioncenter",
        "steam":         "steam"
    })

    // What has to be true at the moment an app STARTS, run just before it. Steam deletes its
    // debug-port flag as it reads it, so a restart that didn't put it back would start Steam
    // closed to the live push (scripts/steam-live.py; a no-op unless the user opted in).
    readonly property var _beforeLaunch: ({
        "steam": "python3 '" + Quickshell.shellPath("scripts/steam-live.py").replace(/'/g, "'\\''") + "' flag; "
    })

    function restartAll() {
        if (restartProc.running || root._restartApps.length === 0) return

        const parts = []
        for (let i = 0; i < root._restartApps.length; i++) {
            const p = root._restartApps[i].proc
            const cmd = root._relaunch[p]
            if (!cmd) continue
            // -x so the name can't also match an unrelated command line that mentions it.
            parts.push("pkill -x " + p + " 2>/dev/null; sleep 0.6; "
                     + (root._beforeLaunch[p] || "")
                     + "nohup setsid " + cmd + " >/dev/null 2>&1 & disown")
        }
        if (parts.length === 0) return

        restartProc.command = ["bash", "-c", parts.join("\n")]
        restartProc.running = true
        root._restartApps = []
    }

    // ── Notifications ─────────────────────────────────────────────────────────
    Process { id: notifyProc; running: false }

    function notify(title, body, urgency) {
        // Grouped under "Quickshell" in the notification centre, same as every other
        // notification the shell sends — `root.appName` stays put for the console log
        // prefix above, which is a different job (telling three ThemeRunner instances
        // apart in the shell's own log) from this one (which app a notification belongs
        // to as far as the user is concerned).
        notifyProc.command = ["notify-send", "--app-name=Quickshell",
                              "--urgency=" + (urgency || "normal"),
                              "--icon=" + Icons.assetPath(root.icon),
                              title, body]
        notifyProc.running = false
        notifyProc.running = true
    }
}
