import QtQuick
import Quickshell
import Quickshell.Io
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── ReloadPill ────────────────────────────────────────────────────────────────
// Reloads the shell in-process, with a watchdog that force-kills it if the
// in-process reload wedges (which it can, if a QML error leaves the engine in a
// bad state — hence the escalation from SIGTERM to SIGKILL).
// ─────────────────────────────────────────────────────────────────────────────
IconButton {
    id: root

    property bool reloading: false

    squareMode:  Config.barShape
    interactive: !root.reloading
    active:      root.reloading

    // The icon lives here rather than in IconButton's `icon` slot so it can be
    // spun and dimmed while the reload is in flight.
    Image {
        anchors.centerIn: parent
        source: Icons.asset("refresh")
        sourceSize: Qt.size(Tokens.iconMd, Tokens.iconMd)
        width:  Tokens.iconMd
        height: Tokens.iconMd
        fillMode: Image.PreserveAspectFit

        opacity: root.reloading ? 0.5 : 1.0
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }

        RotationAnimation on rotation {
            running: root.reloading
            loops: Animation.Infinite
            from: 0; to: 360
            duration: 700
            easing.type: Easing.Linear
        }
    }

    onClicked: {
        root.reloading = true
        notify("--urgency=low", "Shell reloaded!", "Quickshell restarted successfully.")
        Quickshell.reload(false)
        watchdog.restart()
    }

    function notify(urgency, title, body) {
        notifyProc.command = [
            "notify-send",
            "--app-name=Quickshell",
            urgency,
            "--icon=" + Icons.assetPath("refresh"),
            title, body
        ]
        notifyProc.running = true
    }

    Process { id: notifyProc; running: false }

    // If the shell is still alive 3s after an in-process reload was asked for,
    // the reload didn't take. Escalate.
    Timer {
        id: watchdog
        interval: 3000
        onTriggered: {
            root.notify("--urgency=critical", "Shell reload failed!",
                        "Quickshell had to be force-killed.")
            termProc.running = true
            killDelay.restart()
        }
    }

    Process { id: termProc; command: ["pkill", "-TERM", "-x", "qs"] }

    Timer {
        id: killDelay
        interval: 1000
        onTriggered: killProc.running = true
    }

    Process { id: killProc; command: ["pkill", "-KILL", "-x", "qs"] }
}
