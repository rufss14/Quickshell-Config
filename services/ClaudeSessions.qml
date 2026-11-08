pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "../state"

// ── ClaudeSessions ────────────────────────────────────────────────────────────
// Every Claude Code session running on this machine, for the sidebar's Claude module
// (SideClaude → ClaudePanel): working or waiting, waiting on YOUR permission, what
// it's doing, how full its context is — and a click takes you to its terminal.
// Beside them: the RECENT sessions that have ended (a click resumes one in a terminal,
// in the directory it was started from) and the account's rate limit.
//
// scripts/claude-sessions.py does the reading (Claude Code's own session registry,
// plus the optional hook state — see its header), only while the module is placed.
//
// ── The rate limit ────────────────────────────────────────────────────────────
// Claude Code puts it nowhere on disk but its status-line input, so the same optional
// installer that adds the hook sets a status line (scripts/claude-statusline.py) that
// saves just that block. The figures are as fresh as the last session that reported:
// `rate.at` says when, the panel says so once they are old (services/claudeusage.js).
//
// ── "Needs you" and "done" ────────────────────────────────────────────────────
// `needsYou`: a session waiting on a permission prompt (or a question) — needs the
// hooks (scripts/install-claude-hooks.py; the panel offers it). `fresh`: sessions that
// finished a turn (busy → idle) since you last opened the panel — works without them.
//
// Diagnose: `qs ipc -c ~/.config/quicktest call claude status` (counts, never titles).
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property bool wanted: Config.sidebarPlaced("claude")

    // [{ pid, sid, title, project, cwd, status, since, startedAt, model, context,
    //    attention ("permission" | "input" | ""), message, activity, last, hooked }]
    property var sessions: []
    // Ended sessions you can pick up again, newest first:
    // [{ sid, title, project, cwd, since, model, context }]
    property var recent: []
    // { at (ms, 0 = never reported), five_hour: { pct, resetsAt } | null, seven_day: … }
    property var rate: ({ at: 0, five_hour: null, seven_day: null })
    property bool hooksInstalled: false
    property string hooksPath: ""
    property string lastError: ""
    property bool ready: false

    readonly property int busyCount: root.sessions.filter(s => s.status === "busy").length
    readonly property var needsYou: root.sessions.filter(s => s.attention !== "")
    // Session ids that finished since the panel was last open.
    property var fresh: []
    readonly property bool anyFresh: root.fresh.length > 0

    function markSeen() { root.fresh = [] }
    function isFresh(sid) { return root.fresh.indexOf(sid) >= 0 }

    // To its terminal: the helper finds the window, Hypr focuses it.
    function focus(pid) {
        if (typeof pid !== "number") return
        root._send({ c: "locate", pid: pid })
    }

    // Resume an ended session where it was started — `claude --resume` only finds a
    // session from the directory it lives in. The helper vetted `sid` and `cwd`; they
    // go as arguments, never through a shell string.
    function resume(s) {
        if (!s || typeof s.sid !== "string" || typeof s.cwd !== "string") return
        UiState.closeSidePanel()
        Terminal.runIn(s.cwd, ["claude", "--resume", s.sid])
    }

    // A new session in this shell's own directory — where it is worked on.
    function newSession() {
        UiState.closeSidePanel()
        Terminal.runIn(Quickshell.shellDir, ["claude"])
    }

    // The optional hooks: run on a click only — they edit Claude Code's settings.
    property bool hooksBusy: false
    function installHooks() { root._hooks([]) }
    function removeHooks()  { root._hooks(["--remove"]) }
    function _hooks(args) {
        if (root.hooksBusy) return
        root.hooksBusy = true
        hookProc.command = ["python3", Quickshell.shellPath("scripts/install-claude-hooks.py")].concat(args)
        hookProc.running = true
    }
    Process {
        id: hookProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.hooksBusy = false
                try {
                    const r = JSON.parse(text)
                    if (!r.ok) root._error(r.error || "Couldn't change Claude Code's settings")
                    root.hooksInstalled = r.installed === true
                } catch (e) { root._error("The hook installer said something odd") }
            }
        }
    }

    // ── The helper ────────────────────────────────────────────────────────────
    property bool _cycling: false
    property int  _restarts: 0
    Process {
        id: proc
        running: root.wanted && !root._cycling
        command: ["python3", Quickshell.shellPath("scripts/claude-sessions.py")]
        stdinEnabled: true
        stdout: SplitParser { onRead: function (line) { root._ingest(line) } }
        stderr: SplitParser { onRead: function (line) { console.log("ClaudeSessions:", line) } }
        onExited: function (code) {
            root.ready = false
            if (!root.wanted) { root.sessions = []; return }
            if (root._restarts < 5) { root._restarts++; restart.restart() }
            else console.warn("ClaudeSessions: helper keeps exiting (" + code + "); giving up this session")
        }
    }
    Timer {
        id: restart
        interval: 3000 * Math.max(1, root._restarts)
        onTriggered: { root._cycling = true; Qt.callLater(() => root._cycling = false) }
    }
    onWantedChanged: if (!root.wanted) { root.sessions = []; root.recent = []; root.fresh = [] }

    function _send(obj) { if (proc.running) proc.write(JSON.stringify(obj) + "\n") }

    function _ingest(line) {
        let m
        try { m = JSON.parse(line) } catch (e) { return }
        if (m.t === "sessions") {
            root.ready = true
            root._restarts = 0
            const next = Array.isArray(m.sessions) ? m.sessions : []
            // busy → idle, while the panel isn't showing it: finished since you looked.
            const was = {}
            for (const s of root.sessions) was[s.sid] = s.status
            const panelOpen = UiState.sidePanel === "claude"
            let fresh = root.fresh.filter(id => next.some(s => s.sid === id))
            for (const s of next)
                if (!panelOpen && was[s.sid] === "busy" && s.status !== "busy" && fresh.indexOf(s.sid) < 0)
                    fresh.push(s.sid)
            root.fresh = fresh
            root.sessions = next
        } else if (m.t === "recent") {
            root.recent = Array.isArray(m.sessions) ? m.sessions : []
        } else if (m.t === "rate") {
            root.rate = { at: m.at || 0, five_hour: m.five_hour || null, seven_day: m.seven_day || null }
        } else if (m.t === "hooks") {
            root.hooksInstalled = m.installed === true
            root.hooksPath = String(m.path || "")
        } else if (m.t === "located") {
            if (typeof m.address === "string" && m.address !== "") {
                UiState.closeSidePanel()
                Hypr.focusWindow(m.address)
            } else {
                root._error("Couldn't find its terminal window")
            }
        }
    }
    function _error(msg) { root.lastError = msg; errorBeat.restart() }
    Timer { id: errorBeat; interval: 5000; onTriggered: root.lastError = "" }

    IpcHandler {
        target: "claude"
        function status(): string {
            return "wanted=" + root.wanted + " ready=" + root.ready + " sessions=" + root.sessions.length
                 + " busy=" + root.busyCount + " needsYou=" + root.needsYou.length
                 + " fresh=" + root.fresh.length + " recent=" + root.recent.length
                 + " rate=" + (root.rate.at > 0) + " hooks=" + root.hooksInstalled
        }
    }
}
