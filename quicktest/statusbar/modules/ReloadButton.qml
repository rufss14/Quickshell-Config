import QtQuick
import Quickshell
import Quickshell.Io
import "../../theming" as T

// ── ReloadButton ──────────────────────────────────────────────────────────────
// Clean reload button with in-process restart + fallback kill
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool reloading: false
    property bool barShape:  false

    Process { id: notifyProcess; running: false }

    function doReload() {
        root.reloading = true
        notifyProcess.command = [
            "notify-send",
            "--app-name=Quickshell",
            "--urgency=low",
            "--icon=" + Quickshell.env("HOME") + "/.config/quicktest/theming/icons/refresh.svg",
            "Shell reloaded!",
            "Quickshell restarted successfully."
        ]
        notifyProcess.running = true
        Quickshell.reload(false)
        watchdog.restart()
    }

    Timer {
        id: watchdog
        interval: 3000
        repeat: false
        onTriggered: {
            notifyProcess.command = [
                "notify-send",
                "--app-name=Quickshell",
                "--urgency=critical",
                "--icon=" + Quickshell.env("HOME") + "/.config/quicktest/theming/icons/refresh.svg",
                "Shell reload failed!",
                "Quickshell had to be force-killed."
            ]
            notifyProcess.running = true
            termProcess.running = true
            killDelay.restart()
        }
    }

    Process { id: termProcess; command: ["pkill", "-TERM", "-x", "qs"] }

    Timer {
        id: killDelay
        interval: 1000
        repeat: false
        onTriggered: killProcess.running = true
    }

    Process { id: killProcess; command: ["pkill", "-KILL", "-x", "qs"] }

    implicitWidth:  40
    implicitHeight: T.Theme.pillHeight
    radius: T.Theme.radius(barShape)
    color: root.reloading
        ? T.Theme.pw(T.Theme.pal?.colors?.color3, 0.20)
        : (btn.pressed ? T.Theme.btnPressBg : (btn.containsMouse ? T.Theme.btnHoverBg : T.Theme.pillBg))

    Behavior on color  { ColorAnimation  { duration: T.Theme.animFast } }
    Behavior on radius { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }

    Image {
        anchors.centerIn: parent
        source: "../../theming/icons/refresh.svg"
        width: 16; height: 16
        fillMode: Image.PreserveAspectFit
        opacity: root.reloading ? 0.5 : 1.0
        Behavior on opacity { NumberAnimation { duration: T.Theme.animFast } }

        RotationAnimation on rotation {
            running: root.reloading
            loops: Animation.Infinite
            from: 0; to: 360
            duration: 700
            easing.type: Easing.Linear
        }
    }

    MouseArea {
        id: btn
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: !root.reloading
        onClicked: root.doReload()
    }
}
