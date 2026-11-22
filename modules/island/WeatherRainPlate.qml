import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── WeatherRainPlate ──────────────────────────────────────────────────────────
// The rain on the Weather page, a tile like the wind's: a badge and "Rain", the wording ("Rain in ~20 min") large,
// then one bar per slot (the quarter hours of the nowcast, or the hours' chance for another day or a scrubbed
// hour). No bars for a dry spell: stubs would say it was raining a little.
// ─────────────────────────────────────────────────────────────────────────────
IslandPlate {
    id: root

    property string title: ""
    property string symbol: "umbrella"
    // [{ v: 0..1, snow }] (weather.js bars / chanceBars).
    property var bars: []
    readonly property bool wet: root.bars.some(function (b) { return b.v > 0 })

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
                shape: "clover"
                symbol: root.symbol
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Rain")
                variant: "caption"
                font.weight: Font.DemiBold
                emphasis: "dim"
                elide: Text.ElideRight
            }
        }

        Item { Layout.fillHeight: true }

        StyledText {
            Layout.fillWidth: true
            text: root.title
            font.pixelSize: Tokens.fontHeadline
            font.weight: Font.DemiBold
            font.features: ({ tnum: 1 })
            elide: Text.ElideRight
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Tokens.spacingMd + Tokens.spacingSm
            visible: root.wet

            RowLayout {
                anchors.fill: parent
                spacing: Tokens.borderWidth * 2
                Repeater {
                    model: root.bars
                    delegate: Item {
                        id: bar
                        required property int index
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.max(Tokens.borderWidth * 2, Math.min(parent.width, Tokens.spacingSm))
                            height: Math.max(width, parent.height * bar.modelData.v * root.arrive)
                            radius: width / 2
                            color: bar.modelData.v <= 0 ? root.palette.alpha(root.ink, 0.18)
                                 : bar.modelData.snow ? root.palette.fg : root.palette.info
                            Behavior on height { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }
                        }
                    }
                }
            }
        }

    }
}
