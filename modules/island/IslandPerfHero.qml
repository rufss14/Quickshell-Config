import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── IslandPerfHero ────────────────────────────────────────────────────────────
// One of the Performance page's two top cards: a wavy ring round the part's symbol, its name and model, a thermometer
// with the temperature and a bar for it; and on the right "Usage" over a big filled shape holding the percentage. The
// processor's shape is a cookie, the graphics card's a sunburst. `hero` puts it on the accent container.
// ─────────────────────────────────────────────────────────────────────────────
IslandPlate {
    id: root

    property string icon: ""
    property string title: ""
    property string model: ""
    // 0..1.
    property real   usage: 0
    property string shape: "cookie9"
    // Whole degrees, or -1 for no reading.
    property int    temp: -1
    // Per-core load 0..1, drawn as a row of small bars (the CPU's); [] = none.
    property var    cores: []

    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingMd

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingXs

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                RadialGauge {
                    Layout.preferredWidth: Tokens.iconXl + Tokens.spacingXl
                    Layout.preferredHeight: Layout.preferredWidth
                    wavy: true
                    thickness: Tokens.spacingXs + 1
                    value: root.usage * root.arrive
                    accent: root.palette.primary
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: root.icon
                        fill: 1
                        font.pixelSize: Tokens.iconLg
                        color: root.hero ? root.ink : root.palette.primary
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: root.title
                        variant: "title"
                        font.weight: Font.DemiBold
                        color: root.ink
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.model
                        variant: "caption"
                        color: root.inkDim
                        elide: Text.ElideRight
                    }
                }
            }

            // The cores, one narrow bar each, as tall as it is busy, standing on a common line. A fixed-height row: only the
            // bars' heights follow the load.
            Row {
                id: coreRow
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Tokens.spacingXl
                visible: root.cores.length > 0
                spacing: Tokens.spacingSm
                Repeater {
                    model: root.cores.length
                    delegate: Item {
                        id: core
                        required property int index
                        readonly property real load: root.cores[core.index] ?? 0
                        width: Tokens.spacingXs * 2 + 1
                        height: coreRow.height
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: Math.max(width, parent.height * core.load * root.arrive)
                            radius: width / 2
                            color: root.hero ? root.palette.alpha(root.ink, 0.35 + 0.65 * core.load) : root.palette.alpha(root.palette.primary, 0.35 + 0.65 * core.load)
                            Behavior on height { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                        }
                    }
                }
            }
            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: root.temp >= 0
                spacing: Tokens.spacingSm
                MaterialIcon {
                    name: "thermostat"
                    font.pixelSize: Tokens.iconLg
                    color: root.hero ? root.ink : root.palette.primary
                }
                StyledText {
                    text: root.temp + "°C"
                    variant: "label"
                    font.weight: Font.DemiBold
                    font.features: ({ tnum: 1 })
                    color: root.ink
                }
                Meter {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredHeight: Tokens.spacingSm
                    value: root.temp / 100 * root.arrive
                    accent: root.hero ? root.ink : root.palette.primary
                }
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillHeight: false
            spacing: Tokens.spacingXs
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("Usage")
                variant: "caption"
                color: root.inkDim
            }
            IslandBadge {
                Layout.alignment: Qt.AlignHCenter
                filled: true
                size: Tokens.iconXl * 2 + Tokens.spacingMd
                shape: root.shape
                text: Math.round(root.usage * 100) + "%"
                textPx: Tokens.fontTitle
            }
        }
    }
}
