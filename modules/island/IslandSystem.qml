import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/island.js" as Rules
import "../../services/sysstats.js" as Stats

// ── IslandSystem ──────────────────────────────────────────────────────────────
// The card's third page, Performance, laid out as Caelestia's and dressed as the panels are (flat cards, the CPU's on the accent
// container, wavy rings, filled M3E shapes, a spring cascade): the processor and the graphics card across the
// top (IslandPerfHero: a ring round the part's symbol, its model, its temperature, and its usage in a big shape);
// under them the home disk as a large ring with a pill that steps through the filesystems, the network
// (what it carries each way, the last minutes of both, the totals) and the memory. SysInfo, Storage and NetStats
// are held only while this tab is on screen.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property color warm: root.palette.ramp4
    property string tab: "perf"

    Component.onCompleted: {
        SysInfo.acquire(); Storage.acquire(); NetStats.acquire()
        if (!SysInfo.spec.CPU) SysInfo.loadSpec()
    }
    Component.onDestruction: { SysInfo.release(); Storage.release(); NetStats.release() }

    // The filesystem on show: the pill steps through the real ones.
    readonly property var disks: (Storage.filesystems ?? []).filter(f => f.size > 0)
    property int diskIndex: 0
    readonly property var fs: root.disks.length > 0 ? root.disks[root.diskIndex % root.disks.length] : null
    readonly property real diskUsed: root.fs ? root.fs.used / root.fs.size : 0
    // The network chart's window, in samples (NetStats takes one every 250 ms): fifteen seconds, so it fills while you
    // look rather than drawing a sliver at the edge of the history's whole minute.
    property int netSpan: 60
    // The disk card shows what is free instead of what is used when pressed.
    property bool showFree: false
    // A card that has a story opens it: the CPU, GPU and memory cards jump to Tasks sorted by that resource.
    function openTasks(by) {
        tasks.sortBy = by
        root.tab = "tasks"
    }
    readonly property string diskName: root.fs ? String(root.fs.device).split("/").pop() : ""

    // ── The tabs: Performance, and Tasks (every process, searchable, endable) ──
    SegmentSwitch {
        id: tabs
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        model: [
            { value: "perf",  label: Translation.tr("Performance"), icon: "speed" },
            { value: "tasks", label: Translation.tr("Tasks"),       icon: "checklist" }
        ]
        current: root.tab
        onPicked: value => root.tab = value
    }

    IslandTasks {
        id: tasks
        active: root.tab === "tasks"
        anchors.top: tabs.bottom
        anchors.topMargin: Tokens.spacingMd
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        opacity: root.tab === "tasks" ? 1 : 0
        visible: opacity > 0.005
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: tabs.height + Tokens.spacingMd
        spacing: Tokens.spacingMd
        opacity: root.tab === "perf" ? 1 : 0
        visible: opacity > 0.005
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

        // ── The processor and the graphics card ───────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Tokens.spacingXl * 7
            spacing: Tokens.spacingMd

            IslandPerfHero {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                hero: true
                clickable: true
                onClicked: root.openTasks("cpu")
                order: 0
                icon: "memory"
                title: Translation.tr("CPU")
                model: Stats.cleanCpuName(SysInfo.spec.CPU ?? "")
                usage: SysInfo.cpu
                shape: "cookie9"
                temp: SysInfo.hasCpuTemp ? SysInfo.cpuTemp : -1
                cores: SysInfo.cores
            }
            IslandPerfHero {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                order: 1
                clickable: true
                onClicked: root.openTasks("gpu")
                icon: "monitor"
                title: Translation.tr("GPU")
                // lspci's line, as the product name ("AMD Radeon RX …", not "Advanced Micro Devices, Inc. [AMD/ATI] …").
                // Vulkan's own name ("AMD Radeon RX 6700 XT"), from SysStats; lspci's family line only without it.
                model: SysStats.gpuName || Stats.gpuName([], SysInfo.spec.GPU ?? "")
                usage: SysInfo.hasGpu ? SysInfo.gpu : 0
                shape: "sunny"
                temp: SysInfo.hasGpuTemp ? SysInfo.gpuTemp : -1
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            // ── Storage ───────────────────────────────────────────────────────
            IslandPlate {
                id: storagePlate
                clickable: true
                onClicked: root.showFree = !root.showFree
                order: 2
                Layout.fillWidth: true
                Layout.preferredWidth: 6
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Tokens.spacingLg

                        RadialGauge {
                            Layout.fillHeight: true
                            Layout.maximumHeight: Tokens.spacingXl * 6
                            Layout.preferredWidth: Math.min(height, Tokens.spacingXl * 6)
                            wavy: true
                            thickness: Tokens.spacingMd
                            value: (root.showFree ? 1 - root.diskUsed : root.diskUsed) * storagePlate.arrive
                            accent: root.palette.primary
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 0
                                MaterialIcon {
                                    Layout.alignment: Qt.AlignHCenter
                                    name: "hard_drive"
                                    font.pixelSize: Tokens.iconMd
                                    color: root.palette.fgMuted
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Math.round((root.showFree ? 1 - root.diskUsed : root.diskUsed) * 100) + "%"
                                    variant: "title"
                                    font.weight: Font.DemiBold
                                    font.features: ({ tnum: 1 })
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.showFree ? Translation.tr("Free") : Translation.tr("Used")
                                    variant: "label"
                                    emphasis: "dim"
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: Tokens.spacingXs
                            StyledText {
                                text: Translation.tr("Storage")
                                variant: "title"
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: !root.fs ? ""
                                    : root.showFree ? Translation.tr("%1 free of %2").arg(Storage.bytes(root.fs.size - root.fs.used)).arg(Storage.bytes(root.fs.size))
                                    : Storage.bytes(root.fs.used) + " / " + Storage.bytes(root.fs.size)
                                variant: "caption"
                                emphasis: "dim"
                                font.features: ({ tnum: 1 })
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // The pill: the filesystem on show; a press steps to the next.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        implicitHeight: Tokens.iconXl + Tokens.spacingMd
                        radius: height / 2
                        color: root.palette.plate
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: Tokens.spacingSm
                            MaterialIcon {
                                name: "hard_drive"
                                font.pixelSize: Tokens.iconMd
                                color: root.palette.fgMuted
                            }
                            StyledText {
                                text: root.diskName
                                variant: "label"
                                font.weight: Font.Medium
                            }
                            MaterialIcon {
                                visible: root.disks.length > 1
                                name: "expand_more"
                                font.pixelSize: Tokens.iconMd
                                color: root.palette.fgMuted
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.disks.length > 1
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.diskIndex = (root.diskIndex + 1) % root.disks.length
                            Accessible.role: Accessible.Button
                            Accessible.name: Translation.tr("Next disk")
                            Accessible.onPressAction: root.diskIndex = (root.diskIndex + 1) % root.disks.length
                        }
                    }
                }
            }

            // ── Network ───────────────────────────────────────────────────────
            IslandPlate {
                order: 3
                clickable: true
                onClicked: root.netSpan = root.netSpan === 60 ? 240 : 60
                Layout.fillWidth: true
                Layout.preferredWidth: 6
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        MaterialIcon {
                            name: "swap_vert"
                            font.pixelSize: Tokens.iconLg
                            color: root.palette.primary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Network")
                            variant: "title"
                            font.weight: Font.DemiBold
                        }
                        // The chart's window; a press on the card flips it between the last 15 seconds and the last minute.
                        Rectangle {
                            implicitWidth: spanText.implicitWidth + Tokens.spacingMd
                            implicitHeight: spanText.implicitHeight + Tokens.spacingXs
                            radius: height / 2
                            color: root.palette.alpha(root.palette.primary, 0.16)
                            StyledText {
                                id: spanText
                                anchors.centerIn: parent
                                text: root.netSpan === 60 ? Translation.tr("15 s") : Translation.tr("1 min")
                                variant: "caption"
                                font.weight: Font.DemiBold
                                color: root.palette.primary
                            }
                        }
                    }

                    // Both directions' last minutes, one over the other.
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: Tokens.spacingXxl
                        Sparkline {
                            anchors.fill: parent
                            values: Rules.scaled(NetStats.rxHistory, 65536, root.netSpan)
                            capacity: root.netSpan
                            accent: root.warm
                        }
                        Sparkline {
                            anchors.fill: parent
                            values: Rules.scaled(NetStats.txHistory, 65536, root.netSpan)
                            capacity: root.netSpan
                            accent: root.palette.primary
                        }
                    }

                    // The rows: a constant model, never an array of the readings (those change every few hundred ms,
                    // and an array model rebuilds every delegate on each change).
                    Repeater {
                        model: 4
                        delegate: RowLayout {
                            id: line
                            required property int index
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            MaterialIcon {
                                name: line.index === 0 ? "download" : line.index === 1 ? "upload" : "history"
                                font.pixelSize: Tokens.iconMd
                                // The chart's colours: download in the second hue, upload in the accent; the totals muted.
                                color: line.index === 0 ? root.warm : line.index === 1 ? root.palette.primary : root.palette.fgMuted
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: line.index === 0 ? Translation.tr("Download") : line.index === 1 ? Translation.tr("Upload")
                                    : line.index === 2 ? Translation.tr("Total downloaded") : Translation.tr("Total uploaded")
                                variant: "label"
                                emphasis: "dim"
                            }
                            StyledText {
                                text: line.index === 0 ? NetStats.rate(NetStats.rxRate)
                                    : line.index === 1 ? NetStats.rate(NetStats.txRate)
                                    : line.index === 2 ? NetStats.bytes(NetStats.rxTotal)
                                    : NetStats.bytes(NetStats.txTotal)
                                variant: line.index >= 2 ? "caption" : "label"
                                font.weight: line.index >= 2 ? Font.Normal : Font.DemiBold
                                font.features: ({ tnum: 1 })
                                color: line.index >= 2 ? root.palette.fgMuted : root.warm
                            }
                        }
                    }
                }
            }

            // ── Memory ────────────────────────────────────────────────────────
            IslandPlate {
                id: memoryPlate
                clickable: true
                onClicked: root.openTasks("mem")
                order: 4
                Layout.fillWidth: true
                Layout.preferredWidth: 4
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        MaterialIcon {
                            name: "memory_alt"
                            font.pixelSize: Tokens.iconLg
                            color: root.warm
                        }
                        StyledText {
                            text: Translation.tr("Memory")
                            variant: "title"
                            font.weight: Font.DemiBold
                        }
                    }
                    RadialGauge {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        wavy: true
                        thickness: Tokens.spacingMd
                        value: SysInfo.memFraction * memoryPlate.arrive
                        accent: root.warm
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 0
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Math.round(SysInfo.memFraction * 100) + "%"
                                variant: "title"
                                font.weight: Font.DemiBold
                                font.features: ({ tnum: 1 })
                                color: root.warm
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Translation.tr("Used")
                                variant: "label"
                                emphasis: "dim"
                            }
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: SysInfo.memUsed.toFixed(1) + " / " + SysInfo.memTotal.toFixed(1) + " GB"
                        variant: "label"
                        font.weight: Font.Medium
                        font.features: ({ tnum: 1 })
                    }
                    // Swap, when the machine has any: how far memory has spilled to disk.
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        visible: SysInfo.swapTotal > 0
                        text: Translation.tr("Swap %1 / %2 GB").arg(SysInfo.swapUsed.toFixed(1)).arg(SysInfo.swapTotal.toFixed(1))
                        variant: "caption"
                        emphasis: "dim"
                        font.features: ({ tnum: 1 })
                    }
                }
            }
        }
    }
}
