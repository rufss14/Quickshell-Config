pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// ── Ai ────────────────────────────────────────────────────────────────────────
// One question, one answer, for the launcher's `?` mode. scripts/ai-ask.py does the
// talking; this holds the result until the next question or the launcher closes.
//
// ── It only runs when you press Enter ─────────────────────────────────────────
// Never on a keystroke, never on a timer, never speculatively. The prompt leaves this
// machine when — and only when — someone deliberately asks it to, the same contract
// Config.lyricsTranslate keeps for the other feature here that sends text anywhere.
// `ask()` is the only thing that starts a process.
//
// The conversation lives HERE, in memory, for as long as the launcher is open, and is
// dropped when it closes. That is what makes a follow-up mean anything ("and why is it
// red at sunset?") without ever writing a file of everything you asked — which was the
// original reason this was single-shot. What changed is the thread's lifetime, not
// whether one is stored.
//
// ── The key is a BOOLEAN here ─────────────────────────────────────────────────
// `hasKey` is all this service ever learns. The key itself is read inside ai-ask.py,
// out of a 0600 file, and never crosses into QML — where it would sit in a property
// for the session and land in any object dump. Same contract as Discord.hasSecret.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string provider: Config.aiProvider
    // A thread belongs to the model that answered it. Carrying it across a provider
    // switch would send Gemini's replies to Claude as if Claude had said them.
    onProviderChanged: root.clear()

    // ── The provider's mark ───────────────────────────────────────────────────
    // RESOLVED from the icon theme, never vendored. These are other people's
    // trademarks and this config is published — the same reason
    // WallpaperEngine.logoFile reads Steam's mark out of Steam's own cache instead of
    // shipping a copy. `iconPath(name, true)` checks existence and returns "" when the
    // icon is not installed, which is the ordinary case on someone else's machine, so
    // every consumer needs the drawn fallback below.
    //
    // Several names per provider because the icon that exists depends on what the user
    // installed — a desktop app, a Papirus panel indicator, or nothing at all.
    function markFor(id) {
        const names =
              id === "claudecode" || id === "anthropic"
                // `-symbolic` first: a symbolic icon is a single flat glyph with no
                // background plate, which is what "simpler" means here and what lets
                // it be tinted to the shell's palette below. The full-colour app icon
                // is the fallback, not the preference.
                ? ["claude-symbolic", "claude-desktop-symbolic",
                   "claude-desktop", "claude", "anthropic"]
            : id === "gemini" ? ["gemini", "google-gemini"]
            : id === "openai" ? ["chatgpt", "indicator-chatgpt", "openai"]
            : id === "xai"    ? ["grok", "xai"]
            : id === "ollama" ? ["ollama"]
            :                   []
        for (let i = 0; i < names.length; i++) {
            const p = Quickshell.iconPath(names[i], true)
            if (p !== "") return p
        }
        return ""
    }

    // The letter drawn when no icon is installed. Not an imitation of the logo — just
    // the initial, in the shell's own palette.
    function letterFor(id) {
        return id === "claudecode" || id === "anthropic" ? "C"
             : id === "gemini" ? "G"
             : id === "openai" ? "O"
             : id === "xai"    ? "X"
             : id === "ollama" ? "L" : "AI"
    }

    readonly property string mark:   root.markFor(root.provider)
    readonly property string letter: root.letterFor(root.provider)

    readonly property var providers: [
        // Local first (the default since 2026-10-24): a model on this machine (Ollama) — no key,
        // no bill, and the prompt never leaves the box. Then Claude Pro, the other one with no
        // key and no billing setup: it borrows the `claude` CLI's own subscription login.
        { id: "ollama",    label: "Local"   },
        { id: "claudecode", label: "Claude Pro" },
        { id: "gemini",    label: "Gemini"  },
        { id: "anthropic", label: "Claude"  },
        { id: "openai",    label: "ChatGPT" },
        { id: "xai",       label: "Grok"    }
    ]
    readonly property string label:
          root.provider === "gemini"    ? "Gemini"
        : root.provider === "openai"    ? "ChatGPT"
        : root.provider === "anthropic" ? "Claude"
        : root.provider === "xai"       ? "Grok"
        : root.provider === "claudecode" ? "Claude Pro"
        : root.provider === "ollama"    ? "Local AI"
        :                                 root.provider

    // Which providers have a key stored. Refreshed on demand, not polled.
    property var  hasKey: ({})
    readonly property bool ready: root.provider === "claudecode"
                                    ? root.claudeCliFound
                                    : root.provider === "ollama" ? LocalAi.ready
                                    : root.hasKey[root.provider] === true

    // The thread, oldest first: {role: "user"|"model", text: "…"}. Reassigned rather
    // than mutated — a JS array property only notifies on assignment, and a push()
    // would update the model without ever telling the view.
    property var  messages: []
    property bool busy:     false
    property string error:  ""

    readonly property bool hasThread: root.messages.length > 0
    readonly property string answer:
        root.messages.length > 0 && root.messages[root.messages.length - 1].role === "model"
            ? root.messages[root.messages.length - 1].text : ""
    readonly property bool hasAnswer: root.answer !== ""

    // Same contract as Discord.pressBlocker()/WallpaperEngine.blocker(): a short
    // reason the control cannot work, or "" when it can. A missing key DISABLES with
    // an explanation rather than failing on click.
    // The subscription path needs no key — only the CLI. `hasKey` carries a
    // "claudecode" entry that ai-credentials.py never writes; Ai fills it from a probe
    // for the binary instead, so `ready` means the same thing for every provider.
    readonly property bool needsKey: root.provider !== "claudecode" && root.provider !== "ollama"

    // Where to get a key for the current provider, and what to say about it. Gemini is
    // the only free one, which is why it is the default and why the wording differs.
    // Claude Code has no key to get (empty URL).
    readonly property string keyUrl:
          root.provider === "gemini"    ? "https://aistudio.google.com/apikey"
        : root.provider === "anthropic" ? "https://console.anthropic.com/settings/keys"
        : root.provider === "openai"    ? "https://platform.openai.com/api-keys"
        : root.provider === "xai"       ? "https://console.x.ai"
        :                                 ""

    readonly property string keyHelp:
          root.provider === "claudecode"
            ? "Needs the Claude Code CLI on your PATH. No API key and no extra billing — it uses the subscription you are already logged into."
        : root.provider === "ollama"
            ? "Runs a model on this machine through Ollama — no key, nothing leaves your computer. Install ollama, start it, and pull a model (ollama pull llama3.2)."
        : root.provider === "gemini"
            ? "Gemini has a free tier — get a key and paste it above. Free-tier limits are small, and grounding uses them faster."
        : root.provider === "anthropic"
            ? "Claude API keys are billed separately from a Claude Pro subscription — Pro does not cover API use. Create a key in the Anthropic Console."
        :   "Paste an API key from the provider's console. Usage is billed to that account."

    function blocker() {
        if (!Config.aiEnabled) return "AI answers are off"
        if (root.provider === "claudecode" && !root.claudeCliFound)
            return "Claude Code CLI not found"
        if (root.provider === "ollama" && !LocalAi.ready)
            return !LocalAi.probed ? "Checking the local AI…"
                 : !LocalAi.installed ? "Local AI isn't set up yet"
                 : !LocalAi.running ? (LocalAi.starting ? "Starting the local AI…" : "Local AI isn't running")
                 : "No local model yet"
        if (root.needsKey && !root.ready) return "No API key for " + root.label
        return ""
    }

    property bool claudeCliFound: false

    // ── The AppLauncher session ───────────────────────────────────────────────
    // One conversation, scoped to this boot, cleared on demand. The id lives in
    // scripts/ai-ask.py (derived from the name, the boot id and a generation) — this
    // only asks it to start a new one.
    function resetSession() { resetProc.running = false; resetProc.running = true }

    property Process resetProc: Process {
        command: ["python3", Quickshell.shellPath("scripts/ai-ask.py"), "--reset-session"]
        onExited: root.clear()
    }

    property Process cliProbe: Process {
        running: true
        command: ["bash", "-lc", "command -v claude >/dev/null 2>&1"]
        onExited: (code) => root.claudeCliFound = (code === 0)
    }

    function refreshKeys() { statusProc.running = false; statusProc.running = true }

    // ── Storing and clearing a key ────────────────────────────────────────────
    // The key is handed to scripts/ai-credentials.py over STDIN and written 0600
    // there. It is never an argument (argv is world-readable in /proc and ps), never
    // written from QML (FileView cannot create 0600), and never read back — this
    // service only ever learns the boolean in `hasKey`.
    //
    // Same shape as the Discord settings page, which types a client secret into a
    // field and posts it to discord-credentials.py the same way.
    property string _pendingPatch: ""

    function saveKey(provider, key) {
        const k = (key || "").trim()
        if (provider === "" || k === "") return
        const patch = ({}); patch[provider] = k
        root._pendingPatch = JSON.stringify(patch)
        writeProc.running = false
        writeProc.running = true
    }

    // An explicit empty string is what ai-credentials.py reads as "clear this one" —
    // omitting the field would mean "leave it alone".
    function removeKey(provider) {
        if (provider === "") return
        const patch = ({}); patch[provider] = ""
        root._pendingPatch = JSON.stringify(patch)
        writeProc.running = false
        writeProc.running = true
    }

    property Process writeProc: Process {
        command: ["python3", Quickshell.shellPath("scripts/ai-credentials.py")]
        stdinEnabled: true
        onRunningChanged: if (running) stdinEnabled = true
        onStarted: {
            write(root._pendingPatch + "\n")
            stdinEnabled = false
            // Dropped as soon as it is handed over. Holding it would keep the key in a
            // QML property for the rest of the session for no reason at all.
            root._pendingPatch = ""
        }
        stdout: StdioCollector {
            // The script answers with the same booleans --status does, so the UI
            // updates from the write itself rather than racing a second process.
            onStreamFinished: {
                try { root.hasKey = (JSON.parse(text) || {}).has || ({}) }
                catch (e) { root.refreshKeys() }
            }
        }
    }
    Component.onCompleted: root.refreshKeys()

    // Adds a turn and sends the whole thread. Refused while a turn is in flight: two
    // overlapping requests would race to append their answers and interleave the
    // conversation, and the second reply would read as an answer to the first question.
    function ask(q) {
        const text = (q || "").trim()
        if (text === "" || root.busy || root.blocker() !== "") return
        root.messages = root.messages.concat([{ role: "user", text: text }])
        root.busy     = true
        root.thinking = true
        root.error    = ""
        root.pending  = ""
        askProc.running = false
        askProc.running = true
    }

    function clear() {
        askProc.running = false
        root.messages = []
        root.error    = ""
        root.busy     = false
        root.thinking = false
        root.pending  = ""
    }

    property Process statusProc: Process {
        command: ["python3", Quickshell.shellPath("scripts/ai-credentials.py"), "--status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.hasKey = (JSON.parse(text) || {}).has || ({}) }
                catch (e) { root.hasKey = ({}) }
            }
        }
    }

    // ── The turn in flight ────────────────────────────────────────────────────
    // `pending` is the answer as it arrives, before it becomes a message. The UI
    // reveals it a character at a time, so a provider that hands over one big chunk
    // and one that streams tokens both read as typing.
    property string pending: ""
    // True between the request and the first text: the model is reasoning and there is
    // nothing to show yet, which is a different state from "typing".
    property bool thinking: false
    property real lastCost: 0
    property int  lastMs: 0

    function stop() {
        askProc.running = false
        root.busy = false
        root.thinking = false
        // Whatever arrived before the stop is kept — it is a real partial answer, and
        // throwing it away would punish the user for interrupting something useless.
        if (root.pending !== "") {
            root.messages = root.messages.concat([{ role: "model", text: root.pending }])
            root.pending = ""
        }
    }

    property Process askProc: Process {
        command: ["python3", Quickshell.shellPath("scripts/ai-ask.py"), "--stream"]
        stdinEnabled: true

        // Re-armed on every start. `stdinEnabled` is turned OFF after writing so the
        // helper sees EOF and stops waiting for more input — but it does not turn
        // itself back on, so without this line the second question of a session would
        // be sent to a process that never receives it and hangs until the timeout.
        onRunningChanged: if (running) stdinEnabled = true

        onStarted: {
            write(JSON.stringify({
                messages: root.messages,
                provider: root.provider,
                model: Config.aiModel,
                maxTokens: Config.aiMaxTokens,
                grounding: Config.aiGrounding,
                effort: Config.aiEffort
            }) + "\n")
            stdinEnabled = false
        }

        // One simplified event per line — see ai-ask.py's streaming header. SplitParser
        // rather than StdioCollector: the whole point is to act on each line as it
        // arrives, and a collector by definition waits for the process to exit.
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                let d = null
                try { d = JSON.parse(line) } catch (e) { return }
                if (d.t === "thinking") { root.thinking = true; return }
                if (d.t === "delta") {
                    root.thinking = false
                    root.pending += (d.text || "")
                    return
                }
                if (d.t === "error")   { root.error = d.error || "request failed"; return }
                if (d.t === "done") {
                    root.lastCost = d.cost || 0
                    root.lastMs   = d.ms || 0
                }
            }
        }

        // Committed on EXIT, not on the "done" line: a turn that dies mid-stream still
        // has to land whatever it produced, and doing it in one place means a crash and
        // a clean finish cannot disagree about whether the answer was kept.
        onExited: {
            root.busy = false
            root.thinking = false
            if (root.pending !== "") {
                root.messages = root.messages.concat([{ role: "model", text: root.pending }])
                root.pending = ""
            } else if (root.error === "") {
                root.error = "empty answer"
            }
        }
    }
}
