pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../config"
import "cursoreffects.js" as Fx

// ── CursorEffects ─────────────────────────────────────────────────────────────
// The tilt / rotate / stretch / shake-to-find motion effects of the
// hypr-dynamic-cursors plugin, switched and tuned from Settings › Cursor.
//
// ── The compositor draws the cursor, so this is a client of a plugin ────────────
// Nothing here draws anything. The plugin is optional third-party C++ that hyprpm
// builds against the installed Hyprland, so this service does three things and no
// more: find out whether it's loaded, load it if it's installed but not running, and
// hand it configuration. `blocker()` says which of those is missing, in the same
// shape as NightLight.blocker() and WallpaperEngine.blocker().
//
// ── Configuration goes in at RUNTIME, and has to go in again ─────────────────────
// `hyprctl eval` runs Lua in the live compositor, so the shell owns these settings
// and no Hyprland config file is edited (the live ~/.config/hypr is an installed copy
// that has already drifted from the repo's). The catch: a config reload resets a
// plugin's values, and this shell triggers one on every palette change
// (scripts/reload-theme.sh → wal-reload.sh → `hyprctl reload`). So it re-applies on
// Hyprland's own `configreloaded` event — pushed over the socket, no polling.
//
// The Lua itself comes from cursoreffects.js, which whitelists everything that reaches
// it (tested: `bun scripts/test-cursoreffects.js`).
//
// ── Inert while it's off ──────────────────────────────────────────────────────────
// Off (the default) runs nothing at startup and never loads a plugin. Turning it off
// AFTER it was applied sends one `enabled = false`; it does not on a fresh start.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property bool enabled: Config.cursorEffects

    // ── Is the plugin there ───────────────────────────────────────────────────
    // "unknown" until the first probe answers; then "loaded", "missing" (hyprpm is
    // here but the plugin isn't running) or "nohyprpm".
    property string state: "unknown"
    readonly property bool loaded: root.state === "loaded"

    // "" when usable, otherwise the reason — the page shows it instead of a switch that
    // silently does nothing. Reads a plain property, not a walk over a lazy model.
    function blocker() {
        if (root.state === "nohyprpm")
            return "Needs hyprpm, the Hyprland plugin manager"
        if (root.state === "missing")
            return "Needs the dynamic-cursors plugin"
        return ""
    }

    property string lastError: ""
    readonly property string statusText:
        root.lastError !== ""      ? root.lastError
        : root.blocker() !== ""    ? root.blocker()
        : !root.enabled            ? "Off"
        : root.loaded              ? "Active"
        :                            "Checking for the plugin…"

    // ── What to send ──────────────────────────────────────────────────────────
    readonly property string lua: Fx.lua({
        enabled:     Config.cursorEffects,
        mode:        Config.cursorEffectMode,
        sensitivity: Config.cursorEffectSensitivity,
        shake:       Config.cursorShake
    })

    property bool _applied: false      // did THIS session ever configure the plugin
    property bool _triedLoad: false    // one `hyprpm reload` per enable, not a loop
    property bool _again: false

    function probe() { if (!probeProc.running) probeProc.running = true }

    function queue() { debounce.restart() }

    onLuaChanged:     queue()
    onLoadedChanged:  queue()
    onEnabledChanged: {
        if (root.enabled) { root._triedLoad = false; root.probe() }
        root.queue()
    }
    Component.onCompleted: { if (root.enabled) root.probe() }

    Timer {
        id: debounce
        interval: 400
        onTriggered: root._apply()
    }

    // A reload resets the plugin's values to its defaults. Bursts are normal (a palette
    // change can reload twice), so this shares the debounce above.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" && root._applied) root.queue()
        }
    }

    function _apply() {
        if (!root.loaded) return
        if (!root.enabled && !root._applied) return
        if (evalProc.running) { root._again = true; return }
        root._applied = root.enabled          // an "off" push is the last one
        evalProc.command = ["hyprctl", "eval", root.lua]
        evalProc.running = true
    }

    // ── Probe, then load once if it's installed but not running ───────────────
    // `qs ipc -c ~/.config/quicktest call cursoreffects status` — read-only.
    IpcHandler {
        target: "cursoreffects"
        function status(): string {
            return "state=" + root.state + " enabled=" + root.enabled + " applied=" + root._applied
                 + " triedLoad=" + root._triedLoad + " busy=" + evalProc.running
                 + " lastError=" + (root.lastError || "none")
        }
    }

    Process {
        id: probeProc
        command: ["bash", "-c",
            "hyprctl plugin list 2>/dev/null | grep -qiE 'dynamic.?cursors' && { echo loaded; exit 0; }; "
          + "command -v hyprpm >/dev/null 2>&1 || { echo nohyprpm; exit 0; }; "
          + "echo missing"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.state = text.trim() || "unknown"
                // Installed and enabled in hyprpm but not running is the normal state
                // after a Hyprland start. `hyprpm reload` is the tool's own answer to it.
                if (root.state === "missing" && root.enabled && !root._triedLoad) {
                    root._triedLoad = true
                    loadProc.running = true
                }
            }
        }
    }

    Process {
        id: loadProc
        command: ["hyprpm", "reload"]
        onExited: root.probe()
    }

    Process {
        id: evalProc
        stdout: StdioCollector { id: out }
        stderr: StdioCollector { id: err }
        onExited: function (code) {
            const msg = (out.text + err.text).trim()
            // hyprctl answers "ok" on success and prints the Lua error otherwise; the
            // exit code alone isn't trustworthy for either.
            root.lastError = (code !== 0 || /error|fail/i.test(msg))
                ? (msg.split("\n").pop() || ("failed (" + code + ")")) : ""
            if (root.lastError !== "") console.warn("CursorEffects: hyprctl eval failed -", root.lastError)
            if (root._again) { root._again = false; root._apply() }
        }
    }
}
