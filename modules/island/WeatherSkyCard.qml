import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../state"
import "../../components"
import "../../services"

// ── WeatherSkyCard ────────────────────────────────────────────────────────────
// The Weather page's one loud card, a tall column on the accent container: what the reading is for (now, an hour, a
// day), the temperature very large with the sky's badge beside it (its SHAPE is the weather and morphs when it
// changes), the words, and the facts that go with it as pills at the foot. The weather drifts across the card
// (IslandWeatherFx). `chips` is [{ icon, text }].
// ─────────────────────────────────────────────────────────────────────────────
IslandPlate {
    id: root

    property int    code: 0
    property bool   isDay: true
    property bool   fxActive: true
    property string shape: "cookie9"
    property string symbol: "cloud"
    property string when: ""
    property string temp: "—"
    property string unit: ""
    property string words: ""
    property var    chips: []

    hero: true
    radius: Tokens.radiusXl

    IslandWeatherFx {
        anchors.fill: parent
        radius: root.radius
        code: root.code
        isDay: root.isDay
        visible: UiState.islandEffectsOn
        active: root.fxActive && UiState.islandEffectsOn
        tone: root.ink
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: 0

        StyledText {
            Layout.fillWidth: true
            text: root.when
            variant: "label"
            font.weight: Font.DemiBold
            color: root.inkDim
            elide: Text.ElideRight
        }

        Item { Layout.fillHeight: true }

        IslandBadge {
            Layout.alignment: Qt.AlignLeft
            filled: true
            size: Tokens.iconXl * 3
            shape: root.shape
            symbol: root.symbol
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.topMargin: Tokens.spacingMd
            spacing: Tokens.spacingXs
            StyledText {
                text: root.temp
                font.pixelSize: Math.round(Tokens.fontNumeralLg * 1.25)
                font.weight: Font.DemiBold
                font.features: ({ tnum: 1 })
                color: root.ink
            }
            StyledText {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: Tokens.spacingMd
                text: root.unit
                variant: "title"
                font.weight: Font.DemiBold
                color: root.inkDim
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.words
            variant: "title"
            color: root.ink
            elide: Text.ElideRight
        }

        Item { Layout.fillHeight: true }

        Flow {
            id: facts
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            Repeater {
                model: root.chips
                delegate: Rectangle {
                    id: fact
                    required property var modelData
                    implicitHeight: Tokens.iconLg + Tokens.spacingMd
                    implicitWidth: factRow.implicitWidth + Tokens.spacingLg
                    radius: height / 2
                    color: root.palette.alpha(root.ink, 0.14)
                    Row {
                        id: factRow
                        anchors.centerIn: parent
                        spacing: Tokens.spacingXs
                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: fact.modelData.icon
                            fill: 1
                            font.pixelSize: Tokens.iconSm
                            color: root.inkDim
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: fact.modelData.text
                            variant: "caption"
                            font.weight: Font.DemiBold
                            font.features: ({ tnum: 1 })
                            color: root.ink
                        }
                    }
                }
            }
        }
    }
}
