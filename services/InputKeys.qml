pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "inputkeys.js" as InputJs

// ── InputKeys ─────────────────────────────────────────────────────────────────
// Which of the input overlay's keys and mouse buttons are held right now — for the HUD's
// "Input" widget (modules/hud/HudInput), the on-screen keyboard-and-mouse you show over a
// game. services/inputkeys.js has the Lua and what it does and doesn't send.
//
// The mouse buttons come from static binds in hypr/binds.lua, switched on by the same
// hook — never runtime binds, which crashed Hyprland (services/inputkeys.js).
//
// ── It exists only while it should ────────────────────────────────────────────
// The hook is in the compositor only while a view holds it (`acquire` / `release` — the
// widget does, and only exists while it's on screen) AND the screen isn't locked (the
// lock screen's password is made of exactly these letters). Otherwise it is removed:
// nothing on the socket. A Hyprland config reload drops runtime Lua; it goes back in on
// `configreloaded`.
//
// `held` is cleared whenever the hook goes in or out: a key held across that moment never
// gets its release, and would otherwise stay lit. The rates and their bests start over
// then too — a session's best is the overlay's, not the shell's.
//
// ── Rates ─────────────────────────────────────────────────────────────────────
// Clicks / keys per second = presses in the last second (inputkeys.js `prune`). A rate
// has to fall back to 0 after you stop, with no event to say so, so a 100 ms tick runs
// while any press is still inside the window — and only then.
//
// `qs ipc -c ~/.config/quicktest call inputkeys status`
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // id → true for everything held (inputkeys.js KEYS / BUTTONS ids). Replaced whole.
    property var held: ({})

    // Presses in the last second, and the most this session.
    property int cpsLeft: 0
    property int cpsRight: 0
    property int kps: 0
    property int bestLeft: 0
    property int bestRight: 0
    property int bestKeys: 0
    property var _times: ({ left: [], right: [], keys: [] })

    function _count(kind) {
        const now = Date.now()
        root._times[kind].push(now)
        root._rates(now)
        decay.running = true
    }
    function _rates(now) {
        const t = root._times
        for (const k in t) t[k] = InputJs.prune(t[k], now)
        root.cpsLeft = t.left.length
        root.cpsRight = t.right.length
        root.kps = t.keys.length
        root.bestLeft = Math.max(root.bestLeft, root.cpsLeft)
        root.bestRight = Math.max(root.bestRight, root.cpsRight)
        root.bestKeys = Math.max(root.bestKeys, root.kps)
        if (root.cpsLeft + root.cpsRight + root.kps === 0) decay.running = false
    }
    function _reset() {
        root.held = ({})
        root._times = ({ left: [], right: [], keys: [] })
        root.cpsLeft = root.cpsRight = root.kps = 0
        root.bestLeft = root.bestRight = root.bestKeys = 0
        decay.running = false
    }

    Timer {
        id: decay
        interval: 100
        repeat: true
        onTriggered: root._rates(Date.now())
    }

    property int _users: 0
    function acquire() { root._users++; root._sync() }
    function release() { root._users = Math.max(0, root._users - 1); root._sync() }

    readonly property bool wanted: root._users > 0 && !Lock.locked

    property bool installed: false
    // The keyboard preset on screen (Hud's input widget `layout` option): the hook names exactly ITS keys, so changing it
    // puts a new hook in (the install replaces the old one).
    readonly property string layout: InputJs.isLayout(Hud.layout.widgets.input?.opts?.layout) ? Hud.layout.widgets.input.opts.layout : InputJs.DEFAULT_LAYOUT
    property string _layoutIn: ""
    onLayoutChanged: root._sync()
    property int events: 0
    // Presses per drawn id since the shell started — for `status`, to tell a key the hook
    // never reports from one the view fails to light. Drawn ids only, like the socket.
    property var _presses: ({})
    property string lastError: ""
    property string _sent: ""               // "install" | "remove": what the eval in flight is

    function _sync() {
        if (evalProc.running) return        // onExited calls back in
        if (root.wanted && root.installed && root._layoutIn !== root.layout) root.installed = false
        if (root.wanted && !root.installed) {
            root._sent = "install"
            root._layoutIn = root.layout
        } else if (!root.wanted && root.installed) {
            root._sent = "remove"
            root.installed = false
        } else return
        root._reset()
        evalProc.command = ["hyprctl", "eval", root._sent === "install" ? InputJs.installLua(root._layoutIn)
                                                                        : InputJs.REMOVE_LUA]
        evalProc.running = true
    }

    onWantedChanged: root._sync()

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                // Runtime Lua does not survive a reload.
                if (root.installed) { root.installed = false; root._sync() }
                return
            }
            if (event.name !== "custom" || !root.installed) return
            const ev = InputJs.parse(event.data)
            if (ev === null) return
            root.events++
            const kind = InputJs.counts(ev)
            if (kind !== "") root._count(kind)
            if (ev.anon) return
            if (ev.down) root._presses[ev.id] = (root._presses[ev.id] || 0) + 1
            root.held = InputJs.apply(root.held, ev)
        }
    }

    Process {
        id: evalProc
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: function (code) {
            const msg = (out.text + err.text).trim()
            // hyprctl answers "ok" on success and prints the Lua error otherwise; the
            // exit code alone isn't trustworthy for either (SfxKeys).
            const failed = code !== 0 || /error|fail|expected/i.test(msg)
            root.lastError = failed ? (msg.split("\n").pop() || ("failed (" + code + ")")) : ""
            if (failed) console.warn("InputKeys: hyprctl eval failed -", root.lastError)
            if (root._sent === "install") root.installed = !failed
            root._sent = ""
            // The wish may have changed while it was in flight; a failed install is not
            // retried here (it would loop), only on the next change.
            if (!failed) root._sync()
        }
    }

    IpcHandler {
        target: "inputkeys"
        function status(): string {
            return JSON.stringify({ users: root._users, wanted: root.wanted, layout: root.layout,
                                    installed: root.installed, events: root.events,
                                    held: Object.keys(root.held), error: root.lastError,
                                    cps: [root.cpsLeft, root.cpsRight], kps: root.kps,
                                    presses: root._presses })
        }
    }
}
