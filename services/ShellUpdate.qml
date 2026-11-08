pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "shellupdate.js" as SU

// ── ShellUpdate ───────────────────────────────────────────────────────────────
// Updates of THIS SHELL (not the system): is there a newer signed release of
// Config.repo than Config.version, and install it. The release side is the
// maintainer's `qtrelease` (scripts/release.sh); the install side is
// scripts/shell-update.sh, which verifies the release's SSH signature against the
// key this install already carries before touching a file. Version arithmetic and
// response parsing are shellupdate.js (`bun scripts/test-shellupdate.js`); the
// installer has `bash scripts/test-shell-update.sh`.
//
// ── Checking ──────────────────────────────────────────────────────────────────
// GitHub's /releases/latest, a minute after start and then every 6 hours, while
// Config.shellUpdateCheck is on (it's a network call on a schedule, so it can be
// turned off). Unauthenticated, that's 60 requests an hour per IP; we use 4 a day.
// A failed check is quiet — "couldn't reach GitHub" is not worth a notification.
//
// ── Installing ────────────────────────────────────────────────────────────────
// No password: the shell lives in the user's own config dir. The installer runs
// setsid-detached (a reload must not kill it mid-copy) and restarts the shell at
// the end. Hot reload is switched OFF first: Quickshell reloads on every changed
// file with no debounce, so ~500 files landing would be a reload storm over a
// half-new tree. Progress comes back through a status file (see the script's
// header), polled while an install runs; the restarted shell reads `done <ver>`
// once and says so.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string current:   Config.version
    readonly property bool   available: root._rel !== null && SU.newer(root._rel.tag, Config.version)
    readonly property string latest:    root._rel ? root._rel.version : ""
    readonly property string notes:     root._rel ? root._rel.notes : ""
    readonly property string url:       root._rel ? root._rel.url : ""
    readonly property string date:      root._rel ? root._rel.date : ""
    readonly property bool   checking:   checkProc.running
    // A check has finished since start (whatever it found), and whether the last one
    // couldn't reach GitHub at all. A reply that isn't an offerable release (v0.3 and
    // older are unsigned) is NOT a failure — there's simply nothing newer to offer.
    readonly property bool   checked:    root._checked
    readonly property bool   checkFailed: root._checkFailed
    readonly property bool   installing: root._installing
    readonly property string status:     root._status    // the installer's current step
    readonly property string error:      root._error     // why the last install stopped
    // Why Install can't run here, or "" — the Discord.pressBlocker() pattern: a
    // missing tool disables the control with a reason instead of failing on click.
    readonly property string blocker:    root._blocker

    property var    _rel: null
    property bool   _checked: false
    property bool   _checkFailed: false
    property bool   _installing: false
    property string _status: ""
    property string _error: ""
    property string _blocker: ""

    readonly property string _workDir:
        (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
        + "/quicktest-shell-update"
    readonly property string _script: Quickshell.shellPath("scripts/shell-update.sh")

    function check() {
        if (checkProc.running) return
        checkProc.running = true
    }

    function install() {
        if (!root.available || root._installing || root._blocker !== "") return
        root._installing = true
        root._error  = ""
        root._status = "Starting…"
        Quickshell.watchFiles = false
        launchProc.command = ["bash", "-c",
            // The rm first: a previous attempt's `fail` line would otherwise be read
            // by the first poll as THIS attempt failing.
            'rm -f "$3/status"; setsid bash "$0" install "$1" "$2" </dev/null >/dev/null 2>&1 & disown; exit 0',
            root._script, Config.repo, root._rel.tag, root._workDir]
        launchProc.running = true
        statusPoll.start()
    }

    // ── Schedule ──────────────────────────────────────────────────────────────
    Timer {
        id: checkTimer
        running: Config.shellUpdateCheck
        interval: root._rel === null && !root._checkedOnce ? 60000 : 6 * 3600000
        repeat: true
        onTriggered: { root._checkedOnce = true; root.check() }
    }
    property bool _checkedOnce: false

    Process {
        id: checkProc
        running: false
        command: ["curl", "-fsSL", "--max-time", "15",
                  "-H", "Accept: application/vnd.github+json",
                  "https://api.github.com/repos/" + Config.repo + "/releases/latest"]
        stdout: StdioCollector {
            onStreamFinished: {
                const r = SU.release(text)
                if (r) root._rel = r
            }
        }
        onExited: function(code) {
            root._checked = true
            root._checkFailed = code !== 0
        }
    }

    // Once per version, ever — remembered in Config so a reload doesn't re-announce.
    onAvailableChanged: {
        if (!root.available || Config.shellUpdateNotified === root.latest) return
        Config.shellUpdateNotified = root.latest
        root._notify("Quicktest " + root.latest + " is available",
                     "You have " + root.current + ". Open the update panel to install it.")
    }

    // ── Install plumbing ──────────────────────────────────────────────────────
    Process { id: launchProc; running: false }

    FileView {
        id: statusFile
        path: root._workDir + "/status"
        printErrors: false
        onLoaded: root._onStatus(statusFile.text().trim())
    }

    Timer {
        id: statusPoll
        interval: 500
        repeat: true
        onTriggered: statusFile.reload()
    }

    function _onStatus(line) {
        if (!root._installing) return
        const sp = line.indexOf(" ")
        const kind = sp < 0 ? line : line.slice(0, sp)
        const text = sp < 0 ? "" : line.slice(sp + 1)
        if (kind === "step") {
            root._status = text
        } else if (kind === "done") {
            // The installer restarts the shell next; this is the last thing it shows.
            root._status = "Installed " + text + " — restarting…"
            statusPoll.stop()
        } else if (kind === "fail") {
            statusPoll.stop()
            root._installing = false
            root._status = ""
            root._error  = text
            Quickshell.watchFiles = true
        }
    }

    // ── Startup: blockers, a finished install to announce, a live one to follow ─
    Component.onCompleted: startProc.running = true

    Process {
        id: startProc
        running: false
        command: ["bash", "-c", '
            d="$1"; w="$2"
            [ -e "$d/.git" ] && echo "block This copy is a git checkout — update it with git pull."
            [ -s "$d/release/allowed_signers" ] || echo "block This install has no release key; reinstall from a release."
            for t in curl ssh-keygen sha256sum tar xz; do
                command -v "$t" >/dev/null || echo "block Needs $t (scripts/install-dependencies.sh)."
            done
            if [ -f "$w/lock" ] && ! flock -n "$w/lock" true; then echo live
            elif [ -f "$w/status" ]; then echo "last $(cat "$w/status")"; rm -f "$w/status"
            fi', "_", Quickshell.shellPath(""), root._workDir]
        stdout: SplitParser {
            onRead: function(line) {
                if (line.indexOf("block ") === 0 && root._blocker === "") {
                    root._blocker = line.slice(6)
                } else if (line === "live") {
                    // Started before a restart and still running — keep following it.
                    root._installing = true
                    Quickshell.watchFiles = false
                    statusPoll.start()
                } else if (line.indexOf("last done ") === 0) {
                    const v = line.slice(10)
                    if (v === Config.version)
                        root._notify("Quicktest updated to " + v, "The shell restarted on the new version.")
                }
            }
        }
    }

    Process { id: notifyProc; running: false }
    function _notify(title, body) {
        notifyProc.command = ["notify-send", "--app-name=Quickshell", "--urgency=normal",
                              "--icon=" + Icons.assetPath("update"), title, body]
        notifyProc.running = false
        notifyProc.running = true
    }
}
