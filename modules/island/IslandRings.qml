pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../state"
import "../../components"
import "../../services"
import "../../services/island.js" as Rules

// ── IslandRings ───────────────────────────────────────────────────────────────
// The Dashboard's machine at a glance: the processor, the graphics card (when the shell can read one), the memory and
// the home disk as wavy rings (M3E's wavy indicator: the wave is fixed to the ring, nothing redraws at rest) that GLIDE
// between samples (RadialGauge.glide) rather than step. A ring turns to the warning tone when busy and the danger tone when hot (Rules.loadTone). The pointer on
// a ring swells it and the line under the rings says more (temperature, gigabytes, what is free); at rest that line
// says what is busy, or that all is calm. A click goes to the Performance page. SysInfo and Storage are held by the
// page that shows this.
// ─────────────────────────────────────────────────────────────────────────────
IslandPlate {
    id: root

    clickable: true
    Accessible.name: Translation.tr("Performance")
    onClicked: UiState.islandGo("system")

    readonly property var fs: (Storage.filesystems ?? []).find(f => f.mount === "/") ?? (Storage.filesystems ?? [])[0] ?? null
    readonly property real diskUsed: root.fs && root.fs.size > 0 ? root.fs.used / root.fs.size : 0

    // What each ring reads. GPU only where there is one.
    readonly property var rings: [
        { id: "cpu",  label: Translation.tr("Processor"), icon: "memory" },
        { id: "gpu",  label: Translation.tr("Graphics"),  icon: "monitor" },
        { id: "mem",  label: Translation.tr("Memory"),    icon: "memory_alt" },
        { id: "disk", label: Translation.tr("Disk"),      icon: "hard_drive" }
    ].filter(r => r.id !== "gpu" || SysInfo.hasGpu)

    function valueOf(id) {
        return id === "cpu" ? SysInfo.cpu : id === "gpu" ? SysInfo.gpu : id === "mem" ? SysInfo.memFraction : root.diskUsed
    }
    function detailOf(id) {
        if (id === "cpu")  return SysInfo.hasCpuTemp ? SysInfo.cpuTemp + " °C" : Math.round(SysInfo.cpu * 100) + "%"
        if (id === "gpu")  return SysInfo.hasGpuTemp ? SysInfo.gpuTemp + " °C" : Math.round(SysInfo.gpu * 100) + "%"
        if (id === "mem")  return SysInfo.memUsed.toFixed(1) + " / " + SysInfo.memTotal.toFixed(1) + " GB"
        return root.fs ? Translation.tr("%1 free").arg(Storage.bytes(root.fs.size - root.fs.used)) : ""
    }
    function toneOf(id, base) {
        const t = Rules.loadTone(root.valueOf(id))
        return t === "hot" ? root.palette.danger : t === "busy" ? root.palette.warning : base
    }

    // The ring under the pointer, "" for none.
    property string hot: ""
    // At rest: the busiest reading that is past calm, or none.
    readonly property var busiest: {
        let best = null
        for (const r of root.rings) {
            const v = root.valueOf(r.id)
            if (Rules.loadTone(v) !== "calm" && (!best || v > best.v)) best = { id: r.id, label: r.label, v: v }
        }
        return best
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingXs

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingSm

            Repeater {
                model: root.rings
                delegate: ColumnLayout {
                    id: slot
                    required property var modelData
                    required property int index
                    readonly property real value: root.valueOf(slot.modelData.id)
                    readonly property color tone: root.toneOf(slot.modelData.id,
                        slot.index === 0 ? root.palette.primary : slot.index % 2 === 1 ? root.palette.ramp4 : root.palette.fgMuted)
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        SpringValue {
                            id: swell
                            target: root.hot === slot.modelData.id ? 1.1 : 1
                            spec: Motion.springSpatialFast
                            epsilon: 0.002
                        }
                        RadialGauge {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height)
                            height: width
                            scale: swell.value
                            wavy: true
                            glide: true
                            thickness: Tokens.spacingSm
                            value: slot.value * root.arrive
                            accent: slot.tone
                            MaterialIcon {
                                anchors.centerIn: parent
                                name: slot.modelData.icon
                                fill: 1
                                font.pixelSize: Tokens.iconMd
                                color: slot.tone
                            }
                        }
                        HoverHandler {
                            onHoveredChanged: {
                                if (hovered) root.hot = slot.modelData.id
                                else if (root.hot === slot.modelData.id) root.hot = ""
                            }
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Math.round(slot.value * 100) + "%"
                        variant: "micro"
                        font.weight: Font.DemiBold
                        font.features: ({ tnum: 1 })
                        color: slot.tone
                    }
                }
            }
        }

        // ── More about the ring under the pointer, or what is busy ────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingXs
            StyledText {
                Layout.fillWidth: true
                text: root.hot !== "" ? (root.rings.find(r => r.id === root.hot)?.label ?? "")
                    : root.busiest ? Translation.tr("%1 is busy").arg(root.busiest.label)
                    : Translation.tr("All calm")
                variant: "caption"
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            StyledText {
                text: root.hot !== "" ? root.detailOf(root.hot)
                    : root.busiest ? Math.round(root.busiest.v * 100) + "%"
                    : (SysInfo.hasCpuTemp ? SysInfo.cpuTemp + " °C" : "")
                variant: "caption"
                emphasis: "dim"
                font.features: ({ tnum: 1 })
            }
        }
    }
}
