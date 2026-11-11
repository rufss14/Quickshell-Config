pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../config"
import "../../components"
import "../../services"

// ── StatsOptions ──────────────────────────────────────────────────────────────
// System stats' own settings, in the module inspector when Stats is the module picked.
// They were Sidebar & dock › Stats, a tab with its own on/off switch; the user's call
// (2026-11-08): Stats is a module like the rest, its settings where every module's are.
// Moved, not redesigned — the same controls and wording.
// ─────────────────────────────────────────────────────────────────────────────
GridLayout {
    id: root

    readonly property bool wide: root.width >= 640
    columns: root.wide ? 2 : 1
    columnSpacing: Tokens.spacingXxl
    rowSpacing: Tokens.spacingMd
    Layout.fillWidth: true
    Layout.fillHeight: false

    readonly property var readings: [
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
        { key: "devices", symbol: "bluetooth",       label: "Device batteries" }
    ]

    readonly property var shown: Config.sidebarStatsMetrics ?? []
    function has(key) { return root.shown.indexOf(key) >= 0 }
    function toggle(key) {
        Config.sidebarStatsMetrics = root.has(key) ? root.shown.filter(k => k !== key)
                                                   : root.shown.concat([key])
    }

    readonly property var netSteps: [10, 50, 100, 300, 500, 1000, 2500, 10000]
    readonly property int netIndex: {
        let best = 0
        for (let i = 0; i < root.netSteps.length; i++)
            if (Math.abs(root.netSteps[i] - Config.sidebarStatsNetCeiling)
                < Math.abs(root.netSteps[best] - Config.sidebarStatsNetCeiling)) best = i
        return best
    }
    function mbpsText(v) { return v >= 1000 ? (v / 1000) + " Gbit/s" : v + " Mbit/s" }

    // ── Readings and rings ────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredWidth: 0
        Layout.alignment: Qt.AlignTop
        spacing: Tokens.spacingSm

        StyledText {
            text: Translation.tr("Readings — the button shows the first three, its panel every one")
            variant: "caption"
            emphasis: "dim"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm
            Repeater {
                model: root.readings
                delegate: ToggleChip {
                    required property var modelData
                    symbol: modelData.symbol
                    label:  modelData.label
                    hint:   modelData.na ? modelData.why : ""
                    active: root.has(modelData.key) && !modelData.na
                    available: !modelData.na
                    onToggled: root.toggle(modelData.key)
                }
            }
        }
        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            visible: root.has("devices") && DeviceBatteries.devices.length > 0
            wrapMode: Text.WordWrap
            variant: "caption"
            emphasis: "dim"
            text: DeviceBatteries.devices.map(d => d.name + " " + Math.round(d.level * 100) + "%").join("  ·  ")
        }

        SettingRow {
            label:  Translation.tr("Temperatures")
            enabled: SysInfo.hasCpuTemp || SysInfo.hasGpuTemp
            detail: SysInfo.hasCpuTemp || SysInfo.hasGpuTemp
                ? (Config.sidebarStatsTempArcs ? "Inner arc, 0–100°C" : "Off")
                : "No CPU or GPU sensor found"
            help:   Translation.tr("An inner arc on the CPU and GPU rings showing the temperature, 0–100°C.")
            Toggle { checked: Config.sidebarStatsTempArcs; onToggled: Config.sidebarStatsTempArcs = !Config.sidebarStatsTempArcs }
        }
        SettingRow {
            label:  Translation.tr("Split network")
            enabled: root.has("net")
            detail: Config.sidebarStatsNetSplit ? "Down outside, up inside" : "One combined arc"
            help:   Translation.tr("Download on the network ring's outer arc, upload on the inner one.")
            Toggle { checked: Config.sidebarStatsNetSplit; onToggled: Config.sidebarStatsNetSplit = !Config.sidebarStatsNetSplit }
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

    // ── Alerts and the monitor ────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredWidth: 0
        Layout.alignment: Qt.AlignTop
        spacing: Tokens.spacingSm

        SettingRow {
            label:  Translation.tr("Alerts")
            detail: Config.sidebarStatsAlerts ? "After " + Math.round(SysStats.alertSustain / 1000) + "s over" : "Off"
            help:   Translation.tr("A ring held over its threshold says so in its card. CPU and memory alert on load, the temperatures on degrees.")
            Toggle { checked: Config.sidebarStatsAlerts; onToggled: Config.sidebarStatsAlerts = !Config.sidebarStatsAlerts }
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
            Toggle { checked: Config.sidebarStatsAlertNotify; onToggled: Config.sidebarStatsAlertNotify = !Config.sidebarStatsAlertNotify }
        }
        StyledText {
            Layout.topMargin: Tokens.spacingSm
            text: Translation.tr("System monitor") + "  ·  runs in " + Terminal.resolved
            variant: "caption"
            emphasis: "dim"
        }
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
