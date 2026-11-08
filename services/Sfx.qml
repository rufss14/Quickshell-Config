pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "../state"
import "sfx.js" as SfxJs

// ── Sfx ───────────────────────────────────────────────────────────────────────
// Sound effects: a swoosh as a panel opens or closes, a soft click per key typed in
// the shell's own fields, a blip for a switch, a chime for a notification.
//
// ── Where each part lives ─────────────────────────────────────────────────────
//   scripts/gen-sfx.py            makes the sounds (synthesised — no recordings, no licence)
//   pw-play                       plays them, one short process per cue (see "Playing")
//   services/sfx.js               decides: which key, what a panel change means, how loud
//   this file                     wires them: the files, the player, the switches, the hooks
//
// ── Why a process per cue and not QtMultimedia ────────────────────────────────
// It was a SoundEffect per file. Two things went wrong, both measured 2026-10-06:
// creating all of them at once stalled PipeWire (every reload froze), and with Qt
// Multimedia's audio thread (QAudioContext) alive the shell SEGFAULTED when the headset
// was unplugged — inside PipeWire's client library, in a thread this shell cannot guard.
// With sound effects off there was no FFmpeg init and no thread. A pw-play process that
// dies on an unplug takes only itself with it, and Qt Multimedia is no longer loaded for
// sound at all (the clip editor still uses it, and only while a clip plays).
//
// ── Nothing is built until it is wanted ───────────────────────────────────────
// Off by default (Config.sfxEnabled). The generator and the pw-play probe only run once
// sound is switched on — or the settings page asks to preview (`warm()`).
//
// ── Hooks, not per-panel code ─────────────────────────────────────────────────
// Panels are told apart by UiState's slots (leftKey / rightKey / centerKey / sidePanel),
// so ONE Connections here covers every panel, including ones added later. A panel
// swapping for another is one gesture (sfx.js panelCue). Typing comes the other way: a
// text field calls `typed()`; this service can't see keys, and Wayland gives it no way to
// see the ones that go to other apps (so "everywhere" is a separate, later mechanism).
//
// `qs ipc -c ~/.config/quicktest call sfx status | test <cue>`.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string dir:
        (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
        + "/quickshell-quicktest/sfx"

    // Held by the settings page so its Play buttons work while the master is off.
    property bool _warm: false
    readonly property bool wanted: Config.sfxEnabled || root._warm

    property bool generated: false
    property bool genFailed: false
    // Is pw-play on this machine? Asked once, when sound is first wanted.
    property bool _probed:    false
    property bool _havePlayer: false
    readonly property bool ready: root._havePlayer && root.generated

    // Why it can't sound, for the settings page. "" = nothing is wrong (or not asked yet).
    readonly property string blocker:
        !root.wanted     ? ""
        : root._probed && !root._havePlayer ? "Needs pw-play (the pipewire package)"
        : root.genFailed ? "Couldn't generate the sounds — is python3 installed?"
        : ""

    // Each group's switch and level, in sfx.js's vocabulary (GROUPS).
    readonly property var prefs: ({
        enabled: Config.sfxEnabled,   panels: Config.sfxPanels,
        typing:  Config.sfxTyping,    switches: Config.sfxSwitches,
        notify:  Config.sfxNotify,    alerts:   Config.sfxAlerts,
        capture: Config.sfxCapture
    })
    readonly property var levels: ({
        panels: Config.sfxPanelsVolume,     typing: Config.sfxTypingVolume,
        switches: Config.sfxSwitchesVolume, notify: Config.sfxNotifyVolume,
        alerts: Config.sfxAlertsVolume,     capture: Config.sfxCaptureVolume
    })

    function warm() { root._warm = true }

    // ── Playing ───────────────────────────────────────────────────────────────
    property var _lastAt:   ({})
    property var _lastFile: ({})

    function play(id) {
        if (!root.ready || !SfxJs.shouldPlay(id, root.prefs)) return
        root._fire(id)
    }

    // Ignores the switches: the settings page's Play buttons must answer even with the
    // group off. Still needs the files and the player.
    function preview(id) { if (root.ready) root._fire(id) }

    property real _announcedAt: -1

    function _fire(id) {
        const now = Date.now()
        if (!SfxJs.allowed(id, now, root._lastAt[id])) return
        // The notification a timer or a saved clip sends would chime over its own cue.
        if (SfxJs.ducked(id, now, root._announcedAt < 0 ? undefined : root._announcedAt)) return
        if (SfxJs.announces(id)) root._announcedAt = now
        root._lastAt[id] = now
        const file = SfxJs.chooseFile(id, root._lastFile[id], Math.random())
        root._lastFile[id] = file
        root._spawn(file, SfxJs.volumeFor(id, Config.sfxVolume, root.levels))
    }

    // One pw-play per cue, detached: it connects, plays the few hundred ms of the file and
    // exits. 20ms of stream latency rather than its 100ms default, because a key click that
    // trails the key is worse than none. Nothing waits on it and nothing is shared, so a
    // burst of cues is a burst of independent short-lived streams, never one stuck voice.
    function _spawn(file, volume) {
        Quickshell.execDetached(["pw-play", "--latency=20ms", "--volume=" + Number(volume).toFixed(3),
                                 root.dir + "/" + file + ".wav"])
    }

    // A text field calls this per key press (it does not accept the event). Control and
    // Meta chords are shortcuts, not typing.
    function typed(key, text, modifiers) {
        if (!root.ready || !Config.sfxEnabled || !Config.sfxTyping) return
        // Everywhere mode hears these keys too, through the compositor; counting them here
        // as well would click twice. Game Mode's mute covers the shell's own fields too.
        if (SfxKeys.live || Gamemode.silencesKeys) return
        const chord = (modifiers & (Qt.ControlModifier | Qt.MetaModifier)) !== 0
        const id = SfxJs.typingCue(key, text, chord)
        if (id !== "") root.play(id)
    }

    // ── Panels ────────────────────────────────────────────────────────────────
    property var _slots: ({})

    function _slot(name, now) {
        const cue = SfxJs.panelCue(root._slots[name], now)
        root._slots[name] = now || ""
        if (cue !== "") root.play(cue)
    }

    Connections {
        target: UiState
        function onLeftKeyChanged()      { root._slot("left",     UiState.leftKey) }
        function onRightKeyChanged()     { root._slot("right",    UiState.rightKey) }
        function onCenterKeyChanged()    { root._slot("center",   UiState.centerKey) }
        function onSidePanelChanged()    { root._slot("side",     UiState.sidePanel) }
        function onOverviewOpenChanged() { root._slot("overview", UiState.overviewOpen ? "overview" : "") }
        function onLauncherOpenChanged() { root._slot("launcher", UiState.launcherOpen ? "launcher" : "") }
        function onPowerMenuOpenChanged() { root._slot("power",   UiState.powerMenuOpen ? "power" : "") }
    }

    // ── Files and the player ──────────────────────────────────────────────────
    // gen-sfx.py is idempotent (a stamp of its own hash), so asking on every start with
    // sound on costs a stat per file.
    property bool _genStarted: false

    Process {
        id: gen
        command: ["python3", Quickshell.shellPath("scripts/gen-sfx.py"), root.dir]
        stdout: StdioCollector {}
        onExited: function (code) {
            root.generated = code === 0
            root.genFailed = code !== 0
            root._reconcile()
        }
    }

    Process {
        id: probe
        command: ["sh", "-c", "command -v pw-play >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector {
            onStreamFinished: {
                root._havePlayer = text.trim() === "yes"
                root._probed = true
            }
        }
    }

    function _reconcile() {
        if (!root.wanted) return
        if (!root._genStarted) { root._genStarted = true; gen.running = true; probe.running = true }
    }

    // The key hook is a service of its own; this forces it to exist so it can install itself
    // (a Connections evaluates its target when created, which a bare reference does not).
    Connections { target: SfxKeys }

    onWantedChanged: root._reconcile()
    Component.onCompleted: root._reconcile()

    IpcHandler {
        target: "sfx"
        function status(): string {
            return JSON.stringify({ enabled: Config.sfxEnabled, ready: root.ready,
                                    player: root._havePlayer, generated: root.generated,
                                    blocker: root.blocker, volume: Config.sfxVolume })
        }
        // Plays one cue by id, switches ignored — a way to hear it from a terminal.
        function test(cue: string): string {
            if (!SfxJs.CUES[cue]) return "unknown cue; one of " + Object.keys(SfxJs.CUES).join(" ")
            root.preview(cue)
            return root.ready ? "played" : "not ready (see status)"
        }
    }
}
