pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "sidemodules.js" as Side

// ── ColorPicker ───────────────────────────────────────────────────────────────
// Pick a colour off the screen, keep the last few, copy one back — the sidebar's
// colour picker (SideColour) is this service's face.
//
// ── hyprpicker, probed ────────────────────────────────────────────────────────
// Optional (install-dependencies.sh lists it): without it the picker can't work,
// so `blocker()` says so and the module's pick cell stands down — disabled with a
// reason, never failing on click. `command -v` once, when something first asks.
//
// ── What reaches the clipboard ────────────────────────────────────────────────
// Only what `sidemodules.js parseHex` accepts from hyprpicker's stdout: "#rrggbb".
// Cancelling the pick (Escape) prints nothing and changes nothing. The copy goes
// through Clipboard, the one place that writes it.
//
// ── The history is data, not a preference ─────────────────────────────────────
// Its own document (`statePath("picked-colours.json")`), not config.json: it churns
// with every pick and has no place in a shell preset. Hand-editable, so it's
// cleaned on the way in (`Side.clean`).
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Is it there ───────────────────────────────────────────────────────────
    property bool _probed: false
    property bool installed: false

    function blocker() {
        if (!root._probed) return "Checking for hyprpicker…"
        return root.installed ? "" : "Needs hyprpicker, which isn't installed (pacman -S hyprpicker)."
    }

    property Process _probe: Process {
        running: true
        command: ["bash", "-c", "command -v hyprpicker >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.installed = text.trim() === "yes"
                root._probed = true
            }
        }
    }

    // ── The colours ───────────────────────────────────────────────────────────
    // Newest first, "#rrggbb".
    readonly property var history: Side.clean(store.value.colours)
    // The pick just made, for a module's moment of feedback ("" until one lands).
    property string lastPicked: ""
    readonly property bool picking: root._pick.running

    function pick() {
        if (!root.installed || root._pick.running) return
        root._pick.running = true
    }

    function copy(hex) {
        const c = Side.parseHex(hex)
        if (c !== "") Clipboard.copyText(c)
    }

    function forget(hex) {
        root._save(Side.forget(root.history, hex))
    }

    function clear() { root._save([]) }

    function _save(list) { store.value = { colours: list } }

    property Process _pick: Process {
        command: ["hyprpicker", "-f", "hex"]
        stdout: StdioCollector {
            onStreamFinished: {
                const c = Side.parseHex(text)
                if (c === "") return
                root._save(Side.remember(root.history, c))
                root.lastPicked = c
                Clipboard.copyText(c)
            }
        }
    }

    property JsonStore _store: JsonStore {
        id: store
        path: Quickshell.statePath("picked-colours.json")
        defaults: ({ colours: [] })
    }
}
