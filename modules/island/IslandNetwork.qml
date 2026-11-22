pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/island.js" as Rules

// ── IslandNetwork ─────────────────────────────────────────────────────────────
// The network on an island (2026-11-15, one of the user's new pages; the right island, beside Wi-Fi):
//
//   left    the loud card: what is moving right now, down large and up beside it, over the last minutes as two
//           curves, the interface, the gateway, and what has moved since the computer started
//   right   a speed test (one press, the result large; the live trace while it runs; what it costs in data) beside
//           the DNS in use as four option cards (Automatic, Cloudflare, Quad9, Google), and under both the apps
//           moving data right now, busiest first, each with its rate as a bar
//
// Everything real is services/NetStats, NetApps (held only while this shows), SpeedTest and Dns.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 14 + Tokens.spacingSm
    readonly property int span: 120

    Component.onCompleted: { NetStats.acquire(); NetApps.acquire() }
    Component.onDestruction: { NetStats.release(); NetApps.release() }

    readonly property var apps: NetApps.apps.slice(0, 6)
    readonly property real appPeak: Math.max(1, ...root.apps.map(a => (a.rxRate || 0) + (a.txRate || 0)))

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        // ══ Right now, loud ═══════════════════════════════════════════════════
        IslandPlate {
            id: hero
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.minimumWidth: root.sideW
            Layout.fillHeight: true
            hero: true
            order: 0
            radius: Tokens.radiusXl

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    IslandBadge {
                        filled: true
                        symbol: NetStats.iface.charAt(0) === "w" ? "wifi" : "lan"
                        shape: NetStats.rxRate + NetStats.txRate > 65536 ? "cookie9" : "squircle"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: NetStats.iface !== "" ? NetStats.iface : Translation.tr("Offline")
                            variant: "title"
                            font.weight: Font.DemiBold
                            color: hero.ink
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: NetStats.gateway !== "" ? Translation.tr("Gateway %1").arg(NetStats.gateway) : Translation.tr("No gateway")
                            variant: "caption"
                            color: hero.inkDim
                            elide: Text.ElideRight
                        }
                    }
                }

                // Down large, up beside it.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingLg
                    ColumnLayout {
                        spacing: 0
                        RowLayout {
                            Layout.fillHeight: false
                            spacing: Tokens.spacingXs
                            MaterialIcon { name: "arrow_downward"; color: hero.ink }
                            StyledText {
                                text: NetStats.rate(NetStats.rxRate)
                                font.pixelSize: Tokens.fontDisplay
                                font.weight: Font.Bold
                                font.features: ({ tnum: 1 })
                                color: hero.ink
                            }
                        }
                        StyledText { text: Translation.tr("Down"); variant: "micro"; color: hero.inkDim }
                    }
                    ColumnLayout {
                        spacing: 0
                        RowLayout {
                            Layout.fillHeight: false
                            spacing: Tokens.spacingXs
                            MaterialIcon { name: "arrow_upward"; color: hero.ink }
                            StyledText {
                                text: NetStats.rate(NetStats.txRate)
                                variant: "title"
                                font.weight: Font.Bold
                                font.features: ({ tnum: 1 })
                                color: hero.ink
                            }
                        }
                        StyledText { text: Translation.tr("Up"); variant: "micro"; color: hero.inkDim }
                    }
                }

                // The last minutes, both ways.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: Tokens.spacingXxl
                    Sparkline {
                        anchors.fill: parent
                        values: Rules.scaled(NetStats.rxHistory, 65536, root.span)
                        capacity: root.span
                        accent: hero.ink
                    }
                    Sparkline {
                        anchors.fill: parent
                        values: Rules.scaled(NetStats.txHistory, 65536, root.span)
                        capacity: root.span
                        accent: root.palette.primary
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Since start: %1 down · %2 up").arg(NetStats.bytes(NetStats.rxTotal)).arg(NetStats.bytes(NetStats.txTotal))
                    variant: "caption"
                    color: hero.inkDim
                    elide: Text.ElideRight
                }
            }
        }

        // ══ Right ═════════════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Tokens.spacingXl * 10
                spacing: Tokens.spacingMd

                // ── Speed test ─────────────────────────────────────────────────
                IslandPlate {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    order: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingMd
                        spacing: Tokens.spacingXs

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            IslandBadge {
                                size: Tokens.iconXl
                                symbol: "speed"
                                shape: SpeedTest.running ? "burst" : SpeedTest.hasResult ? "cookie9" : "circle"
                                filled: SpeedTest.running || SpeedTest.hasResult
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Speed test")
                                variant: "label"
                                font.weight: Font.DemiBold
                            }
                        }
                        Item { Layout.fillHeight: true }
                        StyledText {
                            Layout.fillWidth: true
                            text: SpeedTest.running ? SpeedTest.mbps(SpeedTest.liveBps)
                                : SpeedTest.hasResult ? SpeedTest.mbps(SpeedTest.downBps)
                                : Translation.tr("Not run yet")
                            font.pixelSize: Tokens.fontDisplay
                            font.weight: Font.Bold
                            font.features: ({ tnum: 1 })
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: SpeedTest.running ? (SpeedTest.phase === "latency" ? Translation.tr("Measuring ping") : SpeedTest.phase === "down" ? Translation.tr("Downloading") : Translation.tr("Uploading"))
                                : SpeedTest.hasResult ? Translation.tr("Up %1 · ping %2").arg(SpeedTest.mbps(SpeedTest.upBps)).arg(SpeedTest.ms(SpeedTest.latencyMs))
                                : SpeedTest.error !== "" ? SpeedTest.error
                                : Translation.tr("Uses about %1 of data").arg(SpeedTest.dataCostLabel)
                            variant: "caption"
                            emphasis: SpeedTest.error !== "" && !SpeedTest.running ? "normal" : "muted"
                            elide: Text.ElideRight
                        }
                        Sparkline {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Tokens.spacingXl
                            visible: SpeedTest.running
                            values: Rules.scaled(SpeedTest.liveTrace, 1, SpeedTest.traceCapacity)
                            capacity: SpeedTest.traceCapacity
                        }
                        Item { Layout.fillHeight: true }
                        ChipButton {
                            solid: !SpeedTest.running
                            tonal: SpeedTest.running
                            symbol: SpeedTest.running ? "close" : "play_arrow"
                            label: SpeedTest.running ? Translation.tr("Stop") : SpeedTest.hasResult ? Translation.tr("Again") : Translation.tr("Run")
                            onActivated: SpeedTest.running ? SpeedTest.cancel() : SpeedTest.start()
                        }
                    }
                }

                // ── DNS ────────────────────────────────────────────────────────
                IslandPlate {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    order: 2

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingMd
                        spacing: Tokens.spacingXs

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            IslandBadge {
                                size: Tokens.iconXl
                                symbol: "dns"
                                shape: Dns.busy ? "burst" : "clover"
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("DNS")
                                variant: "label"
                                font.weight: Font.DemiBold
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: Dns.error !== "" ? Dns.error : Dns.busy ? Translation.tr("Switching…") : ""
                            variant: "micro"
                            emphasis: "muted"
                            elide: Text.ElideRight
                        }
                        Item { Layout.fillHeight: true }
                        GridLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            columns: 2
                            columnSpacing: Tokens.spacingXs
                            rowSpacing: Tokens.spacingXs
                            Repeater {
                                model: Dns.presets
                                delegate: OptionCard {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 1
                                    label: modelData.name
                                    symbol: ["router", "cloud", "security", "public"][index % 4]
                                    shape: ["cookie9", "clover", "sunny", "squircle"][index % 4]
                                    on: Dns.activeId === modelData.id
                                    enabled: !Dns.busy
                                    onActivated: Dns.applyPreset(modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            // ── What is using it ───────────────────────────────────────────────
            IslandPlate {
                Layout.fillWidth: true
                Layout.fillHeight: true
                order: 3

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingXs

                    StyledText {
                        text: Translation.tr("Using the network now")
                        variant: "label"
                        font.weight: Font.DemiBold
                    }
                    StyledText {
                        visible: root.apps.length === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: NetApps.active ? Translation.tr("Nothing is moving data right now") : ""
                        variant: "caption"
                        emphasis: "muted"
                    }
                    Repeater {
                        model: root.apps
                        delegate: RowLayout {
                            id: app
                            required property var modelData
                            readonly property real total: (app.modelData.rxRate || 0) + (app.modelData.txRate || 0)
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            StyledText {
                                Layout.preferredWidth: Tokens.spacingXl * 7
                                text: app.modelData.name
                                variant: "caption"
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.spacingSm
                                radius: height / 2
                                color: root.palette.alpha(root.palette.fg, 0.08)
                                Rectangle {
                                    width: parent.width * Math.min(1, app.total / root.appPeak)
                                    height: parent.height
                                    radius: height / 2
                                    color: root.palette.primary
                                    Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.respondCurve } }
                                }
                            }
                            StyledText {
                                Layout.preferredWidth: Tokens.spacingXl * 5
                                horizontalAlignment: Text.AlignRight
                                text: NetStats.rate(app.total)
                                variant: "caption"
                                emphasis: "muted"
                                font.features: ({ tnum: 1 })
                            }
                        }
                    }
                    Item { Layout.fillHeight: true; visible: root.apps.length > 0 }
                }
            }
        }
    }
}
