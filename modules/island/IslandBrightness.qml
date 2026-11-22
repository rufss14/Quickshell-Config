pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── IslandBrightness ──────────────────────────────────────────────────────────
// Brightness as an island page: on the left the loud card (how many displays, and four levels that set
// them all at once); on the right one tall card per display, each a vertical slider (FillSlider, the
// OSD's) you drag or scroll, with its name above and its level below. A display that cannot be dimmed
// from here says so instead.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 14 + Tokens.spacingSm

    Component.onCompleted: Brightness.ensureProbed()

    function setAll(v) {
        for (let i = 0; i < Brightness.monitors.count; i++) {
            const m = Brightness.monitors.get(i)
            if (m.controllable) Brightness.requestBrightness(i, Brightness.clampFor(m.type, v))
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        IslandPlate {
            id: all
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.fillHeight: true
            hero: true
            order: 0
            clip: true

            MorphShape {
                width: all.height * 0.8
                height: width
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: -width * 0.25
                anchors.topMargin: -width * 0.22
                shape: "sunny"
                turns: false
                fillColor: root.palette.alpha(all.ink, 0.10)
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingXs

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Brightness").toUpperCase()
                        variant: "caption"
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                        color: all.inkDim
                    }
                    BusyDot { running: Brightness.probing; tint: all.ink }
                }
                IslandBadge {
                    Layout.topMargin: Tokens.spacingSm
                    size: Tokens.iconXl * 2 + Tokens.spacingSm
                    filled: true
                    shape: "sunny"
                    symbol: "brightness_6"
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacingSm
                    text: Brightness.probing && Brightness.count === 0 ? Translation.tr("Looking…")
                        : Brightness.count === 0 ? Translation.tr("Nothing to dim")
                        : Brightness.count === 1 ? Translation.tr("One display")
                        :                          Translation.tr("%1 displays").arg(Brightness.count)
                    variant: "headline"
                    font.weight: Font.DemiBold
                    color: all.ink
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Brightness.count === 0 ? Translation.tr("No display can be dimmed from here")
                                                 : Translation.tr("Set every display at once")
                    variant: "caption"
                    color: all.inkDim
                    wrapMode: Text.WordWrap
                }

                Item { Layout.fillHeight: true }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: Brightness.count > 0
                    columns: 2
                    rowSpacing: Tokens.spacingSm
                    columnSpacing: Tokens.spacingSm
                    Repeater {
                        model: [25, 50, 75, 100]
                        delegate: ChipButton {
                            required property int modelData
                            Layout.fillWidth: true
                            label: modelData + "%"
                            onActivated: root.setAll(modelData)
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            IslandPlate {
                anchors.fill: parent
                visible: !Brightness.probing && Brightness.count === 0
                order: 1
                PanelEmpty {
                    anchors.centerIn: parent
                    width: parent.width - Tokens.spacingXl * 2
                    quiet: true
                    symbol: "brightness_6"
                    shape: "sunny"
                    title: Translation.tr("Nothing to dim")
                    text: Translation.tr("External monitors are dimmed over DDC/CI with ddcutil (and the i2c-dev module); laptop panels with brightnessctl.")
                }
            }

            RowLayout {
                anchors.fill: parent
                spacing: Tokens.spacingMd

                Repeater {
                    model: Brightness.monitors

                    delegate: IslandPlate {
                        id: mon
                        required property int index
                        required property var model
                        readonly property real level: mon.model.brightness
                        function apply(v) { Brightness.requestBrightness(mon.index, Brightness.clampFor(mon.model.type, v)) }

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        order: 1 + mon.index

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Tokens.spacingMd
                            spacing: Tokens.spacingSm

                            StyledText {
                                Layout.fillWidth: true
                                text: mon.model.type === "bcl" ? Translation.tr("Built-in display")
                                                               : (mon.model.label || mon.model.name || Translation.tr("Display"))
                                variant: "label"
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: mon.model.controllable ? (mon.model.port || mon.model.name || "")
                                                             : Translation.tr("Can't be dimmed from here")
                                variant: "caption"
                                emphasis: "muted"
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                            FillSlider {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.fillHeight: true
                                Layout.preferredWidth: Tokens.iconXl * 2
                                visible: mon.model.controllable
                                accessibleName: mon.model.label || mon.model.name || Translation.tr("Display")
                                shape: "sunny"
                                glyph: Osd.glyphFor("brightness", mon.level / 100, mon.level <= 0)
                                value: mon.level / 100 * mon.arrive
                                onMoved: v => mon.apply(v * 100)
                                onScrolled: d => mon.apply(mon.level + d * 5)
                            }
                            Item { Layout.fillHeight: true; visible: !mon.model.controllable }
                            StyledText {
                                Layout.fillWidth: true
                                visible: mon.model.controllable
                                text: Math.round(mon.level) + "%"
                                variant: "title"
                                font.weight: Font.DemiBold
                                font.features: ({ tnum: 1 })
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
