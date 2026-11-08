pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../overview"
import "../../discord"

// ── LockStats ── part of LockScreen.qml; `lockSurface` is its lock surface (one per screen). ──
ColumnLayout {
    id: lockStats
    required property var lockSurface
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: Tokens.spacingXxl
    spacing: Tokens.spacingMd

    opacity: lockSurface.revealLast
    transform: Translate { y: (1 - lockSurface.revealLast) * -20 }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Tokens.spacingMd
        visible: Config.lockShowStats

        StatCard {

            // Travels for exactly one sampling period, so the ring tracks the load
            // continuously instead of ticking once a second.
            sampleInterval: SysInfo.interval
            label: "CPU"
            tint:  Colors.of(QsWindow.window).primary
            value: SysInfo.cpu
            // Temperature when the machine reports one — plenty do not, and a
            // card that says "—°C" is worse than a card that says how many
            // threads it has.
            detail: SysInfo.hasCpuTemp
                        ? SysInfo.cpuTemp + "°C  ·  " + SysInfo.cores.length + " threads"
                        : SysInfo.cores.length + " threads"
        }

        StatCard {

            // Travels for exactly one sampling period, so the ring tracks the load
            // continuously instead of ticking once a second.
            sampleInterval: SysInfo.interval
            // Absent, not empty, on a machine with no discrete GPU — the row
            // simply closes up. Same rule as the weather card.
            visible: SysInfo.hasGpu
            label: "GPU"
            tint:  Colors.of(QsWindow.window).info
            value: SysInfo.gpu
            detail: SysInfo.hasGpuTemp
                        ? SysInfo.gpuTemp + "°C  ·  "
                          + SysInfo.vramUsed.toFixed(1) + "/" + SysInfo.vramTotal.toFixed(1) + " GB"
                        : SysInfo.vramUsed.toFixed(1) + " / " + SysInfo.vramTotal.toFixed(1) + " GB"
        }

        StatCard {

            // Travels for exactly one sampling period, so the ring tracks the load
            // continuously instead of ticking once a second.
            sampleInterval: SysInfo.interval
            label: "RAM"
            tint:  Colors.of(QsWindow.window).success
            // memFraction is the RATIO; memUsed is gigabytes. Mixing those up is
            // the one easy mistake in this card.
            value: SysInfo.memFraction
            detail: SysInfo.memUsed.toFixed(1) + " / " + SysInfo.memTotal.toFixed(1) + " GB"
        }
    }

    // ── The call ──────────────────────────────────────────────────────
    // Only while there IS one — an empty call bar on a lockscreen is a widget
    // advertising that you use Discord.
    //
    // `allowInjection: false` is the load-bearing line. Screen share and camera
    // have no RPC command behind them: they work by focusing Discord and typing
    // its keybind. A session lock holds the keyboard, so that keystroke would not
    // reach Discord — it would reach the password surface.centre.field. The card disables both
    // with a reason rather than hiding them, which is its existing contract for
    // a control it cannot honour.
    DiscordCallBar {
        Layout.alignment: Qt.AlignHCenter
        visible: Config.lockShowDiscord && Discord.enabled && Discord.inCall
        allowInjection: false
    }
}
