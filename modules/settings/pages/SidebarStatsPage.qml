pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── SidebarStatsPage — Sidebar & dock › Stats ─────────────────────────────────
// The system stats' settings: a sidebar button (modules/bar/SideStats) glancing at the
// first three readings, and its panel beside it (modules/panels/StatsPanel) with all of
// them. Where the button stands is the sidebar's layout (the Sidebar tab).
// Readouts, alerts and the system monitor are services/SysStats.
//
// ── Readings are a set, so they are chips ─────────────────────────────────────
// Nine of them were nine tiles, each a card with a sentence under it. Which readings
// the ring shows is membership of a set, the same shape as which modules are on the
// sidebar. A reading that can't exist here (no GPU utilisation, no swap, no battery)
// is a dimmed chip whose tip says why.
//
// ── One screen ────────────────────────────────────────────────────────────────
// The readings across the top, then how the rings are drawn beside the alerts, then
// the system monitor command. The sentences that were under each control are tips.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Every metric, in the order they're offered here. Turning one on appends it,
    // off removes it — the order you already have is left alone either way.
    readonly property var rings: [
        { key: "cpu",     symbol: "memory",          label: "CPU" },
        { key: "gpu",     symbol: "developer_board", label: "GPU",
          na: !SysInfo.hasGpu, why: "No utilisation to read — the kernel publishes it for AMD and Intel, not NVIDIA" },
        { key: "ram",     symbol: "memory_alt",      label: "Memory" },
        { key: "net",     symbol: "swap_vert",       label: "Network" },
        { key: "swap",    symbol: "swap_horiz",      label: "Swap",
          na: !(SysInfo.swapTotal > 0), why: "No swap configured" },
        { key: "disk",    symbol: "hard_drive",      label: "Disk" },
        { key: "diskio",  symbol: "sync_alt",        label: "Disk activity" },
        { key: "battery", symbol: "battery_full",    label: "Battery",
          na: !(UPower.displayDevice?.isLaptopBattery ?? false), why: "No laptop battery" },
        // Never `na`: turning it on is what starts looking, and a device can connect later.
        { key: "devices", symbol: "bluetooth",       label: "Device batteries" }
    ]

    readonly property var shown: Config.sidebarStatsMetrics ?? []
    function has(key) { return root.shown.indexOf(key) >= 0 }
    function toggle(key) {
        Config.sidebarStatsMetrics = root.has(key) ? root.shown.filter(k => k !== key)
                                                   : root.shown.concat([key])
    }

    // The network ring's full scale, as steps rather than a 1..10000 slider.
    readonly property var netSteps: [10, 50, 100, 300, 500, 1000, 2500, 10000]
    readonly property int netIndex: {
        let best = 0
        for (let i = 0; i < root.netSteps.length; i++)
            if (Math.abs(root.netSteps[i] - Config.sidebarStatsNetCeiling)
                < Math.abs(root.netSteps[best] - Config.sidebarStatsNetCeiling)) best = i
        return best
    }
    function mbpsText(v) { return v >= 1000 ? (v / 1000) + " Gbit/s" : v + " Mbit/s" }

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "\u{F029A}"
        title:     Translation.tr("System")
        titleTail: "stats"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  !Config.sidebarStats ? "Off"
                 : root.shown.length + (root.shown.length === 1 ? " reading" : " readings")

        actions: Toggle {
            accent:  Colors.of(QsWindow.window).primary
            checked: Config.sidebarStats
            onToggled: Config.sidebarToggle("stats")
        }

        // ══ The readings ══════════════════════════════════════════════════════
        // A set, so chips. A reading that can't exist here (no GPU utilisation, no
        // swap, no battery) is a dimmed chip whose tip says why.
        Section {
            span:    3
            enabled: Config.sidebarStats
            opacity: Config.sidebarStats ? 1 : 0.5
            glyph:   "\u{F029A}"                                   // gauge
            title:   Translation.tr("Readings")
            subtitle: Translation.tr("The button shows the first three")
            help:    Translation.tr("The stats button on the sidebar shows the first three you turn on; its panel shows every one. Clicking a reading in the panel opens its settings.")
            accent:  Colors.of(QsWindow.window).primary

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                Repeater {
                    model: root.rings

                    delegate: ToggleChip {
                        required property var modelData
                        symbol: modelData.symbol
                        label:  modelData.label
                        hint:   modelData.na ? modelData.why : ""
                        active: root.has(modelData.key) && !modelData.na
                        available: Config.sidebarStats && !modelData.na
                        onToggled: root.toggle(modelData.key)
                    }
                }
            }

            // The one reading whose detail is live: what is connected right now.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: root.has("devices") && DeviceBatteries.devices.length > 0
                wrapMode: Text.WordWrap
                variant: "caption"
                emphasis: "dim"
                text: DeviceBatteries.devices
                    .map(d => d.name + " " + Math.round(d.level * 100) + "%").join("  ·  ")
            }
        }

        // ══ How the rings are drawn ═══════════════════════════════════════════
        Section {
            span:    1
            enabled: Config.sidebarStats
            opacity: enabled ? 1 : 0.5
            glyph:   "󰐷"
            title:   Translation.tr("Rings")
            accent:  Colors.of(QsWindow.window).primary

            SettingRow {
                label:  Translation.tr("Temperatures")
                enabled: SysInfo.hasCpuTemp || SysInfo.hasGpuTemp
                detail: SysInfo.hasCpuTemp || SysInfo.hasGpuTemp
                    ? (Config.sidebarStatsTempArcs ? "Inner arc, 0–100°C" : "Off")
                    : "No CPU or GPU sensor found"
                help:   Translation.tr("An inner arc on the CPU and GPU rings showing the temperature, 0–100°C.")
                Toggle {
                    checked: Config.sidebarStatsTempArcs
                    onToggled: Config.sidebarStatsTempArcs = !Config.sidebarStatsTempArcs
                }
            }
            SettingRow {
                label:  Translation.tr("Split network")
                enabled: root.has("net")
                detail: Config.sidebarStatsNetSplit ? "Down outside, up inside" : "One combined arc"
                help:   Translation.tr("Download on the network ring's outer arc, upload on the inner one.")
                Toggle {
                    checked: Config.sidebarStatsNetSplit
                    onToggled: Config.sidebarStatsNetSplit = !Config.sidebarStatsNetSplit
                }
            }
            SliderRow {
                enabled: root.has("net")
                label: Translation.tr("Line speed")
                help:  Translation.tr("What a full network ring means. Fixed, so an idle link never looks busy.")
                stepper: false
                from:  0
                to:    root.netSteps.length - 1
                step:  1
                value: root.netIndex
                readout: root.mbpsText(root.netSteps[root.netIndex])
                onCommit: function (v) { Config.sidebarStatsNetMbps = root.netSteps[Math.round(v)] }
            }
        }

        // ══ Alerts ════════════════════════════════════════════════════════════
        Section {
            span:     1
            enabled:  Config.sidebarStats
            opacity:  enabled ? 1 : 0.5
            glyph:    "\u{F0026}"                                  // alert
            title:    Translation.tr("Alerts")
            subtitle: Config.sidebarStatsAlerts ? "After " + Math.round(SysStats.alertSustain / 1000) + "s over" : "Off"
            help:     Translation.tr("A ring held over its threshold says so in its card. CPU and memory alert on load, the temperatures on degrees.")
            accent:   Colors.of(QsWindow.window).primary

            actions: Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.sidebarStatsAlerts
                onToggled: Config.sidebarStatsAlerts = !Config.sidebarStatsAlerts
            }

            SliderRow {
                enabled: Config.sidebarStatsAlerts
                label: Translation.tr("Load")
                from:  50
                to:    100
                step:  5
                value: Config.sidebarStatsAlertLoad
                readout: Config.sidebarStatsAlertLoad + "%"
                onCommit: function (v) { Config.sidebarStatsAlertLoad = Math.round(v) }
            }
            SliderRow {
                enabled: Config.sidebarStatsAlerts
                label: Translation.tr("Heat")
                from:  60
                to:    105
                step:  5
                value: Config.sidebarStatsAlertTemp
                readout: Config.sidebarStatsAlertTemp + "°C"
                onCommit: function (v) { Config.sidebarStatsAlertTemp = Math.round(v) }
            }
            SettingRow {
                enabled: Config.sidebarStatsAlerts
                label:  Translation.tr("Notify")
                detail: Config.sidebarStatsAlertNotify ? "One notification as it starts" : "Only in the card"
                Toggle {
                    checked: Config.sidebarStatsAlertNotify
                    onToggled: Config.sidebarStatsAlertNotify = !Config.sidebarStatsAlertNotify
                }
            }
        }

        // ══ The system monitor ════════════════════════════════════════════════
        Section {
            span:    3
            enabled: Config.sidebarStats
            opacity: enabled ? 1 : 0.5
            glyph:   "\u{F0379}"                                  // monitor
            title:   Translation.tr("System monitor")
            subtitle: "Runs in " + Terminal.resolved
            help:    Translation.tr("What a middle-click on the stats button, or on a reading in its panel, opens. Right-clicking the button opens this page.")
            accent:  Colors.of(QsWindow.window).primary

            InputField {
                cornerRadius: implicitHeight / 2
                Layout.fillWidth: true
                mono: true
                seed: Config.sidebarStatsMonitor
                placeholder: "Automatic — " + SysStats.monitorCommand
                onCommitted: function (v) { Config.sidebarStatsMonitor = v.trim() }
            }
        }
    }
}
