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
// The panel recipe: PanelHeader + ActionGroup, tokens throughout, shared widgets.
// Everything real is services/SysStats (readout(), metrics, alerts); this shows
// it. It holds the samplers for as long as it exists (StatsSampler).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The room the slot has (SidePanelDock sets it); the tiles scroll past it.
    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingLg
    // Narrower than a bar panel: it hangs off the sidebar beside a button, and a
    // tile is a ring and a few lines of text.
    implicitWidth: Tokens.sideCardUnit * 8
    implicitHeight: Math.min(root.maxHeight,
                             head.implicitHeight + col.spacing + tiles.implicitHeight + root.pad * 2)

    StatsSampler { metrics: Config.sidebarStatsMetrics }

    readonly property var metrics: SysStats.metrics
    readonly property var alerting: root.metrics.filter(k => SysStats.isAlerting(k))

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Tokens.spacingMd

        PanelHeader {
            id: head
            glyph:     "\u{F0EE0}"                                   // 󰻠 cpu-64-bit
            title:     Translation.tr("System")
            titleTail: "stats"
            accent:    Colors.of(QsWindow.window).primary
            subtitle: root.metrics.length === 0 ? "Nothing chosen to show"
                    : root.alerting.length > 0
                    ? root.alerting.map(k => SysStats.readout(k).label).join(", ") + " over threshold"
                    : SysStats.cpuName !== "" ? SysStats.cpuName
                    : root.metrics.length + " readings, live"

            ActionGroup {
                PanelButton {
                    variant: "ghost"
                    symbol:  "terminal"
                    onActivated: SysStats.openMonitor()
                }
                PanelButton {
                    variant: "ghost"
                    symbol:  "settings"
                    onActivated: UiState.openSettingsTo("SidebarStatsPage.qml")
                }
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

                // Nothing chosen, or nothing this machine can read.
                StyledText {
                    visible: root.metrics.length === 0
                    width: parent.width
                    wrapMode: Text.WordWrap
                    variant: "caption"
                    emphasis: "dim"
                    text: Translation.tr("Choose what to show in Settings › Sidebar & dock › System stats.")
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
        readonly property int inset: Tokens.spacingMd
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
            radius: Tokens.radiusSm
            color: Colors.of(QsWindow.window).alpha(tile.alert ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fg,
                                tileMouse.containsMouse ? 0.08 : 0.04)
            border.width: tile.alert ? Tokens.borderWidth : 0
            border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.4)
            Behavior on color { ColorAnimation { duration: Motion.respond } }
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
                        variant: "label"
                        font.bold: true
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
                        radius: Tokens.spacingXs / 2
                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.10)
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: parent.height * (SysInfo.cores[parent.index] ?? 0)
                            radius: parent.radius
                            color: Colors.of(QsWindow.window).focus
                        }
                    }
                }
            }
        }
    }
}
