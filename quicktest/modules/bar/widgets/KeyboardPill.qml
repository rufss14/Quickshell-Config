import QtQuick
import Quickshell.Io
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
IconButton {
    id: root

    label:      Keyboard.layout
    squareMode: Config.barShape

    onClicked: {
        Keyboard.next()
        // The Hyprland event that updates the label lands a moment after the
        // dispatch, so the notification waits for it — otherwise it announces
        // the layout we just left.
        notifyDelay.restart()
    }

    Timer {
        id: notifyDelay
        interval: 150
        onTriggered: notifyProc.running = true
    }

    Process {
        id: notifyProc
        command: [
            "notify-send",
            "--app-name=Keyboard",
            // An absolute asset SVG, not a theme name: "input-keyboard" isn't in the icon
            // theme here, so the notification server logged "could not load icon
            // input-keyboard" on every layout switch. An SVG on disk always resolves and
            // scales to any size the toast asks for — same approach as the Updates icons.
            "--icon=" + Icons.assetPath("keyboard"),
            "--urgency=low",
            "--expire-time=2000",
            "Keyboard Layout",
            "Switched to " + Keyboard.layout
        ]
    }
}
