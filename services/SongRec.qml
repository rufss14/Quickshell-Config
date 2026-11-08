pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "songrec.js" as S

// ── SongRec ───────────────────────────────────────────────────────────────────
// "What is this song?" — Shazam-style recognition through the `songrec` CLI, listening
// to either what the desktop is playing (the default output's monitor) or the microphone
// (a song playing in the room).
//
//     qs ipc -c ~/.config/quicktest call songrec toggle      # desktop audio
//     qs ipc -c ~/.config/quicktest call songrec toggleMic   # microphone
//
// The Now-Playing panel has the two buttons; the result is `track`, and also a
// notification with "Open in Shazam" / "Search YouTube" so it works from a keybind with
// no panel open.
//
// ── One listen, bounded three ways ────────────────────────────────────────────
// `songrec listen` keeps going until it is killed, so a listen ends on the first hit,
// on `listenSeconds`, or by `stop()`. And it runs under `timeout`, so a shell that dies
// mid-listen doesn't leave a microphone open behind it.
//
// ── What reads the output, and what it trusts ─────────────────────────────────
// songrec.js, which finds the JSON by scanning and only lets https links through (the
// track's URL comes off the network and is handed to the browser). The listen is never
// restarted by itself.
//
// songrec is OPTIONAL: `blocker()` says why the control is dead (not installed, no audio
// device) instead of letting it fail on click — the same contract as NightLight.blocker().
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property int listenSeconds: 30

    // ── Is it usable ─────────────────────────────────────────────────────────
    property bool _probed:  false
    property bool _present: false
    function probe() {
        root._probeProc.running = false
        root._probeProc.running = true
    }
    property Process _probeProc: Process {
        command: ["sh", "-c", "command -v songrec"]
        stdout: StdioCollector {
            onStreamFinished: { root._present = text.trim() !== ""; root._probed = true }
        }
    }
    Component.onCompleted: root.probe()

    // The device a listen of this kind would read, or "" when there is none.
    // PipeWire's pulse layer names a sink's monitor `<sink name>.monitor`.
    function device(mic) {
        if (mic) return Audio.source?.name || ""
        const n = Audio.sink?.name || ""
        return n !== "" ? n + ".monitor" : ""
    }

    function blocker(mic) {
        if (!root._probed)  return Translation.tr("Checking for songrec…")
        if (!root._present) return Translation.tr("Needs songrec — it isn't installed")
        if (root.device(mic === true) === "")
            return mic === true ? Translation.tr("No microphone found") : Translation.tr("No audio output to listen to")
        return ""
    }

    // ── State ────────────────────────────────────────────────────────────────
    // "idle" | "listening" | "found" | "missed"
    readonly property string phase: root._phase
    readonly property var    track: root._track          // { title, artist, url, art } | null
    readonly property bool   listening: root._phase === "listening"
    readonly property bool   usingMic:  root._mic
    property string _phase: "idle"
    property var    _track: null
    property bool   _mic: false
    property string _buf: ""

    function start(mic) {
        if (root.listening || root.blocker(mic) !== "") return
        root._mic = mic === true
        root._track = null
        root._buf = ""
        root._phase = "listening"
        root._proc.command = ["timeout", String(root.listenSeconds + 5), "songrec", "listen",
            "--audio-device", root.device(root._mic),
            "--request-interval", "3", "--json", "--disable-mpris"]
        root._proc.running = true
        deadline.restart()
    }

    function stop() {
        deadline.stop()
        root._proc.running = false
        if (root._phase === "listening") root._phase = "idle"
    }

    // The button's gesture: start, or stop what's running.
    function toggle(mic) { if (root.listening) root.stop(); else root.start(mic) }

    function _feed(line) {
        if (root._phase !== "listening") return
        // Bounded: a chatty tool must not grow this for the whole listen.
        root._buf = (root._buf + line + "\n").slice(-65536)
        const t = S.pick(root._buf)
        if (t) root._found(t)
    }

    function _found(t) {
        deadline.stop()
        root._track = t
        root._phase = "found"
        settle.restart()
        root._proc.running = false
        root._announce(t)
    }

    function _miss() {
        root._proc.running = false
        if (root._phase === "listening") {
            root._phase = "missed"
            settle.restart()
            Quickshell.execDetached(["notify-send", "-a", "Music", Translation.tr("Couldn't recognise it"),
                Translation.tr("Perhaps it's too niche, or too quiet")])
        }
    }

    // A result is news for a few seconds, then the panel's subtitle goes back to the
    // track that's playing. `track` stays, for whoever wants the last answer.
    Timer {
        id: settle
        interval: 12000
        onTriggered: if (root._phase !== "listening") root._phase = "idle"
    }

    Timer {
        id: deadline
        interval: root.listenSeconds * 1000
        onTriggered: root._miss()
    }

    property Process _proc: Process {
        stdout: SplitParser { onRead: line => root._feed(line) }
        // songrec ending by itself while we still wait for it = it failed to start or died.
        onExited: if (root._phase === "listening") {
            deadline.stop()
            root._phase = "missed"
            settle.restart()
            Quickshell.execDetached(["notify-send", "-a", "Music", Translation.tr("Couldn't listen"),
                Translation.tr("songrec stopped before hearing anything")])
        }
    }

    // ── The notification, with actions ───────────────────────────────────────
    // notify-send -A waits for a click and prints the chosen action's index; the shell is
    // the notification daemon, so the buttons are its own.
    property var _acts: []
    function _announce(t) {
        const acts = []
        if (t.url !== "") acts.push({ label: Translation.tr("Open in Shazam"), url: t.url })
        acts.push({ label: Translation.tr("Search YouTube"), url: S.searchUrl(t) })
        root._acts = acts
        const cmd = ["notify-send", "-a", "Music"]
        for (const a of acts) cmd.push("-A", a.label)
        cmd.push(Translation.tr("Music recognised"), t.artist !== "" ? t.title + " — " + t.artist : t.title)
        root._note.command = cmd
        root._note.running = true
    }
    property Process _note: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const i = parseInt(text.trim(), 10)
                if (isFinite(i) && root._acts[i]) Qt.openUrlExternally(root._acts[i].url)
            }
        }
    }

    IpcHandler {
        target: "songrec"
        function toggle(): void { root.toggle(false) }
        function toggleMic(): void { root.toggle(true) }
        function stop(): void { root.stop() }
        function status(): string { return root.phase + (root.track ? ": " + root.track.title : "") }
    }
}
