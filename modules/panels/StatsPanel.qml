pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── StatsPanel ────────────────────────────────────────────────────────────────
// The system stats, beside the sidebar's stats button (SidePanelDock). It took
// over from the stats pill: the rings and their hover cards are one tile per
// metric here, everything the card had and room for all of it at once — the
// ring (its temperature as an inner arc), the part and its hardware, the headline,
// every fact with its icon, a minute's trace, the CPU's threads, the devices'
// charge bars, and whether it's over its threshold.
//
//   click a tile     its settings page, in depth (the ring's old left-click)
//   middle-click     the system monitor in a terminal (SysStats.openMonitor)
//
// The shell's Material 3 Expressive panel shape: an optional header (Settings › Modules › System stats),
// a hero that says whether anything is over its threshold, with the monitor and settings buttons, then a
// tonal tile per metric.
// Everything real is services/SysStats (readout(), metrics, alerts); this shows
// it. It holds the samplers for as long as it exists (StatsSampler).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The room the slot has (SidePanelDock sets it); the tiles scroll past it.
    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingXl
    readonly property color accent: Colors.of(QsWindow.window).primary
    // Narrower than a bar panel: it hangs off the sidebar beside a button, and a
    // tile is a ring and a few lines of text.
    implicitWidth: Tokens.sideCardUnit * 8
    implicitHeight: Math.min(root.maxHeight,
                             (head.visible ? head.implicitHeight + col.spacing : 0)
                             + hero.implicitHeight + col.spacing + tiles.implicitHeight + root.pad * 2)

    StatsSampler { metrics: Config.sidebarStatsMetrics }

    // The "Busiest" tile's sampler runs only while this panel exists (the dock's Loader destroys it on close).
    Component.onCompleted: SysStats.acquireTop()
    Component.onDestruction: SysStats.releaseTop()
    // Which list the tile shows: the processes using the most CPU, or the most memory.
    property string topBy: "cpu"
    readonly property var topRows: root.topBy === "cpu" ? SysStats.topCpu : SysStats.topMem

    readonly property var metrics: SysStats.metrics
    readonly property var alerting: root.metrics.filter(k => SysStats.isAlerting(k))

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Tokens.spacingSm

        PanelHeader {
            id: head
            Layout.fillHeight: false
            visible: Config.panelHeader("stats")
            symbol:    "memory"
            title:     Translation.tr("System")
            titleTail: Translation.tr("stats")
            accent:    root.accent
            subtitle: root.metrics.length === 0 ? Translation.tr("Nothing chosen to show")
                    : SysStats.cpuName !== "" ? SysStats.cpuName
                    : Translation.tr("%1 readings, live").arg(root.metrics.length)
        }

        // Calm, or what is over its threshold; the monitor and this module's settings.
        PanelHero {
            id: hero
            compact: true
            symbol: root.alerting.length > 0 ? "warning" : "speed"
            shape: "cookie12"
            active: root.metrics.length > 0 && root.alerting.length === 0
            warn: root.alerting.length > 0
            turning: false
            accent: root.accent
            title: root.metrics.length === 0 ? Translation.tr("Nothing to read")
                 : root.alerting.length > 0  ? Translation.tr("Over threshold")
                 :                             Translation.tr("Running calm")
            line: root.alerting.length > 0
                  ? root.alerting.map(k => SysStats.readout(k).label).join(", ")
                  : root.metrics.length === 1 ? Translation.tr("1 reading, live")
                  : Translation.tr("%1 readings, live").arg(root.metrics.length)

            PanelButton {
                variant: "ghost"
                capsule: true
                symbol:  "terminal"
                glyphTint: hero.ink
                onActivated: SysStats.openMonitor()
                HelpTip { text: Translation.tr("Open the system monitor") }
            }
            PanelButton {
                variant: "ghost"
                capsule: true
                symbol:  "settings"
                glyphTint: hero.ink
                onActivated: UiState.openSettingsTo("SidebarStatsPage.qml")
            }
        }

        Flickable {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: list.width
            contentHeight: tiles.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: list.contentHeight > list.height + 0.5

            Column {
                id: tiles
                width: list.width
                spacing: Tokens.spacingSm

                Repeater {
                    // By name, so a tile keeps its trace and hover across a reorder.
                    model: ScriptModel { values: root.metrics }
                    delegate: Tile {}
                }

                // ── Busiest: what is using the machine right now ─────────────────
                Rectangle {
                    id: busiest
                    width: parent.width
                    visible: SysStats.topMem.length > 0
                    height: busyCol.implicitHeight + (Tokens.spacingMd + Tokens.spacingXs) * 2
                    radius: Tokens.radiusCard
                    color: Colors.of(QsWindow.window).section

                    ColumnLayout {
                        id: busyCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.spacingMd + Tokens.spacingXs
                        spacing: Tokens.spacingSm

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Busiest")
                                variant: "body"
                                font.weight: Font.DemiBold
                            }
                            ChipButton {
                                label: Translation.tr("CPU")
                                on: root.topBy === "cpu"
                                tint: root.accent
                                onActivated: root.topBy = "cpu"
                            }
                            ChipButton {
                                label: Translation.tr("Memory")
                                on: root.topBy === "mem"
                                tint: root.accent
                                onActivated: root.topBy = "mem"
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: root.topRows.length === 0
                            text: Translation.tr("Nothing is using the processor")
                            variant: "caption"
                            emphasis: "dim"
                        }

                        Repeater {
                            model: ScriptModel { values: root.topRows; objectProp: "name" }
                            delegate: ColumnLayout {
                                id: proc
                                required property var modelData
                                // The bar: this row against the list's biggest, so the order reads at a glance.
                                readonly property real peak: root.topBy === "cpu" ? (root.topRows[0]?.cpu ?? 1) : (root.topRows[0]?.mb ?? 1)
                                readonly property real mine: root.topBy === "cpu" ? proc.modelData.cpu : proc.modelData.mb
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: Tokens.spacingXs

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    spacing: Tokens.spacingSm
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: proc.modelData.name + (proc.modelData.procs > 1 ? "  ×" + proc.modelData.procs : "")
                                        variant: "label"
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        text: Math.round(proc.modelData.cpu) + "%"
                                        variant: "caption"
                                        emphasis: root.topBy === "cpu" ? "normal" : "dim"
                                        font.features: ({ tnum: 1 })
                                    }
                                    StyledText {
                                        Layout.preferredWidth: Tokens.sideCardUnit * 1.4
                                        horizontalAlignment: Text.AlignRight
                                        text: proc.modelData.mb >= 1024 ? (proc.modelData.mb / 1024).toFixed(1) + " GB"
                                                                         : Math.round(proc.modelData.mb) + " MB"
                                        variant: "caption"
                                        emphasis: root.topBy === "mem" ? "normal" : "dim"
                                        font.features: ({ tnum: 1 })
                                    }
                                }
                                Meter {
                                    Layout.fillWidth: true
                                    value: proc.peak > 0 ? proc.mine / proc.peak : 0
                                    accent: root.accent
                                }
                            }
                        }
                    }
                }

                // Nothing chosen, or nothing this machine can read.
                PanelEmpty {
                    visible: root.metrics.length === 0
                    width: parent.width
                    quiet: true
                    symbol: "speed"
                    title: Translation.tr("No readings chosen")
                    text: Translation.tr("Choose what to show in Settings › Modules, with System stats picked.")
                }
            }
        }
    }

    // ── One metric ────────────────────────────────────────────────────────────
    component Tile: Item {
        id: tile
        required property string modelData

        readonly property var info: SysStats.readout(tile.modelData)
        readonly property bool alert: SysStats.isAlerting(tile.modelData)
        readonly property int inset: Tokens.spacingMd + Tokens.spacingXs
        readonly property int ring: Tokens.sideCardUnit

        width: tiles.width
        height: body.implicitHeight + tile.inset * 2

        // Arriving: a tile swells in, the dock's icons' curve.
        property real appear: 0
        Component.onCompleted: tile.appear = 1
        Behavior on appear { NumberAnimation { duration: Motion.standard; easing.bezierCurve: Motion.emphasizedDecel
                                               easing.type: Easing.BezierSpline } }
        opacity: tile.appear

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusCard
            color: tile.alert ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).section, Colors.of(QsWindow.window).danger, 0.22)
                              : Colors.of(QsWindow.window).section
            Behavior on color { ColorAnimation { duration: Motion.standard } }
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Colors.of(QsWindow.window).fg
                opacity: tileMouse.containsMouse ? Tokens.stateHover : 0
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            }
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function (m) {
                if (m.button === Qt.MiddleButton) SysStats.openMonitor()
                else UiState.openSettingsTo(tile.info.page)
            }
        }

        Column {
            id: body
            x: tile.inset
            y: tile.inset
            width: tile.width - tile.inset * 2
            spacing: Tokens.spacingSm

            // ── The ring, and what it says ────────────────────────────────────
            Row {
                width: parent.width
                spacing: Tokens.spacingMd

                RadialGauge {
                    id: gauge
                    width:  tile.ring
                    height: tile.ring
                    anchors.verticalCenter: parent.verticalCenter
                    thickness: Math.max(Tokens.spacingXs, Math.round(gauge.width / 14))
                    value: tile.info.ratio
                    wavy: true
                    sampleInterval: tile.modelData === "net" ? NetStats.rateInterval : SysInfo.interval
                    glide: true
                    scale: 0.6 + 0.4 * tile.appear

                    // The inner arc: the part's temperature, or the network's upload.
                    RadialGauge {
                        id: inner
                        anchors.fill: parent
                        visible: tile.info.inner !== undefined
                        thickness: Math.max(Tokens.borderWidth, Math.round(gauge.thickness / 2))
                        accent: Colors.of(QsWindow.window).primary
                        value: tile.info.inner ?? 0
                        sampleInterval: gauge.sampleInterval
                        glide: true
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: !tile.info.logo
                        glyph: tile.info.glyph
                        font.pixelSize: Math.round(gauge.width * 0.4 * (tile.info.glyphScale ?? 1))
                        color: tile.alert ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fg
                    }
                    TintedIcon {
                        anchors.centerIn: parent
                        visible: !!tile.info.logo
                        source: tile.info.logo ?? ""
                        size: Math.round(gauge.width * 0.4 * (tile.info.glyphScale ?? 1))
                        color: tile.alert ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fg
                    }
                }

                Column {
                    width: parent.width - gauge.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacingXs

                    // The part, then the actual hardware: "GPU — AMD Radeon RX 6700 XT".
                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: tile.info.name ? tile.info.label + " — " + tile.info.name : tile.info.label
                        variant: "caption"
                        emphasis: "dim"
                    }
                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: tile.info.value
                        variant: "title"
                        font.weight: Font.DemiBold
                        color: tile.alert ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fg
                    }
                    Flow {
                        width: parent.width
                        spacing: Tokens.spacingMd
                        visible: tile.info.rows.length > 0 || tile.alert
                        IconLine {
                            visible: tile.alert
                            glyph: "\u{F0026}"                           // 󰀦 alert
                            text: Translation.tr("Over its threshold")
                            warn: true
                        }
                        Repeater {
                            model: tile.info.rows
                            delegate: IconLine {
                                required property var modelData
                                glyph: modelData.glyph
                                text: modelData.text
                                warn: modelData.warn ?? false
                            }
                        }
                    }
                }
            }

            // ── Charge bars (devices): one per device ─────────────────────────
            Repeater {
                model: tile.info.meters ?? []
                delegate: Column {
                    id: meterItem
                    required property var modelData
                    width: body.width
                    spacing: Tokens.spacingXs
                    IconLine {
                        visible: meterItem.modelData.text !== ""
                        glyph: meterItem.modelData.glyph
                        text: meterItem.modelData.text
                        warn: meterItem.modelData.warn
                    }
                    Meter {
                        width: parent.width
                        value: meterItem.modelData.level
                        // The mark, never a red fill (Meter's rule).
                        limit: meterItem.modelData.limit
                    }
                }
            }

            // ── A minute of it (fixed 0..1; Sparkline says why) ───────────────
            Sparkline {
                visible: tile.info.history.length > 1
                width: body.width
                height: Math.round(tile.ring * 0.75)
                values: tile.info.history
                capacity: tile.info.capacity ?? 60
                sampleInterval: tile.info.cadence ?? 0
            }

            // ── Every thread, CPU only: one bar each, the same fixed scale ────
            Row {
                id: coreRow
                readonly property int n: tile.modelData === "cpu" ? SysInfo.cores.length : 0
                visible: coreRow.n > 0
                width: body.width
                height: Math.round(tile.ring / 3)
                spacing: Tokens.borderWidth
                readonly property real barW: (coreRow.width - coreRow.spacing * (coreRow.n - 1)) / Math.max(1, coreRow.n)
                Repeater {
                    model: coreRow.n
                    delegate: Rectangle {
                        required property int index
                        width: coreRow.barW
                        height: coreRow.height
                        radius: width / 2
                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.10)
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: parent.height * (SysInfo.cores[parent.index] ?? 0)
                            radius: parent.radius
                            color: root.accent
                        }
                    }
                }
            }
        }
    }
}
