import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"

// ── WeatherMeterPlate ─────────────────────────────────────────────────────────
// One reading on the Weather page as a tall tile: a shape badge with what it is, the value large and a meter under it. Wind (speed on its scale, a tick for the gust) and air (the band) wear it.
// The meter fills on a spring when the reading changes, and sweeps in with the plate.
// ─────────────────────────────────────────────────────────────────────────────
IslandPlate {
    id: root

    property string shape: "cookie9"
    property string symbol: ""
    property real   iconRotation: 0
    property string label: ""
    property string value: ""
    // 0..1 along the meter; `tick` is a second mark (the gust), -1 for none.
    property real   ratio: 0
    property real   tick: -1
    property color  meterTone: root.palette.primary

    SpringValue { id: fill; target: Math.max(0, Math.min(1, root.ratio)); spec: Motion.springSpatialFast }
    SpringValue { id: mark; target: Math.max(0, Math.min(1, root.tick)); spec: Motion.springSpatialFast }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingXs

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            IslandBadge {
                size: Tokens.iconXl
                shape: root.shape
                symbol: root.symbol
                iconRotation: root.iconRotation
            }
            StyledText {
                Layout.fillWidth: true
                text: root.label
                variant: "caption"
                font.weight: Font.DemiBold
                emphasis: "dim"
                elide: Text.ElideRight
            }
        }

        Item { Layout.fillHeight: true }

        StyledText {
            Layout.fillWidth: true
            text: root.value
            font.pixelSize: Tokens.fontHeadline
            font.weight: Font.DemiBold
            font.features: ({ tnum: 1 })
            elide: Text.ElideRight
        }

        Item {
            id: track
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Tokens.spacingMd
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: Tokens.spacingSm
                radius: height / 2
                color: root.palette.alpha(root.ink, 0.14)
                Rectangle {
                    width: Math.max(parent.height, parent.width * fill.value * root.arrive)
                    height: parent.height
                    radius: height / 2
                    color: root.meterTone
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                }
            }
            Rectangle {
                visible: root.tick >= 0
                anchors.verticalCenter: parent.verticalCenter
                x: Math.min(parent.width - width, Math.max(0, parent.width * mark.value - width / 2)) * root.arrive
                width: Tokens.spacingXs + 1
                height: parent.height
                radius: width / 2
                color: root.ink
            }
        }

    }
}
