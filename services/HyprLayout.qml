pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// ── HyprLayout ────────────────────────────────────────────────────────────────
// Hyprland's tiling layout (general.layout): which one is live, and switching it — for
// the layout module on the bar and the sidebar.
//
// ── Live, and remembered ──────────────────────────────────────────────────────
// A switch is applied at once with `hyprctl eval 'hl.config({ general = { layout = … }})'`
// (measured on 0.56.2: dwindle, master, scrolling and monocle all take), AND written to
// the config's own `layout = "…"` line through HyprConfig (scripts/hypr-config.py, with
// its backup and syntax check), so the next Hyprland start keeps it. The name is only
// ever one of `layouts` — it is spliced into Lua, so nothing else may reach it.
//
// What is live is asked of Hyprland (`hyprctl getoption general:layout -j`) on start, on
// a config reload, and after a switch: event-driven, no polling.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // `symbol` for the bar (Material name), `glyph` for a sidebar cell (SideCell draws a
    // codepoint) — the same icon either way.
    readonly property var layouts: [
        { id: "dwindle",   label: "Dwindle",   symbol: "vertical_split", glyph: "\u{F093C}",
          about: "Each new window splits the space of the one beside it" },
        { id: "master",    label: "Master",    symbol: "dashboard",      glyph: "\u{F056E}",
          about: "One big window, the rest stacked beside it" },
        { id: "scrolling", label: "Scrolling", symbol: "swap_horiz",     glyph: "\u{F04E1}",
          about: "Windows in columns on a strip you scroll along" },
        { id: "monocle",   label: "Monocle",   symbol: "fullscreen",     glyph: "\u{F05AF}",
          about: "One window at a time, full size" }
    ]

    property string current: "dwindle"
    readonly property var info: root.layouts.find(l => l.id === root.current) ?? root.layouts[0]
    property string lastError: ""

    function _valid(id) { return root.layouts.some(l => l.id === id) }

    function set(id) {
        if (!root._valid(id) || id === root.current) return
        root.current = id                    // optimistic; the read-back confirms
        setProc.command = ["hyprctl", "eval", `hl.config({ general = { layout = "${id}" } })`]
        setProc.running = true
        root._persist(id)
    }
    // Scroll on the module: the next or previous layout, wrapping.
    function step(d) {
        const i = root.layouts.findIndex(l => l.id === root.current)
        root.set(root.layouts[(i + d + root.layouts.length) % root.layouts.length].id)
    }

    Process {
        id: setProc
        stdout: StdioCollector { id: setOut }
        onExited: function (code) {
            const msg = setOut.text.trim()
            root.lastError = code !== 0 || /error|expected/i.test(msg) ? (msg || "failed") : ""
            readProc.running = true
        }
    }

    Process {
        id: readProc
        running: true
        command: ["hyprctl", "getoption", "general:layout", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const v = JSON.parse(text).str
                    if (root._valid(v)) root.current = v
                } catch (e) {}
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "configreloaded") readProc.running = true }
    }

    // ── Remembering it ────────────────────────────────────────────────────────
    // HyprConfig parses the config only while someone holds it; held just for the
    // write, then let go.
    property string _pendingWrite: ""
    function _persist(id) {
        root._pendingWrite = id
        HyprConfig.acquire()
        root._tryWrite()
    }
    function _tryWrite() {
        if (root._pendingWrite === "") return
        const d = HyprConfig.appearance.layout
        if (!d) return                       // not parsed yet — the Connections retries
        if (String(d.value) !== root._pendingWrite)
            HyprConfig.setValue(d.file, d.line, "layout", "str", root._pendingWrite)
        root._pendingWrite = ""
        HyprConfig.release()
    }
    Connections {
        target: HyprConfig
        function onAppearanceChanged() { root._tryWrite() }
    }
}
