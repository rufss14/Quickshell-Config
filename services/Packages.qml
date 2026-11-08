pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "../state"
import "packages.js" as P

// ── Packages ──────────────────────────────────────────────────────────────────
// The launcher's `+` mode: find a package in the repos (and the AUR, when an AUR helper
// is installed) and install it through the update runner — its password handling, its
// progress, its flock (services/Updates.installPackages). Logic: packages.js
// (`bun scripts/test-packages.js`).
//
// ── What leaves the machine ───────────────────────────────────────────────────
// The repos are searched locally (`pacman -Ss` reads the synced databases). The AUR
// search sends the longest word you typed to aur.archlinux.org — only in `+` mode, only
// with an AUR helper installed (someone with no helper can't install from the AUR, so
// there's nothing to search for), and debounced.
//
// Requests are never killed mid-run: a query that changes while one is out is marked
// and re-run when it lands, so a stale answer can't overwrite a fresh one.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // Set by the launcher while `+` is up; "" otherwise (nothing runs).
    property string query: ""

    property var results: []
    property bool hasPacman: false
    property bool probed: false
    readonly property bool aurEnabled: Config.launcherAur && (Updates.helper === "yay" || Updates.helper === "paru")
    readonly property bool busy: pac.running || aurProc.running || debounce.running
    property string error: ""

    function blocker() {
        if (!root.probed) return ""
        return root.hasPacman ? "" : "Package search needs pacman (Arch Linux)"
    }

    // ── Install ───────────────────────────────────────────────────────────────
    // One package, by the record the list showed. Opens the update panel on the run, so
    // its progress — and a password prompt — are where you'd look.
    function install(pkg) {
        if (!pkg || pkg.installed || !P.validName(pkg.name)) return false
        const ok = pkg.source === "aur"
            ? Updates.installPackages([], [pkg.name], pkg.name)
            : Updates.installPackages([pkg.name], [], pkg.name)
        if (!ok) { root.error = Updates.runBusy ? "The updater is already running" : "Couldn't start the install"; return false }
        UiState.pendingUpdateCount = Updates.total
        UiState.updateRequestId++
        return true
    }

    // ── Search ────────────────────────────────────────────────────────────────
    property var _repo: []
    property var _aur: []
    property var _installed: ({})

    onQueryChanged: {
        root.error = ""
        if (P.terms(root.query).length === 0) {
            debounce.stop()
            root._repo = []; root._aur = []; root.results = []
            return
        }
        debounce.restart()
    }

    Timer {
        id: debounce
        interval: 250
        onTriggered: {
            if (!root.probed) probe.running = true
            installedProc.running = true
            root._runPacman()
            root._runAur()
        }
    }

    function _rerank() { root.results = P.rank(root._repo, root._aur, root.query, root._installed) }

    property bool _pacAgain: false
    function _runPacman() {
        if (pac.running) { root._pacAgain = true; return }
        const argv = P.pacmanArgs(root.query)
        if (argv.length === 0) return
        pac.command = argv
        pac.running = true
    }
    Process {
        id: pac
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._pacAgain) { root._pacAgain = false; Qt.callLater(root._runPacman); return }
                // Exit 1 with no output is "nothing found", not a failure.
                root._repo = P.parsePacman(text)
                root._rerank()
            }
        }
    }

    property bool _aurAgain: false
    function _runAur() {
        if (!root.aurEnabled) { root._aur = []; return }
        if (aurProc.running) { root._aurAgain = true; return }
        const url = P.aurUrl(root.query)
        if (url === "") return
        aurProc.command = ["curl", "-fsS", "--max-time", "6", url]
        aurProc.running = true
    }
    Process {
        id: aurProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._aurAgain) { root._aurAgain = false; Qt.callLater(root._runAur); return }
                const got = P.parseAur(text)
                if (got === null) root.error = "The AUR didn't answer — repos only"
                root._aur = got ?? []
                root._rerank()
            }
        }
    }

    // What's installed, re-read on each search burst (an install in another terminal
    // shows up the next time you type).
    Process {
        id: installedProc
        command: ["pacman", "-Qq"]
        stdout: StdioCollector {
            onStreamFinished: { root._installed = P.parseInstalled(text); root._rerank() }
        }
    }

    Process {
        id: probe
        command: ["sh", "-c", "command -v pacman >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector {
            onStreamFinished: { root.hasPacman = text.trim() === "yes"; root.probed = true }
        }
    }
}
