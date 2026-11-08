import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── ReloadPill ────────────────────────────────────────────────────────────────
// Reloads the shell in-process. A watchdog falls back to a full restart
// (ShellActions "reload" → scripts/reload-quickshell.sh) if the in-process reload
// wedges, which it can when a QML error leaves the engine in a bad state.
//
// The watchdog lives in THIS component, which a successful reload destroys — so it
// only ever fires when the reload didn't happen, which is exactly when it should.
// It used to `pkill -x qs` itself: that missed a shell started as `quickshell` (the
// reload script's name for it) and, when it did hit, killed the shell without
// starting another. The script kills both names and relaunches.
// ─────────────────────────────────────────────────────────────────────────────
IconButton {
    id: root

    property bool reloading: false

    container:   false
    squareMode:  Config.barShape
    interactive: !root.reloading
    active:      root.reloading

    // The icon lives here rather than in IconButton's `symbol` slot so it can be
    // spun and dimmed while the reload is in flight. The font's, at the bar's icon size and
    // in the ladder's colour like every other pill (it was the raw SVG, untinted, so it
    // stayed light grey on a light palette); it rises with the hover as theirs do.
    MaterialIcon {
        anchors.centerIn: parent
        name: "refresh"
        font.pixelSize: root.glyphSize
        color: root.iconColor
        scale: root._lift
        Behavior on color { ColorAnimation { duration: Motion.respond } }

        opacity: root.reloading ? 0.5 : 1.0
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }

        // ── Category 3: busy indicator (see Motion.qml) ───────────────────
        // Deliberately NOT gated on Config.motionEnabled, and deliberately a
        // literal duration. A spinner frozen mid-turn does not read as "animations
        // are off", it reads as "the reload has hung" — which is the one thing this
        // control must never say by accident. The rotation IS the information.
        RotationAnimation on rotation {
            running: root.reloading
            loops: Animation.Infinite
            from: 0; to: 360
            duration: Motion.glide
            easing.type: Easing.Linear
        }
    }

    // ── Refuse while an update is installing ──────────────────────────────────
    // Quickshell.reload() tears down and rebuilds the QML engine in-process, which
    // destroys every live Process object — including the one running pacman/yay for
    // Updates.installAll()/installSelected()/installVencord(). Qt kills a running
    // child when its Process wrapper is destroyed, so this has corrupted files
    // before (mid-kernel-upgrade, once). See the matching guard in
    // scripts/reload-quickshell.sh for the other reload path (the Hyprland keybind),
    // which runs outside this process and can't see this property at all.
    onClicked: {
        if (Updates.runBusy) {
            notify("--urgency=critical", "Reload blocked",
                   "An update is installing — wait for it to finish (or cancel it) before reloading.")
            return
        }
        root.reloading = true
        notify("--urgency=low", "Reloading the shell", "Quickshell is reloading its configuration.")
        Quickshell.reload(false)
        watchdog.restart()
    }

    // Detached: the in-process reload destroys this component, and a Process child
    // would be killed with it before notify-send had delivered anything.
    function notify(urgency, title, body) {
        Quickshell.execDetached(["notify-send", "--app-name=Quickshell", urgency,
                                 "--icon=" + Icons.assetPath("refresh"), title, body])
    }

    // If the shell is still alive 3s after an in-process reload was asked for,
    // the reload didn't take. Escalate.
    Timer {
        id: watchdog
        interval: 3000
        onTriggered: {
            root.notify("--urgency=critical", "Shell reload failed",
                        "Restarting Quickshell instead.")
            ShellActions.run("reload")
        }
    }
}
