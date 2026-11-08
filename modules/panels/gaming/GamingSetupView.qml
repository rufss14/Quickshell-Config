pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/gamemodewatch.js" as Watch

// ── GamingSetupView ── part of GamingPanel.qml; `panel` is the GamingPanel it belongs to. ──
ColumnLayout {
    id: setupPage
    required property var panel
    readonly property int idx: 4
    width: panel.pagesBox.width
    x: (setupPage.idx - panel.pg.value) * panel.pagesBox.width
    opacity: Math.max(0, 1 - Math.abs(setupPage.idx - panel.pg.value) * 1.4)
    visible: setupPage.opacity > 0.01
    spacing: Tokens.spacingSm

    // ── The session couldn't set the governor ─────────────────────
    // gamemoded's governor helper is polkit-gated to the `gamemode` group. Not in it → `gamemode is
    // active` but the CPU never leaves powersave. Say so, with the one-time fix. (The GPU twin: the
    // profile asked for `high` and the card is still elsewhere — same polkit gate, or a gpu_device
    // that no longer names this card; Set up again rewrites it from sysfs.)
    Rectangle {
        Layout.fillWidth: true
        visible: panel._stalled
        implicitHeight: warnRow.implicitHeight + panel.cardPad * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceContainer,
                                               Colors.of(QsWindow.window).warning, 0.22)
        RowLayout {
            id: warnRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: panel.cardPad
            spacing: Tokens.spacingMd
            MaterialIcon { name: "warning"; fill: 1; color: Colors.of(QsWindow.window).warning; variant: "body" }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXs
                StyledText {
                    Layout.fillWidth: true
                    text: Gamemode.sessionStalled
                          ? "The CPU governor is still <b>" + Gamemode.cpuGovernor + "</b>. Add yourself to the gamemode group, then log out and back in:"
                          : "The GPU is still at <b>" + Gamemode.gpuPowerLevel + "</b>, not " + Gamemode.systemProfile.gpuLevel
                            + ". Remove and set up the profile again to re-detect the card."
                    rich: true
                    variant: "caption"
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    visible: Gamemode.sessionStalled
                    text: "sudo usermod -aG gamemode $USER"
                    variant: "caption"
                    font.family: Tokens.fontMono
                    emphasis: "dim"
                }
            }
            ChipButton {
                visible: Gamemode.sessionStalled
                Layout.alignment: Qt.AlignTop
                symbol: "content_copy"
                onActivated: Clipboard.copyText("sudo usermod -aG gamemode $USER")
            }
        }
    }

    // ── What is installed and ready ───────────────────────────────
    // One row per fact: a tonal shape (green when fine, warning when not, the accent when it is
    // only information), what it is, what it means here, and an action where there is one.
    // The old panel spread this over a warning band, a profile row, two captions and an
    // install hint.
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: readyCol.implicitHeight + panel.cardPad * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section

        ColumnLayout {
            id: readyCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: panel.cardPad
            spacing: Tokens.spacingSm

            Repeater {
                model: [
                    { title: "gamemode", icon: "check_circle",
                      tone: Gamemode.toolsAvailable ? "ok" : "warn",
                      detail: Gamemode.toolsAvailable ? "Installed — games can ask for a performance session"
                                                      : "Not installed — pacman -S gamemode" },
                    { title: "Game profile", icon: "tune",
                      tone: !Gamemode.toolsAvailable ? "none" : panel._profileComplete ? "ok" : "warn",
                      detail: panel._profileComplete ? panel._profileSummary
                            : Gamemode.profileGpuAvailable
                              ? "CPU and I/O priority and full GPU clocks while a game runs"
                              : "CPU and I/O priority while a game runs",
                      action: "profile" },
                    { title: "MangoHud", icon: "equalizer",
                      tone: Gamemode.mangohudAvailable ? "ok" : "warn",
                      detail: Gamemode.mangohudAvailable ? "Installed — overlay and frame cap work" : "Not installed — pacman -S mangohud" },
                    { title: "Follow games", icon: "terminal",
                      tone: !Gamemode.toolsAvailable ? "none" : Gamemode.followAvailable ? "ok" : "warn",
                      detail: Gamemode.followAvailable ? "gdbus found — the mode can follow gamemoderun games"
                                                       : "gdbus (glib2) is missing — can't follow games" },
                    { title: "GPU clocks", icon: "bolt",
                      tone: Gamemode.gpuPowerLevel === "" ? "none" : Gamemode.gpuPowerLevel === "high" ? "ok" : "info",
                      detail: "Now " + Gamemode.gpuPowerLevel + (Gamemode.gpuPowerLevel === "high" ? "" : " — the profile raises it to high while a game runs") },
                    { title: "Scheduler", icon: "developer_board",
                      tone: !Gamemode.schedulerKnown ? "none" : Gamemode.scheduler !== "" ? "ok" : "info",
                      detail: Gamemode.scheduler !== "" ? "sched_ext · scx_" + panel._schedName : "The kernel's own — no sched_ext scheduler loaded" },
                    { title: "Steam launch options", icon: "content_copy",
                      tone: Gamemode.toolsAvailable || Gamemode.mangohudAvailable ? "info" : "none",
                      detail: panel._launchOpts, action: "copy" },
                ].filter(r => r.tone !== "none")

                delegate: RowLayout {
                    id: row
                    required property var modelData
                    readonly property color tone: modelData.tone === "ok"   ? Colors.of(QsWindow.window).success
                                                : modelData.tone === "warn" ? Colors.of(QsWindow.window).warning
                                                :                             panel.accent
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd

                    ShapeBox {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: Tokens.iconXl + Tokens.spacingSm
                        implicitHeight: implicitWidth
                        fallback: "rounded"
                        fillColor: Colors.of(QsWindow.window).alpha(row.tone, 0.20)
                        strokeColor: "transparent"
                        MaterialIcon {
                            anchors.centerIn: parent
                            name: row.modelData.tone === "warn" ? "warning" : row.modelData.icon
                            fill: 1
                            color: row.tone
                            font.pixelSize: Tokens.iconMd
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0
                        StyledText { text: row.modelData.title; variant: "body"; font.weight: Font.Medium }
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.detail
                            variant: "caption"; emphasis: "dim"
                            elide: Text.ElideRight
                            font.family: row.modelData.action === "copy" ? Tokens.fontMono : Tokens.fontFamily
                        }
                    }

                    // The profile — what a session asks gamemoded for. Without it gamemoded only moves
                    // the governor. scripts/gamemode-profile.py writes the two halves (priority in
                    // ~/.config, GPU clocks in /etc — gamemoded refuses [gpu] from a user file); the
                    // button runs whichever step is missing, and asks for a password only for /etc.
                    PanelButton {
                        visible: row.modelData.action === "profile"
                        Layout.alignment: Qt.AlignVCenter
                        variant: panel._profileComplete ? "ghost" : "primary"
                        accent: panel.accent
                        label: Gamemode.profileBusy ? "…" : panel._profileComplete ? "Remove" : "Set up"
                        enabled: !Gamemode.profileBusy
                        onActivated: panel._profileComplete ? Gamemode.removeProfile() : Gamemode.installProfile()
                    }
                    ChipButton {
                        id: copyChip
                        visible: row.modelData.action === "copy"
                        Layout.alignment: Qt.AlignVCenter
                        symbol: copyChip._copied ? "check" : "content_copy"
                        on: copyChip._copied
                        tint: panel.accent
                        property bool _copied: false
                        onActivated: {
                            Clipboard.copyText(panel._launchOpts)
                            copyChip._copied = true
                            copiedReset.restart()
                        }
                        Timer { id: copiedReset; interval: 1800; onTriggered: copyChip._copied = false }
                    }
                }
            }
        }
    }
}
