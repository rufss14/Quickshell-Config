import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── OverviewFilters ───────────────────────────────────────────────────────────
// The search's flag operators as chips under the field: Floating, Pinned, Fullscreen, Audio.
// A chip is just `is:floating` typed for you — it writes the word into the field (and takes it
// out again), so the field stays the one source of truth and typing the operator by hand lights
// the chip. The parsing is services/switcher.js (`parseQuery`); nothing here decides what matches.
// ─────────────────────────────────────────────────────────────────────────────
ChipTray {
    id: root

    // A chip asks the overview to switch its operator (a chip inside the search field, or the word typed by hand).
    signal toggled(string flag)

    readonly property var flags: [
        { flag: "floating",   symbol: "open_with",  label: "Floating" },
        { flag: "pinned",     symbol: "keep",       label: "Pinned" },
        { flag: "fullscreen", symbol: "fullscreen", label: "Fullscreen" },
        { flag: "audio",      symbol: "volume_up",  label: "Audio" }
    ]

    Repeater {
        model: root.flags

        ChipButton {
            required property var modelData
            symbol: modelData.symbol
            label:  modelData.label
            on:     Switcher.flagOn(modelData.flag)
            onActivated: root.toggled(modelData.flag)
        }
    }
}
