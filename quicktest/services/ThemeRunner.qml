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
//
// Anything else on stdout is ignored, so a chatty tool can't corrupt the display.
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

    function run(command, runLabel) {
        if (proc.running) return
        root._steps = []
        root._restartApps = []
        root._failed = false
        root.label = runLabel ?? root.label
        proc.command = command
        proc.running = true
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
            root._failed = code !== 0 || root.failedCount > 0
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

    function restartAll() {
        if (restartProc.running || root._restartApps.length === 0) return

        const parts = []
        for (let i = 0; i < root._restartApps.length; i++) {
            const p = root._restartApps[i].proc
            const cmd = root._relaunch[p]
            if (!cmd) continue
            // -x so the name can't also match an unrelated command line that mentions it.
            parts.push("pkill -x " + p + " 2>/dev/null; sleep 0.6; "
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
        notifyProc.command = ["notify-send", "--app-name=" + root.appName,
                              "--urgency=" + (urgency || "normal"),
                              "--icon=" + Icons.assetPath(root.icon),
                              title, body]
        notifyProc.running = false
        notifyProc.running = true
    }
}
