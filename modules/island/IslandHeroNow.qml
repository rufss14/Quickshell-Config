import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../state"
import "../../components"
import "../../services"
import "../../services/island.js" as Rules

// ── IslandHeroNow ─────────────────────────────────────────────────────────────
// The Dashboard's loud card, on the accent container: the weekday and the time very large, the date, and under them the
// weather in a badge whose SHAPE is the sky (a sunburst for clear, a cookie for cloud, a clover for rain, a burst for a
// storm — it morphs when the weather changes) with the temperature, the words and today's low and high. A big shape
// of the same turns slowly behind the time (still when ambient motion is off), and the weather drifts across the card
// (IslandWeatherFx).
// ─────────────────────────────────────────────────────────────────────────────
IslandPlate {
    id: root

    hero: true
    radius: Tokens.radiusXl
    clickable: true
    Accessible.name: Translation.tr("Weather")
    onClicked: UiState.islandGo("weather")

    readonly property string kind: Rules.weatherKind(Weather.code, Weather.isDay)
    readonly property var today: Weather.days.length > 0 ? Weather.days[0] : null
    readonly property real dayDone: (Clock.now.getHours() * 60 + Clock.now.getMinutes()) / 1440
    readonly property bool twelve: Rules.isTwelveHour(Qt.locale().timeFormat(Locale.ShortFormat))
    readonly property var clock: Rules.clockText(Clock.now.getHours(), Clock.now.getMinutes(), root.twelve,
                                                 Qt.locale().amText, Qt.locale().pmText)

    IslandWeatherFx {
        anchors.fill: parent
        radius: root.radius
        visible: UiState.islandEffectsOn
        code: Weather.code
        isDay: Weather.isDay
        active: root.visible && UiState.islandEffectsOn
        tone: root.ink
    }

    MorphShape {
        width: root.height * 0.78
        height: width
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: -width * 0.22
        anchors.topMargin: -width * 0.2
        shape: Rules.weatherShape(root.kind)
        turns: false
        fillColor: root.palette.alpha(root.ink, 0.10)
        NumberAnimation on rotation {
            from: 0
            to: 360
            duration: 90000
            loops: Animation.Infinite
            running: Motion.ambientOn && root.visible && UiState.islandEffectsOn
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: 0

        StyledText {
            text: Qt.locale().dayName(Clock.now.getDay(), Locale.LongFormat).toUpperCase()
            variant: "caption"
            font.weight: Font.Bold
            font.letterSpacing: 1.5
            color: root.inkDim
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            StyledText {
                Layout.fillWidth: true
                text: root.clock.time
                font.pixelSize: Math.round(Tokens.fontDisplay * 2.6)
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Tokens.fontHeadline
                font.weight: Font.DemiBold
                font.features: ({ tnum: 1 })
                color: root.ink
            }
            StyledText {
                Layout.alignment: Qt.AlignBottom
                Layout.bottomMargin: Tokens.spacingMd
                visible: root.clock.marker !== ""
                text: root.clock.marker
                variant: "title"
                font.weight: Font.Bold
                color: root.inkDim
            }
        }
        StyledText {
            text: Qt.formatDate(Clock.now, "d MMMM yyyy")
            variant: "label"
            color: root.ink
        }

        Item { Layout.fillHeight: true }

        // How far through the day, as M3E's wavy line (it lies flat, nothing to drag).
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.bottomMargin: Tokens.spacingMd
            spacing: Tokens.spacingSm
            StyledText {
                text: Translation.tr("Day")
                variant: "caption"
                font.weight: Font.DemiBold
                color: root.inkDim
            }
            WaveSlider {
                Layout.fillWidth: true
                enabled: false
                value: root.dayDone * root.arrive
                accent: root.ink
            }
            StyledText {
                text: Math.round(root.dayDone * 100) + "%"
                variant: "caption"
                font.weight: Font.DemiBold
                font.features: ({ tnum: 1 })
                color: root.inkDim
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            IslandBadge {
                filled: true
                size: Tokens.iconXl + Tokens.spacingXl
                shape: Rules.weatherShape(root.kind)
                symbol: Weather.ready ? Weather.symbol(Weather.code, Weather.isDay) : "cloud"
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: Weather.ready ? Weather.temp(Weather.tempC) + "°" : "—"
                    variant: "headline"
                    font.weight: Font.DemiBold
                    font.features: ({ tnum: 1 })
                    color: root.ink
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Weather.ready ? Weather.describe(Weather.code)
                                        : (Weather.loading ? Translation.tr("Loading…") : Translation.tr("No weather"))
                    variant: "caption"
                    color: root.inkDim
                    elide: Text.ElideRight
                }
            }
            ColumnLayout {
                visible: root.today !== null
                spacing: 0
                StyledText {
                    Layout.alignment: Qt.AlignRight
                    text: root.today ? "↑ " + Weather.temp(root.today.maxC) + "°" : ""
                    variant: "caption"
                    font.weight: Font.DemiBold
                    font.features: ({ tnum: 1 })
                    color: root.ink
                }
                StyledText {
                    Layout.alignment: Qt.AlignRight
                    text: root.today ? "↓ " + Weather.temp(root.today.minC) + "°" : ""
                    variant: "caption"
                    font.features: ({ tnum: 1 })
                    color: root.inkDim
                }
            }
        }
    }
}
