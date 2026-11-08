pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// ── KeyLocks ──────────────────────────────────────────────────────────────────
// The keyboard states worth a glance: the active Hyprland SUBMAP (a resize mode, a
// launcher chord), Caps Lock and Num Lock — for the locks module, which shows only while
// one of them is on.
//
// ── All of it event-driven ────────────────────────────────────────────────────
// The submap comes on the event socket the shell already reads (`submap>>name`, "" when
// it ends). The lock LEDs have no event, so while the module exists a tiny Lua hook is
// put into Hyprland at runtime (`hyprctl eval`, no config file edited — SfxKeys does the
// same) that posts ONE custom event, `qs-locks`, when Caps Lock (keycode 66) or Num Lock
// (77) is released. Those are evdev 58 / 69 plus the xkb +8 Hyprland adds (services/inputkeys.js). Nothing about any other key leaves the compositor: the event socket
// is readable by every process the user runs, so the hook says only "a lock key moved".
// On that event the state is read once from `hyprctl devices -j` (the main keyboard's
// capsLock / numLock). A config reload drops runtime Lua; the hook is put back.
//
// Hyprland hands the key callback bare numbers (time, keycode, state) — measured for
// SfxKeys on 0.56.2 (docs/sound-effects.md) — so the hook just looks for 66/77 among the
// small ones on a release.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property string submap: ""
    property bool caps: false
    property bool num: false
    readonly property bool any: root.submap !== "" || root.caps || root.num

    // Held by every module that shows these; the hook exists only while held.
    property int _users: 0
    function acquire() { root._users++; root._sync() }
    function release() { root._users = Math.max(0, root._users - 1); root._sync() }

    readonly property string _installLua: [
        'if _G.qs_locks_sub then pcall(function() _G.qs_locks_sub:remove() end); _G.qs_locks_sub = nil end',
        '_G.qs_locks_sub = hl.on("input.keyboard.key", function(...)',
        '  local args = table.pack(...)',
        '  pcall(function()',
        '    local lock, released = false, false',
        '    for i = 1, args.n do',
        '      local v = args[i]',
        '      if type(v) == "number" then',
        '        if v == 66 or v == 77 then lock = true end',
        '        if v == 0 then released = true end',
        '      end',
        '    end',
        '    if lock and released then hl.dispatch(hl.dsp.event("qs-locks")) end',
        '  end)',
        'end)'
    ].join("\n")
    readonly property string _removeLua:
        'if _G.qs_locks_sub then pcall(function() _G.qs_locks_sub:remove() end); _G.qs_locks_sub = nil end'

    property bool _installed: false
    function _sync() {
        const want = root._users > 0
        if (want === root._installed || evalProc.running) return
        evalProc.command = ["hyprctl", "eval", want ? root._installLua : root._removeLua]
        evalProc.wantInstalled = want
        evalProc.running = true
        if (want) readProc.running = true
    }

    Process {
        id: evalProc
        property bool wantInstalled: false
        stdout: StdioCollector { id: evalOut }
        onExited: function (code) {
            const failed = code !== 0 || /error|expected/i.test(evalOut.text)
            if (failed) console.warn("KeyLocks: hyprctl eval failed -", evalOut.text.trim())
            root._installed = evalProc.wantInstalled && !failed
            root._sync()            // the wish may have changed meanwhile
        }
    }

    Process {
        id: readProc
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const kbs = JSON.parse(text).keyboards || []
                    const main = kbs.find(k => k.main) || kbs[0]
                    if (!main) return
                    root.caps = !!main.capsLock
                    root.num  = !!main.numLock
                } catch (e) {}
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap") root.submap = String(event.data || "").trim()
            else if (event.name === "custom" && event.data === "qs-locks") readProc.running = true
            else if (event.name === "configreloaded" && root._installed) {
                root._installed = false
                root._sync()
            }
        }
    }
}
