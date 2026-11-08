pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "../state"

// ── LocalAi ───────────────────────────────────────────────────────────────────
// The AI that runs on this machine (Ollama) — the shell's default AI since 2026-10-24 (the user:
// "local AI the default, and an easy set up for it"). scripts/local-ai.py does the asking; this holds
// the state the setup (FeedAssistant → LocalAiSetup) draws and `Ai.ready` reads:
//
//   1. installed   `ollama` (+ `ollama-vulkan` with a GPU) through the update panel —
//                  Updates.installPackages, so the password prompt and progress are pacman's, there
//   2. running     `ollama serve` as a user process; started by itself once it's installed and
//                  the local AI is the chosen one (Config.aiLocalAutostart), or by the Start button
//   3. a model     downloaded from the catalogue below, with progress; the one in use is
//                  Config.aiModel (or the first installed)
//
// Asked at startup only when the local AI is the chosen provider, then on demand (the page coming
// into view, an install finishing) — never on a timer.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property bool probed: false
    property bool installed: false
    property bool running: false
    property var  models: []
    property string gpu: "none"
    property var  packages: ["ollama"]
    property bool local: true
    property string error: ""

    readonly property bool ready: root.installed && root.running && root.models.length > 0
    readonly property bool chosen: Config.aiProvider === "ollama"

    // The models offered, smallest first that's good at following the shell's action format. Sizes are
    // the download's, roughly; the real total comes from the pull itself.
    readonly property var catalog: [
        { name: "qwen3:4b",    label: "Qwen 3",       size: "2.5 GB", note: "Recommended — follows the shell's actions best" },
        { name: "llama3.2:3b", label: "Llama 3.2",    size: "2.0 GB", note: "The smallest, and quick" },
        { name: "gemma3:4b",   label: "Gemma 3",      size: "3.3 GB", note: "Writes the nicest replies" },
        { name: "qwen3:8b",    label: "Qwen 3 · 8B",  size: "5.2 GB", note: "Smarter; wants 8 GB of video memory" }
    ]

    function has(name) { return root.models.some(m => m.name === name || m.name === name + ":latest") }
    // The model answering: the chosen one if it's here, else the first one here.
    readonly property string model: root.has(Config.aiModel) ? Config.aiModel : (root.models.length > 0 ? root.models[0].name : "")
    function use(name) { if (root.has(name)) Config.aiModel = name }

    function _cmd(args) {
        return ["python3", Quickshell.shellPath("scripts/local-ai.py")].concat(args)
               .concat(Config.aiLocalUrl !== "" ? ["--url", Config.aiLocalUrl] : [])
    }

    function refresh() {
        if (statusProc.running) return
        statusProc.command = root._cmd(["status"])
        statusProc.running = true
    }

    // ── 1. Install ────────────────────────────────────────────────────────────
    // The update panel runs it (password, progress); the overview steps aside so it can be seen.
    function install() {
        if (root.installed || Updates.runBusy) return
        if (!Updates.installPackages(root.packages, [], "Local AI")) { root.error = "Couldn't start the install"; return }
        UiState.pendingUpdateCount = Updates.total
        UiState.updateRequestId++
        UiState.leaveOverview(-1)
    }
    // An install (any) finishing: see what changed, and start it if it's the AI in use.
    Connections {
        target: Updates
        function onRunBusyChanged() { if (!Updates.runBusy) root.refresh() }
    }

    // ── 2. Start ──────────────────────────────────────────────────────────────
    property bool starting: false
    property bool _autoTried: false
    function start() {
        if (serveProc.running || root.running) return
        root.starting = true
        root.error = ""
        serveProc.command = root._cmd(["serve"])
        serveProc.running = true
    }

    // ── 3. A model ────────────────────────────────────────────────────────────
    property string pulling: ""
    property real pullDone: 0          // 0..1
    property string pullStatus: ""
    function pull(name) {
        if (pullProc.running || !root.running) return
        root.pulling = name
        root.pullDone = 0
        root.pullStatus = "Starting…"
        root.error = ""
        pullProc.command = root._cmd(["pull", name])
        pullProc.running = true
    }
    function cancelPull() { pullProc.running = false }

    Component.onCompleted: if (root.chosen) root.refresh()
    onChosenChanged: if (root.chosen) root.refresh()

    Process {
        id: statusProc
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(text) } catch (e) { return }
                root.installed = !!d.installed
                root.running = !!d.running
                root.models = d.models || []
                root.gpu = d.gpu || "none"
                root.packages = d.packages || ["ollama"]
                root.local = d.local !== false
                root.probed = true
                // Installed, not running, and it's the AI in use: start it, once a session.
                if (root.installed && !root.running && root.local && root.chosen
                        && Config.aiLocalAutostart && !root._autoTried) {
                    root._autoTried = true
                    root.start()
                }
            }
        }
    }
    Process {
        id: serveProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (!d.ok) root.error = d.error || "Couldn't start the local AI"
                } catch (e) {}
            }
        }
        onExited: { root.starting = false; root.refresh() }
    }
    Process {
        id: pullProc
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                let d = null
                try { d = JSON.parse(line) } catch (e) { return }
                if (d.t === "progress") {
                    root.pullStatus = d.status || ""
                    if (d.total > 0) root.pullDone = d.completed / d.total
                } else if (d.t === "error") root.error = d.error || "The download failed"
                else if (d.t === "done") root.pullDone = 1
            }
        }
        onExited: {
            const got = root.pullDone >= 1 && root.error === ""
            const name = root.pulling
            root.pulling = ""
            root.pullStatus = ""
            root.refresh()
            // The first model is the one in use.
            if (got && (Config.aiModel === "" || !root.has(Config.aiModel))) Config.aiModel = name
        }
    }
}
