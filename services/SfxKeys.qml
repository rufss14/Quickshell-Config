pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../config"
import "sfxkeys.js" as KeysJs

// ── SfxKeys ───────────────────────────────────────────────────────────────────
// "Typing sounds everywhere": key sounds for keys that go to OTHER apps. Wayland shows the
// shell only its own keys, so Hyprland has to say; this installs a small Lua hook into the
// compositor (`hyprctl eval`, at runtime — no config file is edited, as CursorEffects does)
// that posts a custom event per key, and listens for it on the event socket the shell
// already reads. services/sfxkeys.js says what the hook sends — a class, never the key —
// and what is still unknown about Hyprland's payload.
//
// ── It exists only while it should ────────────────────────────────────────────
// The hook is in the compositor only while ALL of these hold, and out of it otherwise
// (zero cost, nothing on the socket):
//   · sound effects on, typing on, and the scope set to "Everywhere"
//   · Game Mode not silencing keys (a game's WASD is not typing)
//   · the screen not locked (the lock screen's password is never clicked)
// A Hyprland config reload drops runtime Lua, so it goes back in on `configreloaded`.
//
// `qs ipc -c ~/.config/quicktest call sfxkeys status` — counts and the payload SHAPE,
// never a key.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property bool wanted:
        Config.sfxEnabled && Config.sfxTyping && Config.sfxTypingScope === "all"
        && !Gamemode.silencesKeys && !Lock.locked

    // True once hyprctl accepted the install and until the hook is removed.
    property bool installed: false
    // The hook is delivering: events are ignored unless this holds, so a lingering
    // subscription (a removal that didn't land) is still silent.
    readonly property bool live: root.installed && root.wanted

    property int    events:    0        // key events heard since the shell started
    property var    shapes:    []       // the distinct payload shapes seen, for diagnosing
    property string lastError: ""

    function _eval(lua) {
        if (evalProc.running) { root._pending = lua; return }
        evalProc.command = ["hyprctl", "eval", lua]
        evalProc.running = true
    }
    property string _pending: ""
    property string _sent:    ""            // "install" | "remove": what the eval in flight is

    function _sync() {
        if (root.wanted && !root.installed && root._sent !== "install") {
            root._sent = "install"
            root._eval(KeysJs.INSTALL_LUA)
        } else if (!root.wanted && (root.installed || root._sent === "install")) {
            root._sent = "remove"
            root.installed = false
            root._eval(KeysJs.REMOVE_LUA)
        }
    }

    onWantedChanged: root._sync()
    Component.onCompleted: root._sync()

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                // Runtime Lua does not survive a reload.
                if (root.installed) { root.installed = false; root._sent = "" ; root._sync() }
                return
            }
            if (event.name !== "custom") return
            const ev = KeysJs.parse(event.data)
            if (ev === null) return
            if (ev.shape !== undefined) {
                if (root.shapes.indexOf(ev.shape) < 0) root.shapes = root.shapes.concat([ev.shape])
                return
            }
            root.events++
            if (!root.live || !KeysJs.sounds(ev)) return
            Sfx.play(ev.cls)
        }
    }

    Process {
        id: evalProc
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: function (code) {
            const msg = (out.text + err.text).trim()
            // hyprctl answers "ok" on success and prints the Lua error otherwise; the
            // exit code alone isn't trustworthy for either.
            const failed = code !== 0 || /error|fail|expected/i.test(msg)
            root.lastError = failed ? (msg.split("\n").pop() || ("failed (" + code + ")")) : ""
            if (failed) console.warn("SfxKeys: hyprctl eval failed -", root.lastError)
            if (root._sent === "install") {
                root.installed = !failed
                // The conditions may have changed while the install was in flight.
                if (!root.wanted && !failed) { root._sent = ""; root._sync() }
            }
            if (root._sent === "remove") root._sent = ""
            if (root._pending !== "") {
                const next = root._pending
                root._pending = ""
                root._eval(next)
            }
        }
    }

    IpcHandler {
        target: "sfxkeys"
        function status(): string {
            return JSON.stringify({ wanted: root.wanted, installed: root.installed,
                                    live: root.live, events: root.events,
                                    shapes: root.shapes, error: root.lastError,
                                    gamemodeMutes: Gamemode.silencesKeys, locked: Lock.locked })
        }
    }
}
