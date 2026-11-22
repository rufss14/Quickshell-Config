import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../state"
import "../../components"
import "../../services"
import "../../services/island.js" as Rules
import "../../services/weather.js" as W

// ── IslandWeather ─────────────────────────────────────────────────────────────
// The card's fourth page: the place and the date, the other places you keep as one-press chips (and a plus
// for a new one), the units and a refresh; under them a tall loud card (a badge whose shape is the sky, the
// temperature very large, the facts as pills), the day's hours as a curve with its high and low named, and four
// plates (wind, rain, the sun's arc, the air); and the week as seven pills. Press a day and the page is that day:
// the card, the curve, the wind, the rain and the sun. All from the shell's Weather service (Open-Meteo); nothing
// is fetched here beyond holding it.
// Weather is held only while this page is on screen.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)

    Component.onCompleted: { Weather.acquire(); AirQuality.acquire() }
    Component.onDestruction: { Weather.release(); AirQuality.release() }

    // ── What the page is showing ──────────────────────────────────────────────
    // 0 is today; or the day you pressed. `hourIdx` is the hour you dragged the ruler to (-1 for now).
    property int dayIdx: 0
    property int hourIdx: -1
    onDayIdxChanged: root.hourIdx = -1
    property bool placesOpen: false
    readonly property bool choosing: root.placesOpen || !Weather.hasLocation
    onChoosingChanged: if (root.choosing) Qt.callLater(places.focusSearch)
    // A new place starts at today.
    Connections {
        target: Weather
        function onPlaceChanged() { root.dayIdx = 0; root.placesOpen = false }
    }

    readonly property string todayIso: Qt.formatDate(Clock.now, "yyyy-MM-dd")
    readonly property var dayObj: Weather.days.length > root.dayIdx ? Weather.days[root.dayIdx] : null
    readonly property bool isToday: root.dayIdx === 0 || root.dayObj === null
    readonly property string todayDate: Weather.days.length > 0 ? Weather.days[0].date : root.todayIso
    readonly property var shownHours: W.dayHours(Weather.hours, Weather.hoursStart, root.dayObj ? root.dayObj.date : root.todayDate, root.todayDate)
    readonly property var pickedHour: root.hourIdx >= 0 && root.hourIdx < root.shownHours.length ? root.shownHours[root.hourIdx] : null
    // The hour the readings come from when it is not now: the one you dragged to, else a day's midday.
    readonly property var focusHour: root.pickedHour ?? (root.isToday ? null : W.middayOf(root.shownHours))
    onShownHoursChanged: if (root.hourIdx >= root.shownHours.length) root.hourIdx = -1

    readonly property int    dCode:  root.pickedHour ? root.pickedHour.code : root.isToday ? Weather.code : root.dayObj.code
    readonly property bool   dDay:   root.pickedHour ? root.pickedHour.isDay : root.isToday ? Weather.isDay : true
    readonly property real   dTemp:  root.pickedHour ? root.pickedHour.tempC : root.isToday ? Weather.tempC : root.dayObj.maxC
    readonly property string kind:   Rules.weatherKind(root.dCode, root.dDay)

    // "7:18 AM" from a local ISO time, in the locale's own clock.
    function clockOf(iso) {
        const t = Rules.isoTime(iso)
        return t ? Qt.formatTime(new Date(2000, 0, 1, t.h, t.m), Qt.locale().timeFormat(Locale.ShortFormat)) : "—"
    }
    function dayNames() {
        const out = []
        for (let i = 0; i < 7; i++) out.push(Qt.locale().dayName(i, Locale.ShortFormat))
        return out
    }
    function monthNames() {
        const out = []
        for (let i = 0; i < 12; i++) out.push(Qt.locale().monthName(i, Locale.ShortFormat))
        return out
    }
    // The places you keep other than this one, as many as fit beside the name.
    readonly property var others: Weather.cities.filter(function (c) { return !Weather.isHere(c) }).slice(0, 3)
    // The first part of "Porto, Portugal" is the name of the place.
    readonly property string city: StreamMode.mask(String(Weather.place || "").split(",")[0].trim())
    // The words over the temperature, and the line under the sky: the feel, the wetness and the sun's strength for
    // now or an hour; a day's low and high.
    readonly property string when: root.pickedHour
        ? Qt.formatDate(new Date(root.pickedHour.date + "T12:00"), "ddd") + " " + (root.pickedHour.hour < 10 ? "0" : "") + root.pickedHour.hour + ":00"
        : root.isToday ? Translation.tr("Now")
        : Translation.tr("%1, the high").arg(Qt.formatDate(new Date(root.dayObj.date + "T12:00"), "dddd"))
    // The facts under the temperature, as pills: the feel, the wetness and the sun's strength for now or an hour; a
    // day's low and high and its sun.
    readonly property var chips: {
        if (!Weather.ready) return []
        const uv = root.uvNow >= 1 && isFinite(root.uvNow) ? [{ icon: "wb_sunny", text: Translation.tr("UV %1").arg(Math.round(root.uvNow)) }] : []
        if (!root.pickedHour && !root.isToday)
            return [{ icon: "arrow_downward", text: Translation.tr("Low %1°").arg(Weather.temp(root.dayObj.minC)) },
                    { icon: "arrow_upward", text: Translation.tr("High %1°").arg(Weather.temp(root.dayObj.maxC)) }].concat(uv)
        const h = root.pickedHour
        return [{ icon: "thermostat", text: Translation.tr("Feels %1°").arg(Weather.temp(h ? h.feelsC : Weather.feelsC)) },
                { icon: "humidity_percentage", text: Math.round(h ? h.humidity : Weather.humidity) + "%" }].concat(uv)
    }

    // The plates' readings.
    readonly property real windKph: root.focusHour ? root.focusHour.windKph : Weather.windKph
    readonly property real gustKph: root.focusHour ? root.focusHour.gustKph : Weather.gustKph
    readonly property real windDir: root.focusHour ? root.focusHour.windDir : Weather.windDir
    readonly property real uvNow: root.pickedHour ? root.pickedHour.uv : root.isToday ? Weather.uv : (root.dayObj ? root.dayObj.uvMax : -1)

    // Live rain (the nowcast) only for now; another day, or an hour you dragged to, reads its chance of rain.
    readonly property bool liveRain: root.isToday && root.pickedHour === null
    readonly property var rainBars: {
        const m = Clock.minutes
        return root.liveRain ? W.bars(Weather.minutely, Date.now(), 12) : W.chanceBars(root.shownHours)
    }
    readonly property var dryWin: {
        const m = Clock.minutes
        const at = String(Weather.observedAt || "")
        return at.length >= 13 ? W.dryWindow(Weather.hours, at.slice(0, 10), parseInt(at.slice(11, 13), 10)) : null
    }
    readonly property string rainTitle: root.pickedHour ? Translation.tr("%1% chance").arg(Math.round(root.pickedHour.precip))
        : root.liveRain ? (Weather.nowcast ? Weather.nowcast.short : (root.dryWin ? root.dryWin.text : "—"))
        : W.rainSpans(root.shownHours).text
    readonly property string rainSymbol: {
        if (root.liveRain && Weather.nowcast)
            return Weather.nowcast.state === "dry" ? "umbrella" : Weather.nowcast.kind === "snow" ? "cloudy_snowing" : "rainy"
        return root.rainBars.some(function (b) { return b.v >= 0.5 }) ? "rainy" : "umbrella"
    }

    // The moment the sun plate shows: the hour you dragged to, else now for today, else none (another day is the whole arc).
    readonly property real sunMs: {
        const m = Clock.minutes
        return root.pickedHour ? new Date(root.pickedHour.date + "T" + (root.pickedHour.hour < 10 ? "0" : "") + root.pickedHour.hour + ":00").getTime()
             : root.isToday ? Date.now() : -1
    }
    readonly property var sunArc: root.dayObj ? W.sunArc(root.dayObj.sunrise, root.dayObj.sunset, root.sunMs >= 0 ? root.sunMs : 0) : null

    // A busy spinner while it fetches (exempt from the ambient gate).
    property real spin: 0
    NumberAnimation on spin {
        running: Weather.loading || AirQuality.loading
        from: 0; to: 360
        duration: Motion.pulse * 2
        loops: Animation.Infinite
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        // ── The place, the date, the tools ────────────────────────────────────
        IslandPiece {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Tokens.iconXl + Tokens.spacingXl
            order: 0
            RowLayout {
                anchors.fill: parent
                spacing: Tokens.spacingMd

                // The place is a button: pressed, the page becomes the place search.
                Item {
                    id: placeBtn
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Rectangle {
                        anchors.fill: parent
                        anchors.rightMargin: -Tokens.spacingMd
                        anchors.leftMargin: -Tokens.spacingMd
                        radius: Tokens.radiusSm
                        color: root.palette.alpha(root.palette.fg, 0.08)
                        opacity: placePress.containsMouse || root.choosing ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    }
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            StyledText {
                                text: root.city !== "" ? root.city : Translation.tr("No place set")
                                font.pixelSize: Tokens.fontHeadline
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                Layout.maximumWidth: placeBtn.width - Tokens.iconLg - Tokens.spacingMd
                            }
                            MaterialIcon {
                                name: "expand_more"
                                font.pixelSize: Tokens.iconLg
                                color: root.palette.fgMuted
                                rotation: root.choosing ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: Motion.standard; easing.type: Motion.respondCurve } }
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.isToday ? Qt.formatDate(Clock.now, "dddd, MMMM d")
                                : Qt.formatDate(new Date(root.dayObj.date + "T12:00"), "dddd, MMMM d")
                            variant: "caption"
                            emphasis: "dim"
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        id: placePress
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.placesOpen = !root.placesOpen
                    }
                }

                // The other places you keep: one press and the page is that place. The plus opens the search.
                Repeater {
                    model: root.others
                    delegate: ChipButton {
                        required property var modelData
                        Layout.alignment: Qt.AlignVCenter
                        symbol: "location_on"
                        label: StreamMode.mask(modelData.name.length > 14 ? modelData.name.slice(0, 13) + "…" : modelData.name)
                        tonal: true
                        onActivated: Weather.choose(modelData)
                    }
                }
                ChipButton {
                    visible: !root.choosing
                    Layout.alignment: Qt.AlignVCenter
                    symbol: "add"
                    label: root.others.length === 0 ? Translation.tr("Add city") : ""
                    tonal: true
                    onActivated: root.placesOpen = true
                }
                ChipButton {
                    visible: (root.dayIdx > 0 || root.hourIdx >= 0) && !root.choosing
                    Layout.alignment: Qt.AlignVCenter
                    symbol: "history"
                    label: root.dayIdx > 0 ? Translation.tr("Today") : Translation.tr("Now")
                    tonal: true
                    onActivated: { root.dayIdx = 0; root.hourIdx = -1 }
                }
                ChipButton {
                    Layout.alignment: Qt.AlignVCenter
                    label: Weather.unit
                    labelVariant: "title"
                    tonal: true
                    onActivated: Config.weatherMetric = !Config.weatherMetric
                }
                ChipButton {
                    Layout.alignment: Qt.AlignVCenter
                    symbol: "refresh"
                    tonal: true
                    iconAngle: Weather.loading || AirQuality.loading ? root.spin : 0
                    enabled: !Weather.loading && !AirQuality.loading && Weather.hasLocation
                    onActivated: { Weather.refresh(); AirQuality.refresh() }
                }
            }
        }

        // ── The middle: the sky, then the hours and the readings; or the place search over them ─
        Item {
            id: stage
            Layout.fillWidth: true
            Layout.fillHeight: true

            RowLayout {
                id: main
                anchors.fill: parent
                spacing: Tokens.spacingMd
                opacity: root.choosing ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.respondCurve } }

                WeatherSkyCard {
                    Layout.fillWidth: false
                    Layout.fillHeight: true
                    Layout.preferredWidth: Tokens.iconXl * 8
                    order: 1
                    code: root.dCode
                    isDay: root.dDay
                    fxActive: root.visible && !root.choosing
                    shape: Rules.weatherShape(root.kind)
                    symbol: Weather.ready ? Weather.symbol(root.dCode, root.dDay) : "cloud"
                    when: root.when
                    temp: Weather.ready ? String(Weather.temp(root.dTemp)) : "—"
                    unit: Weather.ready ? Weather.unit : ""
                    words: Weather.ready ? Weather.describe(root.dCode)
                                         : (Weather.loading ? Translation.tr("Loading…") : Translation.tr("No weather"))
                    chips: root.chips
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Tokens.spacingMd

                    // The day's hours: a curve with its high and low named, and a ruler to drag along.
                    IslandPlate {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        order: 2
                        WeatherHourly {
                            anchors.fill: parent
                            anchors.margins: Tokens.spacingLg
                            hours: root.shownHours
                            selected: root.hourIdx
                            onScrubbed: function (i) { root.hourIdx = i }
                            title: root.isToday ? Translation.tr("Next 24 hours")
                                 : Qt.formatDate(new Date(root.dayObj.date + "T12:00"), "dddd")
                        }
                    }

                    // Wind, rain, the sun, the air.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: Tokens.iconXl * 4 + Tokens.spacingMd
                        spacing: Tokens.spacingMd

                        WeatherMeterPlate {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: 1
                            order: 3
                            shape: "squircle"
                            symbol: "navigation"
                            // It is reported as where it comes FROM; the arrow points the way it blows TO.
                            iconRotation: root.windDir + 180
                            label: Translation.tr("Wind")
                            value: Weather.ready ? Weather.wind(root.windKph) : "—"
                            ratio: root.windKph / 60
                            tick: Weather.ready && root.gustKph > 0 ? Math.min(1, root.gustKph / 60) : -1
                        }
                        WeatherRainPlate {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: 1
                            order: 4
                            title: root.rainTitle
                            symbol: root.rainSymbol
                            bars: root.rainBars
                        }
                        WeatherSunPlate {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: 1
                            order: 5
                            arc: root.sunArc
                            isToday: root.sunMs >= 0
                            riseText: root.dayObj ? root.clockOf(root.dayObj.sunrise) : "—"
                            setText: root.dayObj ? root.clockOf(root.dayObj.sunset) : "—"
                        }
                        WeatherMeterPlate {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: 1
                            order: 6
                            shape: "clover"
                            symbol: "masks"
                            label: Translation.tr("Air quality")
                            value: AirQuality.aqi >= 0 ? Translation.tr(AirQuality.level) + " " + Math.round(AirQuality.aqi) : "—"
                            ratio: AirQuality.ratio
                            meterTone: root.palette[W.aqiRole(AirQuality.aqi)]
                        }
                    }
                }
            }

            WeatherPlaces {
                id: places
                anchors.fill: parent
                radius: Tokens.radiusXl
                opacity: root.choosing ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.respondCurve } }
                onDone: root.placesOpen = false
            }
        }

        // ── The week: seven pills; the one you press is the page ──────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Tokens.iconXl * 2 + Tokens.spacingLg
            spacing: Tokens.spacingSm

            Repeater {
                model: 7
                delegate: IslandPlate {
                    id: day
                    required property int index
                    readonly property var d: Weather.days.length > day.index ? Weather.days[day.index] : null
                    readonly property var label: day.d ? Rules.forecastDay(day.d.date, root.todayIso, root.dayNames(), root.monthNames())
                                                       : ({ name: "", date: "", today: false })
                    readonly property bool chosen: root.dayIdx === day.index
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    hero: day.chosen
                    clickable: day.d !== null
                    order: 7 + day.index
                    radius: day.chosen ? height / 2 : Tokens.radiusCard
                    Behavior on radius { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }
                    Behavior on tone { ColorAnimation { duration: Motion.respond } }
                    onClicked: root.dayIdx = day.index

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacingMd
                        anchors.rightMargin: Tokens.spacingMd
                        spacing: Tokens.spacingSm

                        // The sky, and under it the chance of rain (nothing for a dry day).
                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0
                            MaterialIcon {
                                Layout.alignment: Qt.AlignHCenter
                                name: day.d ? Weather.symbol(day.d.code, true) : "cloud"
                                fill: 1
                                font.pixelSize: Tokens.iconXl
                                color: day.chosen ? day.ink : day.palette.fgMuted
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: day.d && day.d.precipChance >= 20 ? Math.round(day.d.precipChance) + "%" : " "
                                variant: "micro"
                                font.weight: Font.DemiBold
                                font.features: ({ tnum: 1 })
                                color: day.chosen ? day.ink : day.palette.info
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: day.label.today ? Translation.tr("Today") : day.label.name
                                variant: "label"
                                font.weight: Font.Bold
                                color: day.chosen ? day.ink : day.palette.primary
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: day.d ? Weather.temp(day.d.minC) + "° / " + Weather.temp(day.d.maxC) + "°" : "—"
                                variant: "caption"
                                font.weight: Font.DemiBold
                                font.features: ({ tnum: 1 })
                                color: day.ink
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
