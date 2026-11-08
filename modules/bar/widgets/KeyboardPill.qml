import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── KeyboardPill ──────────────────────────────────────────────────────────────
// Active XKB layout, e.g. "US". Click to cycle.
//
// All the state lives in the Keyboard service now — this file used to spawn
// `hyprctl devices -j | python3 -c '...'` on startup just to read the initial
// layout, and did it once per instance (so twice, since the bar built both
// layouts). The service reads it once, over Hyprland's socket, with no
// interpreter.
// ─────────────────────────────────────────────────────────────────────────────
BarIconPill {
    id: root

    // container / squareMode / spacing / accent all come from BarIconPill, keyed on
    // this one id — see BarIconPill.qml.
    moduleId: "keyboard"
    label:    Keyboard.layout

    // The service announces the new layout once Hyprland reports it.
    onClicked: Keyboard.next(true)
}
