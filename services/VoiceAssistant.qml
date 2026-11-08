pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "../state"

// ── VoiceAssistant ────────────────────────────────────────────────────────────
// "Hey Claude, play Odo by Ado" (2026-10-24, the user: "Siri-like"). scripts/voice-listen.py listens for
// the wake phrase and hears the request (Vosk, on this machine); this hands the words to the same AI as
// the overview's Ask page (services/Assistant — the same thread, the same actions, the same safety) and
// keeps what the overlay (modules/voice/VoiceOrb) shows:
//
//     off ─(Config.aiVoice + a model)→ idle ─"hey claude"→ listening ─(a pause)→ thinking → answer → idle
//
// `listen()` skips the wake phrase (a key, a click: `qs ipc call voice listen`).
//
// ── The microphone is open the whole time it's on ─────────────────────────────
// That's what a wake word costs, so it's OFF by default and says so where it's switched on. Audio never
// leaves the listener's memory (see the script); what's heard after the wake phrase goes to whichever AI
// is set — the local one by default, so nothing leaves the machine at all.
//
// ── The speech model ──────────────────────────────────────────────────────────
// Vosk's small English model (~40 MB), fetched by scripts/karaoke-model.sh into the same place Karaoke's
// models live ($XDG_DATA_HOME/quicktest/vosk-en-us). `getModel()` runs it — a button, never by itself.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string modelDir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share"))
                                       + "/quicktest/vosk-en-us"
    property bool modelPresent: false
    property bool downloading: false

    // off · idle · listening · thinking · answer · error
    property string state: "off"
    property string heard: ""
    property real level: 0
    property string reason: ""              // why it can't listen, for the settings row
    property string reply: ""
    property var actions: []                // [{ m, a }] — the reply's cards, read live from Assistant
    property int _askedAt: -1

    readonly property var wakeWords: (Config.aiWakeWords || "hey claude").split(",").map(s => s.trim().toLowerCase()).filter(s => s !== "")
    readonly property bool wanted: Config.aiVoice && root.modelPresent
    readonly property bool active: root.state === "listening" || root.state === "thinking" || root.state === "answer"

    function listen() {
        if (!listener.running) return
        listener.write("listen\n")
    }
    function cancel() {
        if (listener.running) listener.write("cancel\n")
        root._rest()
    }
    function getModel() {
        if (root.downloading) return
        root.downloading = true
        root.reason = ""
        fetch.running = true
    }
    // Look for the model again (it may have been fetched since — by the button, or by hand).
    function recheck() { if (!probe.running) probe.running = true }
    function _rest() {
        hide.stop()
        root.state = listener.running ? "idle" : "off"
        root.level = 0
    }

    Component.onCompleted: { probe.running = true; root._sync() }
    onWantedChanged: root._sync()
    // Running exactly while wanted — and back after a crash or a kill (a beat later, so a listener that
    // can't start doesn't spin): a changed script then takes effect on its next start.
    function _sync() {
        if (root.wanted && !listener.running) revive.restart()
        else if (!root.wanted && listener.running) listener.running = false
    }
    Timer { id: revive; interval: 1500; onTriggered: if (root.wanted && !listener.running) listener.running = true }

    // Is the model there?
    Process {
        id: probe
        command: ["test", "-d", root.modelDir]
        onExited: code => root.modelPresent = (code === 0)
    }
    Process {
        id: fetch
        command: ["bash", Quickshell.shellPath("scripts/karaoke-model.sh"), "en-us"]
        stderr: StdioCollector { id: fetchErr }
        onExited: code => {
            root.downloading = false
            if (code !== 0) root.reason = (fetchErr.text.trim().split("\n").pop() || "The download failed").slice(0, 160)
            probe.running = true
        }
    }

    // ── The listener ──────────────────────────────────────────────────────────
    Process {
        id: listener
        command: {
            const c = ["python3", Quickshell.shellPath("scripts/voice-listen.py"), "--model", root.modelDir]
            for (const w of root.wakeWords) c.push("--wake", w)
            return c
        }
        stdinEnabled: true
        onRunningChanged: {
            if (running) { stdinEnabled = true; root.reason = ""; root.state = "idle" }
            else {
                if (root.state !== "error") root.state = "off"
                // It ended without being asked to: back, unless it said it can't (an error).
                if (root.wanted && root.state !== "error") revive.restart()
            }
        }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                let d = null
                try { d = JSON.parse(line) } catch (e) { return }
                root._event(d)
            }
        }
    }

    function _event(d) {
        switch (d.t) {
        case "ready":
            if (!d.ok) { root.reason = d.reason || "It can't listen"; root.state = "error" }
            else if ((d.unknown || []).length) root.reason = "The model doesn't know: " + d.unknown.join(", ")
            break
        case "wake":
            hide.stop()
            root.heard = ""
            root.reply = ""
            root.actions = []
            root.level = 0
            root.state = "listening"
            break
        case "partial":
            if (root.state === "listening") root.heard = d.text || ""
            break
        case "level":
            root.level = Math.min(1, (d.v || 0) * 6)
            break
        case "final":
            root.heard = d.text || root.heard
            root._ask(root.heard)
            break
        case "timeout":
            root._rest()
            break
        case "error":
            root.reason = d.msg || "The listener stopped"
            root.state = "error"
            break
        }
    }

    // The words → the AI. Its answer lands in Assistant's thread like a typed one.
    function _ask(text) {
        root.level = 0
        if (text.trim() === "") { root._rest(); return }
        const why = Ai.blocker()
        if (why !== "" || Assistant.busy) {
            root.reply = why !== "" ? why : "Still answering the last one"
            root.state = "answer"
            hide.restart()
            return
        }
        root._askedAt = Assistant.messages.length
        root.state = "thinking"
        Assistant.ask(text)
    }
    Connections {
        target: Assistant
        function onBusyChanged() {
            if (Assistant.busy || root.state !== "thinking") return
            const ms = Assistant.messages
            const last = ms.length > root._askedAt + 1 ? ms[ms.length - 1] : null
            if (last && last.role === "model") {
                root.reply = last.text
                root.actions = (last.actions || []).map((a, i) => ({ m: ms.length - 1, a: i }))
            } else root.reply = Assistant.error || "No answer"
            root.state = "answer"
            hide.restart()
        }
    }
    // An answer stays a while — longer when something on it waits for an OK.
    Timer {
        id: hide
        interval: root.actions.some(x => Assistant.stateOf(x.m, x.a)?.state === "ask") ? 14000 : 6500
        onTriggered: root._rest()
    }

    // `qs ipc -c ~/.config/quicktest call voice listen` — for a key: skip the wake phrase.
    IpcHandler {
        target: "voice"
        function listen(): void { root.listen() }
        function cancel(): void { root.cancel() }
        function toggle(): void { Config.aiVoice = !Config.aiVoice }
    }
}
