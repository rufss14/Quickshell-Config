pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "../state"
import "bt.js" as B

// ── BtBridge ──────────────────────────────────────────────────────────────────
// The QML face of scripts/bt-helper.py: the pairing agent, signal strength, and
// sending files. Everything Quickshell.Bluetooth doesn't expose — see the helper's
// header for why each one needs its own D-Bus connection.
//
// ── Always running while there's an adapter ──────────────────────────────────
// The agent has to be registered BEFORE a pairing starts — including one the phone
// starts, with no panel open — so this is eager (shell.qml's Connections) and the
// helper lives as long as an adapter does. Idle it's a GLib loop blocked on D-Bus:
// no polling. `Config.btAgent` flips registration live over stdin, no restart.
//
// ── A question takes the panel ───────────────────────────────────────────────
// A prompt (confirm this code, type this PIN, allow this service) opens the
// Bluetooth panel, which shows it on top. BlueZ waits for the answer; the helper
// rejects after 60s if nobody gives one.
//
// ── Sending a file ───────────────────────────────────────────────────────────
// `stage(path)` parks a file (the screenshot toast's Send, a drop on the panel) and
// opens the panel to pick a device; `sendFile()` starts it. Needs bluez-obex —
// `shareBlocker()` says so rather than failing on click.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    // "" or why the helper can't run at all (python-dbus missing, no system bus).
    // Fatal is fatal: exit code 3 isn't restarted.
    property string fatal: ""
    property bool   ready: false
    property bool   agentOn: false
    property string agentError: ""
    property bool   obexAvailable: false

    // ── Agent prompts ─────────────────────────────────────────────────────────
    // id → { id, kind, address, passkey, pin, entered, service }. `prompt` is the
    // oldest still open — one question on screen at a time.
    property var _prompts: ({})
    readonly property var prompt: {
        const ids = Object.keys(root._prompts).map(Number).sort((a, b) => a - b)
        return ids.length > 0 ? root._prompts[ids[0]] : null
    }

    // ── Per-device facts the helper pushes ────────────────────────────────────
    property var rssi: ({})                  // address → dBm (absent = no reading)
    property var opp:  ({})                  // address → accepts files

    // ── Transfers ─────────────────────────────────────────────────────────────
    // Newest first: { id, address, name, size, sent, status, error }. Finished ones
    // stay (a few) so the panel can say how it went; dismissTransfer() clears one.
    property var transfers: []
    readonly property int transfersKept: 4
    readonly property bool sending: root.transfers.some(t => t.status !== "complete" && t.status !== "error")
    property string staged: ""               // a file waiting for a device to be picked
    property int _nextTransfer: 1

    // ── Reasons, for disabling controls ──────────────────────────────────────
    function agentBlocker() {
        if (root.fatal !== "")  return root.fatal
        if (!Config.btAgent)    return "The pairing agent is turned off in Bluetooth settings"
        if (!root.ready)        return "Starting…"
        return root.agentOn ? "" : (root.agentError || "No pairing agent")
    }
    function shareBlocker() {
        if (root.fatal !== "")      return root.fatal
        if (!root.ready)            return "Starting…"
        if (!root.obexAvailable)    return "Sending files needs bluez-obex"
        return ""
    }

    function barsOf(address)     { return B.signalBars(root.rssi[address]) }
    function canReceive(address) { return root.opp[address] === true }

    // ── Commands ──────────────────────────────────────────────────────────────
    function answer(id, ok, value) {
        root._send({ c: "answer", id: id, ok: ok, value: String(value ?? "") })
        root._dropPrompt(id)                 // the helper's prompt-end confirms it
    }

    function stage(path) {
        root.staged = String(path || "")
        if (root.staged !== "") UiState.openPanel("bluetooth")
    }
    function unstage() { root.staged = "" }

    function sendFile(address, path) {
        if (!B.validAddress(address) || typeof path !== "string" || !path.startsWith("/")) return
        const id = root._nextTransfer++
        root._upsert({ id: id, address: address.toUpperCase(), name: path.split("/").pop(),
                       size: 0, sent: 0, status: "connecting", error: "" })
        root._send({ c: "send", id: id, address: address.toUpperCase(), path: path })
        if (root.staged === path) root.staged = ""
    }
    function cancelTransfer(id)  { root._send({ c: "cancel", id: id }) }
    function dismissTransfer(id) { root.transfers = root.transfers.filter(t => t.id !== id) }

    // ── The helper ────────────────────────────────────────────────────────────
    // `_cycling` dips `running` to restart it: a Process that exits on its own keeps
    // reading `running: true` from its binding and never starts again by itself.
    property bool _cycling: false
    property int  _restarts: 0

    property Process _proc: Process {
        running: Bt.available && root.fatal === "" && !root._cycling
        command: ["python3", Quickshell.shellPath("scripts/bt-helper.py")]
                 .concat(Config.btAgent ? [] : ["--no-agent"])
        stdinEnabled: true

        stdout: SplitParser { onRead: function (line) { root._ingest(line) } }
        // The helper never logs a PIN, passkey or file content — see its header.
        stderr: SplitParser { onRead: function (line) { console.log("BtBridge:", line) } }

        onExited: function (code) {
            root.ready = false
            root.agentOn = false
            root._prompts = ({})
            if (code === 3 || !Bt.available) return
            // Unexpected: back off and try again, a few times per session.
            if (root._restarts < 5) {
                root._restarts++
                root._restartTimer.restart()
            } else {
                console.warn("BtBridge: helper keeps exiting (" + code + "); giving up this session")
            }
        }
    }
    property Timer _restartTimer: Timer {
        interval: 3000 * Math.max(1, root._restarts)
        onTriggered: { root._cycling = true; Qt.callLater(() => root._cycling = false) }
    }

    // The agent switch goes over stdin — registering/unregistering is a D-Bus call,
    // not a reason to restart the whole helper.
    property Connections _cfg: Connections {
        target: Config
        function onBtAgentChanged() { root._send({ c: "agent", on: Config.btAgent }) }
    }

    function _send(obj) {
        if (!root._proc.running) return
        root._proc.write(JSON.stringify(obj) + "\n")
    }

    // ── Parsing ───────────────────────────────────────────────────────────────
    function _ingest(line) {
        let msg
        try { msg = JSON.parse(line) } catch (e) {
            console.warn("BtBridge: unparseable line from helper:", line.substring(0, 80))
            return
        }
        switch (msg.t) {
        case "hello":
            root.ready = true
            root._restarts = 0
            root.obexAvailable = msg.obex === true
            break
        case "fatal":
            root.fatal = String(msg.error || "Bluetooth helper failed")
            console.warn("BtBridge:", root.fatal)
            break
        case "agent":
            root.agentOn = msg.on === true
            root.agentError = String(msg.error || "")
            break
        case "obex":
            root.obexAvailable = msg.available === true
            break
        case "prompt":
            root._addPrompt(msg)
            break
        case "prompt-end":
            root._dropPrompt(msg.id)
            break
        case "dev":
            root._device(msg)
            break
        case "transfer":
            root._transfer(msg)
            break
        }
    }

    function _addPrompt(msg) {
        const next = Object.assign({}, root._prompts)
        const known = next[msg.id] !== undefined
        next[msg.id] = {
            id: msg.id, kind: String(msg.kind || ""), address: String(msg.address || ""),
            passkey: String(msg.passkey ?? ""), pin: String(msg.pin ?? ""),
            entered: Number(msg.entered ?? 0), service: String(msg.service ?? "")
        }
        root._prompts = next
        // Only a NEW question opens the panel — a display-passkey update (one per
        // digit typed on the remote keyboard) must not re-open one you closed.
        if (!known) UiState.openPanel("bluetooth")
    }
    function _dropPrompt(id) {
        if (root._prompts[id] === undefined) return
        const next = Object.assign({}, root._prompts)
        delete next[id]
        root._prompts = next
    }

    function _device(msg) {
        const a = String(msg.address || "")
        if (!B.validAddress(a)) return
        if ("rssi" in msg) {
            const next = Object.assign({}, root.rssi)
            if (typeof msg.rssi === "number") next[a] = msg.rssi
            else delete next[a]
            root.rssi = next
        }
        if ("opp" in msg) {
            const next = Object.assign({}, root.opp)
            next[a] = msg.opp === true
            root.opp = next
        }
    }

    function _upsert(t) {
        const rest = root.transfers.filter(x => x.id !== t.id)
        root.transfers = [t].concat(rest).slice(0, root.transfersKept)
    }

    function _transfer(msg) {
        const prev = root.transfers.find(x => x.id === msg.id)
        const t = {
            id: msg.id, address: String(msg.address || ""), name: String(msg.name || ""),
            size: Number(msg.size || 0), sent: Number(msg.sent || 0),
            status: String(msg.status || ""), error: String(msg.error || "")
        }
        root._upsert(t)
        const ended = t.status === "complete" || t.status === "error"
        const wasEnded = prev && (prev.status === "complete" || prev.status === "error")
        if (ended && !wasEnded) {
            const dev = Bt.deviceFor(t.address)
            const who = dev ? (dev.name || dev.address) : t.address
            if (t.status === "complete") root._notify("Sent " + t.name, "to " + who, "low")
            else root._notify("Couldn't send " + t.name, t.error + " (" + who + ")", "normal")
        }
    }

    property Process _notifyProc: Process {}
    function _notify(title, body, urgency) {
        root._notifyProc.command = ["notify-send", "--app-name=Quickshell", "--urgency=" + urgency,
                                    "--icon=bluetooth", title, body]
        root._notifyProc.running = false
        root._notifyProc.running = true
    }

    // ── Diagnostics ───────────────────────────────────────────────────────────
    //     qs ipc -c ~/.config/quicktest call btbridge status
    // States and counts only — never a PIN, passkey or file name.
    property IpcHandler _ipc: IpcHandler {
        target: "btbridge"
        function status(): string {
            return "running=" + root._proc.running + " ready=" + root.ready
                 + " fatal=" + (root.fatal || "-")
                 + " agent=" + root.agentOn + (root.agentError ? " (" + root.agentError + ")" : "")
                 + " obex=" + root.obexAvailable
                 + " prompts=" + Object.keys(root._prompts).length
                 + " rssi=" + Object.keys(root.rssi).length
                 + " transfers=" + root.transfers.length
        }
    }
}
